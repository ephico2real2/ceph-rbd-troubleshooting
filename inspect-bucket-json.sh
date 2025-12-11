#!/bin/bash
# Inspect the actual JSON structure of bucket stats
# Usage: ./inspect-bucket-json.sh [bucket-name]

set -e

export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'

BUCKET_NAME="${1:-lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7}"

echo "=== Full JSON Structure for: $BUCKET_NAME ==="
echo ""
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.'

echo ""
echo "=== Checking specific paths ==="
echo ""

echo "1. .usage:"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage'
echo ""

echo "2. .usage.rgw:"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage.rgw'
echo ""

echo "3. .usage.rgw.main:"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage.rgw.main'
echo ""

echo "4. Searching for 'size' anywhere:"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '[paths(scalars) as $p | {path: $p | join("."), value: getpath($p)}] | .[] | select(.path | test("size|object"; "i"))'
echo ""

echo "5. All keys at root level:"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq 'keys'
echo ""

echo "6. All keys in .usage:"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage | keys'
echo ""

echo "7. All keys in .usage.rgw (if exists):"
radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | jq '.usage.rgw | keys // "rgw does not exist"'
echo ""
