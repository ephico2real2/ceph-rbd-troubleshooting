# Ceph RBD PVC Troubleshooting Toolkit

A comprehensive set of scripts and tools for troubleshooting Ceph RBD (RADOS Block Device) volumes in OpenShift Data Foundation (ODF) on OpenShift 4.18.

## 🚀 Quick Start

```bash
# Clone the repository
git clone git@github.com:ephico2real2/ceph-rbd-troubleshooting.git
cd ceph-rbd-troubleshooting

# One command to setup and fetch RBD data
./setup-and-fetch-rbd-data.sh

# Run analysis
./run-analysis-in-pod.sh

# Find high usage PVCs
./find-high-usage-pvcs.sh ceph-rbd-out.txt 80
```

## 📋 Features

- **Automated Data Collection**: Automatically copies scripts to rook-ceph-operator pod and fetches RBD data
- **PVC Mapping**: Map RBD volumes to OpenShift PVCs and namespaces
- **Usage Analysis**: Identify high usage and over-provisioned volumes
- **Batch Processing**: Process multiple volumes at once
- **Warning Filtering**: Automatically filters Ceph warning messages

## 📁 Scripts Overview

### Automation Scripts

- **`setup-and-fetch-rbd-data.sh`** - One-command setup: copies script to pod, fetches RBD data, copies output to local directory
- **`run-analysis-in-pod.sh`** - Run the analysis script directly in the rook-ceph-operator pod
- **`get-pod-shell.sh`** - Get an interactive shell in the pod with CEPH_ARGS pre-configured

### Analysis Scripts

- **`ceph-pvc-analysis.sh`** - Analyze RBD volumes directly from Ceph (run in pod)
- **`find-high-usage-pvcs.sh`** - Find PVCs with high usage by combining RBD data with cluster info
- **`batch-map-rbd-to-pvc.sh`** - Batch map multiple RBD volumes to their PVCs
- **`map-rbd-to-pvc.sh`** - Map a single RBD volume to its PVC and namespace
- **`query-all-pvcs.sh`** - Query all PVCs in the cluster with various views

### Reference

- **`quick-commands.sh`** - Quick reference of one-liner commands

## 📚 Documentation

- **[README-WORKFLOW.md](README-WORKFLOW.md)** - Complete workflow guide with step-by-step instructions
- **[SCRIPT-EXPLANATIONS.md](SCRIPT-EXPLANATIONS.md)** - Detailed explanations of each script
- **[README-ceph-troubleshooting.md](README-ceph-troubleshooting.md)** - Original troubleshooting guide
- **[VERIFICATION.md](VERIFICATION.md)** - Verification that scripts use the correct patterns

## 🔧 Prerequisites

1. Access to the `rook-ceph-operator` pod (for RBD commands)
2. Access to OpenShift cluster with `oc` or `kubectl` (for PVC queries)
3. `jq` installed (for JSON parsing)
4. `bc` installed (for calculations)

## 💡 Usage Examples

### Complete Workflow

```bash
# 1. Setup and fetch data
./setup-and-fetch-rbd-data.sh

# 2. Run analysis in pod
./run-analysis-in-pod.sh

# 3. Find high usage PVCs (>80%)
./find-high-usage-pvcs.sh ceph-rbd-out.txt 80

# 4. Batch map all volumes
./batch-map-rbd-to-pvc.sh ceph-rbd-out.txt > volume-mapping.txt

# 5. Query all PVCs
./query-all-pvcs.sh > all-pvcs.txt
```

### Environment Variables

All scripts support:
- `NAMESPACE`: OpenShift namespace (default: `openshift-storage`)
- `POOL`: Ceph pool name (default: `ocs-storagecluster-cephblockpool`)

```bash
NAMESPACE=my-namespace POOL=my-pool ./setup-and-fetch-rbd-data.sh
```

## 🎯 What It Does

1. **Finds the rook-ceph-operator pod** automatically
2. **Copies analysis script** to `/tmp/` in the pod
3. **Runs RBD commands** with proper `CEPH_ARGS` configuration
4. **Filters warnings** from Ceph output
5. **Copies output file** to your current directory
6. **Maps volumes to PVCs** using OpenShift API

## 📝 Script Details

### `setup-and-fetch-rbd-data.sh`

The main automation script that:
- Uses pattern: `TOOLS_POD=$(oc get pods -n openshift-storage -l app=rook-ceph-operator -o name)`
- Uses pattern: `export CEPH_ARGS='-c /var/lib/rook/openshift-storage/openshift-storage.config'`
- Copies `ceph-pvc-analysis.sh` to pod
- Runs `rbd $CEPH_ARGS du -p` to collect data
- Copies `ceph-rbd-out.txt` to local directory

### `ceph-pvc-analysis.sh`

Updated to use `$CEPH_ARGS` in all `rbd` commands:
- Top 20 volumes by provisioned size
- Top 20 volumes by used size
- High usage volumes (>80%)
- Over-provisioned volumes (>50GiB, <10% used)
- Summary statistics

## 🔍 Troubleshooting

See [README-WORKFLOW.md](README-WORKFLOW.md) for detailed troubleshooting guide.

Common issues:
- **Pod not found**: Check namespace and pod label
- **Permission denied**: Verify OpenShift permissions
- **CEPH_ARGS not working**: Verify config file exists in pod

## 📄 License

This toolkit is provided as-is for troubleshooting Ceph RBD volumes in OpenShift Data Foundation.

## 🤝 Contributing

Feel free to submit issues or pull requests for improvements.

## 📧 Support

For issues or questions, please open an issue on GitHub.

---

**Repository**: https://github.com/ephico2real2/ceph-rbd-troubleshooting
