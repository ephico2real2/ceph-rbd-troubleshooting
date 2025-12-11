#!/bin/bash
# Query all PVCs in the cluster with their storage details
# Run this from a machine with kubectl/oc access to the cluster

set -e

echo "=== All PVCs in Cluster ==="
echo "Timestamp: $(date)"
echo ""

# Get all PVCs with details
echo "=== PVCs with Storage Class and Volume Handle ==="
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
        "\(.metadata.namespace)|\(.metadata.name)|\(.spec.storageClassName // "N/A")|\(.spec.csi.volumeHandle // "N/A")|\(.spec.resources.requests.storage // "N/A")|\(.status.phase // "Unknown")|\(.status.capacity.storage // "N/A")"' | \
    column -t -s '|' -N "NAMESPACE,PVC_NAME,STORAGE_CLASS,VOLUME_HANDLE,REQUESTED,STATUS,CAPACITY"
echo ""

echo "=== PVCs by Storage Class ==="
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
        "\(.spec.storageClassName // "N/A")|\(.metadata.namespace)|\(.metadata.name)"' | \
    sort | uniq -c | \
    awk '{printf "%-5s %-30s %-30s %-30s\n", $1, $2, $3, $4}'
echo ""

echo "=== PVCs by Namespace ==="
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
        "\(.metadata.namespace)|\(.metadata.name)|\(.spec.resources.requests.storage // "N/A")"' | \
    sort -t'|' -k1,1 | \
    awk -F'|' '{printf "%-30s %-50s %-15s\n", $1, $2, $3}'
echo ""

echo "=== Large PVCs (>50GiB) ==="
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
        select((.spec.resources.requests.storage // "0") | 
               (if . | test("Gi") then (. | gsub("Gi"; "") | tonumber) else 0 end) > 50) |
        "\(.metadata.namespace)|\(.metadata.name)|\(.spec.resources.requests.storage)|\(.status.phase)"' | \
    column -t -s '|' -N "NAMESPACE,PVC_NAME,REQUESTED,STATUS"
echo ""

echo "=== PVCs with ODF/Rook Storage Classes ==="
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
        select(.spec.storageClassName // "" | test("(ocs|rook|ceph|odf)"; "i")) |
        "\(.metadata.namespace)|\(.metadata.name)|\(.spec.storageClassName)|\(.spec.resources.requests.storage)|\(.spec.csi.volumeHandle // "N/A")"' | \
    column -t -s '|' -N "NAMESPACE,PVC_NAME,STORAGE_CLASS,REQUESTED,VOLUME_HANDLE"
echo ""

echo "=== Export to CSV ==="
echo "To export all PVCs to CSV, run:"
echo "oc get pvc --all-namespaces -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name, .spec.storageClassName, .spec.resources.requests.storage, .spec.csi.volumeHandle, .status.phase] | @csv' > /tmp/all-pvcs.csv"