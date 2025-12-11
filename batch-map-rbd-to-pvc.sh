#!/bin/bash
# Batch map multiple RBD volumes to PVCs
# Run this from a machine with kubectl/oc access to the cluster

set -e

INPUT_FILE="${1:-/tmp/ceph-rbd-out.txt}"
CLUSTER_NAMESPACE="${CLUSTER_NAMESPACE:-openshift-storage}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file not found: $INPUT_FILE"
    echo "Usage: $0 [input-file]"
    exit 1
fi

echo "=== Batch Mapping RBD Volumes to PVCs ==="
echo "Input file: $INPUT_FILE"
echo ""

# Extract volume names from the RBD output (filter out warnings)
VOLUMES=$(grep -v "^warning:" "$INPUT_FILE" | grep "^csi-vol-" | grep -v "@" | grep -v -- "-temp" | awk '{print $1}')

# Get all PVCs once
echo "Fetching all PVCs from cluster..."
ALL_PVCS=$(oc get pvc --all-namespaces -o json)
ALL_PVS=$(oc get pv -o json)

echo ""
echo "=== Volume to PVC Mapping ==="
printf "%-60s %-30s %-30s %-15s %-12s %-12s\n" \
    "RBD Volume" "Namespace" "PVC Name" "Status" "Provisioned" "Used"
echo "================================================================================================================================"

for VOL in $VOLUMES; do
    VOL_UUID=$(echo "$VOL" | sed 's/^csi-vol-//')
    
    # Get provisioned and used from input file (filter out warnings)
    VOL_INFO=$(grep -v "^warning:" "$INPUT_FILE" | grep "^$VOL " | head -1)
    PROVISIONED=$(echo "$VOL_INFO" | awk '{print $2}')
    USED=$(echo "$VOL_INFO" | awk '{print $3}')
    
    # Search in PVCs
    PVC_INFO=$(echo "$ALL_PVCS" | jq -r --arg uuid "$VOL_UUID" '
        .items[] | 
        select(.spec.csi.volumeHandle // "" | contains($uuid)) |
        "\(.metadata.namespace)|\(.metadata.name)|\(.status.phase // "Unknown")"
    ' | head -1)
    
    if [ -n "$PVC_INFO" ]; then
        NAMESPACE=$(echo "$PVC_INFO" | cut -d'|' -f1)
        PVC_NAME=$(echo "$PVC_INFO" | cut -d'|' -f2)
        STATUS=$(echo "$PVC_INFO" | cut -d'|' -f3)
        printf "%-60s %-30s %-30s %-15s %-12s %-12s\n" \
            "$VOL" "$NAMESPACE" "$PVC_NAME" "$STATUS" "$PROVISIONED" "$USED"
    else
        # Try PV search
        PV_INFO=$(echo "$ALL_PVS" | jq -r --arg uuid "$VOL_UUID" '
            .items[] | 
            select(.spec.csi.volumeHandle // "" | contains($uuid)) |
            "\(.spec.claimRef.namespace // "N/A")|\(.spec.claimRef.name // "N/A")|\(.status.phase // "Unknown")"
        ' | head -1)
        
        if [ -n "$PV_INFO" ]; then
            NAMESPACE=$(echo "$PV_INFO" | cut -d'|' -f1)
            PVC_NAME=$(echo "$PV_INFO" | cut -d'|' -f2)
            STATUS=$(echo "$PV_INFO" | cut -d'|' -f3)
            printf "%-60s %-30s %-30s %-15s %-12s %-12s\n" \
                "$VOL" "$NAMESPACE" "$PVC_NAME" "$STATUS" "$PROVISIONED" "$USED"
        else
            printf "%-60s %-30s %-30s %-15s %-12s %-12s\n" \
                "$VOL" "NOT_FOUND" "NOT_FOUND" "N/A" "$PROVISIONED" "$USED"
        fi
    fi
done

echo ""
echo "=== Summary ==="
TOTAL=$(echo "$VOLUMES" | wc -l | tr -d ' ')
echo "Total volumes processed: $TOTAL"
