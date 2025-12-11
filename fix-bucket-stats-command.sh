#!/bin/bash
# Fixed command to check bucket stats - tries multiple paths
# Usage: ./fix-bucket-stats-command.sh [bucket-name]

set -e

export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'

BUCKET_NAME="${1:-lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7}"

echo "=== Checking Bucket: $BUCKET_NAME ==="
echo ""

# First, show the raw JSON to understand the structure
echo "1. Raw JSON structure (first 50 lines):"
echo "---"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.' | head -50
echo ""

# Try multiple possible paths
echo "2. Trying different paths for usage data:"
echo "---"

# Path 1: .usage.rgw.main
echo "Path 1: .usage.rgw.main"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage.rgw.main'
echo ""

# Path 2: .usage.rgw
echo "Path 2: .usage.rgw"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage.rgw'
echo ""

# Path 3: .usage
echo "Path 3: .usage"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage'
echo ""

# Path 4: Look for size_kb anywhere
echo "Path 4: Searching for size_kb anywhere in JSON"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '[paths(scalars) as $p | {path: $p | join("."), value: getpath($p)}] | .[] | select(.path | contains("size") or contains("object"))'
echo ""

# Best attempt - try all paths
echo "3. Best attempt (tries all possible paths):"
echo "---"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq -r '
  # Try multiple paths
  (.usage.rgw.main.size_kb // .usage.rgw.size_kb // .usage.size_kb // .size_kb // 0) as $size_kb |
  (.usage.rgw.main.num_objects // .usage.rgw.num_objects // .usage.num_objects // .num_objects // 0) as $num_objects |
  
  "Size: \($size_kb) KB (\((($size_kb / 1024 / 1024) | floor)) GB, \((($size_kb / 1024 / 1024 / 1024) | floor)) TB)
Objects: \($num_objects)"
'

echo ""
echo "4. Check actual object count:"
echo "---"
OBJECT_COUNT=$(radosgw-admin bucket list --bucket="$BUCKET_NAME" --max-entries=1000 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
echo "Objects found (first 1000): $OBJECT_COUNT"
if [ "$OBJECT_COUNT" = "1000" ]; then
    echo "Note: This is just the first 1000 objects. Bucket likely has many more."
fi
