# Quick Bucket Commands - FIXED (mtime issue)

## Setup
```bash
export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
DAYS_OLD=90
```

## Step 1: Check What Fields Are Available
```bash
# First, check what fields bucket list returns
radosgw-admin bucket list --bucket="$BUCKET" --max-entries=1 2>/dev/null | jq '.[0] | keys'
echo ""
# Check if mtime exists
radosgw-admin bucket list --bucket="$BUCKET" --max-entries=1 2>/dev/null | jq '.[0] | {name, mtime, mtime_utc, mtime_local}'
```

## Step 2: Get Objects Older Than X Days (Method 1 - if mtime in bucket list)
```bash
CUTOFF=$(date -u -d "$DAYS_OLD days ago" +%s)
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | \
  jq -r --arg cutoff "$CUTOFF" '
    .[] | 
    (.mtime // .mtime_utc // "") as $mtime |
    if $mtime != "" then
      ($mtime | split(".")[0] | strptime("%Y-%m-%dT%H:%M:%S") | mktime) as $mtime_ts |
      if $mtime_ts < ($cutoff | tonumber) then .name else empty end
    else
      empty
    end
  ' > /tmp/old_objects.txt

OLD_COUNT=$(wc -l < /tmp/old_objects.txt | tr -d ' ')
echo "Found $OLD_COUNT objects older than $DAYS_OLD days"
```

## Step 2 Alternative: If mtime NOT in bucket list (use object metadata)
```bash
CUTOFF=$(date -u -d "$DAYS_OLD days ago" +%s)
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq -r '.[] | .name' | \
  while read obj; do
    # Try multiple ways to get mtime
    MTIME=$(radosgw-admin object stat --bucket="$BUCKET" --object="$obj" 2>/dev/null | \
      jq -r '.attrs."user.rgw.mtime" // .attrs."user.rgw.source_mtime" // .attrs."user.rgw.x-amz-meta-mtime" // empty')
    
    # If still no mtime, we can't determine age - skip or use a different strategy
    if [ -z "$MTIME" ]; then
      # Option: Skip objects without mtime, or include all (you decide)
      continue
    fi
    
    # Convert to timestamp
    MTIME_TS=$(date -u -d "$MTIME" +%s 2>/dev/null || echo "0")
    if [ "$MTIME_TS" != "0" ] && [ "$MTIME_TS" -lt "$CUTOFF" ]; then
      echo "$obj"
    fi
  done > /tmp/old_objects.txt

OLD_COUNT=$(wc -l < /tmp/old_objects.txt | tr -d ' ')
echo "Found $OLD_COUNT objects older than $DAYS_OLD days"
```

## Step 2 Alternative: Use Object Name Pattern (if objects have date in name)
```bash
# If object names contain dates (e.g., "2024-01-15/..."), extract from name
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

## Step 3: Preview
```bash
head -10 /tmp/old_objects.txt
```

## Step 4: Delete Objects
```bash
DELETED=0
while read obj; do
  if radosgw-admin object rm --bucket="$BUCKET" --object="$obj" >/dev/null 2>&1; then
    DELETED=$((DELETED + 1))
    [ $((DELETED % 1000)) -eq 0 ] && echo "Deleted $DELETED..."
  fi
done < /tmp/old_objects.txt
echo "Total deleted: $DELETED"
```
