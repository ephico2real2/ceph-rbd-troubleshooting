# RGW Bucket Cleanup Guide

This guide provides recommendations and commands for cleaning up RGW (RADOS Gateway) buckets to free up storage space in your Ceph cluster.

## Current Bucket Analysis

### Large Buckets Requiring Cleanup

1. **`lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7`**
   - **Size**: ~5.4 TiB (5,920,860,728,461 bytes)
   - **Objects**: 3,517,443 objects
   - **Owner**: openshift-logging (Loki logs)
   - **Status**: Contains logging data - verify before deletion
   - **Recommendation**: Delete objects older than 30-90 days

2. **`nb.1678954504655.apps.kcs-pre-ewd.k8s.boeing.com`**
   - **Size**: ~517 GiB (555,461,776,756 bytes)
   - **Objects**: 172,522 objects
   - **Owner**: noobaa-ceph-objectstore-user
   - **Status**: **DO NOT DELETE** - Contains NooBaa metadata
   - **Recommendation**: **Exclude from cleanup** - Required for NooBaa operation

3. **Empty Buckets** (usage: {})
   - `dell-program-tool-43b6ff39-5d10-4b17-822a-3e3e5febd2af`
   - `flight-data-bucket-e132979a-8403-4b50-8c62-7cc567fe7897`
   - `flitedx-bucket-25a33c2e-3818-43b8-893e-406e43754c9c`
   - `petool-bucket-732bbde0-45e8-4c4e-84ba-a8ad6f008247`
   - `iceberg-test-9f7186e9-cb3e-4f63-8f54-1b3972070dbf`
   - **Recommendation**: Safe to delete entirely

## Expected Space Recovery

- Loki bucket cleanup: **~5.4 TiB** (if all deleted) or **~2-3 TiB** (if old objects only)
- ~~NooBaa bucket cleanup: **~517 GiB**~~ **DO NOT DELETE** - Contains NooBaa metadata
- Empty buckets: Minimal (already empty)
- **Total potential recovery: ~2-5.4 TiB** (depending on Loki retention policy)

## Step-by-Step Cleanup Process

### Step 1: Verify Bucket Contents (Safety Check)

```bash
# Set CEPH_ARGS
export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'

# Check Loki bucket details
echo "=== Loki Bucket Details ==="
radosgw-admin bucket stats --bucket=lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 | \
  jq -r '.usage.rgw.main | "Size: \(.size_kb) KB (\(.size_kb/1024/1024) GB)\nObjects: \(.num_objects)"'

# Check NooBaa bucket details
echo ""
echo "=== NooBaa Bucket Details ==="
radosgw-admin bucket stats --bucket=nb.1678954504655.apps.kcs-pre-ewd.k8s.boeing.com | \
  jq -r '.usage.rgw.main | "Size: \(.size_kb) KB (\(.size_kb/1024/1024) GB)\nObjects: \(.num_objects)"'

# Sample objects from Loki bucket (check dates)
echo ""
echo "=== Sample Objects from Loki Bucket ==="
radosgw-admin bucket list --bucket=lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 --max-entries=10
```

### Step 2: Delete Objects by Date

#### Method 1: Delete Objects Older Than X Days (Recommended)

