#!/bin/bash
# Map RGW buckets to OpenShift namespaces
# Shows which namespaces own which buckets and their usage

set -e

echo "=== Mapping RGW Buckets to OpenShift Namespaces ==="
echo ""

# Get all buckets with their owners
echo "Fetching bucket information..."
BUCKETS_JSON=$(radosgw-admin bucket stats 2>/dev/null)

# Get all ObjectBucketClaims (OBCs) from cluster
echo "Fetching ObjectBucketClaims from cluster..."
ALL_OBCS=$(oc get obc --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')

# Get all ObjectBucketClaim CRDs if available
ALL_OBCS_CRD=$(oc get objectbucketclaims.objectbucket.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')

echo ""
echo "=== Bucket to Namespace Mapping ==="
printf "%-60s %-30s %-50s %-15s %-15s\n" \
    "BUCKET_NAME" "NAMESPACE" "OWNER/OBC_NAME" "SIZE" "OBJECTS"
echo "================================================================================================================================"

# Process each bucket
echo "$BUCKETS_JSON" | jq -r '.[] | 
    (.usage.rgw.main // {}) as $usage |
    "\(.bucket)|\(.owner)|\($usage.size_kb // 0)|\($usage.num_objects // 0)"' | \
while IFS='|' read -r bucket_name owner size_kb num_objects; do
    NAMESPACE="UNKNOWN"
    OBC_NAME=""
    
    # Try to find namespace from ObjectBucketClaim
    # Check if owner matches OBC spec.bucketName or status.bucketName
    if echo "$owner" | grep -q "^obc-"; then
        # Extract potential OBC name from owner
        OBC_PATTERN=$(echo "$owner" | sed 's/^obc-//' | cut -d'-' -f1-5)
        
        # Search in OBCs
        NAMESPACE_INFO=$(echo "$ALL_OBCS" | jq -r --arg bucket "$bucket_name" --arg owner "$owner" '
            .items[] | 
            select(.spec.bucketName == $bucket or .status.bucketName == $bucket or 
                   (.metadata.name | ascii_downcase | contains($owner | ascii_downcase))) |
            "\(.metadata.namespace)|\(.metadata.name)"
        ' | head -1)
        
        if [ -n "$NAMESPACE_INFO" ]; then
            NAMESPACE=$(echo "$NAMESPACE_INFO" | cut -d'|' -f1)
            OBC_NAME=$(echo "$NAMESPACE_INFO" | cut -d'|' -f2)
        else
            # Try CRD version
            NAMESPACE_INFO=$(echo "$ALL_OBCS_CRD" | jq -r --arg bucket "$bucket_name" '
                .items[] | 
                select(.spec.bucketName == $bucket or .status.bucketName == $bucket) |
                "\(.metadata.namespace)|\(.metadata.name)"
            ' | head -1)
            
            if [ -n "$NAMESPACE_INFO" ]; then
                NAMESPACE=$(echo "$NAMESPACE_INFO" | cut -d'|' -f1)
                OBC_NAME=$(echo "$NAMESPACE_INFO" | cut -d'|' -f2)
            fi
        fi
    fi
    
    # Special handling for known patterns
    case "$owner" in
        *openshift-logging*|*lokistack*)
            NAMESPACE="openshift-logging"
            OBC_NAME="lokistack-objectbucketclaim"
            ;;
        *noobaa*)
            NAMESPACE="openshift-storage"  # or check noobaa namespace
            OBC_NAME="noobaa-bucket"
            ;;
    esac
    
    # Format size
    SIZE_GB=$(echo "$size_kb" | awk '{printf "%.2f GB", $1/1024/1024}')
    if [ "$size_kb" = "0" ] || [ -z "$size_kb" ]; then
        SIZE_GB="0 GB"
    fi
    
    printf "%-60s %-30s %-50s %-15s %-15s\n" \
        "$bucket_name" \
        "$NAMESPACE" \
        "${OBC_NAME:-$owner}" \
        "$SIZE_GB" \
        "$num_objects"
done

echo ""
echo "=== Summary by Namespace ==="
echo "$BUCKETS_JSON" | jq -r '.[] | 
    (.usage.rgw.main // {}) as $usage |
    "\(.bucket)|\(.owner)|\($usage.size_kb // 0)"' | \
while IFS='|' read -r bucket owner size_kb; do
    # Determine namespace (simplified logic)
    if echo "$owner" | grep -q "openshift-logging\|lokistack"; then
        echo "openshift-logging|$bucket|$size_kb"
    elif echo "$owner" | grep -q "noobaa"; then
        echo "openshift-storage|$bucket|$size_kb"
    elif echo "$owner" | grep -q "^obc-"; then
        # Try to find namespace
        NS=$(echo "$ALL_OBCS" | jq -r --arg bucket "$bucket" '
            .items[] | 
            select(.spec.bucketName == $bucket or .status.bucketName == $bucket) |
            .metadata.namespace
        ' | head -1)
        echo "${NS:-UNKNOWN}|$bucket|$size_kb"
    else
        echo "UNKNOWN|$bucket|$size_kb"
    fi
done | awk -F'|' '{
    ns=$1; bucket=$2; size=$3;
    total[ns] += size;
    count[ns]++;
    buckets[ns] = buckets[ns] " " bucket
}
END {
    for (ns in total) {
        printf "Namespace: %s\n", ns;
        printf "  Total Size: %.2f GB\n", total[ns]/1024/1024;
        printf "  Bucket Count: %d\n", count[ns];
        printf "  Buckets:%s\n\n", buckets[ns];
    }
}'

echo ""
echo "=== Finding OBCs Manually ==="
echo "If namespace is UNKNOWN, try:"
echo "  oc get obc --all-namespaces | grep -i <bucket-name-pattern>"
echo "  oc get objectbucketclaims --all-namespaces | grep -i <bucket-name-pattern>"
