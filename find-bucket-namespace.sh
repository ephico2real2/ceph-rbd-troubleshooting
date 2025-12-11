#!/bin/bash
# Find which namespace owns a specific bucket
# Usage: ./find-bucket-namespace.sh <bucket-name>

set -e

BUCKET_NAME="$1"

if [ -z "$BUCKET_NAME" ]; then
    echo "Usage: $0 <bucket-name>"
    echo ""
    echo "Example:"
    echo "  $0 lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7"
    exit 1
fi

echo "=== Finding Namespace for Bucket: $BUCKET_NAME ==="
echo ""

# Get bucket owner
BUCKET_OWNER=$(radosgw-admin bucket stats --bucket="$BUCKET_NAME" 2>/dev/null | \
  jq -r '.owner // "UNKNOWN"')

echo "Bucket Owner: $BUCKET_OWNER"
echo ""

# Method 1: Search ObjectBucketClaims by bucket name
echo "=== Method 1: Searching ObjectBucketClaims ==="
OBC_MATCH=$(oc get obc --all-namespaces -o json 2>/dev/null | \
  jq -r --arg bucket "$BUCKET_NAME" '
    .items[] | 
    select(.spec.bucketName == $bucket or .status.bucketName == $bucket) |
    "\(.metadata.namespace)|\(.metadata.name)|\(.spec.bucketName // "N/A")|\(.status.bucketName // "N/A")"
  ')

if [ -n "$OBC_MATCH" ]; then
    echo "$OBC_MATCH" | while IFS='|' read -r ns name spec_bucket status_bucket; do
        echo "  Namespace: $ns"
        echo "  OBC Name: $name"
        echo "  Spec Bucket: $spec_bucket"
        echo "  Status Bucket: $status_bucket"
    done
else
    echo "  No OBC found with matching bucket name"
fi

echo ""

# Method 2: Search by owner pattern
echo "=== Method 2: Searching by Owner Pattern ==="
if echo "$BUCKET_OWNER" | grep -q "^obc-"; then
    OWNER_PATTERN=$(echo "$BUCKET_OWNER" | sed 's/^obc-//' | cut -d'-' -f1-3)
    echo "Searching for OBCs matching: $OWNER_PATTERN"
    
    oc get obc --all-namespaces -o json 2>/dev/null | \
      jq -r --arg pattern "$OWNER_PATTERN" '
        .items[] | 
        select(.metadata.name | ascii_downcase | contains($pattern | ascii_downcase)) |
        "\(.metadata.namespace)|\(.metadata.name)"
      ' | while IFS='|' read -r ns name; do
        echo "  Found: $ns/$name"
      done
fi

echo ""

# Method 3: Search ObjectBucket CRD
echo "=== Method 3: Searching ObjectBucket CRD ==="
OB_MATCH=$(oc get objectbucket --all-namespaces -o json 2>/dev/null | \
  jq -r --arg bucket "$BUCKET_NAME" '
    .items[] | 
    select(.spec.endpoint.bucketName == $bucket or .status.bucketName == $bucket) |
    "\(.metadata.namespace)|\(.metadata.name)"
  ' | head -1)

if [ -n "$OB_MATCH" ]; then
    echo "$OB_MATCH" | while IFS='|' read -r ns name; do
        echo "  Namespace: $ns"
        echo "  ObjectBucket: $name"
    done
else
    echo "  No ObjectBucket found"
fi

echo ""

# Method 4: Check known patterns
echo "=== Method 4: Known Patterns ==="
case "$BUCKET_OWNER" in
    *openshift-logging*|*lokistack*)
        echo "  Pattern: openshift-logging/lokistack"
        echo "  Likely Namespace: openshift-logging"
        echo "  OBC: lokistack-objectbucketclaim"
        ;;
    *noobaa*)
        echo "  Pattern: noobaa"
        echo "  Likely Namespace: openshift-storage or noobaa"
        ;;
    obc-*)
        echo "  Pattern: ObjectBucketClaim (obc-*)"
        echo "  Searching all namespaces..."
        oc get obc --all-namespaces -o wide | grep -i "$(echo "$BUCKET_OWNER" | sed 's/^obc-//' | cut -d'-' -f1-3)"
        ;;
esac

echo ""
echo "=== Quick Search Commands ==="
echo "Search all OBCs:"
echo "  oc get obc --all-namespaces | grep -i '$(echo "$BUCKET_NAME" | cut -d'-' -f1-3)'"
echo ""
echo "Search by owner:"
echo "  oc get obc --all-namespaces -o json | jq -r '.items[] | select(.status.bucketName == \"$BUCKET_NAME\") | \"\(.metadata.namespace)/\(.metadata.name)\"'"
