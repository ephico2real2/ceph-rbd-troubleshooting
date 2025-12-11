# Ceph RBD PVC Troubleshooting Commands

This collection of scripts helps troubleshoot Ceph RBD volumes in OpenShift Data Foundation (ODF) on OpenShift 4.18.

## Prerequisites

1. Access to the `rook-ceph-operator` pod (for RBD commands)
2. Access to OpenShift cluster with `oc` or `kubectl` (for PVC queries)
3. `jq` installed (for JSON parsing)

## Scripts Overview

### 1. `ceph-pvc-analysis.sh`
**Run in:** `rook-ceph-operator` pod  
**Purpose:** Analyze RBD volumes directly from Ceph

**Usage:**
```bash
# In rook-ceph-operator pod
export POOL=ocs-storagecluster-cephblockpool  # Adjust if different
bash /tmp/ceph-pvc-analysis.sh
```

**Output:**
- Top 20 volumes by provisioned size
- Top 20 volumes by used size
- Volumes with high usage percentage (>80%)
- Volumes with low usage but high provisioned (<10% usage, >50GiB)
- Summary statistics

### 2. `map-rbd-to-pvc.sh`
**Run in:** Machine with cluster access  
**Purpose:** Map a single RBD volume to its PVC and namespace

**Usage:**
```bash
bash /tmp/map-rbd-to-pvc.sh csi-vol-00842451-49b1-4964-b6e9-9730a32c7d52
```

### 3. `batch-map-rbd-to-pvc.sh`
**Run in:** Machine with cluster access  
**Purpose:** Batch map multiple RBD volumes from your data file

**Usage:**
```bash
bash /tmp/batch-map-rbd-to-pvc.sh /tmp/ceph-rbd-out.txt
```

### 4. `query-all-pvcs.sh`
**Run in:** Machine with cluster access  
**Purpose:** Query all PVCs in the cluster

**Usage:**
```bash
bash /tmp/query-all-pvcs.sh
```

**Output:**
- All PVCs with storage class and volume handle
- PVCs grouped by storage class
- PVCs grouped by namespace
- Large PVCs (>50GiB)
- PVCs with ODF/Rook storage classes

### 5. `find-high-usage-pvcs.sh`
**Run in:** Machine with cluster access  
**Purpose:** Find PVCs with high usage by combining RBD data with cluster PVC info

**Usage:**
```bash
bash /tmp/find-high-usage-pvcs.sh /tmp/ceph-rbd-out.txt 80
# Last parameter is usage threshold percentage (default: 80)
```

## Quick Reference Commands

### In rook-ceph-operator Pod

```bash
# Get pool name
ceph osd pool ls

# List all RBD volumes in a pool
POOL=ocs-storagecluster-cephblockpool
rbd ls -p "$POOL"

# Get detailed usage for all volumes (filter warnings)
rbd du -p "$POOL" 2>&1 | grep -v "^warning:" > /tmp/ceph-rbd-out.txt

# Sort by provisioned size (filter warnings)
rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | sort -h -k2 -r | head -20

# Sort by used size (filter warnings)
rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | sort -h -k3 -r | head -20

# Find volumes > 100GiB (filter warnings)
rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | grep -v "@" | awk '$2 ~ /GiB/ && $2+0 > 100'
```

### From Cluster Access Machine

```bash
# Find PVC by volume handle UUID
VOL_UUID="00842451-49b1-4964-b6e9-9730a32c7d52"
oc get pvc --all-namespaces -o json | \
    jq -r --arg uuid "$VOL_UUID" \
    '.items[] | select(.spec.csi.volumeHandle // "" | contains($uuid)) | 
     "\(.metadata.namespace)\t\(.metadata.name)"'

# Get all PVCs with ODF storage classes
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
    select(.spec.storageClassName // "" | test("(ocs|rook|ceph|odf)"; "i")) |
    "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.storageClassName)\t\(.spec.resources.requests.storage)"'

# Export all PVCs to CSV
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
    [.metadata.namespace, .metadata.name, .spec.storageClassName, 
     .spec.resources.requests.storage, .spec.csi.volumeHandle, .status.phase] | 
    @csv' > /tmp/all-pvcs.csv

# Find large PVCs (>50GiB)
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
    select((.spec.resources.requests.storage // "0") | 
           (if . | test("Gi") then (. | gsub("Gi"; "") | tonumber) else 0 end) > 50) |
    "\(.metadata.namespace)\t\(.metadata.name)\t\(.spec.resources.requests.storage)"'
```

## Workflow Example

1. **Get RBD data from Ceph:**
   ```bash
   # In rook-ceph-operator pod
   POOL=ocs-storagecluster-cephblockpool
   rbd du -p "$POOL" 2>&1 | grep -v "^warning:" > /tmp/ceph-rbd-out.txt
   ```

2. **Analyze the data:**
   ```bash
   # In rook-ceph-operator pod
   bash /tmp/ceph-pvc-analysis.sh
   ```

3. **Copy data file to your machine:**
   ```bash
   # From your machine
   oc cp openshift-storage/rook-ceph-operator-xxx:/tmp/ceph-rbd-out.txt /tmp/ceph-rbd-out.txt
   ```

4. **Map volumes to PVCs:**
   ```bash
   # From your machine
   bash /tmp/batch-map-rbd-to-pvc.sh /tmp/ceph-rbd-out.txt
   ```

5. **Find high usage PVCs:**
   ```bash
   # From your machine
   bash /tmp/find-high-usage-pvcs.sh /tmp/ceph-rbd-out.txt 80
   ```

## Notes

- RBD volume names follow pattern: `csi-vol-<UUID>`
- The UUID in the RBD name should match part of the PVC's `volumeHandle`
- Snapshots have pattern: `csi-snap-<UUID>`
- Temporary volumes have `-temp` suffix
- Storage pool name may vary; check with `ceph osd pool ls`
- **Warning messages**: The `rbd du` command may output warning messages like `warning: fast-diff map is not enabled...`. All scripts automatically filter these out using `grep -v "^warning:"`. When running commands manually, use `2>&1 | grep -v "^warning:"` to filter warnings.

## Troubleshooting

If volumes aren't found:
1. Verify the pool name: `ceph osd pool ls`
2. Check volume handle format: `oc get pv <pv-name> -o yaml | grep volumeHandle`
3. Ensure you're searching in the correct namespace
4. Some volumes might be orphaned (no associated PVC)
