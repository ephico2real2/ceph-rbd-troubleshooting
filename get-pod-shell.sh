#!/bin/bash
# Quick helper to get a shell in the rook-ceph-operator pod
# Sets up the CEPH_ARGS environment variable automatically

set -e

NAMESPACE="${NAMESPACE:-openshift-storage}"

# Get the rook-ceph-operator pod name
TOOLS_POD=$(oc get pods -n "$NAMESPACE" -l app=rook-ceph-operator -o name 2>/dev/null | head -1)

if [ -z "$TOOLS_POD" ]; then
    echo "Error: Could not find rook-ceph-operator pod in namespace '$NAMESPACE'"
    exit 1
fi

TOOLS_POD=$(echo "$TOOLS_POD" | sed 's|pod/||')
echo "Connecting to pod: $TOOLS_POD"
echo "CEPH_ARGS will be set automatically"
echo ""

# Connect to pod with CEPH_ARGS pre-set
oc rsh -n "$NAMESPACE" "$TOOLS_POD" sh -c "export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config' && exec \$SHELL"
