# Homelab GitOps Repository

GitOps-managed Kubernetes homelab running on Talos Linux with ArgoCD, featuring persistent storage via TrueNAS SCALE, monitoring with Prometheus/Grafana, and automatic certificate management.

## Infrastructure Overview

- **Cluster**: Single-node Talos Linux v1.11.5 with Kubernetes v1.34.1
- **Node**: `sever-it01` at 192.168.2.20:6443
- **GitOps**: ArgoCD managing all applications
- **Storage**: TrueNAS SCALE 25.04.2.1 at 192.168.2.30
  - iSCSI block storage via democratic-csi
  - NFS shared storage via democratic-csi
- **Load Balancer**: MetalLB in L2 mode
- **Ingress**: Traefik
- **Certificates**: cert-manager with Let's Encrypt (Cloudflare DNS validation)
- **Monitoring**: Prometheus + Grafana with etcd metrics

## Repository Structure

```
.
├── argo/
│   ├── apps/                    # ArgoCD Application manifests (SOPS encrypted)
│   │   ├── argocd.yaml          # ArgoCD self-management
│   │   ├── democratic-csi-iscsi.sops.yaml
│   │   ├── democratic-csi-nfs.sops.yaml
│   │   └── ...
│   └── argocd-install.yaml      # Initial ArgoCD installation
├── platform/
│   ├── cert-manager/            # Certificate management
│   ├── metallb/                 # Load balancer
│   ├── monitoring/              # Prometheus + Grafana + etcd monitoring
│   └── traefik/                 # Ingress controller
├── talos/
│   ├── machine-configs/         # Encrypted Talos machine configurations
│   ├── patches/                 # Talos config patches (installer, GPU, MetalLB fix)
│   └── manifests/               # Kubernetes manifests applied via Talos
└── .sops.yaml                   # SOPS encryption configuration

```

## Prerequisites

### Required Tools

```bash
# Talos CLI
curl -sL https://talos.dev/install | sh

# Kubernetes CLI
# (install kubectl via your package manager)

# SOPS (for encrypted secrets)
# (install sops via your package manager)

# Age encryption
# (install age via your package manager)

# ArgoCD CLI (optional, for easier management)
brew install argocd  # or equivalent
```

### Required Secrets

1. **Age Encryption Key**: Store at `~/.config/sops/age/keys.txt`
   - Public key: `age1033ld5gtn23xsz9lateded3kpssp62hkhjq9vs3jza3ad63uggnsqw5xhd`
   - Used for decrypting SOPS-encrypted files

2. **TrueNAS SSH Key**: Passphrase-less key for democratic-csi
   - Located at `~/.ssh/truenas_csi`
   - Public key already added to TrueNAS root user
   - Private key encrypted in democratic-csi configurations

3. **Cloudflare API Token**: For cert-manager DNS-01 challenges
   - Already encrypted in `platform/cert-manager/secret-cloudflare-api-token.sops.yaml`

## Initial Cluster Setup

### 1. Bootstrap Talos Cluster

The Talos configuration is stored encrypted in `talos/machine-configs/`. See `talos/README.md` for full details.

```bash
# Apply control plane configuration
sops -d talos/machine-configs/controlplane1.sops.yaml > /tmp/controlplane1.yaml
talosctl apply-config --nodes 192.168.2.20 --file /tmp/controlplane1.yaml

# Wait for cluster to be ready
talosctl --nodes 192.168.2.20 bootstrap
talosctl --nodes 192.168.2.20 kubeconfig

# Verify cluster is healthy
kubectl get nodes
```

### 2. Install ArgoCD

```bash
# Install ArgoCD
kubectl apply -f argo/argocd-install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s \
  deployment/argocd-server -n argocd

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD UI (if needed)
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Login at https://localhost:8080
```

### 3. Configure ArgoCD Self-Management

```bash
# Apply ArgoCD self-management application
kubectl apply -f argo/apps/argocd.yaml

# Verify ArgoCD is managing itself
argocd app get argocd -n argocd
```

### 4. Deploy Platform Services

ArgoCD will automatically sync applications from `argo/apps/`, but some require manual intervention due to SOPS encryption:

#### MetalLB (Auto-deployed)
```bash
# Verify MetalLB is running
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

#### Traefik (Auto-deployed)
```bash
# Verify Traefik is running and has an external IP
kubectl get svc -n traefik
```

#### cert-manager (Manual SOPS decryption required)
```bash
# Decrypt and apply Cloudflare API token secret
sops -d platform/cert-manager/secret-cloudflare-api-token.sops.yaml | kubectl apply -f -

# Verify cert-manager is running
kubectl get pods -n cert-manager
kubectl get clusterissuer
```

### 5. Deploy Storage (democratic-csi)

Democratic-csi configurations contain encrypted SSH keys and API keys.

#### Prerequisites on TrueNAS

1. Enable SSH service (should already be enabled)
2. Verify SSH key is in root user's authorized_keys
3. Verify datasets exist:
   ```bash
   ssh root@192.168.2.30 "zfs list | grep k8s-pv"
   # Should show:
   # default/k8s-pv/iscsi
   # default/k8s-pv/iscsi-snapshots
   ```

#### Deploy democratic-csi

```bash
# Decrypt and apply iSCSI driver
sops -d argo/apps/democratic-csi-iscsi.sops.yaml > /tmp/democratic-csi-iscsi.yaml
kubectl apply -f /tmp/democratic-csi-iscsi.yaml

# Decrypt and apply NFS driver
sops -d argo/apps/democratic-csi-nfs.sops.yaml > /tmp/democratic-csi-nfs.yaml
kubectl apply -f /tmp/democratic-csi-nfs.yaml

# Verify both controllers are running
kubectl get pods -n democratic-csi
# Should show 6/6 ready for both iscsi and nfs controllers

# Verify storage classes
kubectl get storageclass
# Should show truenas-iscsi and truenas-nfs
```

### 6. Deploy Monitoring Stack

```bash
# Apply monitoring namespace and configurations
kubectl apply -f platform/monitoring/

# Verify Prometheus and Grafana are running
kubectl get pods -n monitoring

# Access Grafana (default credentials: admin/admin)
kubectl port-forward -n monitoring svc/grafana 3000:80
# Open http://localhost:3000
```

## Service Management

### Viewing and Syncing ArgoCD Applications

```bash
# List all applications
kubectl get applications -n argocd

# Check application status
argocd app get <app-name> -n argocd

# Manually sync an application
argocd app sync <app-name> -n argocd

# Or via kubectl
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{}}}'
```

### Testing Storage Provisioning

```bash
# Create a test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-iscsi
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: truenas-iscsi
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC status
kubectl get pvc test-iscsi
# Should show "Bound" status

# Verify zvol on TrueNAS
ssh root@192.168.2.30 "zfs list -t volume | grep test-iscsi"

# Clean up
kubectl delete pvc test-iscsi
```

### Monitoring etcd Health

```bash
# Check etcd metrics in Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090
# Query: etcd_mvcc_db_total_size_in_bytes

# View etcd dashboard in Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80
# Open http://localhost:3000 -> "etcd" dashboard

# Manual etcd operations
talosctl -n 192.168.2.20 etcd status
talosctl -n 192.168.2.20 etcd members

# Defragment etcd (if database is large)
talosctl -n 192.168.2.20 etcd defragment

# Create etcd snapshot
talosctl -n 192.168.2.20 etcd snapshot /tmp/etcd-snapshot.db
```

## Troubleshooting

### MetalLB Not Announcing LoadBalancer IPs on Control-Plane

**Symptom:** LoadBalancer services get assigned an IP but are unreachable, ARP shows "(incomplete)".

**Root Cause:** Talos automatically adds `node.kubernetes.io/exclude-from-external-load-balancers` label to control-plane nodes.

**Solution:** Applied via `talos/patches/remove-lb-exclusion-label.yaml` in Talos machine config:

```yaml
machine:
  nodeLabels:
    node.kubernetes.io/exclude-from-external-load-balancers:
      $patch: delete
```

**Verification:**
```bash
kubectl get nodes --show-labels | grep exclude-from-external-load-balancers
# Should not show the exclusion label