```bash
#!/bin/bash
# Delete objects older than specified days from a bucket
# Usage: ./delete-objects-by-date.sh <bucket-name> <days-old>

BUCKET_NAME="$1"
DAYS_OLD="${2:-90}"  # Default: 90 days
CUTOFF_DATE=$(date -u -d "$DAYS_OLD days ago" +%Y-%m-%dT%H:%M:%S)

if [ -z "$BUCKET_NAME" ]; then
    echo "Usage: $0 <bucket-name> [days-old]"
    echo "Example: $0 lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 90"
    exit 1
fi

echo "=== Deleting objects older than $DAYS_OLD days from bucket: $BUCKET_NAME ==="
echo "Cutoff date: $CUTOFF_DATE"
echo ""

# List all objects and check their modification time
DELETED=0
TOTAL=0

radosgw-admin bucket list --bucket="$BUCKET_NAME" | \
  jq -r '.[] | .name' | \
  while read -r object_name; do
    TOTAL=$((TOTAL + 1))
    
    # Get object metadata
    OBJECT_INFO=$(radosgw-admin object stat --bucket="$BUCKET_NAME" --object="$object_name" 2>/dev/null)
    
    if [ -n "$OBJECT_INFO" ]; then
      MTIME=$(echo "$OBJECT_INFO" | jq -r '.mtime' | cut -d'.' -f1)
      
      # Compare dates
      if [ "$MTIME" \< "$CUTOFF_DATE" ]; then
        echo "Deleting: $object_name (mtime: $MTIME)"
        radosgw-admin object rm --bucket="$BUCKET_NAME" --object="$object_name" 2>/dev/null
        DELETED=$((DELETED + 1))
        
        # Progress indicator
        if [ $((DELETED % 100)) -eq 0 ]; then
          echo "Progress: Deleted $DELETED objects..."
        fi
      fi
    fi
  done

echo ""
echo "=== Summary ==="
echo "Total objects processed: $TOTAL"
echo "Objects deleted: $DELETED"
```

#### Method 2: Delete Objects by Date Range (More Precise)

```bash
#!/bin/bash
# Delete objects within a specific date range
# Usage: ./delete-objects-by-date-range.sh <bucket-name> <start-date> <end-date>
# Date format: YYYY-MM-DD

BUCKET_NAME="$1"
START_DATE="$2"
END_DATE="$3"

if [ -z "$BUCKET_NAME" ] || [ -z "$START_DATE" ] || [ -z "$END_DATE" ]; then
    echo "Usage: $0 <bucket-name> <start-date> <end-date>"
    echo "Example: $0 lokistack-objectbucketclai-... 2024-01-01 2024-12-31"
    exit 1
fi

START_TIMESTAMP="${START_DATE}T00:00:00"
END_TIMESTAMP="${END_DATE}T23:59:59"

echo "=== Deleting objects from $START_DATE to $END_DATE ==="
echo "Bucket: $BUCKET_NAME"
echo ""

DELETED=0

radosgw-admin bucket list --bucket="$BUCKET_NAME" | \
  jq -r '.[] | .name' | \
  while read -r object_name; do
    OBJECT_INFO=$(radosgw-admin object stat --bucket="$BUCKET_NAME" --object="$object_name" 2>/dev/null)
    
    if [ -n "$OBJECT_INFO" ]; then
      MTIME=$(echo "$OBJECT_INFO" | jq -r '.mtime' | cut -d'.' -f1)
      
      if [ "$MTIME" \> "$START_TIMESTAMP" ] && [ "$MTIME" \< "$END_TIMESTAMP" ]; then
        echo "Deleting: $object_name (mtime: $MTIME)"
        radosgw-admin object rm --bucket="$BUCKET_NAME" --object="$object_name" 2>/dev/null
        DELETED=$((DELETED + 1))
      fi
    fi
  done

echo "Deleted $DELETED objects"
```

#### Method 3: Quick One-Liner for Old Objects

```bash
# Delete objects older than 90 days from Loki bucket
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
DAYS=90
CUTOFF=$(date -u -d "$DAYS days ago" +%s)

radosgw-admin bucket list --bucket="$BUCKET" | \
  jq -r '.[] | .name' | \
  while read obj; do
    MTIME=$(radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | \
      jq -r '.mtime' | cut -d'.' -f1 | xargs -I {} date -u -d {} +%s)
    if [ "$MTIME" -lt "$CUTOFF" ]; then
      radosgw-admin object rm --bucket="$BUCKET" --object="$obj"
    fi
  done
```

### Step 3: Delete Empty Buckets

