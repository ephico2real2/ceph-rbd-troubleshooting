# Workflow Guide: Automated RBD Data Collection

This guide explains how to use the automated scripts to collect RBD data from the rook-ceph-operator pod.

## Quick Start

### Option 1: Automated Setup and Fetch (Recommended)

```bash
# This will:
# 1. Find the rook-ceph-operator pod
# 2. Copy the analysis script to the pod
# 3. Run rbd du and save output
# 4. Copy the output file to your current directory
./setup-and-fetch-rbd-data.sh
```

The output file `ceph-rbd-out.txt` will be in your current working directory.

### Option 2: Run Analysis in Pod

```bash
# Run the analysis script directly in the pod
./run-analysis-in-pod.sh
```

### Option 3: Get Interactive Shell

```bash
# Get a shell in the pod with CEPH_ARGS pre-configured
./get-pod-shell.sh
```

## Detailed Workflow

### Step 1: Initial Setup (One-time or when pod restarts)

```bash
cd /Users/olasumbo/gitRepos/ceph-rbd-troubleshooting

# Run the setup script
./setup-and-fetch-rbd-data.sh
```

**What it does:**
1. Finds the rook-ceph-operator pod automatically
2. Copies `ceph-pvc-analysis.sh` to `/tmp/` in the pod
3. Makes the script executable
4. Runs `rbd du` with proper CEPH_ARGS
5. Filters warnings from output
6. Copies `ceph-rbd-out.txt` to your current directory

**Output:**
- Local file: `ceph-rbd-out.txt` in your current directory
- Script in pod: `/tmp/ceph-pvc-analysis.sh`

### Step 2: Run Analysis

You have two options:

#### Option A: Run analysis in pod (see results immediately)
```bash
./run-analysis-in-pod.sh
```

#### Option B: Use local file with other scripts
```bash
# Find high usage PVCs
./find-high-usage-pvcs.sh ceph-rbd-out.txt 80

# Batch map volumes to PVCs
./batch-map-rbd-to-pvc.sh ceph-rbd-out.txt

# Query all PVCs
./query-all-pvcs.sh
```

### Step 3: Refresh Data (When needed)

If you need fresh data:
```bash
# Just run setup again - it will overwrite the local file
./setup-and-fetch-rbd-data.sh
```

## Script Details

### `setup-and-fetch-rbd-data.sh`

**Purpose:** One-command setup and data collection

**What it does:**
- Automatically finds the rook-ceph-operator pod
- Copies analysis script to pod
- Runs RBD commands with proper environment
- Copies output file to local directory

**Environment Variables:**
- `NAMESPACE`: OpenShift namespace (default: `openshift-storage`)
- `POOL`: Ceph pool name (default: `ocs-storagecluster-cephblockpool`)

**Usage:**
```bash
# Default settings
./setup-and-fetch-rbd-data.sh

# Custom namespace and pool
NAMESPACE=my-namespace POOL=my-pool ./setup-and-fetch-rbd-data.sh
```

**Output Files:**
- Local: `ceph-rbd-out.txt` (in current directory)
- Pod: `/tmp/ceph-rbd-out.txt`
- Pod: `/tmp/ceph-pvc-analysis.sh`

### `run-analysis-in-pod.sh`

**Purpose:** Run the analysis script in the pod

**What it does:**
- Checks if script exists in pod (runs setup if not)
- Executes analysis with proper CEPH_ARGS
- Shows results in terminal

**Usage:**
```bash
./run-analysis-in-pod.sh
```

### `get-pod-shell.sh`

**Purpose:** Get an interactive shell in the pod

**What it does:**
- Connects to rook-ceph-operator pod
- Sets CEPH_ARGS automatically
- Gives you a shell for manual commands

**Usage:**
```bash
./get-pod-shell.sh

# Once in the pod, you can run:
rbd $CEPH_ARGS du -p ocs-storagecluster-cephblockpool
/tmp/ceph-pvc-analysis.sh
```

## Manual Workflow (If Needed)

If you prefer to do things manually:

