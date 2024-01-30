#!/usr/bin/env bash

# The user gets this information from Prism Central.
NUTANIX_ENDPOINT                = "example.com"
NUTANIX_PORT                    = "9440"

# The user gets this from a Prism Central account.
NUTANIX_USERNAME                = "foo"
NUTANIX_PASSWORD                = "bar"

# Given the endpoint and port, the user can download this via browser or openssl.
# We can also download by running openssl in the VM on behalf of the user.
NUTANIX_ADDITIONAL_TRUST_BUNDLE = ""
NUTANIX_INSECURE                = "" # Must be true if no trust bundle is provided, false otherwise. 

# Categories can be left empty.
NUTANIX_CATEGORIES              = ""

# DKP Workspace where the user creates the cluster.
# User will note this in the UI.
# In the future, we might be able to derive this on behalf of the user.
CAPX_NAMESPACE                  = ""

# User will download this from the Management cluster using the UI or CLI.
CAPX_KUBECONFIG                 = 

./cluster-api-provider-nutanix \
    -namespace="$CAPX_NAMESPACE" \
    -kubeconfig="$CAPX_KUBECONFIG"