```bash
# Delete empty buckets (safe - no data loss)
for bucket in \
  "dell-program-tool-43b6ff39-5d10-4b17-822a-3e3e5febd2af" \
  "flight-data-bucket-e132979a-8403-4b50-8c62-7cc567fe7897" \
  "flitedx-bucket-25a33c2e-3818-43b8-893e-406e43754c9c" \
  "petool-bucket-732bbde0-45e8-4c4e-84ba-a8ad6f008247" \
  "iceberg-test-9f7186e9-cb3e-4f63-8f54-1b3972070dbf"; do
  echo "Deleting empty bucket: $bucket"
  radosgw-admin bucket rm --bucket="$bucket" 2>/dev/null && \
    echo "  ✓ Deleted" || \
    echo "  ✗ Failed or already deleted"
done
```

### Step 4: Delete Entire Buckets (If All Data is Old)

```bash
# WARNING: This deletes the entire bucket and all objects!

# Delete NooBaa bucket (old, likely unused)
radosgw-admin bucket rm \
  --bucket=nb.1678954504655.apps.kcs-pre-ewd.k8s.boeing.com \
  --purge-objects \
  --bypass-gc

# Delete Loki bucket (ONLY if all data is old/unneeded)
# radosgw-admin bucket rm \
#   --bucket=lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 \
#   --purge-objects \
#   --bypass-gc
```

## ⚠️ Important: Buckets That Cannot Be Deleted

### NooBaa Metadata Bucket
- **Bucket**: `nb.1678954504655.apps.kcs-pre-ewd.k8s.boeing.com`
- **Reason**: Contains NooBaa's internal metadata
- **Action**: **DO NOT DELETE** - Will break NooBaa functionality
- **Size**: ~517 GiB (must remain)

## Recommended Cleanup Strategy

### Phase 1: Safe Cleanup (Start Here)

1. **Delete empty buckets** (immediate, safe)
   ```bash
   # Run Step 3 commands above
   ```

2. **~~Delete old NooBaa bucket~~** ⚠️ **DO NOT DELETE**
   - **WARNING**: NooBaa bucket contains metadata required for NooBaa operation
   - **Action**: Exclude from cleanup
   - **Reason**: Deleting this bucket will break NooBaa functionality

### Phase 2: Date-Based Cleanup (Recommended)

1. **Delete Loki objects older than 90 days**
   ```bash
   # Use Method 1 script above
   ./delete-objects-by-date.sh lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 90
   ```
   **Expected recovery: ~2-3 TiB** (depending on log retention)

2. **Or delete objects older than 30 days** (more aggressive)
   ```bash
   ./delete-objects-by-date.sh lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 30
   ```
   **Expected recovery: ~4-5 TiB**

### Phase 3: Verify and Monitor

```bash
# Check remaining bucket sizes
radosgw-admin bucket stats | jq -r '.[] | "\(.bucket): \(.usage.rgw.main.size_kb // 0) KB"'

# Check cluster space
ceph $CEPH_ARGS df

# Check OSD usage
ceph $CEPH_ARGS osd df tree | grep -E "NAME|nearfull|osd.2|osd.0"
```

## Complete Cleanup Script

Save this as `cleanup-buckets-by-date.sh`:

