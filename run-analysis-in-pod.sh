#!/bin/bash
# Run the analysis script in the rook-ceph-operator pod
# Assumes setup-and-fetch-rbd-data.sh has been run first

set -e

NAMESPACE="${NAMESPACE:-openshift-storage}"
SCRIPT_NAME="ceph-pvc-analysis.sh"
POOL="${POOL:-ocs-storagecluster-cephblockpool}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Running Ceph Analysis in Pod ==="
echo ""

# Get the rook-ceph-operator pod name
TOOLS_POD=$(oc get pods -n "$NAMESPACE" -l app=rook-ceph-operator -o name 2>/dev/null | head -1)

if [ -z "$TOOLS_POD" ]; then
    echo -e "${RED}Error: Could not find rook-ceph-operator pod${NC}"
    exit 1
fi

TOOLS_POD=$(echo "$TOOLS_POD" | sed 's|pod/||')
echo -e "${GREEN}Using pod: $TOOLS_POD${NC}"
echo ""

# Check if script exists in pod
echo -e "${YELLOW}Checking if script exists in pod...${NC}"
if ! oc exec -n "$NAMESPACE" "$TOOLS_POD" -- test -f "/tmp/$SCRIPT_NAME" 2>/dev/null; then
    echo -e "${YELLOW}Script not found in pod. Running setup first...${NC}"
    "$(dirname "$0")/setup-and-fetch-rbd-data.sh" || exit 1
    echo ""
fi

# Run the analysis script
echo -e "${YELLOW}Running analysis script in pod...${NC}"
echo "Pool: $POOL"
echo ""

oc exec -n "$NAMESPACE" "$TOOLS_POD" -- \
    sh -c "export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config' && \
           export POOL='$POOL' && \
           /tmp/$SCRIPT_NAME"

echo ""
echo -e "${GREEN}Analysis complete${NC}"
