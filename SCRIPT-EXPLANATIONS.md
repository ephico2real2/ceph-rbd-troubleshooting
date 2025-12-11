# Detailed Script Explanations

This document provides comprehensive explanations of each script in the Ceph RBD troubleshooting toolkit.

---

## 1. `ceph-pvc-analysis.sh`

### **Purpose**
Analyzes RBD (RADOS Block Device) volumes directly from Ceph storage. This script runs **inside the rook-ceph-operator pod** and queries Ceph to get storage usage statistics.

### **When to Use**
- You want to see which volumes are consuming the most storage
- You need to identify over-provisioned or underutilized volumes
- You want overall storage statistics for your Ceph cluster
- You're troubleshooting storage capacity issues

### **How It Works**

#### **Setup (Lines 5-13)**
```bash
set -e                    # Exit on any error
POOL="${POOL:-ocs-storagecluster-cephblockpool}"  # Default pool name
```
- Uses environment variable `POOL` or defaults to `ocs-storagecluster-cephblockpool`
- Sets error handling to stop on failures

#### **Section 1: Top 20 by Provisioned Size (Lines 33-38)**
```bash
rbd du -p "$POOL" 2>&1 | grep -v "^warning:" | grep "^csi-vol-" | ...
```
**What it does:**
1. Runs `rbd du` (RBD disk usage) command on the pool
2. `2>&1` captures both stdout and stderr (to catch warnings)
3. `grep -v "^warning:"` filters out warning messages
4. `grep "^csi-vol-"` finds only CSI volume entries (not snapshots)
5. `grep -v "@"` excludes snapshot clones (format: `volume@snapshot`)
6. `grep -v "-temp"` excludes temporary volumes
7. Sorts by provisioned size (column 2) in reverse order
8. Shows top 20

**Output:** Volume name, provisioned size, used size

#### **Section 2: Top 20 by Used Size (Lines 40-45)**
Similar to Section 1, but sorts by **used** size (column 3) instead of provisioned.

#### **Section 3: High Usage Volumes (Lines 47-59)**
```bash
awk '{
    prov=$2; used=$3; name=$1;
    gsub(/[^0-9.]/, "", prov);  # Extract numeric value
    if (prov > 0) {
        pct = (used/prov) * 100;
        if (pct > 80) { ... }   # Show if >80% used
    }
}'
```
**What it does:**
- Calculates usage percentage: `(used / provisioned) × 100`
- Shows volumes with >80% usage
- Helps identify volumes that may need expansion or cleanup

#### **Section 4: Over-Provisioned Volumes (Lines 61-74)**
Finds volumes that are:
- Provisioned >50GiB
- But using <10% of that space
- These are candidates for downsizing to save storage

#### **Section 5: Summary Statistics (Lines 76-99)**
```bash
awk '{
    count++;
    if ($2 ~ /TiB/) { prov_total += $2 * 1024^4 }
    else if ($2 ~ /GiB/) { prov_total += $2 * 1024^3 }
    ...
}'
```
**What it does:**
- Counts total volumes
- Converts all sizes to bytes, then sums them
- Calculates total provisioned, total used, and overall usage percentage
- Provides cluster-wide storage overview

### **Example Output**
```
=== 1. Top 20 Volumes by PROVISIONED Size ===
csi-vol-77119f23-c539-11ed-8e9b-0a58af030611    500 GiB    406 GiB
csi-vol-614e209e-8f79-47ee-80c4-937f22b62378    300 GiB    291 GiB
...

=== 5. Summary Statistics ===
Total Volumes: 570
Total Provisioned: 1234.56 GiB
Total Used: 456.78 GiB
Overall Usage: 37.0%
```

---

## 2. `map-rbd-to-pvc.sh`

### **Purpose**
Maps a **single** RBD volume name to its corresponding OpenShift PVC (PersistentVolumeClaim) and namespace. This is useful when you have a volume name from Ceph and need to find which application is using it.

### **When to Use**
- You have a specific RBD volume name and need to find its PVC
- You're investigating a specific volume issue
- You need to identify which namespace/application owns a volume

### **How It Works**

#### **Input Validation (Lines 10-14)**
```bash
if [ -z "$RBD_VOLUME_NAME" ]; then
    echo "Usage: $0 <rbd-volume-name>"
    exit 1
fi
```
Requires a volume name as argument.

