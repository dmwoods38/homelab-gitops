# Disaster Recovery Guide

Complete disaster recovery procedures for the entire homelab Kubernetes cluster.

## Critical Prerequisites (MUST HAVE BACKUPS)

### 1. SOPS AGE Private Key
**Location**: Stored in ArgoCD as secret `sops-age` in `argocd` namespace
**Backup Command**:
```bash
kubectl get secret sops-age -n argocd -o jsonpath='{.data.age\.agekey}' | base64 -d > ~/backup/sops-age-key.txt
chmod 600 ~/backup/sops-age-key.txt
```
**Recovery**: Required to decrypt all `.sops.yaml` files in the GitOps repo

### 2. OpenBao Unseal Keys & Root Token
**Location**: `~/openbao-keys.yaml` (chmod 600)
**Backup Command**:
```bash
cp ~/openbao-keys.yaml ~/backup/openbao-keys.yaml
# OR encrypt with SOPS and commit to repo
sops -e ~/openbao-keys.yaml > platform/openbao/openbao-keys.sops.yaml
```
**Contains**:
- 5 unseal keys (threshold: 3)
- Root token: `s.wh72MLXFxoN69Qmsvfca3TKm`

### 3. TrueNAS SSH Key
**Location**: `~/.ssh/truenas_csi`
**Purpose**: Required for NFS share management via democratic-csi
**Backup Command**:
```bash
cp ~/.ssh/truenas_csi ~/backup/
```

### 4. TrueNAS API Key
**Location**: Encrypted in `argo/apps/democratic-csi-nfs.sops.yaml`
**Current Key**: `2-w9S8Dlb6lowTJL8mQCI3tcIYpEvFZB3n1VcJOtnuytUlu92yMOXZbj6isDWY4LbC`
**Recovery**: Decrypt SOPS file or regenerate in TrueNAS UI (Settings → API Keys)

### 5. Cloudflare API Token
**Location**: Encrypted in cert-manager secret `cloudflare-api-token3`
**Purpose**: DNS-01 challenge for Let's Encrypt certificates
**Recovery**: Regenerate in Cloudflare dashboard if lost

### 6. Talos Machine Configurations
**Location**: `/home/dmwoods38/dev/homelab/talos/machine-configs/`
**Encrypted**: Yes (SOPS)
**Contains**: Node join tokens, secrets, certificates
**Backup Command**:
```bash
tar -czf ~/backup/talos-configs-$(date +%Y%m%d).tar.gz talos/
```

### 7. GitOps Repository
**Location**: https://github.com/dmwoods38/homelab-gitops
**Contains**: All manifests, configs, SOPS-encrypted secrets
**Backup**: Git commits are backup, but clone locally:
```bash
git clone https://github.com/dmwoods38/homelab-gitops ~/backup/homelab-gitops
```

### 8. Persistent Data Backups (TrueNAS)
**Media Stack**: `/mnt/default/media` (NFS)
**OpenBao Data**: `/mnt/default/openbao` (NFS)
**Backup Strategy**:
- TrueNAS ZFS snapshots (recommended: daily)
- TrueNAS Cloud Sync to remote storage
- Manual: `rsync -av root@192.168.2.30:/mnt/default/media ~/backup/`

---

## Recovery Scenarios

### Scenario 1: Complete Cluster Loss (Talos Nodes Destroyed)

**Prerequisites**: All items from "Critical Prerequisites" backed up

**Steps**:

1. **Restore Talos Linux**
   ```bash
   # Boot from Talos ISO on new hardware
   # Apply machine configs
   cd talos/machine-configs/
   sops -d controlplane-1.sops.yaml | talosctl apply-config --insecure --nodes 192.168.2.20 --file -

   # Wait for node to be ready
   talosctl health --nodes 192.168.2.20
   ```

2. **Bootstrap Kubernetes**
   ```bash
   talosctl bootstrap --nodes 192.168.2.20
   talosctl kubeconfig --nodes 192.168.2.20 --force
   kubectl wait --for=condition=Ready nodes --all --timeout=300s
   ```

3. **Restore SOPS AGE Key**
   ```bash
   kubectl create namespace argocd
   kubectl create secret generic sops-age \
     --from-file=age.agekey=~/backup/sops-age-key.txt \
     -n argocd
   ```

4. **Deploy ArgoCD**
   ```bash
   kubectl apply -f argo/argocd-install.yaml
   kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

   # Deploy ArgoCD Application (self-management)
   kubectl apply -f argo/apps/argocd.yaml
   ```

