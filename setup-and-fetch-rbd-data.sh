#!/bin/bash
# Setup script: Copy analysis script to pod and fetch RBD data
# Automates the process of getting RBD data from rook-ceph-operator pod
# Uses oc rsync with --strategy=tar for reliable file copying

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
TOOLS_POD=$(oc get pods -l app=rook-ceph-operator -o name 2>/dev/null | head -1)

if [ -z "$TOOLS_POD" ]; then
    echo -e "${RED}Error: Could not find rook-ceph-operator pod in namespace '$NAMESPACE'${NC}"
    echo "Available pods:"
    oc get pods -l app=rook-ceph-operator 2>/dev/null || echo "No pods found"
    exit 1
fi

# Remove 'pod/' prefix if present (handle both "pod/name" and just "name" formats)
TOOLS_POD=$(echo "$TOOLS_POD" | sed 's|^pod/||' | tr -d '\n' | tr -d '\r')
echo -e "${GREEN}Found pod: $TOOLS_POD${NC}"
echo ""

# Check if script exists locally
SCRIPT_PATH="$(dirname "$0")/$SCRIPT_NAME"
if [ ! -f "$SCRIPT_PATH" ]; then
    echo -e "${RED}Error: Script '$SCRIPT_NAME' not found at $SCRIPT_PATH${NC}"
    exit 1
fi

# Create temporary directory for rsync (rsync needs a directory)
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT
cp "$SCRIPT_PATH" "$TEMP_DIR/$SCRIPT_NAME"
chmod +x "$TEMP_DIR/$SCRIPT_NAME"

# Copy analysis script to pod using oc rsync with tar strategy
echo -e "${YELLOW}Step 3: Copying $SCRIPT_NAME to pod using rsync (tar strategy)...${NC}"
oc rsync "$TEMP_DIR/" "$TOOLS_POD:/tmp/" --strategy=tar --no-perms=false 2>/dev/null || {
    echo -e "${RED}Error: Failed to copy script to pod using rsync${NC}"
    echo "Trying alternative method..."
    # Alternative: try copying just the file
    oc rsync "$TEMP_DIR/$SCRIPT_NAME" "$TOOLS_POD:/tmp/" --strategy=tar --no-perms=false 2>/dev/null || {
        echo -e "${RED}Error: All copy methods failed${NC}"
        exit 1
    }
}
echo -e "${GREEN}Script copied successfully${NC}"

# IMPORTANT: Make script executable in pod (rsync may not preserve execute permissions)
echo -e "${YELLOW}Step 4: Making script executable in pod (required after rsync)...${NC}"
oc exec "$TOOLS_POD" -- chmod +x "/tmp/$SCRIPT_NAME" || {
    echo -e "${RED}Error: Failed to make script executable in pod${NC}"
    exit 1
}
echo -e "${GREEN}Script is now executable${NC}"
echo ""

# Run RBD command to get usage data
echo -e "${YELLOW}Step 5: Fetching RBD usage data from pool '$POOL'...${NC}"
echo "This may take a while depending on the number of volumes..."
oc exec "$TOOLS_POD" -- \
    sh -c "export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config' && \
           rbd \$CEPH_ARGS du -p '$POOL' 2>&1 | grep -v '^warning:' > $POD_RBD_OUTPUT" 2>/dev/null || {
    echo -e "${RED}Error: Failed to run rbd du command${NC}"
    exit 1
}
echo -e "${GREEN}RBD data collected${NC}"
echo ""

# Copy output file from pod to local directory using oc rsync
echo -e "${YELLOW}Step 6: Copying RBD output file to local directory using rsync (tar strategy)...${NC}"
# Create a temporary directory to receive the file
RECEIVE_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR $RECEIVE_DIR" EXIT

# Use rsync to copy from pod to local
oc rsync "$TOOLS_POD:/tmp/" "$RECEIVE_DIR/" --strategy=tar --include="$LOCAL_RBD_OUTPUT" --exclude="*" --no-perms=false 2>/dev/null || {
    # Alternative: try copying the specific file
    oc rsync "$TOOLS_POD:$POD_RBD_OUTPUT" "$RECEIVE_DIR/" --strategy=tar --no-perms=false 2>/dev/null || {
        echo -e "${RED}Error: Failed to copy output file from pod${NC}"
        exit 1
    }
    # If we copied the file directly, it might have a different name
    if [ -f "$RECEIVE_DIR/ceph-rbd-out.txt" ]; then
        mv "$RECEIVE_DIR/ceph-rbd-out.txt" "$LOCAL_RBD_OUTPUT"
    elif [ -f "$RECEIVE_DIR/$(basename $POD_RBD_OUTPUT)" ]; then
        mv "$RECEIVE_DIR/$(basename $POD_RBD_OUTPUT)" "$LOCAL_RBD_OUTPUT"
    fi
}

# If file was copied to receive dir, move it to current directory
if [ -f "$RECEIVE_DIR/$LOCAL_RBD_OUTPUT" ]; then
    mv "$RECEIVE_DIR/$LOCAL_RBD_OUTPUT" "$LOCAL_RBD_OUTPUT"
elif [ -f "$RECEIVE_DIR/$(basename $POD_RBD_OUTPUT)" ]; then
    mv "$RECEIVE_DIR/$(basename $POD_RBD_OUTPUT)" "$LOCAL_RBD_OUTPUT"
fi

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
