#!/bin/bash
# Ceph RBD PVC Analysis Script for OpenShift Data Foundation
# Run this in the rook-ceph-operator pod
# 
# Usage:
#   export POOL=ocs-storagecluster-cephblockpool
#   export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'
#   /tmp/ceph-pvc-analysis.sh

set -e

POOL="${POOL:-ocs-storagecluster-cephblockpool}"
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/ceph-rbd-analysis.txt}"

# Use CEPH_ARGS if set (for rook-ceph-operator pod)
if [ -n "$CEPH_ARGS" ]; then
    export CEPH_ARGS
fi

echo "=== Ceph RBD PVC Analysis ==="
echo "Pool: $POOL"
echo "Timestamp: $(date)"
echo ""

# Function to convert size to bytes for sorting
# Note: Available for future enhancements and custom size calculations
size_to_bytes() {
    local size=$1
    local unit=$(echo "$size" | grep -oE '[KMGTPE]i?B$' || echo "")
    local num=$(echo "$size" | sed 's/[KMGTPE]i\?B$//')
    
    case "$unit" in
        B|"") echo "$num" ;;
        KiB) echo "$((num * 1024))" ;;
        MiB) echo "$((num * 1024 * 1024))" ;;
        GiB) echo "$((num * 1024 * 1024 * 1024))" ;;
        TiB) echo "$((num * 1024 * 1024 * 1024 * 1024))" ;;
        PiB) echo "$((num * 1024 * 1024 * 1024 * 1024 * 1024))" ;;
        EiB) echo "$((num * 1024 * 1024 * 1024 * 1024 * 1024 * 1024))" ;;
        *) echo "0" ;;
    esac
}

echo "=== 1. Top 20 Volumes by PROVISIONED Size ==="
rbd $CEPH_ARGS du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | grep -v -- "-temp" | \
    awk '{print $2, $3, $1}' | \
    sort -h -k1,1 -r | head -20 | \
    awk '{printf "%-60s %12s %12s\n", $3, $1, $2}'
echo ""

echo "=== 2. Top 20 Volumes by USED Size ==="
rbd $CEPH_ARGS du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | grep -v -- "-temp" | \
    awk '{print $3, $2, $1}' | \
    sort -h -k1,1 -r | head -20 | \
    awk '{printf "%-60s %12s %12s\n", $3, $2, $1}'
echo ""

echo "=== 3. Volumes with High Usage Percentage (>80%) ==="
rbd $CEPH_ARGS du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | grep -v -- "-temp" | \
    awk '{
        prov=$2; used=$3; name=$1;
        gsub(/[^0-9.]/, "", prov); gsub(/[^0-9.]/, "", used);
        if (prov > 0) {
            pct = (used/prov) * 100;
            if (pct > 80) {
                printf "%-60s %12s %12s %.1f%%\n", name, $2, $3, pct
            }
        }
    }' | sort -k4 -rn
echo ""

echo "=== 4. Volumes with Low Usage but High Provisioned (<10% usage, >50GiB) ==="
rbd $CEPH_ARGS du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | grep -v -- "-temp" | \
    awk '{
        prov=$2; used=$3; name=$1;
        gsub(/[^0-9.]/, "", prov); gsub(/[^0-9.]/, "", used);
        prov_unit=$2; used_unit=$3;
        if (prov_unit ~ /GiB/ && prov > 50 && prov > 0) {
            pct = (used/prov) * 100;
            if (pct < 10) {
                printf "%-60s %12s %12s %.1f%%\n", name, $2, $3, pct
            }
        }
    }' | sort -k4 -n | head -20
echo ""

echo "=== 5. Summary Statistics ==="
rbd $CEPH_ARGS du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | grep -v -- "-temp" | \
    awk '{
        count++;
        if ($2 ~ /TiB/) { prov_total += $2 * 1024 * 1024 * 1024 * 1024 }
        else if ($2 ~ /GiB/) { prov_total += $2 * 1024 * 1024 * 1024 }
        else if ($2 ~ /MiB/) { prov_total += $2 * 1024 * 1024 }
        else if ($2 ~ /KiB/) { prov_total += $2 * 1024 }
        else { prov_total += $2 }
        
        if ($3 ~ /TiB/) { used_total += $3 * 1024 * 1024 * 1024 * 1024 }
        else if ($3 ~ /GiB/) { used_total += $3 * 1024 * 1024 * 1024 }
        else if ($3 ~ /MiB/) { used_total += $3 * 1024 * 1024 }
        else if ($3 ~ /KiB/) { used_total += $3 * 1024 }
        else { used_total += $3 }
    }
    END {
        printf "Total Volumes: %d\n", count
        printf "Total Provisioned: %.2f GiB\n", prov_total / (1024*1024*1024)
        printf "Total Used: %.2f GiB\n", used_total / (1024*1024*1024)
        if (prov_total > 0) {
            printf "Overall Usage: %.1f%%\n", (used_total/prov_total) * 100
        }
    }'
echo ""

echo "Analysis saved to: $OUTPUT_FILE"