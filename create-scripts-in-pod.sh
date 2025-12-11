=== Commands to create radosgw-admin scripts in pod ===

Copy and paste these commands into the pod:

# Create check-bucket-size.sh
cat > /tmp/check-bucket-size.sh << 'ENDOFFILE'
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
ENDOFFILE
chmod +x /tmp/check-bucket-size.sh

# Create inspect-bucket-json.sh
cat > /tmp/inspect-bucket-json.sh << 'ENDOFFILE'
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
ENDOFFILE
chmod +x /tmp/inspect-bucket-json.sh

# Create delete-objects-by-date.sh
cat > /tmp/delete-objects-by-date.sh << 'ENDOFFILE'
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
ENDOFFILE
chmod +x /tmp/delete-objects-by-date.sh

# Create cleanup-buckets-by-date.sh
cat > /tmp/cleanup-buckets-by-date.sh << 'ENDOFFILE'
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

# Step 1: Delete empty buckets (if any)
echo "=== Step 1: Checking for Empty Buckets ==="
echo "Note: Empty buckets should be identified and deleted manually as needed"
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
  LOKI_SIZE=$(echo "$LOKI_STATS" | jq -r '(.usage.rgw.main // {} | .size_kb // 0)')
  LOKI_OBJECTS=$(echo "$LOKI_STATS" | jq -r '(.usage.rgw.main // {} | .num_objects // 0)')
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
ENDOFFILE
chmod +x /tmp/cleanup-buckets-by-date.sh

=== All scripts created in /tmp/ ===
You can now run them with: /tmp/script-name.sh