```bash
#!/bin/bash
# Complete bucket cleanup script with date-based deletion
# Run in rook-ceph-operator pod

set -e

export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'

# Configuration
LOKI_BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
NOOBAA_BUCKET="nb.1678954504655.apps.kcs-pre-ewd.k8s.boeing.com"
DAYS_TO_KEEP="${1:-90}"  # Default: keep last 90 days

echo "=== RGW Bucket Cleanup ==="
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
  radosgw-admin bucket rm --bucket="$bucket" 2>/dev/null && \
    echo "  ✓ Deleted" || \
    echo "  ✗ Failed or already deleted"
done

echo ""

# Step 2: Delete old NooBaa bucket
echo "=== Step 2: Deleting Old NooBaa Bucket ==="
echo "Bucket: $NOOBAA_BUCKET"
radosgw-admin bucket rm --bucket="$NOOBAA_BUCKET" --purge-objects --bypass-gc && \
  echo "  ✓ Deleted" || \
  echo "  ✗ Failed or already deleted"

echo ""

# Step 3: Delete old objects from Loki bucket
echo "=== Step 3: Deleting Objects Older Than $DAYS_TO_KEEP Days from Loki Bucket ==="
echo "Bucket: $LOKI_BUCKET"
echo "This may take a while (3.5M objects)..."
echo ""

CUTOFF_DATE=$(date -u -d "$DAYS_TO_KEEP days ago" +%Y-%m-%dT%H:%M:%S)
CUTOFF_TIMESTAMP=$(date -u -d "$DAYS_TO_KEEP days ago" +%s)

echo "Cutoff date: $CUTOFF_DATE"
echo "Starting deletion..."
echo ""

DELETED=0
PROCESSED=0
ERRORS=0

# Process objects in batches
radosgw-admin bucket list --bucket="$LOKI_BUCKET" | \
  jq -r '.[] | .name' | \
  while read -r object_name; do
    PROCESSED=$((PROCESSED + 1))
    
    # Get object metadata
    OBJECT_INFO=$(radosgw-admin object stat --bucket="$LOKI_BUCKET" --object="$object_name" 2>/dev/null)
    
    if [ -z "$OBJECT_INFO" ]; then
      ERRORS=$((ERRORS + 1))
      continue
    fi
    
    # Extract and convert mtime to timestamp
    MTIME_STR=$(echo "$OBJECT_INFO" | jq -r '.mtime' | cut -d'.' -f1)
    MTIME_TS=$(date -u -d "$MTIME_STR" +%s 2>/dev/null)
    
    if [ -n "$MTIME_TS" ] && [ "$MTIME_TS" -lt "$CUTOFF_TIMESTAMP" ]; then
      radosgw-admin object rm --bucket="$LOKI_BUCKET" --object="$object_name" 2>/dev/null && \
        DELETED=$((DELETED + 1)) || \
        ERRORS=$((ERRORS + 1))
      
      # Progress indicator every 1000 objects
      if [ $((PROCESSED % 1000)) -eq 0 ]; then
        echo "Progress: Processed $PROCESSED, Deleted $DELETED, Errors $ERRORS"
      fi
    fi
  done

echo ""
echo "=== Cleanup Summary ==="
echo "Objects processed: $PROCESSED"
echo "Objects deleted: $DELETED"
echo "Errors: $ERRORS"
echo ""

# Step 4: Verify results
echo "=== Step 4: Verifying Results ==="
echo "Remaining buckets:"
radosgw-admin bucket list | jq -r '.[] | .bucket' | wc -l

echo ""
echo "Loki bucket remaining size:"
radosgw-admin bucket stats --bucket="$LOKI_BUCKET" 2>/dev/null | \
  jq -r '.usage.rgw.main.size_kb // 0' | \
  awk '{printf "%.2f GB\n", $1/1024/1024}' || echo "Bucket deleted or empty"

echo ""
echo "Cluster space:"
ceph $CEPH_ARGS df | grep -E "TOTAL|AVAIL"
```

## Usage Examples

### Example 1: Keep Last 90 Days of Logs

```bash
# Run cleanup script keeping last 90 days
./cleanup-buckets-by-date.sh 90
```

### Example 2: Keep Last 30 Days of Logs (More Aggressive)

```bash
# Run cleanup script keeping last 30 days
./cleanup-buckets-by-date.sh 30
```

### Example 3: Manual Date-Based Deletion

```bash
# Delete objects from Loki bucket older than 60 days
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
DAYS=60
CUTOFF=$(date -u -d "$DAYS days ago" +%s)

radosgw-admin bucket list --bucket="$BUCKET" | \
  jq -r '.[] | .name' | \
  head -100 | \
  while read obj; do
    MTIME_STR=$(radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | \
      jq -r '.mtime' | cut -d'.' -f1)
    MTIME_TS=$(date -u -d "$MTIME_STR" +%s 2>/dev/null)
    if [ -n "$MTIME_TS" ] && [ "$MTIME_TS" -lt "$CUTOFF" ]; then
      echo "Deleting: $obj (mtime: $MTIME_STR)"
      radosgw-admin object rm --bucket="$BUCKET" --object="$obj"
    fi
  done
```

