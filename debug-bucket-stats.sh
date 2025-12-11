#!/bin/bash
# Debug bucket stats to see the actual JSON structure
# Usage: ./debug-bucket-stats.sh [bucket-name]

set -e

export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'

BUCKET_NAME="${1:-lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7}"

echo "=== Debugging Bucket Stats: $BUCKET_NAME ==="
echo ""

echo "1. Full JSON output:"
echo "---"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.'
echo ""

echo "2. Usage structure:"
echo "---"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage'
echo ""

echo "3. RGW main usage:"
echo "---"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage.rgw.main'
echo ""

echo "4. Size and objects (with null handling):"
echo "---"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq -r '
  (.usage.rgw.main // {}) as $usage |
  "Size KB: \($usage.size_kb // "null")
Size KB Actual: \($usage.size_kb_actual // "null")
Objects: \($usage.num_objects // "null")
Multipart: \($usage.multipart_size // "null")"
echo ""

echo "5. Alternative: Check if usage exists at all:"
echo "---"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq 'has("usage")'
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage | has("rgw")'
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage.rgw | has("main")'
echo ""

echo "6. All size-related fields:"
echo "---"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '[paths(scalars) as $p | {path: $p | join("."), value: getpath($p)}] | .[] | select(.path | contains("size") or contains("object"))'
echo ""

echo "=== If bucket shows 0 KB, possible reasons:"
echo "1. Bucket is actually empty (all objects deleted)"
echo "2. Usage data hasn't been updated yet (may need to wait)"
echo "3. Bucket structure is different (check JSON above)"
echo "4. Bucket was recreated/renamed"
