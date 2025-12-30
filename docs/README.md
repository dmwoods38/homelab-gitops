# Homelab Documentation

Quick reference guides for cluster operations and recovery.

## Current Cluster Info

📋 **[Cluster Status & Configuration](./CLUSTER-STATUS.md)** - Current state, node details, versions

## Critical Guides

### 🚨 [3-Node Cluster DR Guide](./3-node-cluster-DR.md) **[USE THIS FIRST]**
**Use this when:** 3-node cluster needs recovery or rebuild.
**Updated:** 2025-12-29

Current cluster:
- Node .20 (192.168.2.20) - GPU node - /dev/nvme0n1
- Node .223 (192.168.2.223) - Standard - /dev/nvme0n1
- Mac .49 (192.168.2.49) - Standard - /dev/sda

Quick verification:
```bash
kubectl get nodes
talosctl --nodes 192.168.2.20,192.168.2.223,192.168.2.49 get machinestatus
```

### 🚨 [Single-Node Bootstrap/Recovery](./cluster-bootstrap.md)
**Use this when:** Legacy single-node cluster or individual node needs rebuild.

Quick commands:
```bash
sops -d talos/machine-configs/controlplane1.sops.yaml > /tmp/controlplane1.yaml
talosctl apply-config --insecure --nodes 192.168.2.20 --file /tmp/controlplane1.yaml
talosctl --nodes 192.168.2.20 bootstrap  # ONLY if fresh cluster
```

### 🎮 [GPU Setup Guide](./talos-gpu-setup.md)
**Use this when:** Setting up NVIDIA GPU support on node .20 for Plex hardware transcoding.
**Status:** ✅ Working on node .20

Critical steps:
- NVIDIA kernel modules patch required (or node stays in "booting")
- **sysctl `net.core.bpf_jit_harden: 1` is MANDATORY** (or nvidia runtime fails with BPF errors)
- Device plugin **MUST** use `runtimeClassName: nvidia`

## Cluster Destruction Counter: 4

Learn from these mistakes:
1. ❌ Don't deploy heavy monitoring stack on single node
2. ❌ Never use `kubectl delete --force --grace-period=0`
3. ❌ Don't deploy ArgoCD + Prometheus simultaneously on limited resources
4. ❌ **NVIDIA kernel modules patch is REQUIRED on .20** - or node stays in "booting" state forever
5. ❌ **sysctl `net.core.bpf_jit_harden: 1` is REQUIRED for GPU** - or nvidia-container-runtime BPF fails
6. ❌ Only node .20 has GPU - don't use NVIDIA factory image on .223 or .49

## File Organization

```
homelab-gitops/
├── docs/
│   ├── cluster-bootstrap.md        # Emergency recovery procedures
│   └── talos-gpu-setup.md          # NVIDIA GPU configuration
├── platform/
│   ├── gpu/
│   │   └── nvidia-device-plugin.yaml
│   └── media/
│       ├── media-storage.yaml       # NFS PV/PVC
│       ├── plex.yaml                # Plex with GPU
│       └── plex-cpu-only.yaml       # Plex without GPU (minimal)
└── talos/
    ├── machine-configs/
    │   └── controlplane1.sops.yaml  # Main cluster config (encrypted)
    ├── patches/
    │   ├── gpu-patch.yaml           # NVIDIA kernel modules
    │   └── installer-patch.yaml     # Factory image with extensions
    └── manifests/
        └── nvidia-runtimeclass.yaml
```

## Quick Reference

### Decrypt Configs
```bash
sops -d talos/machine-configs/controlplane1.sops.yaml > /tmp/controlplane1.yaml
```

### Check Cluster Health
```bash
kubectl get nodes
kubectl get pods -A
talosctl --nodes 192.168.2.20 service
```

### Deploy Plex
```bash
# With GPU
kubectl apply -f platform/media/media-storage.yaml
kubectl apply -f platform/media/plex.yaml

# Without GPU (minimal)
kubectl apply -f platform/media/plex-cpu-only.yaml
```

### Access Services
- Plex: http://192.168.2.20:32400
- Kubernetes API: https://192.168.2.20:6443

## When Things Break

1. **API server down:** See [cluster-bootstrap.md](./cluster-bootstrap.md)
2. **GPU not detected:** See [talos-gpu-setup.md](./talos-gpu-setup.md) troubleshooting section
3. **etcd "too many requests":** Delete heavy services immediately, DO NOT use --force
4. **Stuck namespace:** Use JSON patch to remove finalizers (see bootstrap guide)

## Recovery Time Estimates

- Bootstrap only: 2-3 minutes
- Bootstrap + Plex CPU: 5 minutes
- Bootstrap + Plex GPU: 15-20 minutes
- Full stack: DON'T on single node

## Important Files to Never Lose

1. `~/.config/sops/age/keys.txt` - Decryption key for all secrets
2. `~/.talos/config` - Talos cluster access
3. `~/.kube/config` - Kubernetes cluster access
4. `talos/machine-configs/controlplane1.sops.yaml` - Cluster configuration

Backup these regularly!
