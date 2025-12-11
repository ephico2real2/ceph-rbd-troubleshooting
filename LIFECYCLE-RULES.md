# RGW Lifecycle Rules - Automatic Object Expiration

## Check Existing Lifecycle Rules
```bash
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
radosgw-admin lc get --bucket="$BUCKET"
```

## Create Lifecycle Rule to Delete Objects Older Than X Days

### Method 1: Delete ALL objects older than X days (no tag filter)
```bash
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
DAYS_OLD=90

# Create LC rule JSON
cat > /tmp/lc_rule.json << EOF
{
  "rule_map": [
    {
      "id": "Delete objects older than ${DAYS_OLD} days",
      "rule": {
        "id": "Delete objects older than ${DAYS_OLD} days",
        "prefix": "",
        "status": "Enabled",
        "expiration": {
          "days": "${DAYS_OLD}",
          "date": ""
        },
        "filter": {
          "prefix": "",
          "obj_tags": {}
        },
        "transitions": {},
        "noncur_transitions": {},
        "dm_expiration": false
      }
    }
  ]
}
EOF

# Apply the rule
radosgw-admin lc set --bucket="$BUCKET" --lc-config=/tmp/lc_rule.json
```

### Method 2: Delete objects with specific tag older than X days
```bash
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
DAYS_OLD=90
TAG_KEY="processed"
TAG_VALUE="true"

cat > /tmp/lc_rule.json << EOF
{
  "rule_map": [
    {
      "id": "Delete ${TAG_KEY}=${TAG_VALUE} objects older than ${DAYS_OLD} days",
      "rule": {
        "id": "Delete ${TAG_KEY}=${TAG_VALUE} objects older than ${DAYS_OLD} days",
        "prefix": "",
        "status": "Enabled",
        "expiration": {
          "days": "${DAYS_OLD}",
          "date": ""
        },
        "filter": {
          "prefix": "",
          "obj_tags": {
            "tagset": {
              "${TAG_KEY}": "${TAG_VALUE}"
            }
          }
        },
        "transitions": {},
        "noncur_transitions": {},
        "dm_expiration": false
      }
    }
  ]
}
EOF

radosgw-admin lc set --bucket="$BUCKET" --lc-config=/tmp/lc_rule.json
```

## Process Lifecycle Rules Manually (Run Immediately)
```bash
# Process LC rules for a specific bucket
radosgw-admin lc process --bucket="$BUCKET"

# Process LC rules for all buckets
radosgw-admin lc process
```

## Check LC Processing Status
```bash
# List buckets with LC rules
radosgw-admin lc list

# Get LC status for specific bucket
radosgw-admin lc get --bucket="$BUCKET"
```

## Remove Lifecycle Rule
```bash
# Remove all LC rules from bucket
radosgw-admin lc rm --bucket="$BUCKET"

# Verify rules are removed
radosgw-admin lc get --bucket="$BUCKET"
```

## Delete a Bucket

### Check Bucket Before Deletion
```bash
BUCKET="bucket-name-to-delete"

# Check bucket stats
radosgw-admin bucket stats --bucket="$BUCKET"

# List objects in bucket
radosgw-admin bucket list --bucket="$BUCKET" --max-entries=10

# Get object count
radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq 'length'
```

### Delete Empty Bucket
```bash
BUCKET="bucket-name-to-delete"

# Delete empty bucket
radosgw-admin bucket rm --bucket="$BUCKET"

# Verify deletion
radosgw-admin bucket list | jq -r '.[] | .bucket' | grep -q "^${BUCKET}$" && echo "Still exists" || echo "Deleted"
```

### Delete Bucket with All Objects
```bash
BUCKET="bucket-name-to-delete"

# Delete bucket and all its objects
radosgw-admin bucket rm --bucket="$BUCKET" --purge-objects

# Verify deletion
radosgw-admin bucket list | jq -r '.[] | .bucket' | grep -q "^${BUCKET}$" && echo "Still exists" || echo "Deleted"
```

### Delete Bucket with Objects (Bypass GC)
```bash
BUCKET="bucket-name-to-delete"

# Delete bucket, purge objects, and bypass garbage collection (faster but less safe)
radosgw-admin bucket rm --bucket="$BUCKET" --purge-objects --bypass-gc
```

### Step-by-Step: Safe Bucket Deletion
```bash
BUCKET="bucket-name-to-delete"

# Step 1: Check what's in the bucket
echo "=== Bucket Stats ==="
radosgw-admin bucket stats --bucket="$BUCKET" | jq '{bucket, owner, usage}'

# Step 2: List some objects
echo ""
echo "=== Sample Objects ==="
radosgw-admin bucket list --bucket="$BUCKET" --max-entries=5 | jq -r '.[] | .name'

# Step 3: Get total object count
TOTAL=$(radosgw-admin bucket list --bucket="$BUCKET" 2>/dev/null | jq 'length')
echo ""
echo "Total objects: $TOTAL"

# Step 4: Delete bucket (with objects)
echo ""
echo "Deleting bucket and all objects..."
radosgw-admin bucket rm --bucket="$BUCKET" --purge-objects

# Step 5: Verify
echo ""
echo "=== Verification ==="
radosgw-admin bucket list | jq -r '.[] | .bucket' | grep -q "^${BUCKET}$" && \
  echo "ERROR: Bucket still exists!" || \
  echo "SUCCESS: Bucket deleted"
```

## Example: Delete Loki Objects Older Than 90 Days
```bash
BUCKET="lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
DAYS=90

# Create rule
cat > /tmp/loki_lc.json << EOF
{
  "rule_map": [
    {
      "id": "Delete Loki objects older than ${DAYS} days",
      "rule": {
        "id": "Delete Loki objects older than ${DAYS} days",
        "prefix": "",
        "status": "Enabled",
        "expiration": {
          "days": "${DAYS}",
          "date": ""
        },
        "filter": {
          "prefix": "",
          "obj_tags": {}
        },
        "transitions": {},
        "noncur_transitions": {},
        "dm_expiration": false
      }
    }
  ]
}
EOF

# Apply rule
radosgw-admin lc set --bucket="$BUCKET" --lc-config=/tmp/loki_lc.json

# Process immediately (or wait for automatic processing)
radosgw-admin lc process --bucket="$BUCKET"
```

## Check What Will Be Deleted (Dry Run)
```bash
# LC rules process automatically, but you can check the rule
radosgw-admin lc get --bucket="$BUCKET" | jq '.rule_map[] | {id, expiration}'
```

## Schedule Automatic Processing
```bash
# LC rules are processed automatically by RGW, but you can trigger manually
# Check LC processing interval in ceph config:
ceph config get client.rgw.* rgw_lc_debug_interval
```