5. **Deploy Core Infrastructure**
   ```bash
   # Deploy in this order for dependencies
   kubectl apply -f argo/apps/metallb.sops.yaml
   kubectl apply -f argo/apps/traefik.yaml
   kubectl apply -f argo/apps/cert-manager.yaml

   # Wait for cert-manager to be ready
   kubectl wait --for=condition=available --timeout=300s deployment/cert-manager -n cert-manager
   ```

6. **Deploy Storage (Democratic-CSI NFS)**
   ```bash
   # Restore TrueNAS SSH key
   mkdir -p ~/.ssh
   cp ~/backup/truenas_csi ~/.ssh/
   chmod 600 ~/.ssh/truenas_csi

   # Deploy democratic-csi
   kubectl apply -f argo/apps/democratic-csi-nfs.sops.yaml
   ```

7. **Deploy OpenBao**
   ```bash
   kubectl apply -f platform/openbao/namespace.yaml
   kubectl apply -f platform/openbao/openbao-nfs-storage.yaml
   kubectl apply -f platform/openbao/openbao-deployment.yaml
   kubectl apply -f platform/openbao/ingress.yaml

   # Wait for pod to be running
   kubectl wait --for=condition=ready pod -l app=openbao -n openbao --timeout=120s
   ```

8. **Unseal and Restore OpenBao**
   ```bash
   # Get pod name
   POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')

   # Unseal with 3 of 5 keys from ~/openbao-keys.yaml
   kubectl exec -n openbao $POD -- bao operator unseal <KEY_1>
   kubectl exec -n openbao $POD -- bao operator unseal <KEY_2>
   kubectl exec -n openbao $POD -- bao operator unseal <KEY_3>

   # Verify unsealed
   kubectl exec -n openbao $POD -- bao status

   # Login and re-enable engines if needed
   kubectl exec -n openbao $POD -- bao login <ROOT_TOKEN>
   kubectl exec -n openbao $POD -- bao auth enable kubernetes
   kubectl exec -n openbao $POD -- bao secrets enable -version=2 -path=secret kv

   # Restore VPN credentials
   kubectl exec -n openbao $POD -- bao kv put secret/media/vpn \
     OPENVPN_USER=<USER> \
     OPENVPN_PASSWORD=<PASSWORD>
   ```

9. **Deploy External Secrets Operator**
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets \
     -n external-secrets --create-namespace --set installCRDs=true
   ```

10. **Restore OpenBao K8s Auth** (see "OpenBao Recovery" section below)

11. **Deploy Media Stack**
    ```bash
    kubectl apply -f platform/media/
    ```

12. **Verify Everything**
    ```bash
    kubectl get pods -A
    kubectl get pv,pvc -A
    kubectl get externalsecret -n media
    ```

---

### Scenario 2: OpenBao Pod Restart (Sealed State)

**Issue**: OpenBao pod restarts and becomes sealed
**Impact**: External Secrets Operator can't sync secrets

**Recovery**:
```bash
# Get OpenBao pod name
POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')

# Check status
kubectl exec -n openbao $POD -- bao status

# Unseal with 3 of 5 keys
kubectl exec -n openbao $POD -- bao operator unseal <KEY_1>
kubectl exec -n openbao $POD -- bao operator unseal <KEY_2>
kubectl exec -n openbao $POD -- bao operator unseal <KEY_3>

# Verify unsealed
kubectl exec -n openbao $POD -- bao status | grep "Sealed.*false"
```

**Prevention**: Set up auto-unseal with cloud KMS (future enhancement)

---

### Scenario 3: Lost SOPS AGE Key

**Impact**: Cannot decrypt any `.sops.yaml` files in the repo
**Recovery**:
1. **If key is in cluster secret**:
   ```bash
   kubectl get secret sops-age -n argocd -o jsonpath='{.data.age\.agekey}' | base64 -d
   ```

2. **If completely lost**: No recovery possible. Must:
   - Regenerate new AGE key pair
   - Re-encrypt all `.sops.yaml` files with new key
   - Update `.sops.yaml` config with new recipient

**Prevention**:
- Store AGE key in password manager
- Print paper backup
- Store in secure offline location

---

### Scenario 4: TrueNAS Data Loss

**Impact**: All persistent data lost (media library, OpenBao data)
**Recovery**:
1. Restore TrueNAS from backups (ZFS snapshots, cloud sync)
2. Recreate NFS shares:
   ```bash
   # SSH to TrueNAS
   ssh -i ~/.ssh/truenas_csi root@192.168.2.30

   # Recreate shares
   zfs create default/media
   zfs create default/openbao

   # Configure NFS exports via TrueNAS UI
   ```
3. Re-initialize OpenBao if data is lost (use unseal keys from backup)
4. Restore media files from backup

---

## OpenBao Recovery Details

### Re-configure Kubernetes Authentication

After restoring OpenBao, you must recreate the K8s auth configuration:

```bash
POD=$(kubectl get pod -n openbao -l app=openbao -o jsonpath='{.items[0].metadata.name}')