#### **UUID Extraction (Line 17)**
```bash
VOL_UUID=$(echo "$RBD_VOLUME_NAME" | sed 's/^csi-vol-//' | sed 's/-temp$//')
```
Extracts the UUID from `csi-vol-UUID` format. Example:
- Input: `csi-vol-00842451-49b1-4964-b6e9-9730a32c7d52`
- Output: `00842451-49b1-4964-b6e9-9730a32c7d52`

#### **Method 1: PVC Spec Search (Lines 28-36)**
```bash
oc get pvc --all-namespaces -o json | \
    jq -r --arg uuid "$VOL_UUID" '
        .items[] | 
        select(.spec.csi.volumeHandle // "" | contains($uuid))
```
**What it does:**
- Gets all PVCs in the cluster as JSON
- Uses `jq` to search for PVCs where `volumeHandle` contains the UUID
- The `volumeHandle` in PVC spec contains the RBD volume identifier
- Returns: namespace, PVC name, and full volume handle

#### **Method 2: PV Search (Lines 38-46)**
If Method 1 fails, searches PersistentVolumes directly:
- PVs also have `volumeHandle` in their spec
- PVs have `claimRef` that points back to the PVC
- Useful if PVC lookup fails

#### **Method 3: Pattern Search (Lines 48-56)**
Fallback method that searches:
- PVC names containing the UUID
- Volume handles containing the UUID
- More flexible but less precise

### **Example Usage**
```bash
./map-rbd-to-pvc.sh csi-vol-00842451-49b1-4964-b6e9-9730a32c7d52
```

**Output:**
```
=== Method 1: PVC Spec Search ===
my-namespace    my-pvc    ceph-csi://pool/csi-vol-00842451-...
```

---

## 3. `batch-map-rbd-to-pvc.sh`

### **Purpose**
Maps **multiple** RBD volumes to their PVCs in batch. Processes an entire RBD output file and creates a mapping table.

### **When to Use**
- You have a file with many RBD volumes (from `rbd du` output)
- You want to see which namespaces/applications are using the most storage
- You need a comprehensive mapping of all volumes to PVCs

### **How It Works**

#### **File Processing (Lines 20-21)**
```bash
VOLUMES=$(grep -v "^warning:" "$INPUT_FILE" | grep "^csi-vol-" | ...)
```
- Reads the input file (default: `/tmp/ceph-rbd-out.txt`)
- Filters warnings and extracts all volume names
- Creates a list of volumes to process

#### **Bulk Data Fetch (Lines 24-26)**
```bash
ALL_PVCS=$(oc get pvc --all-namespaces -o json)
ALL_PVS=$(oc get pv -o json)
```
- Fetches **all** PVCs and PVs once (not per volume)
- Much faster than querying for each volume individually
- Stores in variables for reuse

#### **Volume Loop (Lines 34-74)**
For each volume:
1. **Extract UUID** from volume name
2. **Get storage info** from the input file (provisioned, used)
3. **Search PVCs** using the UUID
4. **Fallback to PV search** if PVC not found
5. **Output formatted line** with all information

#### **Output Format**
```
RBD Volume                                    Namespace                    PVC Name                      Status          Provisioned  Used
csi-vol-00842451-...                        my-namespace                 my-pvc                        Bound           10 GiB       5.2 GiB
```

### **Performance Note**
- Fetches cluster data once, not per volume
- Processes volumes sequentially
- For 500+ volumes, may take 1-2 minutes

---

## 4. `query-all-pvcs.sh`

### **Purpose**
Queries and displays all PVCs in the cluster with various views and filters. Does **not** require RBD data - works purely from OpenShift API.

### **When to Use**
- You want an overview of all PVCs in the cluster
- You need to see PVCs grouped by namespace or storage class
- You want to find large PVCs or specific storage classes
- You're doing general storage inventory

### **How It Works**

#### **Section 1: All PVCs with Details (Lines 12-17)**
```bash
oc get pvc --all-namespaces -o json | \
    jq -r '.items[] | 
        "\(.metadata.namespace)|\(.metadata.name)|\(.spec.storageClassName)..."
```
**What it shows:**
- Namespace, PVC name, storage class
- Volume handle (RBD identifier)
- Requested size, status, capacity
- Complete PVC information

