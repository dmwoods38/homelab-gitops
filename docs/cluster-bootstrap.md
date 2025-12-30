# Talos Cluster Bootstrap/Recovery Guide

Quick reference for rebuilding the cluster after catastrophic failure.

## Prerequisites
- Talos node accessible at 192.168.2.20
- SOPS age key: `~/.config/sops/age/keys.txt`
- Machine config: `talos/machine-configs/controlplane1.sops.yaml`
- Talosconfig: Stored in `platform/etcd-backup/talosconfig-secret.sops.yaml`

## Quick Bootstrap Procedure

### 0. CRITICAL: Verify Node Configuration FIRST

**ALWAYS check these BEFORE applying config:**

```bash
# Check Talos is running (should see maintenance mode message)
talosctl --nodes 192.168.2.XX version --insecure

# List available disks (CRITICAL - don't assume /dev/sda or /dev/nvme0n1)
talosctl --nodes 192.168.2.XX get disks --insecure

# Common disk paths:
# - Intel NUC: /dev/nvme0n1 or /dev/sda
# - Mac: /dev/sda, /dev/nvme0n1, or /dev/disk/by-id/...
# - VM: /dev/vda or /dev/sda

# Check current machine config for correct disk path
grep "disk:" /tmp/controlplane1.yaml
# UPDATE THE CONFIG if disk doesn't match!

# Verify factory image matches node type:
# - NVIDIA GPU node: factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.5
# - Standard node: ghcr.io/siderolabs/installer:v1.11.5
grep "image:" /tmp/controlplane1.yaml
```

### 1. Decrypt Machine Config
```bash
cd /home/dmwoods38/dev/homelab/homelab-gitops
sops -d talos/machine-configs/controlplane1.sops.yaml > /tmp/controlplane1.yaml
```

### 2. UPDATE Config with Verified Disk and Image

**Edit the config BEFORE applying:**
```bash
# Example: Change disk path if needed
sed -i 's|disk: /dev/nvme0n1|disk: /dev/sda|' /tmp/controlplane1.yaml

# Example: Change to vanilla Talos if no GPU
sed -i 's|factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.5|ghcr.io/siderolabs/installer:v1.11.5|' /tmp/controlplane1.yaml

# Set wipe: true for fresh install (overwrites existing OS)
sed -i 's|wipe: false|wipe: true|' /tmp/controlplane1.yaml

# VERIFY changes
grep -A2 "install:" /tmp/controlplane1.yaml
```

### 3. Apply Configuration (Insecure if TLS broken)
```bash
# If certs are invalid, use --insecure
talosctl apply-config --insecure --nodes 192.168.2.XX --file /tmp/controlplane1.yaml

# If certs are valid
talosctl apply-config --nodes 192.168.2.XX --file /tmp/controlplane1.yaml
```

### 3. Bootstrap etcd
```bash
# Set endpoint first
talosctl --talosconfig /home/dmwoods38/.talos/config config endpoint 192.168.2.20

# Bootstrap the cluster (ONLY do this once, ONLY on fresh install)
talosctl --nodes 192.168.2.20 bootstrap
```

### 4. Wait for Cluster Ready
```bash
# Wait for API server (~60-90 seconds)
watch kubectl get nodes

# Expected output:
# NAME            STATUS   ROLES           AGE   VERSION
# talos-xxx-xxx   Ready    control-plane   2m    v1.34.1
```

### 5. Verify Core Services
```bash
# Check control plane pods
kubectl get pods -n kube-system

# Should see:
# - kube-apiserver
# - kube-controller-manager
# - kube-scheduler
# - coredns (2 replicas)
# - kube-flannel (CNI)
# - kube-proxy
```

## Post-Bootstrap: Deploy Minimal Services

### 6. Create Namespaces
```bash
kubectl create namespace media
kubectl label namespace media pod-security.kubernetes.io/enforce=privileged --overwrite
```

### 7. Deploy Media Storage
```bash
kubectl apply -f platform/media/media-storage.yaml
```

### 8. Deploy Plex (Minimal - CPU Only)
If GPU is not yet configured, deploy without GPU first:
```bash
# Use the CPU-only version temporarily
kubectl apply -f /tmp/plex-cpu-only.yaml
```

Or with GPU if already set up:
```bash
kubectl apply -f platform/media/plex.yaml
```

### 9. Verify Plex
```bash
kubectl get pods -n media
kubectl logs -n media deployment/plex

# Access at: http://192.168.2.20:32400
```

## Full Stack Deployment (After Cluster Stable)

**WARNING:** Only deploy these on a stable cluster with adequate resources.

