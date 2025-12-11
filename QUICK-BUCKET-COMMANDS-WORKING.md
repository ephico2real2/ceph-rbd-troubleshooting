# Quick Bucket Commands - WORKING VERSION (mtime from attrs)

## Setup
```bash
export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
DAYS_OLD=90
```

## Step 1: Check Object Attrs for mtime
```bash
# Test one object to see what attrs are available
radosgw-admin bucket list --bucket="$BUCKET" --max-entries=1 2>/dev/null | jq -r '.[0].name' | \
  while read obj; do
    echo "Object: $obj"
    radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | jq '.attrs'
  done
```

## Step 2: Get Objects Older Than X Days (using attrs)
```bash
CUTOFF=$(date -u -d "$DAYS_OLD days ago" +%s)

# Get old objects - check attrs for mtime
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq -r '.[] | .name' | \
  while read obj; do
    # Try multiple attr keys for mtime
    MTIME=$(radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | \
      jq -r '.attrs."user.rgw.mtime" // .attrs."user.rgw.source_mtime" // .attrs."user.rgw.x-amz-meta-mtime" // empty')
    
    if [ -n "$MTIME" ] && [ "$MTIME" != "null" ]; then
      # Convert to timestamp (handle different formats)
      MTIME_TS=$(date -u -d "$MTIME" +%s 2>/dev/null || echo "0")
      if [ "$MTIME_TS" != "0" ] && [ "$MTIME_TS" -lt "$CUTOFF" ]; then
        echo "$obj"
      fi
    fi
  done > /tmp/old_objects.txt

OLD_COUNT=$(wc -l < /tmp/old_objects.txt | tr -d ' ')
echo "Found $OLD_COUNT objects older than $DAYS_OLD days"
```

## Step 2 Alternative: If no mtime in attrs, use object name pattern
```bash
# If objects have date in name (e.g., "2024-01-15/...")
CUTOFF_DATE=$(date -u -d "$DAYS_OLD days ago" +%Y-%m-%d)
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq -r '.[] | .name' | \
  while read obj; do
    # Extract date from object name (adjust pattern as needed)
    OBJ_DATE=$(echo "$obj" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    if [ -n "$OBJ_DATE" ] && [ "$OBJ_DATE" \< "$CUTOFF_DATE" ]; then
      echo "$obj"
    fi
  done > /tmp/old_objects.txt
```

## Step 2 Alternative: Delete ALL objects (if you can't determine age)
```bash
# WARNING: This deletes ALL objects regardless of age
# Only use if you're sure you want to delete everything
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq -r '.[] | .name' > /tmp/all_objects.txt
echo "WARNING: This will delete ALL $(wc -l < /tmp/all_objects.txt | tr -d ' ') objects!"
```

## Step 3: Preview
```bash
head -10 /tmp/old_objects.txt
```

## Step 4: Delete Objects (with progress)
```bash
DELETED=0
TOTAL=$(wc -l < /tmp/old_objects.txt | tr -d ' ')
while read obj; do
  if radosgw-admin object rm --bucket="$BUCKET" --object="$obj" >/dev/null 2>&1; then
    DELETED=$((DELETED + 1))
    if [ $((DELETED % 1000)) -eq 0 ]; then
      echo "Progress: $DELETED/$TOTAL deleted..."
    fi
  fi
done < /tmp/old_objects.txt
echo "Total deleted: $DELETED/$TOTAL"
```

## Step 4: Delete in Small Batches (safer)
```bash
# Delete first 1000 objects
DELETED=0
head -1000 /tmp/old_objects.txt | while read obj; do
  radosgw-admin object rm --bucket="$BUCKET" --object="$obj" >/dev/null 2>&1 && \
    DELETED=$((DELETED + 1)) && \
    [ $((DELETED % 100)) -eq 0 ] && echo "Deleted $DELETED..."
done
# Note: DELETED count won't persist outside subshell, but objects are deleted
```

## Quick: Get Object Count
```bash
TOTAL=$(radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq 'length')
echo "Total objects: $TOTAL"
```
