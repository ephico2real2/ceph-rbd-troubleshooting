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
        (.usage.rgw.main // .usage.rgw // .usage // {}) as $usage |
        (.size_kb // $usage.size_kb // 0) as $size_kb |
        (.num_objects // $usage.num_objects // 0) as $num_objects |
        "Bucket: \(.bucket)
Owner: \(.owner)
Size: \((($size_kb / 1024 / 1024) | floor) GB (\(((($size_kb / 1024 / 1024 / 1024)) | floor) TB)
Objects: \($num_objects)
---"'
else
    echo "=== Bucket Details: $BUCKET_NAME ==="
    echo ""
    
    BUCKET_STATS=$(radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null)
    
    if [ -z "$BUCKET_STATS" ]; then
        echo "Error: Bucket not found"
        exit 1
    fi
    
    # Try multiple possible paths for usage data
    echo "$BUCKET_STATS" | jq -r '
        # Try .usage.rgw.main first, then .usage, then look for size_kb anywhere
        (.usage.rgw.main // .usage.rgw // .usage // {}) as $usage |
        # Also check if size_kb exists at root level
        (.size_kb // $usage.size_kb // 0) as $size_kb |
        (.num_objects // $usage.num_objects // 0) as $num_objects |
        
        "Bucket: \(.bucket)
Owner: \(.owner)
Creation: \(.creation_time)
Last Modified: \(.mtime)

Usage:
  Size: \((($size_kb / 1024 / 1024) | floor) GB (\((($size_kb / 1024 / 1024 / 1024) | floor) TB)
  Size Actual: \((($usage.size_kb_actual // 0) / 1024 / 1024) | floor) GB
  Objects: \($num_objects)
  Shards: \(.num_shards // "N/A")"
    '
    
    # Verify the data - check actual object count
    echo ""
    echo "=== Verification ==="
    ACTUAL_OBJECTS=$(radosgw-admin bucket list --bucket="$BUCKET_NAME" --max-entries=1000 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    if [ "$ACTUAL_OBJECTS" != "0" ] && [ -n "$ACTUAL_OBJECTS" ]; then
        echo "Objects found via bucket list: $ACTUAL_OBJECTS (showing first 1000)"
        echo "Note: If this is less than reported, bucket may have more objects"
    fi
fi
