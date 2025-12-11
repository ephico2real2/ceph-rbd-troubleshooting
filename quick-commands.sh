#!/bin/bash
# Quick one-liner commands for Ceph RBD troubleshooting
# Copy and paste these commands as needed

# ============================================================================
# COMMANDS TO RUN IN rook-ceph-operator POD
# ============================================================================

# 1. Get pool name (if not known)
# ceph osd pool ls

# 2. Set pool variable
# export POOL=ocs-storagecluster-cephblockpool

# 3. Get RBD usage data (save to file, filter warnings)
# rbd du -p "$POOL" 2>&1 | grep -v "^warning:" > /tmp/ceph-rbd-out.txt

# 4. Top 10 by PROVISIONED size (filter warnings)
# rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | grep -v "-temp" | sort -h -k2 -r | head -10

# 5. Top 10 by USED size (filter warnings)
# rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | grep -v "-temp" | sort -h -k3 -r | head -10

# 6. Find volumes > 100GiB provisioned (filter warnings)
# rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | awk '$2 ~ /GiB/ && $2+0 > 100'

# 7. Find volumes > 1TiB provisioned (filter warnings)
# rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | awk '$2 ~ /TiB/'

# 8. Find volumes with > 50GiB used (filter warnings)
# rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | awk '$3 ~ /GiB/ && $3+0 > 50'

# ============================================================================
# COMMANDS TO RUN FROM CLUSTER ACCESS MACHINE (with oc/kubectl)
# ============================================================================

# 9. Find PVC by RBD volume UUID (replace UUID)
# VOL_UUID="00842451-49b1-4964-b6e9-9730a32c7d52"
# oc get pvc --all-namespaces -o json | jq -r --arg uuid "$VOL_UUID" '.items[] | select(.spec.csi.volumeHandle // "" | contains($uuid)) | "\(.metadata.namespace)\t\(.metadata.name)"'

# 10. Get all PVCs with ODF storage classes
# oc get pvc --all-namespaces -o json | jq -r '.items[] | select(.spec.storageClassName // "" | test("(ocs|rook|ceph|odf)"; "i")) | "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.storageClassName)\t\(.spec.resources.requests.storage)"'

# 11. Find large PVCs (>50GiB)
# oc get pvc --all-namespaces -o json | jq -r '.items[] | select((.spec.resources.requests.storage // "0") | (if . | test("Gi") then (. | gsub("Gi"; "") | tonumber) else 0 end) > 50) | "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.resources.requests.storage)"'

# 12. Get all PVCs sorted by namespace
# oc get pvc --all-namespaces --sort-by=.metadata.namespace

# 13. Get PVCs in specific namespace
# oc get pvc -n <namespace-name>

# 14. Get detailed PVC info
# oc get pvc <pvc-name> -n <namespace> -o yaml

# 15. Get PV details by name
# oc get pv <pv-name> -o yaml

# 16. Find PV by volume handle
# VOL_UUID="00842451-49b1-4964-b6e9-9730a32c7d52"
# oc get pv -o json | jq -r --arg uuid "$VOL_UUID" '.items[] | select(.spec.csi.volumeHandle // "" | contains($uuid)) | "\(.metadata.name)\t\(.spec.claimRef.namespace)\t\(.spec.claimRef.name)"'

# 17. Export all PVCs to CSV
# oc get pvc --all-namespaces -o json | jq -r '.items[] | [.metadata.namespace, .metadata.name, .spec.storageClassName, .spec.resources.requests.storage, .spec.csi.volumeHandle, .status.phase] | @csv' > /tmp/all-pvcs.csv

# 18. Count PVCs by storage class
# oc get pvc --all-namespaces -o json | jq -r '.items[] | .spec.storageClassName // "N/A"' | sort | uniq -c

# 19. Get total requested storage per namespace
# oc get pvc --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace)\t\(.spec.resources.requests.storage // "0")"' | awk '{sum[$1]+=$2} END {for (ns in sum) print ns, sum[ns]}'

# 20. Find PVCs with Bound status
# oc get pvc --all-namespaces -o json | jq -r '.items[] | select(.status.phase == "Bound") | "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.resources.requests.storage)"'

echo "Quick commands reference. See comments above for copy-paste commands."