# 3-Node Talos Cluster - Disaster Recovery Guide

**Last Updated:** 2025-12-29
**Cluster Status:** 3-node HA cluster operational

## Current Cluster Configuration

### Node Inventory

| Node | IP | Hostname | Role | Disk | Factory Image | GPU |
|------|-------|----------|------|------|---------------|-----|
| NUC .20 | 192.168.2.20 | talos-hfv-ykp | control-plane | /dev/nvme0n1 (256GB Intel) | NVIDIA (86a5d7c9...) | Yes (GTX 1650) |
| Node .223 | 192.168.2.223 | talos-6zg-d0c | control-plane | /dev/nvme0n1 (500GB Samsung) | Vanilla (ghcr.io) | No |
| Mac .49 | 192.168.2.49 | talos-qu2-nh1 | control-plane | /dev/sda (500GB Apple SSD) | Vanilla (ghcr.io) | No |

**etcd Quorum:** 2-of-3 (can survive 1 node failure)
**Talos Version:** v1.11.5
**Kubernetes Version:** v1.34.1

### Critical Files Location

```
homelab-gitops/
├── talos/machine-configs/
│   ├── controlplane1.sops.yaml    # Node .20 (GPU)
│   ├── controlplane2.sops.yaml    # Mac .49 (if exists)
│   └── controlplane3.sops.yaml    # Node .223 (if exists)
└── docs/
    ├── 3-node-cluster-DR.md       # This file
    └── talos-gpu-setup.md         # NVIDIA setup guide
```

**Working temp configs from last rebuild:**
- `/tmp/controlplane1-rebuild.yaml` or `/tmp/cp1-clean.yaml` - Node .20
- `/tmp/controlplane2-mac.yaml` - Mac .49
- `/tmp/controlplane3-223.yaml` - Node .223

## Disaster Recovery Scenarios

### Scenario 1: Single Node Failure (Cluster Still Up)

**If .223 or .49 fails (non-GPU nodes):**

1. Boot failed node from Talos USB installer (maintenance mode)
2. Verify disk path:
   ```bash
   talosctl --nodes 192.168.2.XXX --insecure disks
   ```
3. Apply appropriate config:
   ```bash
   # For .223:
   sops -d talos/machine-configs/controlplane3.sops.yaml > /tmp/cp3.yaml
   # OR use: /tmp/controlplane3-223.yaml if recent

   # For Mac .49:
   sops -d talos/machine-configs/controlplane2.sops.yaml > /tmp/cp2.yaml
   # OR use: /tmp/controlplane2-mac.yaml if recent

   # Apply (set wipe: true for fresh install)
   talosctl apply-config --insecure --nodes 192.168.2.XXX --file /tmp/cpX.yaml
   ```
4. Node will automatically join existing cluster (DO NOT bootstrap)
5. Verify:
   ```bash
   kubectl get nodes
   talosctl --nodes 192.168.2.XXX get members
   ```

**If .20 fails (GPU node):**

Same as above, but ensure:
- Config uses NVIDIA factory image: `factory.talos.dev/installer/86a5d7c9beb23b4aea2777e44ca06c8c2ceea8a874ccd2b9a6743c4f734329e0:v1.11.5`
- After node joins, apply NVIDIA kernel modules patch (see below)

### Scenario 2: Complete Cluster Failure (All Nodes Down)

**CRITICAL:** Only bootstrap ONE node. The others will join automatically.

#### Step 1: Prepare Fresh USB Installer

```bash
# Download fresh Talos ISO
cd ~/Downloads
wget https://github.com/siderolabs/talos/releases/download/v1.11.5/metal-amd64.iso

# Write to USB drive (verify device path first!)
sudo dd if=metal-amd64.iso of=/dev/sdX bs=4M status=progress
```

#### Step 2: Install Node .20 (Bootstrap Node)

1. Boot .20 from USB installer
2. Verify it's in maintenance mode:
   ```bash
   talosctl --nodes 192.168.2.20 --insecure version
   ```
3. Check disk path:
   ```bash
   talosctl --nodes 192.168.2.20 --insecure disks
   # Should show /dev/nvme0n1 (256GB Intel NVMe)
   ```
