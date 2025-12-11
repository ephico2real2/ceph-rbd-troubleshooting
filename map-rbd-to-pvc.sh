#!/bin/bash
# Map RBD Volume Names to OpenShift PVCs and Namespaces
# Run this from a machine with kubectl/oc access to the cluster

set -e

RBD_VOLUME_NAME="${1}"
CLUSTER_NAMESPACE="${CLUSTER_NAMESPACE:-openshift-storage}"

if [ -z "$RBD_VOLUME_NAME" ]; then
    echo "Usage: $0 <rbd-volume-name>"
    echo "Example: $0 csi-vol-00842451-49b1-4964-b6e9-9730a32c7d52"
    exit 1
fi

# Extract UUID from RBD volume name (format: csi-vol-UUID)
VOL_UUID=$(echo "$RBD_VOLUME_NAME" | sed 's/^csi-vol-//' | sed 's/-temp$//')

echo "=== Mapping RBD Volume to PVC ==="
echo "RBD Volume: $RBD_VOLUME_NAME"
echo "Volume UUID: $VOL_UUID"
echo ""

# Search for PVCs across all namespaces
echo "Searching for PVC with volume handle containing: $VOL_UUID"
echo ""

# Method 1: Search PVCs by volume handle in spec
echo "=== Method 1: PVC Spec Search ==="
oc get pvc --all-namespaces -o json | \
    jq -r --arg uuid "$VOL_UUID" '
        .items[] | 
        select(.spec.csi.volumeHandle // "" | contains($uuid)) |
        "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.csi.volumeHandle)"
    ' | column -t -s $'\t'
echo ""

# Method 2: Search by PV volume handle
echo "=== Method 2: PV Search ==="
oc get pv -o json | \
    jq -r --arg uuid "$VOL_UUID" '
        .items[] | 
        select(.spec.csi.volumeHandle // "" | contains($uuid)) |
        "\(.metadata.name)\t\(.spec.csi.volumeHandle)\t\(.spec.claimRef.namespace // "N/A")\t\(.spec.claimRef.name // "N/A")"
    ' | column -t -s $'\t'
echo ""

# Method 3: Direct PVC search using the UUID pattern
echo "=== Method 3: Direct PVC Name Pattern Search ==="
oc get pvc --all-namespaces -o json | \
    jq -r --arg uuid "$VOL_UUID" '
        .items[] | 
        select(.metadata.name // "" | contains($uuid) or (.spec.csi.volumeHandle // "" | contains($uuid))) |
        "\(.metadata.namespace)\t\(.metadata.name)\t\(.status.phase // "Unknown")\t\(.spec.resources.requests.storage // "N/A")"
    ' | column -t -s $'\t'
echo ""

echo "=== If no results found, try searching all PVCs manually ==="
echo "oc get pvc --all-namespaces | grep -i \"$VOL_UUID\""