# Login
kubectl exec -n openbao $POD -- bao login <ROOT_TOKEN>

# Enable K8s auth
kubectl exec -n openbao $POD -- bao auth enable kubernetes

# Get K8s auth values
TOKEN_JWT=$(kubectl get secret openbao-auth-token -n openbao -o jsonpath='{.data.token}' | base64 -d)
K8S_HOST=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.server}')
K8S_CA=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d)

# Configure K8s auth
kubectl exec -n openbao $POD -- bao write auth/kubernetes/config \
  token_reviewer_jwt="$TOKEN_JWT" \
  kubernetes_host="$K8S_HOST" \
  kubernetes_ca_cert="$K8S_CA"

# Create media-secrets policy
cat > /tmp/media-policy.hcl <<'EOF'
path "secret/data/media/*" {
  capabilities = ["read", "list"]
}
path "secret/metadata/media/*" {
  capabilities = ["read", "list"]
}
EOF

kubectl cp /tmp/media-policy.hcl openbao/$POD:/tmp/media-policy.hcl
kubectl exec -n openbao $POD -- bao policy write media-secrets /tmp/media-policy.hcl

# Create K8s auth role
kubectl exec -n openbao $POD -- bao write auth/kubernetes/role/media-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=media \
  policies=media-secrets \
  ttl=24h
```

---

## Recovery Checklist

### Before Disaster (Preventive Backups)

- [ ] Export SOPS AGE key: `kubectl get secret sops-age -n argocd -o jsonpath='{.data.age\.agekey}' | base64 -d > ~/backup/sops-age-key.txt`
- [ ] Backup OpenBao keys: `cp ~/openbao-keys.yaml ~/backup/`
- [ ] Backup TrueNAS SSH key: `cp ~/.ssh/truenas_csi ~/backup/`
- [ ] Clone GitOps repo: `git clone https://github.com/dmwoods38/homelab-gitops ~/backup/homelab-gitops`
- [ ] Backup Talos configs: `tar -czf ~/backup/talos-configs.tar.gz talos/`
- [ ] Configure TrueNAS ZFS snapshots (daily retention)
- [ ] Test TrueNAS Cloud Sync to remote storage
- [ ] Document TrueNAS API key in password manager
- [ ] Document Cloudflare API token in password manager
- [ ] Store critical credentials in password manager (1Password, Bitwarden, etc.)

### After Disaster (Recovery Verification)

- [ ] All Talos nodes are Ready
- [ ] ArgoCD syncing all applications
- [ ] All pods in Running state
- [ ] OpenBao unsealed and accessible
- [ ] External Secrets syncing (check `kubectl get externalsecret -A`)
- [ ] Persistent volumes bound (check `kubectl get pv,pvc -A`)
- [ ] TLS certificates issued (check `kubectl get certificate -A`)
- [ ] Media services accessible via ingress
- [ ] VPN connection working (gluetun)
- [ ] Media library accessible from Plex

---

## Estimated Recovery Times

| Scenario | Time to Recovery | Data Loss Risk |
|----------|------------------|----------------|
| Single pod restart | < 5 minutes | None |
| OpenBao sealed | < 2 minutes | None |
| Single node failure | 10-30 minutes | None (if PVs intact) |
| Complete cluster rebuild | 1-2 hours | None (if backups exist) |
| TrueNAS data loss | 2-8 hours | Depends on backup recency |
| Lost SOPS key | N/A | Cannot recover encrypted secrets |

---

## Critical Contacts & Resources

- **TrueNAS**: https://192.168.2.30 (admin access required)
- **GitHub Repo**: https://github.com/dmwoods38/homelab-gitops
- **Talos Docs**: https://www.talos.dev/
- **OpenBao Docs**: https://openbao.org/docs/
- **ArgoCD**: https://argocd.internal.sever-it.com

---

## Testing Recovery Procedures

**Recommendation**: Test recovery procedures quarterly

1. **Simulated OpenBao failure**:
   ```bash
   kubectl delete pod -n openbao -l app=openbao
   # Verify auto-restart and practice unseal
   ```

2. **Simulated secrets loss**:
   ```bash
   kubectl delete secret gluetun-vpn -n media
   # Verify External Secrets Operator recreates it
   ```

3. **Simulated node failure**:
   - Reboot Talos node
   - Verify pod rescheduling and service recovery

---

**Last Updated**: 2025-12-08
**Next Review Date**: 2025-03-08
