# Current Cluster Status

**Last Updated:** 2025-12-29 (GPU working)
**Cluster Type:** 3-node HA Talos Kubernetes cluster
**Status:** ✅ Operational (with GPU transcoding)

## Quick Health Check

```bash
# All nodes should be Ready
kubectl get nodes

# All nodes should be in "running" stage (not "booting")
talosctl --nodes 192.168.2.20,192.168.2.223,192.168.2.49 get machinestatus

# etcd should have 3 healthy members
talosctl --nodes 192.168.2.20 get members
```

## Node Details

| Node | IP | Hostname | Role | CPU | RAM | Disk | Factory Image | GPU |
|------|-------|----------|------|-----|-----|------|---------------|-----|
| **NUC .20** | 192.168.2.20 | talos-gpu | worker | ? | ? | /dev/nvme0n1 (256GB Intel) | NVIDIA (86a5d7c9...) | GTX 1650 |
| **Node .223** | 192.168.2.223 | talos-nuc | control-plane | ? | ? | /dev/nvme0n1 (500GB Samsung) | Vanilla (ghcr.io) | None |
| **Mac .49** | 192.168.2.49 | talos-mac | control-plane | ? | ? | /dev/sda (500GB Apple SSD) | Vanilla (ghcr.io) | None |

## Software Versions

- **Talos:** v1.11.5
- **Kubernetes:** v1.34.1
- **NVIDIA Driver:** 535.247.01 (on .20 only)
- **NVIDIA Container Toolkit:** 535.247.01-v1.17.8 (on .20 only)

## etcd Configuration

- **Quorum:** 2-of-2 (requires minimum 2 healthy nodes)
- **Fault Tolerance:** Can survive 0 node failures (both control-plane nodes required)
- **Members:** 2 voting members (talos-nuc, talos-mac)
- **Data Location:** `/var/lib/etcd` on each control plane node

## Factory Images Used

**Node .20 (GPU):**
```
factory.talos.dev/installer/86a5d7c9beb23b4aea2777e44ca06c8c2ceea8a874ccd2b9a6743c4f734329e0:v1.11.5
```
Extensions:
- nonfree-kmod-nvidia-lts (535.247.01)
- nvidia-container-toolkit-lts (535.247.01)
- iscsi-tools

**Node .223 & Mac .49 (Standard):**
```
ghcr.io/siderolabs/installer:v1.11.5
```
No extensions.

## NVIDIA Configuration (Node .20 Only)

**Required Kernel Modules:**
- nvidia
- nvidia_uvm
- nvidia_drm
- nvidia_modeset

**Verification:**
```bash
# Modules should be loaded
talosctl --nodes 192.168.2.20 read /proc/modules | grep nvidia

# ext-nvidia-persistenced service should be Running
talosctl --nodes 192.168.2.20 services | grep nvidia

# Node should be in "running" stage (not "booting")
talosctl --nodes 192.168.2.20 get machinestatus
```

**If .20 is stuck in "booting":**
See [3-Node Cluster DR Guide](./3-node-cluster-DR.md#issue-node-stuck-in-booting-stage)

## Network Configuration

**API Server Endpoints:**
- 192.168.2.223:6443 (talos-nuc)
- 192.168.2.49:6443 (talos-mac)

**certSANs (must include all control plane IPs):**
- 192.168.2.223
- 192.168.2.49

## Critical Files

**Machine Configs (SOPS encrypted):**
- `talos/machine-configs/controlplane1.sops.yaml` - Node .20
- `talos/machine-configs/controlplane2.sops.yaml` - Mac .49
- `talos/machine-configs/controlplane3.sops.yaml` - Node .223

**Recent Working Configs (unencrypted, for DR):**
- `/tmp/controlplane1-rebuild.yaml` or `/tmp/cp1-clean.yaml` - Node .20
- `/tmp/controlplane2-mac.yaml` - Mac .49
- `/tmp/controlplane3-223.yaml` - Node .223

**Keys:**
- `~/.config/sops/age/keys.txt` - SOPS decryption key
- `~/.talos/config` - Talosctl configuration
- `~/.kube/config` - Kubectl configuration

## Known Issues

### 1. Node .20 Requires NVIDIA Kernel Modules Patch

**Issue:** After fresh install, node .20 stays in "booting" stage forever.

**Cause:** ext-nvidia-persistenced service waits for nvidia driver, but kernel modules aren't configured.

**Fix:**
```bash
cat > /tmp/nvidia-kernel-modules-patch.yaml <<'EOF'
machine:
  kernel:
    modules:
      - name: nvidia
      - name: nvidia_uvm
      - name: nvidia_drm
      - name: nvidia_modeset
EOF

talosctl --nodes 192.168.2.20 patch machineconfig --patch @/tmp/nvidia-kernel-modules-patch.yaml
talosctl --nodes 192.168.2.20 reboot
```

### 2. Mac Disk Path Changes Based on USB Presence

**Issue:** Mac disk shows as /dev/sdc when USB is inserted, /dev/sda when USB is removed.

**Fix:** Always verify disk path before applying config:
```bash
talosctl --nodes 192.168.2.49 --insecure disks
```

### 3. Only Node .20 Should Have NVIDIA Configuration

**Issue:** Node .223 or Mac .49 installed with NVIDIA factory image get stuck in "booting".

**Fix:** Upgrade to vanilla Talos:
```bash
talosctl --nodes 192.168.2.XXX upgrade --image ghcr.io/siderolabs/installer:v1.11.5 --preserve
```

## Cluster History

**Build Date:** 2025-12-29
**Previous Destructions:** 4
**Current Uptime:** New cluster

**Last Changes:**
- Migrated from single-node to 3-node HA cluster
- Fixed NVIDIA kernel modules issue on .20
- Removed NVIDIA configuration from .223
- Verified all nodes boot correctly from disk

## Maintenance Schedule

**Regular Checks:**
- Daily: `kubectl get nodes` - verify all Ready
- Weekly: Verify etcd health and backup
- Monthly: Test DR procedure on test node

**Backup Schedule:**
- etcd snapshots: TBD
- Machine configs: Version controlled in Git + SOPS encrypted
- Age keys: Backed up offline

## Emergency Contacts

- **DR Guide:** [3-node-cluster-DR.md](./3-node-cluster-DR.md)
- **GPU Setup:** [talos-gpu-setup.md](./talos-gpu-setup.md)
- **Talos Docs:** https://www.talos.dev/
- **Talos Discord:** https://discord.gg/talos

## Upgrade Path

**Current:** Talos v1.11.5 / Kubernetes v1.34.1

**Before upgrading:**
1. Check Talos release notes
2. Backup etcd
3. Test on non-production node first
4. Upgrade one node at a time
5. Verify cluster health between upgrades

## Resource Limits

**Current Cluster Resources:**
- Total nodes: 3
- Control plane nodes: 3
- Worker nodes: 0 (control plane also runs workloads)

**Safe to Deploy:**
- ✅ Plex (GPU on .20, or CPU fallback)
- ✅ Basic storage (NFS PV/PVC)
- ✅ Lightweight services

**DO NOT Deploy:**
- ❌ ArgoCD (insufficient resources)
- ❌ Prometheus/Grafana stack (overwhelms etcd)
- ❌ Heavy monitoring
- ❌ Multiple resource-intensive services simultaneously

**Recommendation:** Add dedicated worker nodes if you need to run heavy services.
