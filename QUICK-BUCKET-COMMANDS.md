# Quick Bucket Commands - Copy & Paste

## Setup
```bash
export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
```

## Step 1: Get Total Object Count
```bash
# Count all objects (may take time for large buckets)
TOTAL_OBJECTS=$(radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq 'length')
echo "Total objects: $TOTAL_OBJECTS"
```

## Step 2: Get Objects Older Than X Days & Save to File
```bash
# Set days threshold
DAYS_OLD=90
CUTOFF=$(date -u -d "$DAYS_OLD days ago" +%s)

# Get list of old objects and save directly to file (more efficient)
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq -r '.[] | .name' | \
  while read obj; do
    MTIME=$(radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | \
      jq -r '.mtime' | cut -d'.' -f1)
    MTIME_TS=$(date -u -d "$MTIME" +%s 2>/dev/null)
    if [ -n "$MTIME_TS" ] && [ "$MTIME_TS" -lt "$CUTOFF" ]; then
      echo "$obj"
    fi
  done > /tmp/old_objects.txt

# Count old objects
OLD_COUNT=$(wc -l < /tmp/old_objects.txt | tr -d ' ')
echo "Found $OLD_COUNT objects older than $DAYS_OLD days"
```

## Step 3: Verify File Contents
```bash
# Check file was created and has content
echo "File size: $(wc -l < /tmp/old_objects.txt | tr -d ' ') objects"
```

## Step 4: Preview First 10 Objects
```bash
echo "First 10 objects to delete:"
head -10 /tmp/old_objects.txt
```

## Step 5: Delete Objects (DRY RUN - shows what would be deleted)
```bash
# Dry run - just count
echo "Would delete $(wc -l < /tmp/old_objects.txt | tr -d ' ') objects"
```

## Step 6: Delete Objects (ACTUAL DELETION)
```bash
# Delete all objects from file
DELETED=0
while read obj; do
  if radosgw-admin object rm --bucket="$BUCKET" --object="$obj" >/dev/null 2>&1; then
    DELETED=$((DELETED + 1))
    if [ $((DELETED % 1000)) -eq 0 ]; then
      echo "Deleted $DELETED objects..."
    fi
  fi
done < /tmp/old_objects.txt
echo "Total deleted: $DELETED"
```

## Step 7: Delete in Batches (safer, with progress)
```bash
# Delete first 1000 objects
DELETED=0
head -1000 /tmp/old_objects.txt | while read obj; do
  radosgw-admin object rm --bucket="$BUCKET" --object="$obj" >/dev/null 2>&1 && \
    DELETED=$((DELETED + 1)) && \
    [ $((DELETED % 100)) -eq 0 ] && echo "Deleted $DELETED..."
done
```

## Quick One-Liners

### Count objects by date range
```bash
# Objects older than 90 days
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq -r '.[] | .name' | \
  while read obj; do
    MTIME=$(radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | jq -r '.mtime' | cut -d'.' -f1)
    MTIME_TS=$(date -u -d "$MTIME" +%s 2>/dev/null)
    CUTOFF=$(date -u -d "90 days ago" +%s)
    [ -n "$MTIME_TS" ] && [ "$MTIME_TS" -lt "$CUTOFF" ] && echo "$obj"
  done | wc -l
```

### Get objects from specific date range
```bash
# Objects between 90-180 days old
START=$(date -u -d "180 days ago" +%s)
END=$(date -u -d "90 days ago" +%s)
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq -r '.[] | .name' | \
  while read obj; do
    MTIME=$(radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | jq -r '.mtime' | cut -d'.' -f1)
    MTIME_TS=$(date -u -d "$MTIME" +%s 2>/dev/null)
    [ -n "$MTIME_TS" ] && [ "$MTIME_TS" -ge "$START" ] && [ "$MTIME_TS" -lt "$END" ] && echo "$obj"
  done > /tmp/objects_90_180_days.txt
```

### Delete objects from file
```bash
# Delete all objects in file
cat /tmp/old_objects.txt | xargs -I {} -P 10 radosgw-admin object rm --bucket="$BUCKET" --object="{}" 2>/dev/null
```

## Check Bucket Size After Deletion
```bash
# Get current size
radosgw-admin bucket stats --bucket="$BUCKET" 2>/dev/null | \
  jq -r '(.usage.rgw.main.size_kb // .usage.rgw.size_kb // .usage.size_kb // 0) / 1024 / 1024 | floor'
echo "GB"
```