arp -n | grep <LOADBALANCER_IP>
# Should show a MAC address, not "(incomplete)"
```

### democratic-csi: "driver is only available with TrueNAS SCALE"

**Symptom:** Pods crash with error about driver only being available with SCALE, despite running SCALE.

**Root Cause:** The experimental `freenas-api-*` drivers have issues detecting TrueNAS SCALE correctly.

**Solution:** Switched to stable SSH-based drivers:
- `freenas-api-iscsi` → `freenas-iscsi`
- `freenas-api-nfs` → `freenas-nfs`

Required configuration:
```yaml
driver:
  config:
    driver: freenas-iscsi  # or freenas-nfs
    httpConnection:        # Still needed for some operations
      protocol: https
      host: 192.168.2.30
      port: 443
      apiKey: <encrypted>
      allowInsecure: true
    sshConnection:
      host: 192.168.2.30
      port: 22
      username: root
      privateKey: <encrypted>
    zfs:
      cli:
        sudoEnabled: false
        paths:
          zfs: /usr/sbin/zfs      # Critical: not /usr/local/sbin/zfs
          zpool: /usr/sbin/zpool
          sudo: /usr/bin/sudo
          chroot: /usr/sbin/chroot
```

### democratic-csi: "no such file or directory: /usr/local/sbin/zfs"

**Symptom:** CreateVolume fails with error about missing `/usr/local/sbin/zfs`.

**Root Cause:** democratic-csi defaults to FreeBSD/FreeNAS paths, but TrueNAS SCALE uses Linux paths.

**Solution:** Configure correct ZFS paths in `zfs.cli.paths` (see above).

### democratic-csi: "parent is not a filesystem"

**Symptom:** Volume creation fails with "cannot create 'default/k8s-pv/talos-iscsi-share/pvc-xxx': parent is not a filesystem".

**Root Cause:** The configured `datasetParentName` was a zvol (volume), not a filesystem. You can't create child datasets under zvols.

**Solution:** Created proper filesystem datasets as parents:

```bash
# On TrueNAS
ssh root@192.168.2.30 "zfs create default/k8s-pv/iscsi"
ssh root@192.168.2.30 "zfs create default/k8s-pv/iscsi-snapshots"
```

Updated configuration:
```yaml
zfs:
  datasetParentName: default/k8s-pv/iscsi  # Must be a filesystem
  detachedSnapshotsDatasetParentName: default/k8s-pv/iscsi-snapshots
```

### etcd Database Growing Too Large (12GB+)

**Symptom:** etcd database size over 12GB, cluster performance degraded, high memory usage.

**Root Cause:** Default 7-day history retention with active cluster creates large databases.

**Solution Applied:**

1. **Immediate**: Defragmentation
   ```bash
   talosctl -n 192.168.2.20 etcd defragment
   ```

2. **Long-term**: Monitoring with Prometheus + Grafana
   - etcd metrics exported via ServiceMonitor
   - Grafana dashboard for database size, key/revision counts
   - Set up alerts for database size thresholds

**Prevention:**
- Monitor `etcd_mvcc_db_total_size_in_bytes` metric
- Defragment when database exceeds 2-3GB
- Consider reducing history retention if growth is excessive

### ArgoCD Cannot Decrypt SOPS-Encrypted Application Manifests

**Symptom:** ArgoCD sync appears successful but uses old/unencrypted configuration from Application manifest.

**Root Cause:** ArgoCD's KSOPS plugin only works with Kustomize generators, not with Application manifests themselves. When an Application manifest is SOPS-encrypted, ArgoCD cannot decrypt it.

**Current Workaround:** Manual kubectl apply after SOPS decryption:

```bash
sops -d argo/apps/democratic-csi-iscsi.sops.yaml > /tmp/democratic-csi-iscsi.yaml
kubectl apply -f /tmp/democratic-csi-iscsi.yaml
```

**Future Solution:** Refactor to use Kustomize + KSOPS pattern (like cert-manager):
- Move democratic-csi configs to platform/democratic-csi/
- Create ksops-secret-generator.yaml
- Use non-encrypted Application manifest that references Kustomize resources
- KSOPS plugin will decrypt secrets during sync

## Session History

### Session 1: etcd Crisis and Recovery
- **Problem**: etcd database at 12GB, cluster degraded
- **Resolution**:
  - Emergency defragmentation reduced size to ~243MB
  - Set up Prometheus monitoring for etcd
  - Created Grafana dashboard for etcd metrics
  - Documented defragmentation procedure

### Session 2: democratic-csi Configuration
- **Problem**: democratic-csi failing with "driver only available with SCALE" error
- **Investigation**:
  - Discovered `freenas-api-*` drivers are experimental
  - Found driver detection issues with TrueNAS SCALE 25.04.2.1
- **Resolution**:
  - Switched to stable SSH-based drivers (`freenas-iscsi`, `freenas-nfs`)
  - Generated passphrase-less SSH key for democratic-csi
  - Enabled SSH on TrueNAS SCALE
  - Configured hybrid SSH + HTTPS access
  - Fixed ZFS path configuration for SCALE
  - Created proper filesystem datasets as parents
  - Encrypted sensitive data (SSH keys, API keys) with SOPS
  - Tested iSCSI provisioning successfully

### Session 3: Talos Configuration Integration
- **Task**: Merge Talos configurations from separate directory into GitOps repo
- **Work Done**:
  - Created `talos/` directory structure
  - Encrypted machine configs with SOPS
  - Copied patches and manifests
  - Created comprehensive Talos README
  - Updated .sops.yaml for Talos-specific encryption rules

## Security Notes

### SOPS Encryption

All sensitive data is encrypted using SOPS with Age encryption:

```bash
# Encrypting a file
sops -e -i path/to/file.sops.yaml

# Decrypting a file
sops -d path/to/file.sops.yaml

# Editing encrypted file
sops path/to/file.sops.yaml
```

**Encrypted Fields:**
- `data` - Kubernetes Secret data
- `stringData` - Kubernetes Secret stringData
- `apiKey` - TrueNAS API keys
- `privateKey` - SSH private keys

**Full-File Encryption:**
- Talos machine configs in `talos/machine-configs/*.sops.yaml`

### Never Commit These Files

Already in `.gitignore`:
- `talosconfig` - Contains cluster admin credentials
- `kubeconfig` - Contains Kubernetes credentials
- `keys.txt`, `*.age.key` - Age encryption private keys
- `*.dec.yaml` - Decrypted SOPS files

## Useful Commands Reference

### Talos

```bash
# Get cluster info
talosctl -n 192.168.2.20 version
talosctl -n 192.168.2.20 health

# View logs
talosctl -n 192.168.2.20 logs -f

# Resource usage
talosctl -n 192.168.2.20 usage

# etcd operations
talosctl -n 192.168.2.20 etcd status
talosctl -n 192.168.2.20 etcd members
talosctl -n 192.168.2.20 etcd defragment

# Upgrade cluster
talosctl -n 192.168.2.20 upgrade --image ghcr.io/siderolabs/installer:v1.11.5
```

### Kubernetes

```bash
# Get all resources in namespace
kubectl get all -n <namespace>

# Describe resource for troubleshooting
kubectl describe <resource> <name> -n <namespace>

# View logs
kubectl logs -f <pod-name> -n <namespace>
kubectl logs -f <pod-name> -c <container-name> -n <namespace>

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Port forward for local access
kubectl port-forward -n <namespace> svc/<service-name> <local-port>:<service-port>
```

### ArgoCD

```bash
# Get all applications
argocd app list

# Get application details
argocd app get <app-name>

# Sync application
argocd app sync <app-name>

# View application logs
argocd app logs <app-name> -f

# Diff what would change
argocd app diff <app-name>
```

### TrueNAS (via SSH)

```bash
# List all datasets
ssh root@192.168.2.30 "zfs list"

# List only volumes (for iSCSI)
ssh root@192.168.2.30 "zfs list -t volume"

# Check dataset properties
ssh root@192.168.2.30 "zfs get all default/k8s-pv/iscsi"

# Check disk usage
ssh root@192.168.2.30 "zpool list"
```

## Future Improvements

- [ ] Migrate democratic-csi to Kustomize + KSOPS pattern for ArgoCD compatibility
- [ ] Set up automated etcd backups to TrueNAS
- [ ] Configure etcd compaction policy
- [ ] Add more applications (database, application hosting, etc.)
- [ ] Set up external secrets operator
- [ ] Implement disaster recovery procedures
- [ ] Add worker nodes to cluster
- [ ] Configure Prometheus AlertManager with notifications
- [ ] Set up automated certificate renewal monitoring
- [ ] Add persistent storage for Grafana dashboards

## References

- [Talos Linux Documentation](https://www.talos.dev/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [democratic-csi Documentation](https://github.com/democratic-csi/democratic-csi)
- [TrueNAS SCALE Documentation](https://www.truenas.com/docs/scale/)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [cert-manager Documentation](https://cert-manager.io/)
- [Prometheus Operator](https://prometheus-operator.dev/)
