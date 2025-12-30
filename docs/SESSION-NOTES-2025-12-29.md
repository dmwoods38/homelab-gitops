# Session Notes - 2025-12-29

## Summary

Successfully completed 3-node Talos Kubernetes HA cluster build and verification. Fixed critical NVIDIA kernel modules issue that was preventing node .20 from completing boot sequence.

## What Was Done

### 1. Cluster Bootstrap (from previous session)

Built fresh 3-node cluster:
- Node .20 (192.168.2.20) - NUC with NVIDIA GTX 1650
- Node .223 (192.168.2.223) - Standard node
- Mac .49 (192.168.2.49) - Mac Mini

All nodes installed with `wipe: true` to ensure clean installations and remove old boot entries.

### 2. Verification Reboot Testing

Rebooted each node one-by-one to verify installations:

**Node .20 Issue Discovered:**
- Rebooted .20 for verification
- kubectl showed node as Ready
- But `talosctl get machinestatus` showed `STAGE=booting` (not "running")
- User correctly identified nvidia-persistenced service was waiting in boot logs

**Root Cause:**
- NVIDIA factory image includes nvidia extensions
- But kernel modules (nvidia, nvidia_uvm, nvidia_drm, nvidia_modeset) were NOT configured
- ext-nvidia-persistenced service waited forever for `/sys/bus/pci/drivers/nvidia`
- This prevented Talos from reaching "running" stage

**Fix Applied:**
```bash
# Created kernel modules patch
cat > /tmp/nvidia-kernel-modules-patch.yaml <<'EOF'
machine:
  kernel:
    modules:
      - name: nvidia
      - name: nvidia_uvm
      - name: nvidia_drm
      - name: nvidia_modeset
EOF

# Applied patch
talosctl --nodes 192.168.2.20 patch machineconfig --patch @/tmp/nvidia-kernel-modules-patch.yaml

# Rebooted to load modules
talosctl --nodes 192.168.2.20 reboot
```

**Result:**
- NVIDIA kernel modules loaded successfully
- ext-nvidia-persistenced service started
- Node .20 reached `STAGE=running`
- Verified with `talosctl get machinestatus`

### 3. Node .223 Misconfiguration Fix

**Issue Discovered:**
- Node .223 was using NVIDIA factory image (86a5d7c9...)
- .223 doesn't have a GPU
- Node stuck in `STAGE=booting` waiting for nvidia driver that doesn't exist

**Fix Applied:**
```bash
# Upgraded to vanilla Talos image
talosctl --nodes 192.168.2.223 upgrade --image ghcr.io/siderolabs/installer:v1.11.5 --preserve
```

**Result:**
- Node .223 upgraded to vanilla image
- No nvidia services running
- Node reached `STAGE=running`
- Verified with reboot test

### 4. Mac .49 Verification

**Status:**
- Already using vanilla Talos image (correct)
- No nvidia configuration (correct)
- Rebooted successfully
- Reached `STAGE=running`

### 5. Final Cluster Verification

All three nodes verified:
```bash
kubectl get nodes
# All 3 nodes Ready

talosctl --nodes 192.168.2.20,192.168.2.223,192.168.2.49 get machinestatus
# All 3 nodes: STAGE=running, READY=true

talosctl --nodes 192.168.2.20 get members
# 3 voting members in etcd
```

Each node rebooted individually to verify they boot correctly from installed disk.

## Documentation Created/Updated

### New Documents:
1. **`docs/3-node-cluster-DR.md`** - Comprehensive disaster recovery guide
   - Complete cluster rebuild procedures
   - Single node replacement procedures
   - etcd quorum recovery
   - Common issues and fixes
   - Pre-flight checklist

2. **`docs/CLUSTER-STATUS.md`** - Current cluster state reference
   - Node inventory and specifications
   - Software versions
   - Known issues and workarounds
   - Quick health check commands

3. **`docs/SESSION-NOTES-2025-12-29.md`** - This file
   - What we did today
   - Issues discovered and fixed
   - Lessons learned

### Updated Documents:
1. **`docs/README.md`**
   - Added link to new 3-node DR guide as primary reference
   - Updated cluster destruction counter (3 → 4)
   - Added lessons learned about NVIDIA kernel modules

2. **`docs/talos-gpu-setup.md`**
   - Added critical warning about kernel modules at top
   - Added comprehensive troubleshooting section for "stuck in booting"
   - Documented the exact fix with step-by-step commands

## Key Lessons Learned

### 1. NVIDIA Kernel Modules Are Mandatory
**Problem:** NVIDIA factory image includes extensions but doesn't configure kernel modules.

**Impact:** Node stays in "booting" stage forever, ext-nvidia-persistenced waits for nvidia driver.

**Solution:** Always apply kernel modules patch:
```yaml
machine:
  kernel:
    modules:
      - name: nvidia
      - name: nvidia_uvm
      - name: nvidia_drm
      - name: nvidia_modeset
```

**When to apply:**
- Include in initial machine config, OR
- Apply as patch immediately after node installation, before expecting it to fully boot

### 2. Only GPU Nodes Should Use NVIDIA Factory Image
**Problem:** Node .223 was using NVIDIA factory image even though it has no GPU.

**Impact:** Unnecessary services waiting for hardware that doesn't exist, node stuck in "booting".

**Solution:**
- Only .20 should use: `factory.talos.dev/installer/86a5d7c9beb23b4aea2777e44ca06c8c2ceea8a874ccd2b9a6743c4f734329e0:v1.11.5`
- .223 and .49 should use: `ghcr.io/siderolabs/installer:v1.11.5`

