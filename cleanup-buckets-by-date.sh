#!/bin/bash
# Complete bucket cleanup script with date-based deletion
# Run in rook-ceph-operator pod
# Usage: ./cleanup-buckets-by-date.sh [days-to-keep]

set -e

export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'

# Configuration
LOKI_BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
NOOBAA_BUCKET="nb.1678954504655.apps.kcs-pre-ewd.k8s.boeing.com"
DAYS_TO_KEEP="${1:-90}"  # Default: keep last 90 days

echo "=== RGW Bucket Cleanup by Date ==="
echo "Date: $(date)"
echo "Days to keep: $DAYS_TO_KEEP"
echo ""

# Step 1: Delete empty buckets
echo "=== Step 1: Deleting Empty Buckets ==="
EMPTY_BUCKETS=(
  "dell-program-tool-43b6ff39-5d10-4b17-822a-3e3e5febd2af"
  "flight-data-bucket-e132979a-8403-4b50-8c62-7cc567fe7897"
  "flitedx-bucket-25a33c2e-3818-43b8-893e-406e43754c9c"
  "petool-bucket-732bbde0-45e8-4c4e-84ba-a8ad6f008247"
  "iceberg-test-9f7186e9-cb3e-4f63-8f54-1b3972070dbf"
)

for bucket in "${EMPTY_BUCKETS[@]}"; do
  echo "Deleting empty bucket: $bucket"
  if radosgw-admin bucket rm --bucket="$bucket" 2>/dev/null; then
    echo "  ✓ Deleted"
  else
    echo "  ✗ Failed or already deleted"
  fi
done

echo ""

# Step 2: Skip NooBaa bucket (contains metadata - DO NOT DELETE)
echo "=== Step 2: NooBaa Bucket (Skipping) ==="
echo "Bucket: $NOOBAA_BUCKET"
echo "  ⚠️  SKIPPED - Contains NooBaa metadata (required for operation)"
echo "  Size: ~517 GiB (cannot be deleted)"
echo ""

# Step 3: Delete old objects from Loki bucket using the dedicated script
echo "=== Step 3: Deleting Objects Older Than $DAYS_TO_KEEP Days from Loki Bucket ==="
echo "Bucket: $LOKI_BUCKET"
echo "This may take a while (3.5M objects)..."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -f "$SCRIPT_DIR/delete-objects-by-date.sh" ]; then
  "$SCRIPT_DIR/delete-objects-by-date.sh" "$LOKI_BUCKET" "$DAYS_TO_KEEP"
else
  echo "Error: delete-objects-by-date.sh not found in $SCRIPT_DIR"
  echo "Please run delete-objects-by-date.sh manually:"
  echo "  ./delete-objects-by-date.sh $LOKI_BUCKET $DAYS_TO_KEEP"
fi

echo ""

# Step 4: Verify results
echo "=== Step 4: Verifying Results ==="
echo "Remaining buckets:"
BUCKET_COUNT=$(radosgw-admin bucket list 2>/dev/null | jq -r '.[] | .bucket' | wc -l | tr -d ' ')
echo "  Total buckets: $BUCKET_COUNT"

echo ""
echo "Loki bucket remaining size:"
LOKI_STATS=$(radosgw-admin bucket stats --bucket="$LOKI_BUCKET" 2>/dev/null)
if [ -n "$LOKI_STATS" ]; then
  LOKI_SIZE=$(echo "$LOKI_STATS" | jq -r '(.usage.rgw.main.size_kb // 0)')
  LOKI_OBJECTS=$(echo "$LOKI_STATS" | jq -r '(.usage.rgw.main.num_objects // 0)')
  if [ "$LOKI_SIZE" != "0" ] && [ -n "$LOKI_SIZE" ]; then
    echo "  Size: $(echo "$LOKI_SIZE" | awk '{printf "%.2f GB\n", $1/1024/1024}')"
    echo "  Objects: $LOKI_OBJECTS"
  else
    echo "  Bucket empty or no usage data"
  fi
else
  echo "  Bucket deleted or not found"
fi

echo ""
echo "=== Cluster Space ==="
ceph $CEPH_ARGS df | grep -E "TOTAL|AVAIL"

echo ""
echo "=== OSD Usage (checking for nearfull) ==="
ceph $CEPH_ARGS osd df | awk 'NR==1 || $7 > 80 {print}'

echo ""
echo "=== Cleanup Complete ==="
