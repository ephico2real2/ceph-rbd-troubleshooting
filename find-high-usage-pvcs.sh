#!/bin/bash
# Find PVCs with high usage by comparing RBD data with cluster PVCs
# Combines RBD usage data with OpenShift PVC information

set -e

RBD_FILE="${1:-/tmp/ceph-rbd-out.txt}"
THRESHOLD_PCT="${2:-80}"

if [ ! -f "$RBD_FILE" ]; then
    echo "Error: RBD data file not found: $RBD_FILE"
    echo "Usage: $0 [rbd-data-file] [usage-threshold-percent]"
    exit 1
fi

echo "=== Finding High Usage PVCs ==="
echo "RBD Data File: $RBD_FILE"
echo "Usage Threshold: ${THRESHOLD_PCT}%"
echo ""

# Get all PVCs
echo "Fetching PVC data from cluster..."
ALL_PVCS=$(oc get pvc --all-namespaces -o json)

echo ""
echo "=== High Usage PVCs (>${THRESHOLD_PCT}%) ==="
printf "%-30s %-50s %-60s %-12s %-12s %-10s\n" \
    "NAMESPACE" "PVC_NAME" "RBD_VOLUME" "PROVISIONED" "USED" "USAGE%"
echo "================================================================================================================================"

# Process each volume from RBD output (filter out warnings)
grep -v "^warning:" "$RBD_FILE" | grep "^csi-vol-" | grep -v "@" | grep -v -- "-temp" | while read -r line; do
    VOL_NAME=$(echo "$line" | awk '{print $1}')
    PROVISIONED=$(echo "$line" | awk '{print $2, $3}')  # e.g., "1 GiB"
    USED=$(echo "$line" | awk '{print $4, $5}')         # e.g., "28 MiB"
    VOL_UUID=$(echo "$VOL_NAME" | sed 's/^csi-vol-//')
    
    # Calculate percentage using awk with unit conversion
    USAGE_PCT=$(echo "$PROVISIONED $USED" | awk '{
        prov=$1; prov_unit=$2; used=$3; used_unit=$4;
        # Convert to bytes
        if (prov_unit ~ /TiB/) prov *= 1024*1024*1024*1024;
        else if (prov_unit ~ /GiB/) prov *= 1024*1024*1024;
        else if (prov_unit ~ /MiB/) prov *= 1024*1024;
        else if (prov_unit ~ /KiB/) prov *= 1024;
        
        if (used_unit ~ /TiB/) used *= 1024*1024*1024*1024;
        else if (used_unit ~ /GiB/) used *= 1024*1024*1024;
        else if (used_unit ~ /MiB/) used *= 1024*1024;
        else if (used_unit ~ /KiB/) used *= 1024;
        
        if (prov > 0) printf "%.1f", (used/prov)*100;
        else print "0";
    }')
    
    if [ -n "$USAGE_PCT" ] && [ "$USAGE_PCT" != "0" ]; then
        
        # Check if usage exceeds threshold
        if (( $(awk -v pct="$USAGE_PCT" -v thresh="$THRESHOLD_PCT" 'BEGIN {print (pct > thresh) ? 1 : 0}') )); then
            # Find matching PVC
            PVC_INFO=$(echo "$ALL_PVCS" | jq -r --arg uuid "$VOL_UUID" '
                .items[] | 
                select(.spec.csi.volumeHandle // "" | contains($uuid)) |
                "\(.metadata.namespace)|\(.metadata.name)"
            ' | head -1)
            
            if [ -n "$PVC_INFO" ]; then
                NAMESPACE=$(echo "$PVC_INFO" | cut -d'|' -f1)
                PVC_NAME=$(echo "$PVC_INFO" | cut -d'|' -f2)
                printf "%-30s %-50s %-60s %-12s %-12s %-10s\n" \
                    "$NAMESPACE" "$PVC_NAME" "$VOL_NAME" "$PROVISIONED" "$USED" "${USAGE_PCT}%"
            else
                printf "%-30s %-50s %-60s %-12s %-12s %-10s\n" \
                    "NOT_FOUND" "NOT_FOUND" "$VOL_NAME" "$PROVISIONED" "$USED" "${USAGE_PCT}%"
            fi
        fi
    fi
done | sort -k6 -rn

echo ""
echo "=== High Provisioned but Low Usage (<10% usage, >50GiB) ==="
printf "%-30s %-50s %-60s %-12s %-12s %-10s\n" \
    "NAMESPACE" "PVC_NAME" "RBD_VOLUME" "PROVISIONED" "USED" "USAGE%"
echo "================================================================================================================================"

grep -v "^warning:" "$RBD_FILE" | grep "^csi-vol-" | grep -v "@" | grep -v -- "-temp" | while read -r line; do
    VOL_NAME=$(echo "$line" | awk '{print $1}')
    PROVISIONED=$(echo "$line" | awk '{print $2, $3}')  # e.g., "40 GiB"
    USED=$(echo "$line" | awk '{print $4, $5}')         # e.g., "9.2 GiB"
    VOL_UUID=$(echo "$VOL_NAME" | sed 's/^csi-vol-//')
    
    # Check if provisioned is in GiB and > 50
    if echo "$PROVISIONED" | grep -q "GiB"; then
        PROV_NUM=$(echo "$PROVISIONED" | awk '{print $1}')
        
        if [ -n "$PROV_NUM" ] && (( $(awk -v prov="$PROV_NUM" 'BEGIN {print (prov > 50) ? 1 : 0}') )); then
            # Calculate percentage with unit conversion
            USAGE_PCT=$(echo "$PROVISIONED $USED" | awk '{
                prov=$1; prov_unit=$2; used=$3; used_unit=$4;
                # Convert to bytes
                if (prov_unit ~ /TiB/) prov *= 1024*1024*1024*1024;
                else if (prov_unit ~ /GiB/) prov *= 1024*1024*1024;
                else if (prov_unit ~ /MiB/) prov *= 1024*1024;
                else if (prov_unit ~ /KiB/) prov *= 1024;
                
                if (used_unit ~ /TiB/) used *= 1024*1024*1024*1024;
                else if (used_unit ~ /GiB/) used *= 1024*1024*1024;
                else if (used_unit ~ /MiB/) used *= 1024*1024;
                else if (used_unit ~ /KiB/) used *= 1024;
                
                if (prov > 0) printf "%.1f", (used/prov)*100;
                else print "0";
            }')
                
                # Check if usage < 10%
                if (( $(awk -v pct="$USAGE_PCT" 'BEGIN {print (pct < 10) ? 1 : 0}') )); then
                    # Find matching PVC
                    PVC_INFO=$(echo "$ALL_PVCS" | jq -r --arg uuid "$VOL_UUID" '
                        .items[] | 
                        select(.spec.csi.volumeHandle // "" | contains($uuid)) |
                        "\(.metadata.namespace)|\(.metadata.name)"
                    ' | head -1)
                    
                    if [ -n "$PVC_INFO" ]; then
                        NAMESPACE=$(echo "$PVC_INFO" | cut -d'|' -f1)
                        PVC_NAME=$(echo "$PVC_INFO" | cut -d'|' -f2)
                        printf "%-30s %-50s %-60s %-12s %-12s %-10s\n" \
                            "$NAMESPACE" "$PVC_NAME" "$VOL_NAME" "$PROVISIONED" "$USED" "${USAGE_PCT}%"
                    fi
                fi
            fi
        fi
    fi
done | sort -k4 -h -r