### 3. kubectl "Ready" Doesn't Mean Talos Is "Running"
**Problem:** kubectl showed node as Ready, but Talos was still in "booting" stage.

**Impact:** Services start, cluster appears healthy, but node isn't actually fully booted.

**Solution:** Always check Talos machine status separately:
```bash
# Check Kubernetes status
kubectl get nodes

# Check Talos status
talosctl --nodes 192.168.2.XX get machinestatus
# Look for STAGE=running (not "booting")
```

### 4. Verify Installations with Reboot Testing
**Why:** Ensures nodes actually boot from installed disk, not USB or old OS.

**How:** Reboot each node one-by-one and verify:
- Node comes back online
- Talos reaches "running" stage
- Kubernetes shows Ready
- No services stuck in Waiting

### 5. Mac Disk Paths Are Volatile
**Issue:** Mac disk path changes based on USB presence.

**WITH USB:** /dev/sdc (Apple SSD)
**WITHOUT USB:** /dev/sda (Apple SSD)

**Solution:** Always verify with `talosctl disks` before applying config.

## Current Cluster State

**Status:** ✅ Fully Operational

**Nodes:**
- .20: `STAGE=running`, NVIDIA modules loaded, GPU functional
- .223: `STAGE=running`, vanilla Talos, no GPU
- .49: `STAGE=running`, vanilla Talos, no GPU

**etcd:** 3 voting members, 2-of-3 quorum

**Verification:**
```bash
# All passed
kubectl get nodes                          # 3/3 Ready
talosctl get machinestatus --nodes all     # 3/3 running
talosctl get members --nodes 192.168.2.20  # 3/3 voting members
```

## Next Steps

### Immediate:
- ✅ Documentation complete
- ✅ Cluster verified operational
- ✅ All nodes tested with reboot

### Future:
1. **Deploy GPU workloads** (if needed)
   - Apply RuntimeClass: `kubectl apply -f talos/manifests/nvidia-runtimeclass.yaml`
   - Deploy device plugin (see talos-gpu-setup.md Step 5)
   - Deploy Plex with GPU support

2. **Setup etcd backups**
   - Implement automated etcd snapshots
   - Store backups off-cluster

3. **Consider adding worker nodes**
   - Current cluster is 3 control-plane nodes only
   - Adding workers would allow:
     - Running heavier workloads (ArgoCD, Prometheus)
     - Better resource isolation
     - Dedicated GPU workload nodes

4. **Monitor cluster health**
   - Set up lightweight monitoring (avoid heavy Prometheus stack)
   - Watch etcd performance
   - Track node resource usage

## Files to Backup

Critical files that must not be lost:

1. `~/.config/sops/age/keys.txt` - SOPS decryption key
2. `~/.talos/config` - Talosctl cluster access
3. `~/.kube/config` - Kubectl cluster access
4. Machine configs (SOPS encrypted):
   - `talos/machine-configs/controlplane1.sops.yaml`
   - `talos/machine-configs/controlplane2.sops.yaml`
   - `talos/machine-configs/controlplane3.sops.yaml`
5. Recent working configs (for DR):
   - `/tmp/controlplane1-rebuild.yaml` or `/tmp/cp1-clean.yaml`
   - `/tmp/controlplane2-mac.yaml`
   - `/tmp/controlplane3-223.yaml`

## Commands Reference

### Quick Health Check
```bash
kubectl get nodes
talosctl --nodes 192.168.2.20,192.168.2.223,192.168.2.49 get machinestatus
talosctl --nodes 192.168.2.20 get members
```

### Check NVIDIA on .20
```bash
talosctl --nodes 192.168.2.20 read /proc/modules | grep nvidia
talosctl --nodes 192.168.2.20 services | grep nvidia
talosctl --nodes 192.168.2.20 get machinestatus
```

### Verify etcd Cluster
```bash
talosctl --nodes 192.168.2.20 etcd members
talosctl --nodes 192.168.2.20 etcd status
```

## Time Spent

**Total cluster rebuild:** ~30 minutes
**NVIDIA issue diagnosis and fix:** ~15 minutes
**Documentation:** ~20 minutes
**Verification testing:** ~10 minutes

**Total session:** ~75 minutes

## Success Metrics

✅ 3-node HA cluster operational
✅ All nodes in "running" stage
✅ etcd quorum healthy (3/3 members)
✅ NVIDIA modules loaded on .20
✅ All nodes verified with reboot test
✅ Comprehensive DR documentation created
✅ Known issues documented with fixes
✅ Cluster ready for workload deployment

## Cluster Destruction Counter

**Previous:** 3
**Current:** 4

**Latest destruction:** etcd quorum deadlock during 3-node migration (2025-12-29)
**Recovery method:** Complete rebuild with fresh installations

**Lessons applied:**
- Used fresh USB installer
- Verified disk paths before config application
- Set wipe: true on all nodes
- Bootstrapped only first node
- Let other nodes join automatically
- Fixed NVIDIA kernel modules issue immediately
- Verified with reboot testing

## Final Notes

This cluster is now properly configured as a 3-node HA setup with:
- Proper etcd quorum (can survive 1 node failure)
- GPU support on .20 with working NVIDIA drivers
- Clean installations on all nodes
- Comprehensive DR documentation
- Known issues documented and resolved

The cluster is ready for production workloads, but remember:
- Don't deploy heavy monitoring stack (ArgoCD, Prometheus) - insufficient resources
- Deploy lightweight services only (Plex, basic storage)
- Monitor etcd health closely
- Consider adding dedicated worker nodes for heavy workloads

**Key takeaway:** Always verify Talos machine status, not just Kubernetes node status. A node can be "Ready" in Kubernetes but still "booting" in Talos if a service is waiting for dependencies.