4. Apply config with wipe:
   ```bash
   # Use temp file or decrypt SOPS
   sops -d talos/machine-configs/controlplane1.sops.yaml > /tmp/cp1.yaml

   # VERIFY critical settings:
   grep "disk:" /tmp/cp1.yaml  # Should be /dev/nvme0n1
   grep "image:" /tmp/cp1.yaml # Should be factory.talos.dev...86a5d7c9...
   grep "wipe:" /tmp/cp1.yaml  # Should be true

   # VERIFY certSANs includes all 3 nodes:
   grep -A5 "certSANs:" /tmp/cp1.yaml
   # Should list: 192.168.2.20, 192.168.2.223, 192.168.2.49

   # Apply
   talosctl apply-config --insecure --nodes 192.168.2.20 --file /tmp/cp1.yaml
   ```
5. Wait for installation to complete (~30 seconds)
6. Bootstrap etcd:
   ```bash
   talosctl --nodes 192.168.2.20 bootstrap
   ```
7. Wait for cluster to come up (~60-90 seconds):
   ```bash
   watch kubectl get nodes
   ```

#### Step 3: Install Node .223

1. Boot .223 from USB installer
2. Verify disk:
   ```bash
   talosctl --nodes 192.168.2.223 --insecure disks
   # Should show /dev/nvme0n1 (500GB Samsung)
   ```
3. Apply config:
   ```bash
   sops -d talos/machine-configs/controlplane3.sops.yaml > /tmp/cp3.yaml
   # OR use /tmp/controlplane3-223.yaml

   # VERIFY:
   grep "disk:" /tmp/cp3.yaml    # /dev/nvme0n1
   grep "image:" /tmp/cp3.yaml   # ghcr.io/siderolabs/installer:v1.11.5
   grep "wipe:" /tmp/cp3.yaml    # true
   grep -A5 "certSANs:" /tmp/cp3.yaml  # All 3 IPs

   # Apply
   talosctl apply-config --insecure --nodes 192.168.2.223 --file /tmp/cp3.yaml
   ```
4. Wait for node to join (~30-60 seconds)
5. Verify:
   ```bash
   kubectl get nodes  # Should show 2 nodes
   talosctl --nodes 192.168.2.20 get members  # Should show 2 members
   ```

#### Step 4: Install Mac .49

1. Boot Mac from USB installer
2. **CRITICAL:** Mac disk path changes based on USB presence:
   - **WITH USB inserted:** /dev/sdc
   - **WITHOUT USB:** /dev/sda

   Always check:
   ```bash
   talosctl --nodes 192.168.2.49 --insecure disks
   # Look for 500GB Apple SSD - note the path!
   ```
3. Apply config (update disk path if needed):
   ```bash
   sops -d talos/machine-configs/controlplane2.sops.yaml > /tmp/cp2.yaml
   # OR use /tmp/controlplane2-mac.yaml

   # VERIFY and UPDATE disk path:
   grep "disk:" /tmp/cp2.yaml
   # If USB is inserted and you see /dev/sdc in the disk list, keep it
   # If USB is NOT inserted, change to /dev/sda

   # VERIFY:
   grep "image:" /tmp/cp2.yaml   # ghcr.io/siderolabs/installer:v1.11.5
   grep "wipe:" /tmp/cp2.yaml    # true
   grep -A5 "certSANs:" /tmp/cp2.yaml  # All 3 IPs

   # Apply
   talosctl apply-config --insecure --nodes 192.168.2.49 --file /tmp/cp2.yaml
   ```
4. Wait for node to join
5. Verify final cluster:
   ```bash
   kubectl get nodes  # Should show 3 nodes, all Ready
   talosctl --nodes 192.168.2.20 get members  # Should show 3 members
   ```

#### Step 5: Configure NVIDIA on Node .20

**CRITICAL:** The NVIDIA kernel modules AND sysctl patch is required or node .20 will be stuck in "booting" state!

1. Apply kernel modules and sysctl patch:
   ```bash
   cat > /tmp/nvidia-kernel-modules-patch.yaml <<'EOF'
   machine:
     kernel:
       modules:
         - name: nvidia
         - name: nvidia_uvm
         - name: nvidia_drm
         - name: nvidia_modeset
     sysctls:
       net.core.bpf_jit_harden: 1  # CRITICAL for nvidia-container-runtime BPF
   EOF

   talosctl --nodes 192.168.2.20 patch machineconfig --patch @/tmp/nvidia-kernel-modules-patch.yaml
   ```