#### **Section 2: PVCs by Storage Class (Lines 19-25)**
Groups and counts PVCs by storage class:
```
  45 ocs-storagecluster-cephblockpool    namespace1    pvc-1
  23 ocs-storagecluster-cephblockpool    namespace2    pvc-2
```
Shows which storage classes are most used.

#### **Section 3: PVCs by Namespace (Lines 27-33)**
Lists all PVCs sorted by namespace:
```
namespace1    pvc-1    10Gi
namespace1    pvc-2    20Gi
namespace2    pvc-3    5Gi
```
Helps identify which namespaces consume the most storage.

#### **Section 4: Large PVCs (Lines 35-42)**
```bash
select((.spec.resources.requests.storage // "0") | 
       (if . | test("Gi") then (. | gsub("Gi"; "") | tonumber) else 0 end) > 50)
```
- Filters PVCs requesting >50GiB
- Converts size strings to numbers for comparison
- Shows large storage consumers

#### **Section 5: ODF/Rook Storage Classes (Lines 44-50)**
Filters for Ceph-related storage classes:
- Matches: `ocs-*`, `rook-*`, `ceph-*`, `odf-*` (case-insensitive)
- Shows only PVCs using Ceph storage
- Useful for ODF-specific analysis

### **Key Features**
- **No RBD data needed** - works from OpenShift API only
- **Multiple views** - different perspectives on the same data
- **Filtering** - finds specific PVCs (large, by class, etc.)
- **Export ready** - includes CSV export command

---

## 5. `find-high-usage-pvcs.sh`

### **Purpose**
**Combines** RBD usage data with OpenShift PVC information to find problematic volumes. This is the most powerful script for identifying issues.

### **When to Use**
- You have RBD usage data and want to find which PVCs are problematic
- You need to identify volumes that are nearly full (>80% used)
- You want to find over-provisioned volumes (large but unused)
- You're planning storage optimization

### **How It Works**

#### **Input Parameters (Lines 7-8)**
```bash
RBD_FILE="${1:-/tmp/ceph-rbd-out.txt}"    # RBD data file
THRESHOLD_PCT="${2:-80}"                   # Usage threshold (default 80%)
```

#### **Part 1: High Usage PVCs (Lines 26-65)**
```bash
grep -v "^warning:" "$RBD_FILE" | grep "^csi-vol-" | ... | while read -r line; do
    VOL_NAME=$(echo "$line" | awk '{print $1}')
    PROVISIONED=$(echo "$line" | awk '{print $2}')
    USED=$(echo "$line" | awk '{print $3}')
    
    # Calculate percentage
    USAGE_PCT=$(echo "scale=1; ($USED_NUM / $PROV_NUM) * 100" | bc)
    
    if (( $(echo "$USAGE_PCT > $THRESHOLD_PCT" | bc -l) )); then
        # Find matching PVC
        PVC_INFO=$(echo "$ALL_PVCS" | jq -r --arg uuid "$VOL_UUID" '...')
    fi
done
```

**Process:**
1. Reads each volume from RBD file
2. Extracts provisioned and used sizes
3. Calculates usage percentage using `bc` (calculator)
4. If usage > threshold, searches for matching PVC
5. Outputs: namespace, PVC name, volume, sizes, usage %

**Example Output:**
```
NAMESPACE    PVC_NAME              RBD_VOLUME                              PROVISIONED  USED        USAGE%
my-ns        database-pvc          csi-vol-abc123...                      100 GiB      95 GiB      95.0%
```

#### **Part 2: Over-Provisioned Volumes (Lines 68-108)**
Finds volumes that are:
- Provisioned >50GiB (large)
- But using <10% (wasteful)

**Logic:**
```bash
if echo "$PROVISIONED" | grep -q "GiB"; then
    PROV_NUM=$(echo "$PROVISIONED" | sed 's/GiB//' | sed 's/[^0-9.]//g')
    if (( $(echo "$PROV_NUM > 50" | bc -l) )); then
        USAGE_PCT=$(echo "scale=1; ($USED_NUM / $PROV_NUM) * 100" | bc)
        if (( $(echo "$USAGE_PCT < 10" | bc -l) )); then
            # This is over-provisioned!
        fi
    fi
fi
```

### **Key Features**
- **Combines two data sources**: RBD (actual usage) + OpenShift (PVC info)
- **Calculates percentages**: Uses `bc` for precise math
- **Configurable threshold**: Change default 80% via parameter
- **Two problem types**: High usage AND over-provisioned
- **Sorted output**: High usage sorted by %, over-provisioned by size