### 1. Find the Pod
```bash
TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-operator -o jsonpath='{.items[0].metadata.name}')
echo $TOOLS_POD
```

### 2. Copy Script to Pod
```bash
oc cp ceph-pvc-analysis.sh openshift-storage/$TOOLS_POD:/tmp/ceph-pvc-analysis.sh
oc exec -n openshift-storage $TOOLS_POD -- chmod +x /tmp/ceph-pvc-analysis.sh
```

### 3. Run RBD Command in Pod
```bash
oc exec -n openshift-storage $TOOLS_POD -- \
  sh -c "export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config' && \
         rbd \$CEPH_ARGS du -p ocs-storagecluster-cephblockpool 2>&1 | \
         grep -v '^warning:' > /tmp/ceph-rbd-out.txt"
```

### 4. Copy Output from Pod
```bash
oc cp openshift-storage/$TOOLS_POD:/tmp/ceph-rbd-out.txt ./ceph-rbd-out.txt
```

### 5. Run Analysis Script in Pod
```bash
oc exec -n openshift-storage $TOOLS_POD -- \
  sh -c "export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config' && \
         export POOL=ocs-storagecluster-cephblockpool && \
         /tmp/ceph-pvc-analysis.sh"
```

## Environment Variables

All scripts respect these environment variables:

- **NAMESPACE**: OpenShift namespace (default: `openshift-storage`)
- **POOL**: Ceph pool name (default: `ocs-storagecluster-cephblockpool`)

Example:
```bash
export NAMESPACE=my-storage-namespace
export POOL=my-ceph-pool
./setup-and-fetch-rbd-data.sh
```

## Troubleshooting

### Pod Not Found
```
Error: Could not find rook-ceph-operator pod
```
**Solution:** Check namespace and pod label:
```bash
oc get pods -n openshift-storage -l app=rook-ceph-operator
```

### Permission Denied
```
Error: Failed to copy script to pod
```
**Solution:** Check your OpenShift permissions:
```bash
oc auth can-i create pods/exec -n openshift-storage
```

### CEPH_ARGS Not Working
If `rbd` commands fail, verify the config file exists:
```bash
oc exec -n openshift-storage $TOOLS_POD -- \
  ls -la /var/lib/rook/openshift-storage/openshift-storage.config
```

### File Not Found After Copy
If the output file doesn't appear locally:
1. Check if copy succeeded: `oc exec -n openshift-storage $TOOLS_POD -- ls -la /tmp/ceph-rbd-out.txt`
2. Try copying manually: `oc cp openshift-storage/$TOOLS_POD:/tmp/ceph-rbd-out.txt ./ceph-rbd-out.txt`

## Complete Example Workflow

```bash
# 1. Navigate to script directory
cd /Users/olasumbo/gitRepos/ceph-rbd-troubleshooting

# 2. Setup and fetch data (one command!)
./setup-and-fetch-rbd-data.sh

# 3. Run analysis in pod
./run-analysis-in-pod.sh

# 4. Use local file for PVC mapping
./find-high-usage-pvcs.sh ceph-rbd-out.txt 80

# 5. Batch map all volumes
./batch-map-rbd-to-pvc.sh ceph-rbd-out.txt > volume-mapping.txt

# 6. Query all PVCs
./query-all-pvcs.sh > all-pvcs.txt
```

## File Locations

### Local Files (Your Machine)
- `ceph-rbd-out.txt` - RBD usage data (in current directory)
- All analysis scripts in the directory

### Pod Files (rook-ceph-operator)
- `/tmp/ceph-pvc-analysis.sh` - Analysis script
- `/tmp/ceph-rbd-out.txt` - RBD usage data (temporary)

## Best Practices

1. **Run setup once** - The script stays in the pod until pod restart
2. **Refresh data regularly** - Run `setup-and-fetch-rbd-data.sh` to get fresh data
3. **Keep local files** - The local `ceph-rbd-out.txt` persists even if pod restarts
4. **Use local files for analysis** - Faster than querying pod each time
5. **Check pod before running** - Pods can restart, script may need to be re-copied