2. Reboot node .20 to load modules:
   ```bash
   talosctl --nodes 192.168.2.20 reboot
   ```

3. Verify modules loaded:
   ```bash
   talosctl --nodes 192.168.2.20 read /proc/modules | grep nvidia
   # Should see: nvidia, nvidia_uvm, nvidia_drm, nvidia_modeset
   ```

4. Check machine status:
   ```bash
   talosctl --nodes 192.168.2.20 get machinestatus
   # STAGE should be "running" (not "booting")
   ```

5. Verify nvidia service:
   ```bash
   talosctl --nodes 192.168.2.20 services | grep nvidia
   # ext-nvidia-persistenced should be "Running"
   ```

#### Step 6: Verify Entire Cluster

```bash
# All nodes should be Ready
kubectl get nodes

# All nodes should be in "running" stage
talosctl --nodes 192.168.2.20,192.168.2.223,192.168.2.49 get machinestatus

# etcd should have 3 healthy members
talosctl --nodes 192.168.2.20 get members

# Reboot each node one-by-one to verify installations
talosctl --nodes 192.168.2.20 reboot
# Wait for .20 to come back
talosctl --nodes 192.168.2.223 reboot
# Wait for .223 to come back
talosctl --nodes 192.168.2.49 reboot
# Wait for .49 to come back

# Final verification
kubectl get nodes
# All should be Ready
```

### Scenario 3: etcd Quorum Lost (2+ Nodes Down)

If 2 or more nodes fail, you lose etcd quorum and the cluster is dead.

**Recovery:** Follow Scenario 2 (Complete Cluster Failure) - full rebuild required.

**Prevention:** This is why we have 3 nodes. Keep at least 2 running at all times.

## Common Issues and Fixes

### Issue: Node Stuck in "booting" Stage

**Symptom:**
```bash
talosctl --nodes 192.168.2.XX get machinestatus
# Shows STAGE=booting even though READY=true
```

**Cause:** Missing service waiting for dependencies (e.g., nvidia-persistenced waiting for nvidia driver)

**Fix for .20 (GPU node):**
1. Check if nvidia modules are loaded:
   ```bash
   talosctl --nodes 192.168.2.20 read /proc/modules | grep nvidia
   ```
2. If empty, apply kernel modules patch (see Step 5 above)
3. Reboot node

**Fix for .223 or .49 (Non-GPU nodes):**
- These should NOT have nvidia configuration
- If they do, upgrade to vanilla image:
  ```bash
  talosctl --nodes 192.168.2.XXX upgrade --image ghcr.io/siderolabs/installer:v1.11.5 --preserve
  ```

### Issue: Mac Disk Not Found After Apply

**Symptom:** Mac installed but boots to old Linux install instead of Talos

**Cause:** Disk path changed (USB presence affects device names)

**Fix:**
1. Boot from USB installer
2. Check disks WITHOUT USB:
   ```bash
   # Remove USB drive first!
   talosctl --nodes 192.168.2.49 --insecure disks
   ```
3. Update config with correct disk path (/dev/sda vs /dev/sdc)
4. Reapply with wipe: true

### Issue: etcd "too many requests" Errors

**Symptom:** API server slow or unresponsive, etcd logs show rate limiting

**Cause:** Cluster overload (too many services, resource contention)

**Fix:**
1. Delete heavy services immediately:
   ```bash
   kubectl delete namespace monitoring argocd --grace-period=30
   ```
2. **NEVER use --force --grace-period=0** (corrupts cluster state)
3. Wait for cluster to stabilize
4. Only deploy lightweight services

### Issue: Node Has Wrong certSANs (Can't Connect to API)

**Symptom:** Can't connect to API server from specific node IP

**Cause:** certSANs in machine config doesn't include all control plane IPs

**Fix:**
1. Update machine config to include all 3 node IPs:
   ```yaml
   cluster:
     apiServer:
       certSANs:
         - 192.168.2.20
         - 192.168.2.223
         - 192.168.2.49
   ```
