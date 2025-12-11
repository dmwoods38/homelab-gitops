# Disaster Recovery Guide

**Last Updated**: 2025-12-10

This guide documents procedures for recovering from various failure scenarios in the homelab infrastructure.

## Table of Contents

1. [Critical Secrets Backup](#critical-secrets-backup)
2. [TrueNAS Snapshot Schedule](#truenas-snapshot-schedule)
3. [Recovery Scenarios](#recovery-scenarios)
4. [Talos Cluster Recovery](#talos-cluster-recovery)
5. [OpenBao Recovery](#openbao-recovery)
6. [Application Data Recovery](#application-data-recovery)

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

4. **If no etcd backup**: Reinstall all applications
   - Clone gitops repository
   - Apply ArgoCD bootstrap
   - ArgoCD will sync all applications from git

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
