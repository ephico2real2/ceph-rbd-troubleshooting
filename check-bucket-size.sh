#!/bin/bash
# Check bucket size and usage - handles null values properly
# Usage: ./check-bucket-size.sh [bucket-name]

set -e

export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'

BUCKET_NAME="${1:-}"

if [ -z "$BUCKET_NAME" ]; then
    echo "=== All Buckets Usage ==="
    echo ""
    radosgw-admin bucket stats 2>/dev/null | \
      jq -r '.[] | 
        (.usage.rgw.main // {}) as $usage |
        "Bucket: \(.bucket)
Owner: \(.owner)
Size: \((($usage.size_kb // 0) / 1024 / 1024) | floor) GB (\(((($usage.size_kb // 0) / 1024 / 1024 / 1024)) | floor) TB)
Objects: \($usage.num_objects // 0)
---"'
else
    echo "=== Bucket Details: $BUCKET_NAME ==="
    echo ""
    
    BUCKET_STATS=$(radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null)
    
    if [ -z "$BUCKET_STATS" ]; then
        echo "Error: Bucket not found"
        exit 1
    fi
    
    echo "$BUCKET_STATS" | jq -r '
        (.usage.rgw.main // {}) as $usage |
        "Bucket: \(.bucket)
Owner: \(.owner)
Creation: \(.creation_time)
Last Modified: \(.mtime)

Usage:
  Size: \((($usage.size_kb // 0) / 1024 / 1024) | floor) GB (\(((($usage.size_kb // 0) / 1024 / 1024 / 1024)) | floor) TB)
  Size Actual: \((($usage.size_kb_actual // 0) / 1024 / 1024) | floor) GB
  Objects: \($usage.num_objects // 0)
  Shards: \(.num_shards // "N/A")"
    '
    
    # If usage shows 0, check if bucket actually has objects
    USAGE_SIZE=$(echo "$BUCKET_STATS" | jq -r '(.usage.rgw.main.size_kb // 0)')
    if [ "$USAGE_SIZE" = "0" ] || [ -z "$USAGE_SIZE" ] || [ "$USAGE_SIZE" = "null" ]; then
        echo ""
        echo "⚠️  Warning: Usage shows 0 KB. Checking if bucket has objects..."
        OBJECT_COUNT=$(radosgw-admin bucket list --bucket="$BUCKET_NAME" --max-entries=1 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
        if [ "$OBJECT_COUNT" != "0" ] && [ -n "$OBJECT_COUNT" ]; then
            echo "  → Bucket appears to have objects but usage stats show 0 KB"
            echo "  → This may indicate:"
            echo "    1. Usage stats haven't been updated yet"
            echo "    2. Objects exist but are not counted in usage"
            echo "    3. Run 'debug-bucket-stats.sh $BUCKET_NAME' for detailed analysis"
        else
            echo "  → Bucket appears to be empty (no objects found)"
        fi
    fi
fi