2. Apply updated config to all nodes
3. Restart API server or reboot nodes

## Pre-Flight Checklist Before DR

Before you need to rebuild, make sure you have:

- [ ] Fresh Talos USB installer written to USB drive
- [ ] Age key backed up: `~/.config/sops/age/keys.txt`
- [ ] Talosconfig backed up: `~/.talos/config`
- [ ] Kubeconfig backed up: `~/.kube/config`
- [ ] Machine configs accessible:
  - [ ] `/tmp/controlplane1-rebuild.yaml` or SOPS encrypted version
  - [ ] `/tmp/controlplane2-mac.yaml` or SOPS encrypted version
  - [ ] `/tmp/controlplane3-223.yaml` or SOPS encrypted version
- [ ] Know which node has GPU (.20) and which don't (.223, .49)
- [ ] Verified disk paths for each node documented above
- [ ] This DR guide printed or accessible offline

## Factory Images Reference

**NVIDIA Image (for .20 only):**
```
factory.talos.dev/installer/86a5d7c9beb23b4aea2777e44ca06c8c2ceea8a874ccd2b9a6743c4f734329e0:v1.11.5
```

Includes:
- nonfree-kmod-nvidia-lts (535.247.01)
- nvidia-container-toolkit-lts (535.247.01)
- iscsi-tools

**Vanilla Image (for .223 and .49):**
```
ghcr.io/siderolabs/installer:v1.11.5
```

Standard Talos with no extensions.

## Lessons Learned

1. **ALWAYS verify disk paths before applying config** - don't assume /dev/sda or /dev/nvme0n1
2. **Mac disk paths change based on USB presence** - /dev/sdc with USB, /dev/sda without
3. **Only node .20 should have NVIDIA configuration** - .223 and .49 use vanilla Talos
4. **NVIDIA kernel modules patch is REQUIRED** - or node .20 stays in "booting" state
5. **Bootstrap ONLY the first node** - others join automatically
6. **Set wipe: true for clean installs** - removes old boot entries and OS
7. **Verify certSANs includes all control plane IPs** - or API access fails
8. **3-node etcd quorum requires 2-of-3 nodes** - can survive single node failure
9. **Check machine status with talosctl, not just kubectl** - kubectl shows Ready doesn't mean Talos is "running"
10. **Keep temp configs from last rebuild** - faster than decrypting SOPS every time

## Recovery Time Estimates

- **Single node replacement:** 5-10 minutes
- **Complete cluster rebuild (3 nodes):** 20-30 minutes
- **Complete rebuild + NVIDIA setup:** 30-45 minutes
- **Complete rebuild + GPU + workloads:** 45-60 minutes

## Cluster Destruction Counter: 6

Previous failures:
1. Initial cluster failure (pre-existing)
2. Prometheus/monitoring deployment overload
3. Force-delete corruption requiring re-bootstrap
4. **etcd quorum deadlock during 3-node migration** (2025-12-29)
5. **talosctl reset on talos-gpu (.20) - single node kill** (2026-01-02)
   - Attempted to fix CNI networking issue after node rename
   - Used `talosctl reset` instead of reboot - wiped entire node
   - Required full node recovery from scratch
6. **etcd auto-compaction failure - 12+ hour cluster outage** (2026-01-03)
   - During talos-gpu recovery, etcd auto-compaction config not validated
   - Node rejoined with default etcd settings (no compaction, 2GB quota vs 4GB)
   - Caused etcd database bloat leading to raft consensus deadlock
   - Entire cluster unavailable for 12+ hours before discovery
   - Required physical power cycle of all nodes to recover

Current cluster built: 2025-12-29 (survived incidents 5-6 without full rebuild)

## Next Steps After DR

1. Wait 5 minutes for cluster to stabilize
2. Verify all nodes Ready and in "running" stage
3. Deploy minimal workloads only (Plex, basic storage)
4. Monitor resource usage before adding services
5. Never deploy ArgoCD/Prometheus on this cluster (insufficient resources)
6. Consider dedicated worker nodes for heavy workloads

## Emergency Contact Info

- Talos Documentation: https://www.talos.dev/
- Talos Discord: https://discord.gg/talos
- This guide location: `docs/3-node-cluster-DR.md`