## Performance Considerations

### For Large Buckets (3.5M objects)

1. **Process in batches**: Don't process all objects at once
2. **Use parallel processing**: Process multiple objects simultaneously
3. **Monitor progress**: Check cluster health during deletion
4. **Time estimate**: ~3.5M objects may take 4-8 hours

### Optimized Batch Deletion Script

```bash
#!/bin/bash
# Optimized batch deletion with parallel processing
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
DAYS=90
CUTOFF=$(date -u -d "$DAYS days ago" +%s)
BATCH_SIZE=1000
PARALLEL=10

# Create temporary file with objects to delete
TEMP_FILE=$(mktemp)
radosgw-admin bucket list --bucket="$BUCKET" | \
  jq -r '.[] | .name' > "$TEMP_FILE"

TOTAL=$(wc -l < "$TEMP_FILE")
echo "Total objects: $TOTAL"
echo "Processing in batches of $BATCH_SIZE with $PARALLEL parallel operations..."

# Process in batches
split -l $BATCH_SIZE "$TEMP_FILE" /tmp/batch_

for batch in /tmp/batch_*; do
  while read -r obj; do
    MTIME_STR=$(radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | \
      jq -r '.mtime' | cut -d'.' -f1)
    MTIME_TS=$(date -u -d "$MTIME_STR" +%s 2>/dev/null)
    
    if [ -n "$MTIME_TS" ] && [ "$MTIME_TS" -lt "$CUTOFF" ]; then
      radosgw-admin object rm --bucket="$BUCKET" --object="$obj" &
      
      # Limit parallel operations
      if [ $(jobs -r | wc -l) -ge $PARALLEL ]; then
        wait
      fi
    fi
  done < "$batch"
  wait
  echo "Completed batch: $batch"
done

rm -f /tmp/batch_* "$TEMP_FILE"
```

## Monitoring During Cleanup

```bash
# Terminal 1: Watch bucket size decrease
watch -n 30 'radosgw-admin bucket stats --bucket=lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7 | jq -r ".usage.rgw.main.size_kb" | awk "{printf \"%.2f GB\n\", \$1/1024/1024}"'

# Terminal 2: Watch cluster space
watch -n 30 'ceph $CEPH_ARGS df | grep -E "TOTAL|AVAIL"'

# Terminal 3: Watch OSD usage
watch -n 30 'ceph $CEPH_ARGS osd df tree | grep -E "NAME|nearfull|osd.2|osd.0"'
```

## Safety Checklist

Before running cleanup:

- [ ] Verify bucket contents and dates
- [ ] Confirm retention policy requirements
- [ ] Backup critical data if needed
- [ ] Test on a small subset first
- [ ] Monitor cluster health during deletion
- [ ] Have rollback plan if needed

## Troubleshooting

### If deletion is too slow:
- Increase parallel operations
- Process in smaller time windows
- Consider lifecycle policies for future

### If errors occur:
- Check object permissions
- Verify bucket exists
- Check radosgw-admin logs

### If cluster becomes unstable:
- Stop deletion process
- Monitor OSD health
- Resume with smaller batches

## Post-Cleanup Verification

```bash
# Check remaining bucket sizes
echo "=== Remaining Bucket Sizes ==="
radosgw-admin bucket stats | \
  jq -r '.[] | select(.usage.rgw.main.size_kb > 0) | "\(.bucket): \(.usage.rgw.main.size_kb/1024/1024) GB"'

# Check cluster space recovery
echo ""
echo "=== Cluster Space ==="
ceph $CEPH_ARGS df

# Check OSD usage improvement
echo ""
echo "=== OSD Usage ==="
ceph $CEPH_ARGS osd df | awk '$7 > 80 {print}'
```

## Expected Results

After cleanup:
- **Space freed**: ~2-6 TiB (depending on retention period)
- **OSD usage**: Should drop below 85% on nearfull OSDs
- **Cluster health**: "nearfull" warnings should clear
- **Recovery**: Misplaced objects should decrease as space frees up