### **Example Usage**
```bash
# Find PVCs >80% used
./find-high-usage-pvcs.sh /tmp/ceph-rbd-out.txt 80

# Find PVCs >90% used
./find-high-usage-pvcs.sh /tmp/ceph-rbd-out.txt 90
```

---

## 6. `quick-commands.sh`

### **Purpose**
Reference file with copy-paste ready one-liner commands. Not meant to be executed directly - it's a cheat sheet.

### **Structure**
- **Lines 6-32**: Commands for rook-ceph-operator pod
- **Lines 34-74**: Commands for cluster access machine
- All commands are commented out (prefixed with `#`)

### **Key Commands**

#### **In Pod:**
- Get pool name
- Set pool variable
- Get RBD usage data (with warning filtering)
- Sort by provisioned/used size
- Find large volumes

#### **From Cluster:**
- Find PVC by UUID
- Get all ODF PVCs
- Find large PVCs
- Export to CSV
- Count by storage class

### **Usage**
Just copy the command you need, remove the `#`, and paste in terminal.

---

## Common Patterns Across Scripts

### **Warning Filtering**
All scripts use: `grep -v "^warning:"` or `2>&1 | grep -v "^warning:"`
- Filters out Ceph warning messages
- Ensures clean data parsing

### **Volume Filtering**
Common pattern: `grep "^csi-vol-" | grep -v "@" | grep -v "-temp"`
- `^csi-vol-`: Only CSI volumes (not system volumes)
- `-v "@"`: Exclude snapshot clones
- `-v "-temp"`: Exclude temporary volumes

### **UUID Extraction**
```bash
VOL_UUID=$(echo "$VOL_NAME" | sed 's/^csi-vol-//' | sed 's/-temp$//')
```
Extracts UUID from `csi-vol-UUID` format.

### **PVC Matching**
```bash
jq -r --arg uuid "$VOL_UUID" '
    .items[] | 
    select(.spec.csi.volumeHandle // "" | contains($uuid))
```
Uses `jq` to search JSON for volume handles containing the UUID.

### **Size Calculations**
- Uses `bc` for floating-point math
- Converts units (GiB, TiB) to bytes for totals
- Handles different size formats

---

## Workflow Recommendations

### **Scenario 1: Storage Capacity Alert**
1. Run `ceph-pvc-analysis.sh` in pod → Get overview
2. Run `find-high-usage-pvcs.sh` → Find problematic PVCs
3. Use `map-rbd-to-pvc.sh` for specific volumes → Identify owners

### **Scenario 2: Storage Optimization**
1. Run `ceph-pvc-analysis.sh` → See over-provisioned volumes
2. Run `find-high-usage-pvcs.sh` → Get list with namespaces
3. Contact application owners to downsize

### **Scenario 3: New Volume Investigation**
1. Get volume name from Ceph
2. Run `map-rbd-to-pvc.sh <volume-name>` → Find PVC
3. Check namespace and application

### **Scenario 4: Complete Inventory**
1. Run `query-all-pvcs.sh` → Get all PVCs
2. Run `batch-map-rbd-to-pvc.sh` → Map to RBD volumes
3. Export to CSV for analysis

---

## Dependencies

All scripts require:
- **Bash** (standard shell)
- **jq** (JSON processor) - for parsing OpenShift API responses
- **bc** (calculator) - for percentage calculations
- **oc/kubectl** - for cluster access (scripts 2-5)
- **rbd** command - for Ceph access (script 1, run in pod)

---

## Error Handling

- `set -e`: Scripts exit on errors
- Input validation: Check for required files/parameters
- Fallback methods: Multiple search strategies
- Graceful failures: Shows "NOT_FOUND" instead of crashing

---

## Performance Considerations

- **batch-map-rbd-to-pvc.sh**: Fetches all PVCs once (efficient)
- **find-high-usage-pvcs.sh**: Processes volumes sequentially (may be slow for 1000+ volumes)
- **query-all-pvcs.sh**: Single API call (fast)
- **ceph-pvc-analysis.sh**: Runs in pod (no network overhead)

For large clusters (1000+ volumes), consider:
- Running during off-peak hours
- Processing in batches
- Using parallel processing (advanced)
