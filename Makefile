
# Image URL to use all building/pushing image targets
#IMG ?= controller:latest
CONTROLLER_IMG_VER = v0.2.0
IMG = ghcr.io/nutanix-cloud-native/cluster-api-provider-nutanix/controller:${CONTROLLER_IMG_VER}
CRD_OPTIONS ?= "crd:crdVersions=v1"
export GOOS:=$(shell go env GOOS)
export GOARCH:=$(shell go env GOARCH)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

all: init build clusterctl_install

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

init: kind-create
	# install kustomize 
	curl -L -O "https://github.com/kubernetes-sigs/kustomize/releases/download/v3.1.0/kustomize_3.1.0_$${GOOS}_$${GOARCH}"
	sudo chmod +x kustomize_3.1.0_$${GOOS}_$${GOARCH}
	sudo mv kustomize_3.1.0_$${GOOS}_$${GOARCH} /usr/local/bin/kustomize

	# install kubebuilder
	curl -L -O "https://github.com/kubernetes-sigs/kubebuilder/releases/download/v1.0.8/kubebuilder_1.0.8_$${GOOS}_$${GOARCH}.tar.gz"
	tar -zxvf kubebuilder_1.0.8_$${GOOS}_$${GOARCH}.tar.gz
	mv kubebuilder_1.0.8_$${GOOS}_$${GOARCH} kubebuilder
	sudo mv kubebuilder /usr/local/
	rm kubebuilder_1.0.8_$${GOOS}_$${GOARCH}.tar.gz

	# install clusterctl
	curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.1.3/clusterctl-${GOOS}-${GOARCH} -o clusterctl
	chmod +x ./clusterctl
	sudo mv ./clusterctl /usr/local/bin/clusterctl


CLUSTER_NAME = capi-test1
kind-create: ##Get the relevant clustercrl for the latest supported cluster API version
	# create kind cluster
	kind create cluster --name=${CLUSTER_NAME}
	clusterctl init --core cluster-api:v1.0.0 --bootstrap kubeadm:v1.0.0 --control-plane kubeadm:v1.0.0 -v 9

kind-delete:
	# delete kind cluster
	kind delete cluster --name=${CLUSTER_NAME}

manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Set --output-base for conversion-gen if we are not within GOPATH
#ifneq ($(abspath $(PROJECT_DIR)),$(shell go env GOPATH)/src/github.com/nutanix-core/cluster-api-provider-nutanix)
#	OUTPUT_BASE := --output-base=$(PROJECT_DIR)
#endif

generate: controller-gen conversion-gen## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations, and API conversion implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

	$(CONVERSION_GEN) \
		--input-dirs=./api/v1alpha4 \
		--input-dirs=./api/v1beta1 \
		--build-tag=ignore_autogenerated_core \
		--output-file-base=zz_generated.conversion \
		--go-header-file=./hack/boilerplate.go.txt

fmt: ## Run go fmt against code.
	go fmt ./...

vet: ## Run go vet against code.
	go vet ./...

ENVTEST_ASSETS_DIR=$(shell pwd)/testbin
test: manifests generate fmt vet ## Run tests.
	mkdir -p ${ENVTEST_ASSETS_DIR}
	test -f ${ENVTEST_ASSETS_DIR}/setup-envtest.sh || curl -sSLo ${ENVTEST_ASSETS_DIR}/setup-envtest.sh https://raw.githubusercontent.com/kubernetes-sigs/controller-runtime/v0.8.3/hack/setup-envtest.sh
	source ${ENVTEST_ASSETS_DIR}/setup-envtest.sh; fetch_envtest_tools $(ENVTEST_ASSETS_DIR); setup_envtest_env $(ENVTEST_ASSETS_DIR); go test ./... -coverprofile cover.out

##@ Build

build: generate fmt vet ## Build manager binary.
	go build -o bin/manager main.go

run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go

docker-build: test ## Build docker image with the manager.
	docker build -f package/docker/Dockerfile -t ${IMG} .

docker-push: ## Push docker image with the manager.
	docker push ${IMG}

docker-push-kind: ## Make docker image available to kind cluster.
	kind load docker-image --name ${CLUSTER_NAME} ${IMG}

##@ Deployment

install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl delete -f -

TEST_NAMESPACE = test-ns-nutanix-capi
deploy: prepare-local-clusterctl docker-push-kind ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	clusterctl init --infrastructure nutanix -v 9
	# TODO verify if we need to restart the controller pod to use latest uploaded image in kind cluster
	# cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	# $(KUSTOMIZE) build config/default | kubectl apply -f -

TEST_CLUSTER_NAME = test-nutanix-cluster-1
deploy-test: ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	rm ./cluster.yaml || true
	clusterctl generate cluster ${TEST_CLUSTER_NAME} --infrastructure nutanix:v0.2.0 --target-namespace ${TEST_NAMESPACE} --list-variables
	clusterctl generate cluster ${TEST_CLUSTER_NAME} --infrastructure nutanix:v0.2.0 --target-namespace ${TEST_NAMESPACE}  > ./cluster.yaml
	kubectl create ns $(TEST_NAMESPACE) || true
	kubectl apply -f ./cluster.yaml -n $(TEST_NAMESPACE)

undeploy-test:
	kubectl delete -f ./cluster.yaml -n $(TEST_NAMESPACE)
	kubectl delete ns $(TEST_NAMESPACE)

undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config.
	# $(KUSTOMIZE) build config/default | kubectl delete -f -
	clusterctl delete --include-crd --infrastructure nutanix:v0.2.0

release-manifests:
	mkdir -p release-manifests
	$(KUSTOMIZE) build config/default > release-manifests/infrastructure-components.yaml

prepare-local-clusterctl:
	mkdir -p ~/.cluster-api/overrides/infrastructure-nutanix/v0.2.0
	$(KUSTOMIZE) build config/default > ~/.cluster-api/overrides/infrastructure-nutanix/v0.2.0/infrastructure-components.yaml
	cp ./metadata.yaml ~/.cluster-api/overrides/infrastructure-nutanix/v0.2.0
	cp ./cluster-template.yaml ~/.cluster-api/overrides/infrastructure-nutanix/v0.2.0
	cp ./clusterctl.yaml ~/.cluster-api/

CONTROLLER_GEN = $(shell pwd)/bin/controller-gen
controller-gen: ## Download controller-gen locally if necessary.
	rm -f $(CONTROLLER_GEN)
	$(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.7.0)

CONVERSION_GEN = $(shell pwd)/bin/conversion-gen
conversion-gen: ## Download conversion-gen locally if necessary.
	rm -f $(CONVERSION_GEN)
	$(call go-get-tool,$(CONVERSION_GEN),k8s.io/code-generator/cmd/conversion-gen@v0.22.2)

KUSTOMIZE = $(shell pwd)/bin/kustomize
kustomize: ## Download kustomize locally if necessary.
	rm -f $(KUSTOMIZE)
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v4@v4.5.2)

# go-get-tool will 'go get' any package $2 and install it to $1.
PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(PROJECT_DIR)/bin go get $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef
