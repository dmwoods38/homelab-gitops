# Disaster Recovery Guide

**Last Updated**: 2025-12-21

This guide documents procedures for recovering from various failure scenarios in the homelab infrastructure.

## Table of Contents

1. [Critical Secrets Backup](#critical-secrets-backup)
2. [TrueNAS Snapshot Schedule](#truenas-snapshot-schedule)
3. [etcd Automated Snapshots](#etcd-automated-snapshots)
4. [Recovery Scenarios](#recovery-scenarios)
5. [Talos Cluster Recovery](#talos-cluster-recovery)
6. [OpenBao Recovery](#openbao-recovery)
7. [Application Data Recovery](#application-data-recovery)

---

## Critical Secrets Backup

**IMPORTANT**: Keep these files in a secure location (encrypted USB drive, password manager, printed in safe):

### Required Files

1. **SOPS AGE Key**: `~/.config/sops/age/keys.txt`
   - Required to decrypt all `.sops.yaml` files in the repository
   - Without this key, encrypted credentials cannot be recovered
   - **Action**: Copy to password manager and encrypted backup drive

2. **OpenBao Keys**: `~/openbao-keys.yaml`
   - Contains unseal keys (need 3 of 5) and root token
   - Required to unseal OpenBao after any restart
   - **Action**: Print and store in safe, copy to password manager

3. **TrueNAS SSH Key**: `~/.ssh/id_ed25519_truenas`
   - Used by democratic-csi for NFS/iSCSI provisioning
   - **Action**: Backup to encrypted storage

4. **Talos Configuration**: `~/.talos/config`
   - Required for talosctl access to cluster
   - **Action**: Backup to password manager

### Backup Verification

Run these commands to verify critical files exist:

```bash
# Check SOPS AGE key
ls -la ~/.config/sops/age/keys.txt

# Check OpenBao keys
ls -la ~/openbao-keys.yaml

# Check TrueNAS SSH key
ls -la ~/.ssh/id_ed25519_truenas

# Check Talos config
ls -la ~/.talos/config
```

---

## TrueNAS Snapshot Schedule

Automated snapshots protect against data loss and corruption.

### Snapshot Tasks

| Dataset | Frequency | Retention | Schedule | Purpose |
|---------|-----------|-----------|----------|---------|
| `default/media` | Daily | 7 days | 02:00 daily | Media library protection |
| `default/media` | Weekly | 4 weeks | 03:00 Sunday | Long-term media backup |
| `default/smb-share` | Every 4 hours | 24 hours | 00:00, 04:00, 08:00, 12:00, 16:00, 20:00 | OpenBao + app configs |
| `default/smb-share` | Weekly | 4 weeks | 03:30 Sunday | Long-term config backup |

### Manual Snapshot

To create an immediate snapshot:

```bash
# Snapshot media dataset
ssh root@192.168.2.30 "zfs snapshot default/media@manual-$(date +%Y%m%d-%H%M)"

# Snapshot smb-share (includes OpenBao)
ssh root@192.168.2.30 "zfs snapshot -r default/smb-share@manual-$(date +%Y%m%d-%H%M)"
```

### List Available Snapshots

```bash
# List media snapshots
ssh root@192.168.2.30 "zfs list -t snapshot -r default/media"

# List smb-share snapshots
ssh root@192.168.2.30 "zfs list -t snapshot -r default/smb-share"
```

### Restore from Snapshot

```bash
# Rollback to most recent snapshot (DESTRUCTIVE - loses changes after snapshot)
ssh root@192.168.2.30 "zfs rollback default/media@<SNAPSHOT_NAME>"

# Restore specific file from snapshot (safer)
ssh root@192.168.2.30 "cp /mnt/default/media/.zfs/snapshot/<SNAPSHOT_NAME>/<FILE_PATH> /mnt/default/media/<FILE_PATH>"
```

---

## etcd Automated Snapshots

**Purpose**: Automated etcd snapshots protect against cluster state corruption from power outages, hardware failures, or software bugs.

**Schedule**: Daily at 02:00 AM
**Retention**: 7 days
**Storage Location**: Talos node at `/var/lib/etcd-snapshots/etcd-backups/`
**Snapshot Size**: ~22MB per snapshot

### How It Works

A Kubernetes CronJob runs daily using:
- **Image**: Alpine Linux with talosctl binary
- **Volumes**: hostPath for persistent storage on Talos node
- **Configuration**: Talos API credentials via secret

The job:
1. Downloads talosctl in initContainer
2. Creates etcd snapshot using `talosctl etcd snapshot`
3. Stores snapshot with timestamp: `etcd-snapshot-YYYYMMDD-HHMMSS.db`
4. Rotates old snapshots (keeps last 7 days)

### Manual Snapshot Creation

To create an immediate snapshot:

```bash
# Create a one-time job from the CronJob
kubectl create job --from=cronjob/etcd-snapshot -n kube-system etcd-snapshot-manual

# Watch the job
kubectl get job -n kube-system -w

# View logs
kubectl logs -n kube-system -l job-name=etcd-snapshot-manual -c backup
```

### List Available Snapshots

```bash
# List snapshots on Talos node
talosctl ls /var/lib/etcd-snapshots/etcd-backups/ --nodes 192.168.2.20

# Get snapshot details
talosctl ls -l /var/lib/etcd-snapshots/etcd-backups/ --nodes 192.168.2.20
```

### Copy Snapshot to Local Machine

```bash
# Copy specific snapshot to local machine for safekeeping
talosctl cp /var/lib/etcd-snapshots/etcd-backups/etcd-snapshot-YYYYMMDD-HHMMSS.db \
  ./etcd-snapshot-YYYYMMDD-HHMMSS.db \
  --nodes 192.168.2.20
```

### Restore from Snapshot

**WARNING**: Restoring etcd from a snapshot will revert the entire cluster state to the snapshot time. All changes made after the snapshot will be lost.

```bash
# 1. Copy snapshot to Talos node (if restoring from local backup)
talosctl cp ./etcd-snapshot-YYYYMMDD-HHMMSS.db \
  /var/lib/etcd-snapshots/restore.db \
  --nodes 192.168.2.20

# 2. Stop etcd service
talosctl service etcd stop --nodes 192.168.2.20

# 3. Restore the snapshot
talosctl etcd snapshot /var/lib/etcd-snapshots/restore.db --nodes 192.168.2.20

# 4. Bootstrap the cluster
talosctl bootstrap --nodes 192.168.2.20

# 5. Verify cluster health
kubectl get nodes
kubectl get pods -A
```

### Restore Testing (Recommended Monthly)

To verify snapshots are valid without impacting production:

```bash
# Download most recent snapshot
LATEST_SNAPSHOT=$(talosctl ls /var/lib/etcd-snapshots/etcd-backups/ --nodes 192.168.2.20 | tail -1 | awk '{print $2}')
talosctl cp /var/lib/etcd-snapshots/etcd-backups/$LATEST_SNAPSHOT ./test-snapshot.db --nodes 192.168.2.20

# Verify snapshot integrity (optional - requires etcdctl)
docker run --rm -v $(pwd):/backup quay.io/coreos/etcd:v3.5.11 \
  etcdctl snapshot status /backup/test-snapshot.db --write-out=table
```

### Troubleshooting

**CronJob Not Running**:
```bash
# Check CronJob status
kubectl get cronjob -n kube-system etcd-snapshot

# Check recent jobs
kubectl get jobs -n kube-system | grep etcd-snapshot

# Check pod logs if failed
kubectl logs -n kube-system -l app=etcd-snapshot --tail=50
```

**Snapshot Creation Failed**:
```bash
# Verify talosconfig secret exists
kubectl get secret -n kube-system talosconfig

# Test talosctl connectivity manually
kubectl run -it --rm debug --image=alpine:3.19 --restart=Never -- sh
# Inside pod:
apk add curl
curl -sL https://github.com/siderolabs/talos/releases/download/v1.8.3/talosctl-linux-amd64 -o /tmp/talosctl
chmod +x /tmp/talosctl
/tmp/talosctl --nodes 192.168.2.20 etcd status
```

**Disk Space Issues**:
```bash
# Check available space on Talos node
talosctl df --nodes 192.168.2.20

# Manually clean old snapshots if needed
talosctl rm /var/lib/etcd-snapshots/etcd-backups/etcd-snapshot-<OLD_DATE>.db --nodes 192.168.2.20
```

### Offsite Backup Recommendation

While snapshots are stored on the Talos node, it's recommended to periodically copy them offsite:

```bash
# Weekly offsite backup script (run from workstation)
#!/bin/bash
BACKUP_DIR=~/backups/etcd/$(date +%Y-%m)
mkdir -p $BACKUP_DIR

# Copy all snapshots from last 7 days
talosctl cp /var/lib/etcd-snapshots/etcd-backups/ $BACKUP_DIR/ --nodes 192.168.2.20

# Optional: Upload to cloud storage
# aws s3 sync $BACKUP_DIR s3://my-backup-bucket/etcd-snapshots/
# rclone sync $BACKUP_DIR remote:etcd-snapshots/
```

---

## Recovery Scenarios

### Scenario 1: Lost SOPS AGE Key

**Symptoms**: Cannot decrypt `.sops.yaml` files

**Recovery**:
1. Restore `~/.config/sops/age/keys.txt` from backup
2. Verify decryption works:
   ```bash
   cd ~/dev/homelab/homelab-gitops
   sops -d argo/apps/democratic-csi-nfs.sops.yaml
   ```
3. If no backup exists: **Credentials must be rotated manually**
   - Generate new AGE key: `age-keygen -o ~/.config/sops/age/keys.txt`
   - Update `.sops.yaml` with new public key
   - Re-encrypt all `.sops.yaml` files with new key
   - Rotate all secrets stored in SOPS files

### Scenario 2: TrueNAS Storage Failure

**Symptoms**: PVCs not mounting, storage unavailable

**Recovery**:
1. **If ZFS pool is intact**: Reimport pool
   ```bash
   ssh root@192.168.2.30
   zpool import default
   ```

2. **If pool is degraded**: Replace failed disk
   ```bash
   # Check pool status
   zpool status default

   # Replace disk (example)
   zpool replace default <OLD_DISK> <NEW_DISK>
   ```

3. **If pool is destroyed**: Restore from offsite backup
   - TrueNAS replication task should be configured to remote storage
   - Restore datasets from replication target

4. Restart democratic-csi pods after storage recovery:
   ```bash
   kubectl rollout restart deployment -n democratic-csi democratic-csi-controller
   kubectl delete pods -n democratic-csi -l app=democratic-csi
   ```

### Scenario 3: Complete Talos Cluster Loss

**Symptoms**: All control plane nodes failed, cluster unrecoverable

**Prerequisites**:
- Talos ISO or boot media
- Backup of `~/.talos/config`
- Backup of etcd snapshots (if available)

**Recovery Steps**:

1. **Reinstall Talos on node**:
   ```bash
   # Boot from Talos ISO
   # Apply saved machine configuration
   talosctl apply-config --insecure --nodes <NODE_IP> --file ~/.talos/machine-config.yaml
   ```

2. **Bootstrap new cluster**:
   ```bash
   talosctl bootstrap --nodes <CONTROL_PLANE_IP>
   ```

3. **Restore etcd from snapshot** (if available):
   ```bash
   # Copy snapshot to node
   talosctl -n <NODE_IP> cp /tmp/etcd-snapshot.db /var/lib/etcd/snapshot.db

   # Restore snapshot
   talosctl -n <NODE_IP> etcd snapshot restore
   ```

4. **If no etcd backup**: Reinstall all applications from GitOps
   - Follow "Scenario 3a: etcd Data Corruption Recovery" below

### Scenario 3a: etcd Data Corruption Recovery (Power Outage)

**Symptoms**: etcd stuck in "Preparing" state, cluster API unreachable, etcd data directory empty/corrupted

**What Happens**: Power loss can corrupt etcd data. Bootstrap wipes cluster state but apps can be restored from GitOps.

**Recovery Steps**:

1. **Check etcd status**:
   ```bash
   talosctl service etcd --nodes 192.168.2.20
   # If stuck in "Preparing" state for >5 minutes, proceed with bootstrap
   ```

2. **Bootstrap fresh etcd** (DESTRUCTIVE - wipes cluster state):
   ```bash
   talosctl bootstrap --nodes 192.168.2.20

   # Wait 30 seconds, then verify
   kubectl get nodes
   ```

3. **Install ArgoCD**:
   ```bash
   # Create namespace
   kubectl create namespace argocd

   # Install ArgoCD from upstream
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

   # Wait for ready
   kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

   # Create SOPS AGE secret for decryption
   kubectl create secret generic sops-age \
     --from-file=keys.txt=/home/dmwoods38/.config/sops/age/keys.txt \
     -n argocd
   ```

4. **Apply all ArgoCD applications**:
   ```bash
   # Apply all apps (democratic-csi will fail - expected)
   kubectl apply -f /home/dmwoods38/dev/homelab/homelab-gitops/argo/apps/

   # Decrypt and apply democratic-csi separately
   sops -d /home/dmwoods38/dev/homelab/homelab-gitops/argo/apps/democratic-csi-nfs.sops.yaml | kubectl apply -f -
   ```

5. **Install required CRDs**:
   ```bash
   # External Secrets CRDs
   kubectl apply --server-side=true --force-conflicts \
     -f https://raw.githubusercontent.com/external-secrets/external-secrets/main/deploy/crds/bundle.yaml

   # Volume Snapshot CRDs
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
   ```

6. **Install External Secrets Operator**:
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update
   helm install external-secrets external-secrets/external-secrets \
     -n external-secrets --create-namespace --set installCRDs=false
   ```

7. **Install democratic-csi for storage**:
   ```bash
   # Create values file (stored in /tmp after decrypt)
   sops -d /home/dmwoods38/dev/homelab/homelab-gitops/argo/apps/democratic-csi-nfs.sops.yaml > /tmp/democratic-csi-nfs.yaml

   # Extract values and save to file
   cat > /tmp/democratic-csi-values.yaml <<EOF
   # (Copy valuesObject section from decrypted file)
   EOF

   # Install with Helm
   helm repo add democratic-csi https://democratic-csi.github.io/charts/
   helm install democratic-csi-nfs democratic-csi/democratic-csi \
     -n democratic-csi --create-namespace \
     -f /tmp/democratic-csi-values.yaml --version 0.14.7

   # Verify storage class created
   kubectl get storageclass truenas-nfs
   ```

8. **Fix PodSecurity labels** (required for privileged pods):
   ```bash
   # MetalLB needs privileged for speaker
   kubectl label namespace kube-system pod-security.kubernetes.io/enforce=privileged --overwrite

   # Media namespace needs privileged for Gluetun (NET_ADMIN) and Plex (hostNetwork)
   kubectl label namespace media pod-security.kubernetes.io/enforce=privileged --overwrite
   ```

9. **Install MetalLB manually** (if speaker doesn't deploy):
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

   # Apply IP pool config
   kubectl apply -f /home/dmwoods38/dev/homelab/homelab-gitops/platform/metallb/

   # Verify speaker is running
   kubectl get pods -n metallb-system
   ```

10. **Unseal OpenBao**:
    ```bash
    # Get OpenBao pod
    POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')

    # Check if sealed
    kubectl exec -n openbao $POD -c openbao -- bao status

    # Unseal with 3 keys from ~/openbao-keys.yaml
    kubectl exec -n openbao $POD -c openbao -- bao operator unseal <KEY_1>
    kubectl exec -n openbao $POD -c openbao -- bao operator unseal <KEY_2>
    kubectl exec -n openbao $POD -c openbao -- bao operator unseal <KEY_3>
    ```

11. **Generate new OpenBao root token** (if old token doesn't work):
    ```bash
    POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')

    # Initialize root token generation
    kubectl exec -n openbao $POD -c openbao -- bao operator generate-root -init
    # Note the Nonce and OTP

    # Provide 3 unseal keys
    kubectl exec -n openbao $POD -c openbao -- bao operator generate-root -nonce=<NONCE> <KEY_1>
    kubectl exec -n openbao $POD -c openbao -- bao operator generate-root -nonce=<NONCE> <KEY_2>
    kubectl exec -n openbao $POD -c openbao -- bao operator generate-root -nonce=<NONCE> <KEY_3>
    # Note the Encoded Token

    # Decode the token
    kubectl exec -n openbao $POD -c openbao -- bao operator generate-root -decode=<ENCODED_TOKEN> -otp=<OTP>
    # This outputs the new root token

    # Update ~/openbao-keys.yaml with new root token
    ```

12. **Configure OpenBao Kubernetes auth**:
    ```bash
    POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')

    # Configure Kubernetes auth
    kubectl exec -n openbao $POD -c openbao -- sh -c 'export BAO_TOKEN=<ROOT_TOKEN> && \
      bao write auth/kubernetes/config \
      kubernetes_host=https://kubernetes.default.svc:443 \
      kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
      token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token'

    # Create media role
    kubectl exec -n openbao $POD -c openbao -- sh -c 'export BAO_TOKEN=<ROOT_TOKEN> && \
      bao write auth/kubernetes/role/media-role \
      bound_service_account_names=external-secrets \
      bound_service_account_namespaces=media \
      policies=media-policy \
      ttl=24h'

    # Create media policy
    kubectl exec -n openbao $POD -c openbao -- sh -c 'export BAO_TOKEN=<ROOT_TOKEN> && \
      bao policy write media-policy - <<EOF
path "secret/data/media/*" {
  capabilities = ["read", "list"]
}
EOF'
    ```

13. **Create VPN secret manually** (if External Secrets not working):
    ```bash
    # Get credentials from OpenBao
    POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n openbao $POD -c openbao -- sh -c 'export BAO_TOKEN=<ROOT_TOKEN> && bao kv get secret/media/vpn'

    # Create secret manually
    kubectl create secret generic gluetun-vpn -n media \
      --from-literal=OPENVPN_USER=<USER> \
      --from-literal=OPENVPN_PASSWORD=<PASSWORD>
    ```

14. **Apply Cloudflare secret for certificates**:
    ```bash
    sops -d /home/dmwoods38/dev/homelab/homelab-gitops/platform/cert-manager/secret-cloudflare-api-token.sops.yaml | kubectl apply -f -

    # Apply cluster issuers
    kubectl apply -f /home/dmwoods38/dev/homelab/homelab-gitops/platform/cert-manager/

    # Certificates will be issued automatically (takes 1-5 minutes for DNS propagation)
    ```

15. **Deploy media applications**:
    ```bash
    kubectl create namespace media
    kubectl label namespace media pod-security.kubernetes.io/enforce=privileged --overwrite
    kubectl apply -f /home/dmwoods38/dev/homelab/homelab-gitops/platform/media/

    # Verify all pods running
    kubectl get pods -n media
    ```

16. **Verify services are accessible**:
    ```bash
    # Check LoadBalancer IPs
    kubectl get svc -n media plex
    kubectl get svc -n traefik traefik

    # Test Traefik
    curl -I http://<TRAEFIK_IP>

    # Test Plex
    curl -I http://<PLEX_IP>:32400/web

    # Test HTTPS (after certs issue)
    curl -k -I https://plex.internal.sever-it.com
    ```

**Important Notes**:
- OpenBao data survives on PVC if using persistent storage
- Root token may need regeneration if it was rotated before the crash
- All Kubernetes resources are recreated from GitOps repository
- Certificates will be re-issued from Let's Encrypt (count against rate limits)
- PodSecurity labels MUST be set before deploying privileged workloads
- MetalLB speaker requires privileged PSS in kube-system namespace

### Scenario 4: OpenBao Sealed After Restart

**Symptoms**: OpenBao pod running but sealed, External Secrets failing

**Recovery**:
1. Retrieve unseal keys from secure backup:
   ```bash
   cat ~/openbao-keys.yaml
   ```

2. Unseal OpenBao (need 3 of 5 keys):
   ```bash
   POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')

   kubectl exec -n openbao $POD -- bao operator unseal <UNSEAL_KEY_1>
   kubectl exec -n openbao $POD -- bao operator unseal <UNSEAL_KEY_2>
   kubectl exec -n openbao $POD -- bao operator unseal <UNSEAL_KEY_3>
   ```

3. Verify unsealed:
   ```bash
   kubectl exec -n openbao $POD -- bao status
   ```

4. External Secrets Operator will automatically resume syncing

### Scenario 5: OpenBao Data Loss

**Symptoms**: OpenBao starts but all secrets are gone

**Recovery**:
1. **Check TrueNAS snapshots**:
   ```bash
   ssh root@192.168.2.30 "zfs list -t snapshot -r default/smb-share | grep openbao"
   ```

2. **Restore from snapshot**:
   ```bash
   # Find the OpenBao PVC dataset name
   ssh root@192.168.2.30 "zfs list -r default/smb-share | grep pvc-"

   # Rollback to snapshot (example)
   ssh root@192.168.2.30 "zfs rollback default/smb-share/<PVC_NAME>@<SNAPSHOT_NAME>"
   ```

3. **Restart OpenBao pod**:
   ```bash
   kubectl delete pod -n openbao -l app=openbao
   ```

4. **Unseal with recovery keys**

5. **If no snapshots available**: Manual secret recreation
   - Retrieve secrets from password manager
   - Re-create secrets in OpenBao using root token
   - Verify External Secrets sync

### Scenario 6: Lost OpenBao Root Token

**Symptoms**: Need admin access but root token lost

**Recovery**:
1. **Generate new root token** (requires unseal keys):
   ```bash
   POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')

   # Start root token generation
   kubectl exec -n openbao $POD -- bao operator generate-root -init

   # Note the Nonce and OTP
   # Provide unseal keys (need 3 of 5)
   kubectl exec -n openbao $POD -- bao operator generate-root -nonce=<NONCE>
   # (repeat for each key)

   # Decode the encoded token using the OTP
   kubectl exec -n openbao $POD -- bao operator generate-root -decode=<ENCODED_TOKEN> -otp=<OTP>
   ```

2. **Update backup file**:
   ```bash
   # Save new root token to ~/openbao-keys.yaml
   # Update backup in password manager
   ```

3. **Revoke old root token** (if compromised)

### Scenario 7: Democratic-CSI Not Provisioning Storage

**Symptoms**: PVCs stuck in Pending, democratic-csi errors

**Recovery**:
1. **Check TrueNAS API connectivity**:
   ```bash
   curl -k https://192.168.2.30/api/v2.0/pool/dataset \
     -H "Authorization: Bearer <TRUENAS_API_KEY_FROM_SOPS>"
   ```

2. **Check democratic-csi logs**:
   ```bash
   kubectl logs -n democratic-csi -l app=democratic-csi-controller
   kubectl logs -n democratic-csi -l app=democratic-csi-node
   ```

3. **Common fixes**:
   - **API key expired**: Rotate in TrueNAS UI, update SOPS file, restart pods
   - **SSH key wrong**: Update secret, restart pods
   - **Network issue**: Check TrueNAS reachability from cluster
   - **Dataset permissions**: Check ZFS dataset permissions on TrueNAS

4. **Restart democratic-csi**:
   ```bash
   kubectl rollout restart statefulset -n democratic-csi democratic-csi-controller
   kubectl delete pods -n democratic-csi -l app=democratic-csi-node
   ```

---

## Talos Cluster Recovery

### Create etcd Backup

```bash
# Create snapshot
talosctl -n <CONTROL_PLANE_IP> etcd snapshot /tmp/etcd-snapshot.db

# Download snapshot
talosctl -n <CONTROL_PLANE_IP> cp /var/lib/etcd/snapshot.db ./etcd-backup-$(date +%Y%m%d).db
```

### Check Cluster Health

```bash
# Check etcd members
talosctl -n <CONTROL_PLANE_IP> etcd members

# Check service status
talosctl -n <CONTROL_PLANE_IP> service etcd status
talosctl -n <CONTROL_PLANE_IP> service kubelet status

# Check node health
kubectl get nodes
```

---

## OpenBao Recovery

### Backup OpenBao Data

OpenBao data is automatically protected by TrueNAS snapshots (every 4 hours + weekly).

Manual backup:
```bash
# Export secrets to JSON (requires root token)
kubectl exec -n openbao <POD> -- bao kv export -format=json secret/ > openbao-backup.json

# Store encrypted
age -r <YOUR_AGE_PUBLIC_KEY> -o openbao-backup.json.age openbao-backup.json
rm openbao-backup.json
```

### Restore Secrets

```bash
# Unseal OpenBao first (see Scenario 4)

# Login with root token
kubectl exec -n openbao $POD -- bao login <ROOT_TOKEN_FROM_BACKUP>

# Manually recreate secrets
kubectl exec -n openbao $POD -- bao kv put secret/media/vpn OPENVPN_USER=<USER> OPENVPN_PASSWORD=<PASS>
```

---

## Application Data Recovery

### Media Stack

All media data is on `default/media` dataset with daily/weekly snapshots.

**Recover deleted file**:
```bash
# Find snapshot with file
ssh root@192.168.2.30 "ls /mnt/default/media/.zfs/snapshot/"

# Copy file from snapshot
ssh root@192.168.2.30 "cp /mnt/default/media/.zfs/snapshot/<SNAPSHOT>/path/to/file /mnt/default/media/path/to/file"
```

**Full rollback** (DESTRUCTIVE):
```bash
# This will lose all changes after the snapshot
ssh root@192.168.2.30 "zfs rollback default/media@<SNAPSHOT_NAME>"
```

### Application Configs

App configs (Sonarr, Radarr, etc.) are in `default/smb-share` PVCs with 4-hourly snapshots.

**List app PVCs**:
```bash
kubectl get pvc -A
```

**Restore app config from snapshot**:
```bash
# Find PVC dataset
ssh root@192.168.2.30 "zfs list -r default/smb-share | grep pvc-"

# List snapshots
ssh root@192.168.2.30 "zfs list -t snapshot default/smb-share/<PVC_DATASET>"

# Rollback
ssh root@192.168.2.30 "zfs rollback default/smb-share/<PVC_DATASET>@<SNAPSHOT>"

# Restart pod to pick up restored data
kubectl delete pod -n <NAMESPACE> <POD_NAME>
```

---

## Testing Recovery Procedures

**IMPORTANT**: Test these procedures regularly to ensure they work when needed.

### Monthly Tests

1. **Verify backups exist**:
   ```bash
   ls -la ~/.config/sops/age/keys.txt
   ls -la ~/openbao-keys.yaml
   ```

2. **Test SOPS decryption**:
   ```bash
   sops -d argo/apps/democratic-csi-nfs.sops.yaml > /dev/null && echo "✅ SOPS working"
   ```

3. **Verify snapshot tasks**:
   ```bash
   # Check via TrueNAS API
   curl -k "https://192.168.2.30/api/v2.0/pool/snapshottask" \
     -H "Authorization: Bearer <API_KEY>" | jq '.'
   ```

4. **Test OpenBao unseal** (in non-prod):
   ```bash
   # Seal OpenBao
   kubectl exec -n openbao $POD -- bao operator seal

   # Unseal with keys
   kubectl exec -n openbao $POD -- bao operator unseal <KEY_1>
   kubectl exec -n openbao $POD -- bao operator unseal <KEY_2>
   kubectl exec -n openbao $POD -- bao operator unseal <KEY_3>
   ```

### Quarterly Tests

1. **Test snapshot restore** (on non-critical data)
2. **Verify etcd backup procedure**
3. **Test democratic-csi failover**

---

## Emergency Contacts & Resources

- **TrueNAS WebUI**: https://192.168.2.30
- **TrueNAS SSH**: `ssh root@192.168.2.30`
- **Talos Dashboard**: Access via talosctl
- **ArgoCD**: https://argocd.homelab.local
- **OpenBao**: https://vault.homelab.local

## Additional Notes

- All times in snapshot schedules are in the system's local timezone
- ZFS snapshots are read-only and space-efficient (only stores changed blocks)
- TrueNAS automatically prunes old snapshots based on retention policies
- For complete disaster recovery, keep offsite backups of critical secrets
