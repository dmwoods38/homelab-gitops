# Adding New Node to Cluster

Step-by-step guide with proper verification to avoid boot loops and failed installs.

## Pre-Flight Checklist

Before doing ANYTHING, verify these on the new node:

### 1. Check Node is in Maintenance Mode
```bash
# Replace XX with actual IP
talosctl --nodes 192.168.2.XX version --insecure

# Should show:
# Server:
#   error: API is not implemented in maintenance mode
# OR
# Server:
#   Tag: v1.11.5
```

### 2. Identify Available Disks
```bash
talosctl --nodes 192.168.2.XX get disks --insecure

# Look for the main system disk - examples:
# /dev/sda (SATA/SAS drives)
# /dev/nvme0n1 (NVMe drives)
# /dev/vda (Virtual machines)
```

### 3. Check for GPU (determines which image to use)
```bash
talosctl --nodes 192.168.2.XX read /proc/driver/nvidia/version --insecure 2>&1

# If you see "NVRM version: NVIDIA UNIX..." → Use NVIDIA image
# If you see "no such file or directory" → Use vanilla image
```

## Node Configuration

### 4. Decrypt and Prepare Config

```bash
cd /home/dmwoods38/dev/homelab/homelab-gitops

# For control plane:
sops -d talos/machine-configs/controlplane1.sops.yaml > /tmp/new-node.yaml

# For worker:
sops -d talos/machine-configs/worker.sops.yaml > /tmp/new-node.yaml
```

### 5. Update Config with Verified Values

**CRITICAL: Update BEFORE applying!**

```bash
# 1. Set correct disk (from step 2)
sed -i 's|disk: /dev/nvme0n1|disk: /dev/sda|' /tmp/new-node.yaml

# 2. Set correct installer image:
# If GPU detected in step 3:
sed -i 's|image: ghcr.io/siderolabs/installer:v1.11.5|image: factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.5|' /tmp/new-node.yaml

# If NO GPU:
sed -i 's|image: factory.talos.dev/installer/.*|image: ghcr.io/siderolabs/installer:v1.11.5|' /tmp/new-node.yaml

# 3. Enable disk wipe (fresh install)
sed -i 's|wipe: false|wipe: true|' /tmp/new-node.yaml

# 4. Add node IP to API server cert SANs (control plane only)
# Find the certSANs section and add the new IP
```

### 6. Verify Config Before Applying

```bash
# Check install section has correct values
grep -A3 "install:" /tmp/new-node.yaml

# Should show:
#   disk: /dev/sda (or your actual disk)
#   image: ghcr.io/siderolabs/installer:v1.11.5 (or NVIDIA factory image)
#   wipe: true
```

## Apply Configuration

### 7. Apply Config to Node

```bash
talosctl apply-config --insecure --nodes 192.168.2.XX --file /tmp/new-node.yaml

# Node will now:
# 1. Download installer image
# 2. Wipe disk (because wipe: true)
# 3. Install Talos
# 4. Reboot into installed system
```

### 8. Wait for Installation (2-3 minutes)

```bash
# Watch for node to reboot and come online
watch kubectl get nodes
```

### 9. Verify Node Joined

```bash
# Should see new node
kubectl get nodes -o wide

# Check node is Ready (may take 1-2 minutes)
# NAME            STATUS   ROLES           AGE   VERSION
# talos-xxx-xxx   Ready    control-plane   2m    v1.34.1
```

## Troubleshooting

### Node boots back into old OS
**Problem:** `wipe: false` in config or wrong disk specified

**Fix:**
```bash
# 1. Reboot into Talos installer/maintenance mode
# 2. Verify disk path with: talosctl get disks --insecure
# 3. Update config with correct disk
# 4. Ensure wipe: true
# 5. Reapply config
```

### Node stuck "NotReady" with NVIDIA service errors
**Problem:** Used NVIDIA factory image on non-GPU node

**Fix:**
```bash
# Upgrade to vanilla image
talosctl --nodes 192.168.2.XX upgrade \
  --image ghcr.io/siderolabs/installer:v1.11.5 \
  --preserve

# Or reboot into maintenance and reapply with correct image
```

### "Insufficient nvidia.com/gpu" errors on GPU node
**Problem:** Used vanilla image instead of NVIDIA factory image

**Fix:**
```bash
# Upgrade to NVIDIA image
talosctl --nodes 192.168.2.XX upgrade \
  --image factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.5 \
  --preserve
```

### Node shows "SchedulingDisabled"
**Fix:**
```bash
kubectl uncordon talos-xxx-xxx
```

## Common Node Types

### Intel NUC (GPU)
```yaml
install:
  disk: /dev/nvme0n1  # or /dev/sda - CHECK FIRST
  image: factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.5
  wipe: true
```

### Mac Mini (No GPU)
```yaml
install:
  disk: /dev/sda  # CHECK - Macs vary
  image: ghcr.io/siderolabs/installer:v1.11.5
  wipe: true
```

### VM (No GPU)
```yaml
install:
  disk: /dev/vda  # or /dev/sda - depends on VM config
  image: ghcr.io/siderolabs/installer:v1.11.5
  wipe: true
```

## Factory Images Reference

### NVIDIA GPU + iSCSI
```
factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.5
```
Includes:
- nonfree-kmod-nvidia-lts (535.247.01)
- nvidia-container-toolkit-lts
- iscsi-tools

### Vanilla Talos
```
ghcr.io/siderolabs/installer:v1.11.5
```
Standard installation, no extensions.

## NEVER DO THIS

❌ **DON'T** assume disk path - always check with `get disks`
❌ **DON'T** apply config without verifying image type matches hardware
❌ **DON'T** forget to set `wipe: true` for fresh installs
❌ **DON'T** use NVIDIA image on non-GPU nodes
❌ **DON'T** use vanilla image on GPU nodes (GPU won't work)
