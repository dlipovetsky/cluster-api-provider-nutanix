#!/usr/bin/env bash

CAPX_IMG="docker.io/dlipovetsky/cluster-api-provider-nutanix:1.0h"

# We need to source this to use $CAPX_KUBECONFIG and $CAPX_NAMESPACE in the docker run command.
source capx.env

docker run \
    --name capx \
    --volume "$CAPX_KUBECONFIG:/kubeconfig" \
    --env-file capx.env \
    "$CAPX_IMG" \
        -namespace="$CAPX_NAMESPACE" \
        -kubeconfig="/kubeconfig"
