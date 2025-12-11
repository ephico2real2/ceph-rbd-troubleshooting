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
