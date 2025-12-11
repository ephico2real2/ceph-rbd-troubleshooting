#!/bin/bash
# Delete objects from RGW bucket older than specified days
# Usage: ./delete-objects-by-date.sh <bucket-name> <days-old> [dry-run]

set -e

BUCKET_NAME="$1"
DAYS_OLD="${2:-90}"  # Default: 90 days
DRY_RUN="${3:-false}"

if [ -z "$BUCKET_NAME" ]; then
    echo "Usage: $0 <bucket-name> <days-old> [dry-run]"
    echo ""
    echo "Examples:"
    echo "  $0 lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 90"
    echo "  $0 lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 30 dry-run"
    exit 1
fi

export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'

# Calculate cutoff date
CUTOFF_DATE=$(date -u -d "$DAYS_OLD days ago" +%Y-%m-%dT%H:%M:%S)
CUTOFF_TIMESTAMP=$(date -u -d "$DAYS_OLD days ago" +%s)

echo "=== Delete Objects by Date ==="
echo "Bucket: $BUCKET_NAME"
echo "Days to keep: $DAYS_OLD"
echo "Cutoff date: $CUTOFF_DATE"
echo "Mode: $([ "$DRY_RUN" = "dry-run" ] && echo "DRY RUN (no deletion)" || echo "LIVE (will delete)")"
echo ""

# Verify bucket exists
if ! radosgw-admin bucket stats --bucket="$BUCKET_NAME" >/dev/null 2>&1; then
    echo "Error: Bucket '$BUCKET_NAME' not found"
    exit 1
fi

# Get initial bucket stats
INITIAL_SIZE=$(radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | \
  jq -r '(.usage.rgw.main // {} | .size_kb // 0)')
INITIAL_OBJECTS=$(radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | \
  jq -r '(.usage.rgw.main // {} | .num_objects // 0)')

echo "Initial bucket stats:"
echo "  Size: $(echo "$INITIAL_SIZE" | awk '{printf "%.2f GB\n", $1/1024/1024}')"
echo "  Objects: $INITIAL_OBJECTS"
echo ""

# Count objects to delete first
echo "Scanning objects to identify candidates for deletion..."
CANDIDATES=0
PROCESSED=0

# Create temp file for objects to delete
TEMP_DELETE_LIST=$(mktemp)

radosgw-admin bucket list --bucket="$BUCKET_NAME" 2>/dev/null | \
  jq -r '.[] | .name' | \
  while read -r object_name; do
    PROCESSED=$((PROCESSED + 1))
    
    # Progress indicator
    if [ $((PROCESSED % 10000)) -eq 0 ]; then
      echo "  Scanned $PROCESSED objects, found $CANDIDATES candidates..."
    fi
    
    # Get object metadata
    OBJECT_INFO=$(radosgw-admin object stat --bucket="$BUCKET_NAME" --object="$object_name" 2>/dev/null)
    
    if [ -z "$OBJECT_INFO" ]; then
      continue
    fi
    
    # Extract and convert mtime to timestamp
    MTIME_STR=$(echo "$OBJECT_INFO" | jq -r '.mtime' | cut -d'.' -f1)
    MTIME_TS=$(date -u -d "$MTIME_STR" +%s 2>/dev/null)
    
    if [ -n "$MTIME_TS" ] && [ "$MTIME_TS" -lt "$CUTOFF_TIMESTAMP" ]; then
      echo "$object_name|$MTIME_STR" >> "$TEMP_DELETE_LIST"
      CANDIDATES=$((CANDIDATES + 1))
    fi
  done

TOTAL_CANDIDATES=$(wc -l < "$TEMP_DELETE_LIST" | tr -d ' ')
echo ""
echo "Scan complete:"
echo "  Total objects scanned: $PROCESSED"
echo "  Objects to delete: $TOTAL_CANDIDATES"
echo ""

if [ "$TOTAL_CANDIDATES" -eq 0 ]; then
    echo "No objects found older than $DAYS_OLD days. Nothing to delete."
    rm -f "$TEMP_DELETE_LIST"
    exit 0
fi

# Confirm deletion
if [ "$DRY_RUN" != "dry-run" ]; then
    echo "WARNING: This will delete $TOTAL_CANDIDATES objects!"
    echo "Press Ctrl+C to cancel, or wait 10 seconds to proceed..."
    sleep 10
fi

# Delete objects
echo ""
echo "=== Starting Deletion ==="
DELETED=0
ERRORS=0
BATCH=0

while IFS='|' read -r object_name mtime_str; do
    BATCH=$((BATCH + 1))
    
    if [ "$DRY_RUN" = "dry-run" ]; then
        echo "[DRY RUN] Would delete: $object_name (mtime: $mtime_str)"
        DELETED=$((DELETED + 1))
    else
        if radosgw-admin object rm --bucket="$BUCKET_NAME" --object="$object_name" >/dev/null 2>&1; then
            DELETED=$((DELETED + 1))
            
            # Progress indicator
            if [ $((DELETED % 1000)) -eq 0 ]; then
                echo "Progress: Deleted $DELETED/$TOTAL_CANDIDATES objects..."
            fi
        else
            ERRORS=$((ERRORS + 1))
            echo "Error deleting: $object_name" >&2
        fi
    fi
done < "$TEMP_DELETE_LIST"

rm -f "$TEMP_DELETE_LIST"

echo ""
echo "=== Deletion Summary ==="
echo "Objects processed: $PROCESSED"
echo "Objects deleted: $DELETED"
echo "Errors: $ERRORS"

if [ "$DRY_RUN" != "dry-run" ] && [ "$DELETED" -gt 0 ]; then
    echo ""
    echo "=== Final Bucket Stats ==="
    FINAL_SIZE=$(radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | \
      jq -r '(.usage.rgw.main // {} | .size_kb // 0)')
    FINAL_OBJECTS=$(radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | \
      jq -r '(.usage.rgw.main // {} | .num_objects // 0)')
    
    SIZE_FREED=$(echo "$INITIAL_SIZE $FINAL_SIZE" | awk '{printf "%.2f GB\n", ($1-$2)/1024/1024}')
    
    echo "Final size: $(echo "$FINAL_SIZE" | awk '{printf "%.2f GB\n", $1/1024/1024}')"
    echo "Final objects: $FINAL_OBJECTS"
    echo "Space freed: $SIZE_FREED"
fi
