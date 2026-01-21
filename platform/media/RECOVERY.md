# Media Stack Disaster Recovery Guide

This document provides complete recovery procedures for the media stack in case of catastrophic failure.

## Prerequisites for Recovery

### Required Information

1. **SOPS/Age Key**: AGE private key for decrypting secrets
   - Location: `~/.config/sops/age/keys.txt` (or wherever you store it)
   - **CRITICAL**: Back this up securely! Without it, you cannot decrypt VPN credentials

2. **VPN Credentials** (if SOPS key is lost):
   - VPN Provider username
   - VPN Provider password
   - VPN Provider name (e.g., "nordvpn", "private internet access")

3. **DNS Configuration**:
   - Domain: `internal.sever-it.com`
   - DNS provider API credentials (for cert-manager Let's Encrypt DNS-01 challenge)

4. **TrueNAS Access**:
   - TrueNAS IP: `192.168.2.30`
   - TrueNAS API key (for NFS share management)
   - SSH access to TrueNAS (for emergency recovery)

### Required Infrastructure

Before deploying media stack, ensure these are operational:

1. **Kubernetes Cluster** (Talos Linux)
   - At least one node with NVIDIA GPU
   - Node labeled: `nvidia.com/gpu.present=true`
   - Namespace `default` with Pod Security: `privileged`

2. **MetalLB** (Layer 2 load balancer)
   - IP pool configured for LoadBalancer services
   - Example: `192.168.2.220-192.168.2.230`

3. **Traefik** (Ingress controller)
   - Deployed and listening on websecure (443)
   - TLS configured

4. **cert-manager** (TLS certificate management)
   - ClusterIssuer: `letsencrypt-dns` configured
   - DNS-01 challenge solver working

5. **NVIDIA Device Plugin** (GPU support)
   - DaemonSet running on GPU node
   - GPU allocatable: `nvidia.com/gpu: 1`

6. **TrueNAS NFS Share**
   - Path: `/mnt/default/media`
   - NFS service enabled
   - Network access: `192.168.0.0/16`
   - maproot_user: `root`, maproot_group: `wheel`

## Recovery Inventory

### Git Repository Files

All manifests are in: `platform/media/`

**Core Infrastructure:**
- `media-storage.yaml` - Static NFS PV and PVC
- `gluetun-secret.sops.yaml` - VPN credentials (SOPS encrypted)

**Application Deployments:**
- `gluetun-qbittorrent.yaml` - VPN proxy + download client
- `flaresolverr.yaml` - Cloudflare bypass proxy
- `prowlarr.yaml` - Indexer management
- `sonarr.yaml` - TV show management
- `radarr.yaml` - Movie management
- `plex.yaml` - Media server with GPU transcoding
- `overseerr.yaml` - Request management interface

**TLS Certificates:**
- `certificates.yaml` - Certificates for *arr apps and qBittorrent
- `plex-overseerr-certificates.yaml` - Certificates for Plex and Overseerr

**Ingress Routes:**
- `ingress.yaml` - Traefik routes for *arr apps and qBittorrent
- `plex-overseerr-ingress.yaml` - Traefik routes for Plex and Overseerr

### Kubernetes Secrets

**Managed by SOPS:**
- `gluetun-vpn` (namespace: media) - VPN provider credentials

**Managed by cert-manager:**
- `sonarr-tls-cert`
- `radarr-tls-cert`
- `prowlarr-tls-cert`
- `qbittorrent-tls-cert`
- `plex-tls-cert`
- `overseerr-tls-cert`

### Persistent Data

**NFS Volume:** `/mnt/default/media` on TrueNAS (1Ti total)

**Critical Application Data:**
```
/mnt/default/media/
├── gluetun/              # VPN configuration and state
├── qbittorrent/config/   # Download client config, RSS feeds
├── prowlarr/             # Indexer definitions and API keys
├── sonarr/               # TV library metadata, download history
├── radarr/               # Movie library metadata, download history
├── plex/                 # Media server config, watch history, metadata
├── plex-transcode/       # Temporary transcoding files (can be lost)
├── overseerr/            # Request management config, user data
├── downloads/            # Active downloads (can be lost)
├── tv/                   # TV show library (MEDIA FILES)
└── movies/               # Movie library (MEDIA FILES)
```

**What to Back Up:**
- **CRITICAL**: `/mnt/default/media/tv/` and `/mnt/default/media/movies/` (your actual media)
- **IMPORTANT**: All config directories (gluetun, qbittorrent, prowlarr, sonarr, radarr, plex, overseerr)
- **OPTIONAL**: `downloads/` and `plex-transcode/` (can be recreated)

### Non-Persistent Configuration

These configurations exist only in the running pods and must be reconfigured after recovery:

**Prowlarr:**
- Indexers (1337x, YTS, EZTV, TorrentGalaxy, etc.)
- FlareSolverr proxy configuration
- Application connections (Sonarr, Radarr API keys)

**Sonarr:**
- Root folder: `/tv`
- Download client: qBittorrent connection
- (Indexers sync from Prowlarr automatically)

**Radarr:**
- Root folder: `/movies`
- Download client: qBittorrent connection
- (Indexers sync from Prowlarr automatically)

**qBittorrent:**
- Admin password (default temp password on first boot)
- Download paths

**Plex:**
- Server claiming (plex.tv account)
- Library definitions (TV Shows: `/tv`, Movies: `/movies`)
- GPU transcoding enabled
- Watch history, user accounts

**Overseerr:**
- Plex server connection
- Sonarr/Radarr API connections
- User permissions

**NOTE:** If you have the NFS config directories backed up, most of these settings will be preserved! Only reconfigure if starting from scratch.

## Complete Recovery Procedure

### Step 1: Restore Infrastructure

1. **Verify Kubernetes cluster is healthy:**
   ```bash
   kubectl get nodes
   kubectl get pods -A
   ```

2. **Verify GPU is available:**
   ```bash
   kubectl label node <node-name> nvidia.com/gpu.present=true
   kubectl label namespace default pod-security.kubernetes.io/enforce=privileged
   kubectl describe node <node-name> | grep nvidia.com/gpu
   # Should show: nvidia.com/gpu: 1
   ```

3. **Verify TrueNAS NFS share exists:**
   ```bash
   ssh root@192.168.2.30 "showmount -e"
   # Should show: /mnt/default/media  192.168.0.0/16
   ```

   If NFS share doesn't exist, create it:
   ```bash
   curl -k -X POST https://192.168.2.30/api/v2.0/sharing/nfs \
     -H "Authorization: Bearer $TRUENAS_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
       "path": "/mnt/default/media",
       "comment": "Media stack storage",
       "networks": ["192.168.0.0/16"],
       "maproot_user": "root",
       "maproot_group": "wheel"
     }'

   curl -k -X PUT https://192.168.2.30/api/v2.0/service/id/nfs/ \
     -H "Authorization: Bearer $TRUENAS_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"enable": true}'
   ```

### Step 2: Restore Media Data (if from backup)

If recovering from backup, restore NFS data BEFORE deploying applications:

```bash
# Example using rsync from backup location
rsync -avP /path/to/backup/media/ root@192.168.2.30:/mnt/default/media/
```

**Verify ownership after restore:**
```bash
ssh root@192.168.2.30 "chown -R 1000:1000 /mnt/default/media/tv"
ssh root@192.168.2.30 "chown -R 1000:1000 /mnt/default/media/movies"
ssh root@192.168.2.30 "chown -R 1000:1000 /mnt/default/media/downloads"
ssh root@192.168.2.30 "chmod -R 775 /mnt/default/media/{tv,movies,downloads}"
```

### Step 3: Deploy Media Stack

1. **Create media namespace:**
   ```bash
   kubectl create namespace media
   ```

2. **Deploy in order:**
   ```bash
   cd /home/dmwoods38/dev/homelab/homelab-gitops/platform/media/

   # 1. Storage
   kubectl apply -f media-storage.yaml

   # 2. VPN credentials (requires SOPS key)
   kubectl apply -f gluetun-secret.sops.yaml

   # 3. VPN + Download client
   kubectl apply -f gluetun-qbittorrent.yaml

   # 4. Cloudflare bypass
   kubectl apply -f flaresolverr.yaml

   # 5. Indexer management
   kubectl apply -f prowlarr.yaml

   # 6. Content management
   kubectl apply -f sonarr.yaml
   kubectl apply -f radarr.yaml

   # 7. Media server and request management
   kubectl apply -f plex.yaml
   kubectl apply -f overseerr.yaml

   # 8. TLS certificates
   kubectl apply -f certificates.yaml
   kubectl apply -f plex-overseerr-certificates.yaml

   # 9. Ingress routes
   kubectl apply -f ingress.yaml
   kubectl apply -f plex-overseerr-ingress.yaml
   ```

3. **Wait for all pods to be running:**
   ```bash
   kubectl get pods -n media -w
   ```

4. **Wait for certificates to be ready (2-3 minutes):**
   ```bash
   kubectl get certificates -n media -w
   ```

### Step 4: Fix NFS Permissions (if needed)

```bash
# Get pod names
SONARR_POD=$(kubectl get pod -n media -l app=sonarr -o jsonpath='{.items[0].metadata.name}')
RADARR_POD=$(kubectl get pod -n media -l app=radarr -o jsonpath='{.items[0].metadata.name}')
GLUETUN_POD=$(kubectl get pod -n media -l app=gluetun -o jsonpath='{.items[0].metadata.name}')

# Fix ownership (media apps run as uid 1000)
kubectl exec -n media $SONARR_POD -- chown -R 1000:1000 /tv
kubectl exec -n media $SONARR_POD -- chmod -R 775 /tv

kubectl exec -n media $RADARR_POD -- chown -R 1000:1000 /movies
kubectl exec -n media $RADARR_POD -- chmod -R 775 /movies

kubectl exec -n media -c qbittorrent $GLUETUN_POD -- chown -R 1000:1000 /downloads
kubectl exec -n media -c qbittorrent $GLUETUN_POD -- chmod -R 775 /downloads
```

### Step 5: Verify VPN is Working

```bash
kubectl exec -n media -c qbittorrent \
  $(kubectl get pod -n media -l app=gluetun -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s ifconfig.me
# Should return VPN provider's IP, NOT your home IP
```

### Step 6: Configure Applications

If config directories were restored from backup, most settings will be preserved. Only need to:

1. **qBittorrent:** Change password from temp password
2. **Plex:** Claim server if not already claimed
3. **Overseerr:** May need to reconnect to Plex

If starting from scratch, follow full configuration guide in README.md sections:
- Section "1. qBittorrent First Login"
- Section "2. Prowlarr Setup"
- Section "3. Sonarr Configuration"
- Section "4. Radarr Configuration"
- Section "5. Plex Configuration"
- Section "6. Overseerr Configuration"

## Recovery Without SOPS Key

If you lose the AGE private key, you cannot decrypt `gluetun-secret.sops.yaml`. To recover:

1. **Create new VPN secret manually:**
   ```bash
   kubectl create secret generic gluetun-vpn \
     --from-literal=OPENVPN_USER='<your-vpn-username>' \
     --from-literal=OPENVPN_PASSWORD='<your-vpn-password>' \
     -n media
   ```

2. **Continue with Step 3** above, but skip applying `gluetun-secret.sops.yaml`

3. **Re-encrypt secret with new SOPS key** (recommended):
   ```bash
   # Create new secret file
   cat > gluetun-secret.yaml <<EOF
   apiVersion: v1
   kind: Secret
   metadata:
     name: gluetun-vpn
     namespace: media
   type: Opaque
   stringData:
     OPENVPN_USER: '<your-vpn-username>'
     OPENVPN_PASSWORD: '<your-vpn-password>'
   EOF

   # Encrypt with SOPS (requires new AGE key setup)
   sops -e gluetun-secret.yaml > gluetun-secret.sops.yaml

   # Verify encryption worked
   sops -d gluetun-secret.sops.yaml

   # Delete plaintext file
   rm gluetun-secret.yaml
   ```

## Backup Recommendations

### Critical Backups (MUST HAVE)

1. **SOPS AGE Private Key**
   - File: `~/.config/sops/age/keys.txt`
   - Store in: Password manager, encrypted USB drive, secure cloud storage
   - **This is your master key - lose this and you lose all encrypted secrets!**

2. **Media Files**
   - Path: `/mnt/default/media/tv/` and `/mnt/default/media/movies/`
   - Size: Potentially hundreds of GB to several TB
   - Backup strategy: External hard drives, cloud storage, or RAID on TrueNAS
   - Frequency: After adding new content (or rely on TrueNAS ZFS snapshots)

### Important Backups (Configuration)

3. **Application Configuration Directories**
   - Path: `/mnt/default/media/{prowlarr,sonarr,radarr,plex,overseerr,qbittorrent}/`
   - Size: Usually < 1GB total
   - Contains: Indexer configs, API keys, watch history, metadata
   - Backup strategy: Daily snapshots via TrueNAS ZFS or rsync
   - Frequency: Daily or after major configuration changes

4. **VPN Credentials**
   - Store separately from SOPS key
   - Keep in password manager

### Optional Backups

5. **Downloads Directory**
   - Path: `/mnt/default/media/downloads/`
   - Can be recreated by re-downloading content
   - Only backup if you have incomplete downloads you want to preserve

## Testing Recovery

Test your recovery procedure regularly:

```bash
# 1. Delete everything except data
kubectl delete namespace media

# 2. Verify data still exists on NFS
ls /mnt/default/media/tv/
ls /mnt/default/media/movies/

# 3. Run recovery procedure
# Follow "Complete Recovery Procedure" above

# 4. Verify everything works:
# - All pods running
# - Can access all web UIs
# - VPN is connected
# - Plex shows your media
# - Can make a test request in Overseerr
```

## Emergency Contacts and References

- **TrueNAS Documentation:** https://www.truenas.com/docs/
- **Talos Linux Docs:** https://www.talos.dev/
- **SOPS Documentation:** https://github.com/getsops/sops
- **Gluetun Wiki:** https://github.com/qdm12/gluetun-wiki
- **Plex Support:** https://support.plex.tv/
- **Servarr Wiki:** https://wiki.servarr.com/

## Emergency: Database Corruption (Radarr/Sonarr)

**Symptoms**: Application shows errors like `database disk image is malformed`, won't add downloads

**Cause**: SQLite database corruption from power loss, unclean shutdown, or storage issues

**Quick Recovery** (uses automatic backups):

```bash
# Example for Radarr (same steps for Sonarr)
APP=radarr  # or sonarr

# 1. Scale down
kubectl scale deployment $APP -n media --replicas=0
kubectl wait --for=delete pod -l app=$APP -n media --timeout=60s

# 2. Restore from backup
kubectl run -n media temp-$APP-fix --rm -i --image=busybox --restart=Never --overrides="{
  \"spec\": {
    \"securityContext\": {
      \"runAsNonRoot\": true,
      \"runAsUser\": 1000,
      \"runAsGroup\": 1000,
      \"fsGroup\": 1000,
      \"seccompProfile\": {\"type\": \"RuntimeDefault\"}
    },
    \"containers\": [{
      \"name\": \"fix\",
      \"image\": \"busybox\",
      \"securityContext\": {
        \"allowPrivilegeEscalation\": false,
        \"capabilities\": {\"drop\": [\"ALL\"]}
      },
      \"command\": [\"sh\", \"-c\", \"cd /config && cp ${APP}.db ${APP}.db.corrupt.backup && ls -lh Backups/scheduled/ && LATEST=\$(ls -t Backups/scheduled/*.zip | head -1) && unzip -o \$LATEST ${APP}.db && echo Database restored && ls -lh ${APP}.db* && sleep 10\"],
      \"volumeMounts\": [{
        \"name\": \"media-storage\",
        \"mountPath\": \"/config\",
        \"subPath\": \"$APP\"
      }]
    }],
    \"volumes\": [{
      \"name\": \"media-storage\",
      \"persistentVolumeClaim\": {\"claimName\": \"media-nfs\"}
    }]
  }
}"

# 3. Scale back up
kubectl scale deployment $APP -n media --replicas=1

# 4. Verify
kubectl logs -n media -l app=$APP --tail=50 | grep -i "error\|corrupt"
```

**What This Does**:
- Backs up the corrupted database to `${APP}.db.corrupt.backup`
- Extracts the most recent automatic backup from `Backups/scheduled/`
- Restarts the application with the restored database

**Backup Locations**:
- Radarr: `/mnt/default/media/radarr/Backups/scheduled/`
- Sonarr: `/mnt/default/media/sonarr/Backups/scheduled/`
- Automatic backups created weekly by the applications

## Post-Recovery Checklist

- [ ] All pods in `media` namespace are Running (1/1 or 2/2)
- [ ] VPN is connected (IP check shows VPN provider IP)
- [ ] All TLS certificates are Ready
- [ ] Can access all web UIs via HTTPS
- [ ] Plex shows media libraries with content
- [ ] Prowlarr has indexers configured
- [ ] Sonarr and Radarr have indexers synced from Prowlarr
- [ ] qBittorrent is accessible and configured
- [ ] Overseerr is connected to Plex, Sonarr, and Radarr
- [ ] Test download: Make a request in Overseerr and verify it downloads
- [ ] GPU transcoding works in Plex (check logs during playback)