### ArgoCD (GitOps)
```bash
# Create namespace and install CRDs
kubectl create namespace argocd
kubectl apply -k platform/argocd/bootstrap

# Create SOPS age secret for KSOPS
kubectl create secret generic sops-age \
  --namespace=argocd \
  --from-file=keys.txt=/home/dmwoods38/.config/sops/age/keys.txt

# Apply all applications
kubectl apply -f argo/apps/
```

### Monitoring Stack (Resource Intensive - AVOID on single node)
```bash
# Only if cluster has adequate resources (multi-node or 16GB+ RAM)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values /tmp/kube-prometheus-stack-values.yaml
```

## Critical Notes

### DO NOT Deploy These on Single Node Cluster:
- ❌ ArgoCD (causes resource contention)
- ❌ Prometheus/Grafana (overwhelms etcd)
- ❌ Full democratic-csi stack
- ❌ Multiple heavy services simultaneously

### Safe to Deploy:
- ✅ Plex (with or without GPU)
- ✅ Media storage (NFS PV/PVC)
- ✅ Basic namespaces and RBAC

### Resource Guidelines:
- **Single node (8 cores, 16GB RAM):** Plex + minimal services only
- **Multi-node OR 16+ cores, 32GB+ RAM:** Can add monitoring, ArgoCD
- **Production:** 3+ control plane nodes, dedicated worker nodes

## Troubleshooting Bootstrap

### "Connection refused" to API server
```bash
# Wait longer - API server takes 60-90 seconds to start
sleep 60
kubectl get nodes
```

### "TLS certificate verification failed"
```bash
# Use --insecure flag on first apply-config
talosctl apply-config --insecure --nodes 192.168.2.20 --file /tmp/controlplane1.yaml
```

### "etcd is already initialized"
```bash
# DO NOT re-run talosctl bootstrap
# Bootstrap is ONLY for fresh installations
# If cluster exists, just wait for it to come up
```

### Node has different name after bootstrap
```bash
# This is normal - Talos generates new node identity on fresh bootstrap
# Old: talos-kmt-qq0
# New: talos-vr0-305
# Update any node-specific configs if needed
```

### Flannel/CNI keeps restarting
```bash
# This causes all pods to recreate network sandboxes
# Usually self-resolves, but may require:
kubectl delete pod -n kube-system -l app=flannel
```

### etcd shows "too many requests"
```bash
# Cluster is overloaded
# IMMEDIATELY remove heavy services:
kubectl delete namespace monitoring argocd --grace-period=30

# NEVER use --force --grace-period=0 (corrupts cluster state)
```

## Emergency Recovery Commands

### Force Delete Stuck Namespace (Use with EXTREME CAUTION)
```bash
# Only if namespace stuck in Terminating for >5 minutes
kubectl get namespace <name> -o json \
  | jq '.spec.finalizers = []' \
  | kubectl replace --raw "/api/v1/namespaces/<name>/finalize" -f -

# NEVER use: kubectl delete --force --grace-period=0
# This WILL corrupt the cluster
```

### Check Talos Service Status
```bash
talosctl --nodes 192.168.2.20 service etcd
talosctl --nodes 192.168.2.20 service kubelet
talosctl --nodes 192.168.2.20 dmesg | tail -50
```

### Get Talos Logs
```bash
talosctl --nodes 192.168.2.20 logs kubelet
talosctl --nodes 192.168.2.20 logs etcd
```

## Backup Important Configs Before Changes

```bash
# Always backup before major changes
kubectl get all -A -o yaml > /tmp/cluster-backup-$(date +%Y%m%d-%H%M%S).yaml

# Backup etcd (if cluster is healthy)
talosctl --nodes 192.168.2.20 etcd snapshot /tmp/etcd-snapshot.db
```

## Cluster Destruction Counter
Keep track of how many times the cluster had to be completely rebuilt:

**Current Count: 3**

1. Initial cluster failure (pre-conversation)
2. Failed prometheus/monitoring deployment overload
3. Force-delete corruption requiring re-bootstrap

## Recovery Time Estimates
- **Bootstrap only:** 2-3 minutes
- **Bootstrap + Plex (CPU):** 5 minutes
- **Bootstrap + Plex (GPU):** 15-20 minutes (includes extension install)
- **Bootstrap + Full Stack:** 30-45 minutes (NOT recommended on single node)

## Files Reference
- Machine config: `talos/machine-configs/controlplane1.sops.yaml`
- GPU patch: `talos/patches/gpu-patch.yaml`
- Installer patch: `talos/patches/installer-patch.yaml`
- Media storage: `platform/media/media-storage.yaml`
- Plex deployment: `platform/media/plex.yaml`
- Age key: `~/.config/sops/age/keys.txt`

## Next Steps After Bootstrap
1. Verify cluster is stable (wait 5 minutes, check node status)
2. Deploy only Plex initially
3. Monitor resource usage: `kubectl top nodes` (requires metrics-server)
4. Only add more services if resources allow
5. Consider multi-node cluster for production workloads
