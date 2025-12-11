#!/bin/bash
# Setup script: Copy analysis script to pod and fetch RBD data
# Automates the process of getting RBD data from rook-ceph-operator pod
# Uses oc cp for reliable file copying

set -e

NAMESPACE="${NAMESPACE:-openshift-storage}"
POOL="${POOL:-ocs-storagecluster-cephblockpool}"
SCRIPT_NAME="ceph-pvc-analysis.sh"
LOCAL_RBD_OUTPUT="ceph-rbd-out.txt"
POD_RBD_OUTPUT="/tmp/ceph-rbd-out.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Ceph RBD Data Setup and Fetch ==="
echo ""

# Switch to correct project/namespace
echo -e "${YELLOW}Step 1: Switching to namespace '$NAMESPACE'...${NC}"
oc project "$NAMESPACE" >/dev/null 2>&1 || {
    echo -e "${RED}Error: Failed to switch to namespace '$NAMESPACE'${NC}"
    echo "Available projects:"
    oc get projects 2>/dev/null | head -10
    exit 1
}
echo -e "${GREEN}Switched to namespace: $NAMESPACE${NC}"
echo ""

# Get the rook-ceph-operator pod name
echo -e "${YELLOW}Step 2: Finding rook-ceph-operator pod...${NC}"
TOOLS_POD=$(oc get pods -n "$NAMESPACE" -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$TOOLS_POD" ]; then
    echo -e "${RED}Error: Could not find rook-ceph-operator pod in namespace '$NAMESPACE'${NC}"
    echo "Available pods:"
    oc get pods -n "$NAMESPACE" -l app=rook-ceph-operator 2>/dev/null || echo "No pods found"
    exit 1
fi

echo -e "${GREEN}Found pod: $TOOLS_POD${NC}"
echo ""

# Check if script exists locally
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

if [ ! -f "$SCRIPT_PATH" ]; then
    echo -e "${RED}Error: Script '$SCRIPT_NAME' not found at $SCRIPT_PATH${NC}"
    echo -e "${YELLOW}Looked in: $SCRIPT_DIR${NC}"
    echo -e "${YELLOW}Current directory: $(pwd)${NC}"
    exit 1
fi

# Copy analysis script to pod using oc cp
echo -e "${YELLOW}Step 3: Copying $SCRIPT_NAME to pod...${NC}"
oc cp "$SCRIPT_PATH" "$NAMESPACE/$TOOLS_POD:/tmp/$SCRIPT_NAME" || {
    echo -e "${RED}Error: Failed to copy script to pod${NC}"
    exit 1
}
echo -e "${GREEN}Script copied successfully${NC}"

# Make script executable in pod
echo -e "${YELLOW}Step 4: Making script executable in pod...${NC}"
oc exec -n "$NAMESPACE" "$TOOLS_POD" -- chmod +x "/tmp/$SCRIPT_NAME" || {
    echo -e "${RED}Error: Failed to make script executable in pod${NC}"
    exit 1
}
echo -e "${GREEN}Script is now executable${NC}"
echo ""

# Run RBD command to get usage data
echo -e "${YELLOW}Step 5: Fetching RBD usage data from pool '$POOL'...${NC}"
echo "This may take a while depending on the number of volumes..."
oc exec -n "$NAMESPACE" "$TOOLS_POD" -- \
    sh -c "export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config' && \
           rbd \$CEPH_ARGS du -p '$POOL' 2>&1 | grep -v '^warning:' > $POD_RBD_OUTPUT" || {
    echo -e "${RED}Error: Failed to run rbd du command${NC}"
    exit 1
}
echo -e "${GREEN}RBD data collected${NC}"
echo ""

# Copy output file from pod to local directory using oc cp
echo -e "${YELLOW}Step 6: Copying RBD output file to local directory...${NC}"
oc cp "$NAMESPACE/$TOOLS_POD:$POD_RBD_OUTPUT" "./$LOCAL_RBD_OUTPUT" || {
    echo -e "${RED}Error: Failed to copy output file from pod${NC}"
    exit 1
}

# Verify file exists
if [ ! -f "$LOCAL_RBD_OUTPUT" ]; then
    echo -e "${RED}Error: Output file not found after copy${NC}"
    exit 1
fi

echo -e "${GREEN}File copied to: $(pwd)/$LOCAL_RBD_OUTPUT${NC}"
echo ""

# Show file info
LINE_COUNT=$(wc -l < "$LOCAL_RBD_OUTPUT" | tr -d ' ')
FILE_SIZE=$(du -h "$LOCAL_RBD_OUTPUT" | cut -f1)
echo -e "${GREEN}=== Summary ===${NC}"
echo "Output file: $LOCAL_RBD_OUTPUT"
echo "File size: $FILE_SIZE"
echo "Lines: $LINE_COUNT"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Run analysis in pod: ./run-analysis-in-pod.sh"
echo "2. Or use local file with: ./find-high-usage-pvcs.sh $LOCAL_RBD_OUTPUT"
echo "3. Or batch map: ./batch-map-rbd-to-pvc.sh $LOCAL_RBD_OUTPUT"
