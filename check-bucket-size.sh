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
  Shards: \(.num_shards)"
    '
fi
