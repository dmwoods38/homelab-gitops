# Media Management Stack

Automated media management stack with VPN routing, download client, and content organization.

## Architecture

```
Internet → Gluetun (VPN) → qBittorrent → NFS Storage
                          ↓
                     Prowlarr (Indexer Management)
                          ↓
                   Sonarr/Radarr (Content Management)
                          ↓
                    Media Library (NFS)
```

## Components

### Gluetun VPN Proxy
- **Purpose**: Routes download traffic through VPN provider
- **Provider**: Configured via Secret (supports multiple providers)
- **Network**: Sidecar pattern with qBittorrent
- **Features**: Kill switch, DNS leak protection, HTTP proxy

### qBittorrent
- **Purpose**: Download client
- **Network**: Shares network namespace with Gluetun (all traffic through VPN)
- **WebUI**: Port 8080 (accessed via qbittorrent service)
- **Storage**: Downloads to shared NFS volume

### Prowlarr
- **Purpose**: Central indexer management
- **Integration**: Connects to Sonarr and Radarr
- **WebUI**: Port 9696

### Sonarr
- **Purpose**: TV show content management
- **Download Client**: qBittorrent
- **Indexers**: Via Prowlarr
- **Storage**: TV library on NFS

### Radarr
- **Purpose**: Movie content management
- **Download Client**: qBittorrent
- **Indexers**: Via Prowlarr
- **Storage**: Movie library on NFS

### Plex Media Server
- **Purpose**: Stream and organize media library
- **Hardware Transcoding**: NVIDIA GPU acceleration
- **Storage**: Read-only access to TV and movie libraries
- **WebUI**: Port 32400
- **Network**: LoadBalancer service for external access

### Overseerr
- **Purpose**: Media request management interface
- **Integration**: Connects to Plex, Sonarr, and Radarr
- **Features**: User requests, approval workflows, notifications
- **WebUI**: Port 5055

## Storage Layout

All applications share a single NFS PV (1Ti) with subdirectories:

```
/mnt/default/media/
├── gluetun/           # Gluetun VPN config
├── qbittorrent/
│   └── config/        # qBittorrent config
├── prowlarr/          # Prowlarr config
├── sonarr/            # Sonarr config
├── radarr/            # Radarr config
├── plex/              # Plex config and metadata
├── plex-transcode/    # Temporary transcoding files
├── overseerr/         # Overseerr config
├── downloads/         # Shared download directory
├── tv/                # TV show library
└── movies/            # Movie library
```

## Deployment

### Prerequisites

1. **NFS Share on TrueNAS**:
   ```bash
   # Create NFS share
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

   # Start NFS service
   curl -k -X PUT https://192.168.2.30/api/v2.0/service/id/nfs/ \
     -H "Authorization: Bearer $TRUENAS_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"enable": true}'
   ```

2. **VPN Credentials Secret** (SOPS encrypted):
   ```bash
   kubectl apply -f gluetun-secret.sops.yaml
   ```

### Deploy Stack

```bash
# 1. Create static NFS PV and PVC
kubectl apply -f media-storage.yaml

# 2. Deploy Gluetun + qBittorrent
kubectl apply -f gluetun-qbittorrent.yaml

# 3. Deploy Prowlarr
kubectl apply -f prowlarr.yaml

# 4. Deploy Sonarr and Radarr
kubectl apply -f sonarr.yaml
kubectl apply -f radarr.yaml

# 5. Deploy Plex and Overseerr
kubectl apply -f plex.yaml
kubectl apply -f overseerr.yaml

# 6. Create TLS certificates
kubectl apply -f certificates.yaml
kubectl apply -f plex-overseerr-certificates.yaml

# 7. Configure ingress
kubectl apply -f ingress.yaml
kubectl apply -f plex-overseerr-ingress.yaml
```

### Prerequisites for Plex GPU Transcoding

Ensure GPU is available to Kubernetes:

```bash
# Label node with GPU
kubectl label node <node-name> nvidia.com/gpu.present=true

# Set Pod Security to privileged (for NVIDIA device plugin)
kubectl label namespace default pod-security.kubernetes.io/enforce=privileged

# Verify GPU is allocatable
kubectl describe node <node-name> | grep nvidia.com/gpu
# Should show: nvidia.com/gpu: 1
```

### Verify Deployment

```bash
# Check all pods
kubectl get pods -n media

# Verify VPN connection
kubectl exec -n media -c qbittorrent \
  $(kubectl get pod -n media -l app=gluetun -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s ifconfig.me
# Should return VPN provider's IP, not your home IP

# Check services
kubectl get svc -n media

# Check ingress routes
kubectl get ingressroute -n media
```

## Access URLs

All services accessible via Traefik with TLS:

- **Plex**: https://plex.internal.sever-it.com (also LoadBalancer IP via MetalLB)
- **Overseerr**: https://overseerr.internal.sever-it.com
- **qBittorrent**: https://qbittorrent.internal.sever-it.com
- **Prowlarr**: https://prowlarr.internal.sever-it.com
- **Sonarr**: https://sonarr.internal.sever-it.com
- **Radarr**: https://radarr.internal.sever-it.com

## Configuration

### 1. qBittorrent First Login

1. Access WebUI at https://qbittorrent.internal.sever-it.com
2. Default credentials: `admin` / (check pod logs for temp password)
3. Change password immediately in Tools → Options → Web UI
4. Configure download paths to use `/downloads`

### 2. Prowlarr Setup

1. Access https://prowlarr.internal.sever-it.com
2. Add indexers in Settings → Indexers
3. Add applications:
   - **Sonarr**: `http://sonarr.media.svc.cluster.local:8989`
   - **Radarr**: `http://radarr.media.svc.cluster.local:7878`

### 3. Sonarr Configuration

1. Access https://sonarr.internal.sever-it.com
2. Add download client (Settings → Download Clients):
   - Type: qBittorrent
   - Host: `qbittorrent.media.svc.cluster.local`
   - Port: 8080
   - Username/Password: (your qBittorrent credentials)
3. Configure root folder: `/tv`
4. Indexers sync automatically from Prowlarr

### 4. Radarr Configuration

1. Access https://radarr.internal.sever-it.com
2. Add download client (Settings → Download Clients):
   - Type: qBittorrent
   - Host: `qbittorrent.media.svc.cluster.local`
   - Port: 8080
   - Username/Password: (your qBittorrent credentials)
3. Configure root folder: `/movies`
4. Indexers sync automatically from Prowlarr

### 5. Plex Configuration

1. Access https://plex.internal.sever-it.com (or LoadBalancer IP on port 32400)
2. Sign in with your Plex account (or create one)
3. Name your server
4. **Add Libraries**:
   - TV Shows: `/tv`
   - Movies: `/movies`
5. **Enable Hardware Transcoding**:
   - Settings → Transcoder
   - Check "Use hardware acceleration when available"
   - Transcoder temporary directory: `/transcode`
6. **Verify GPU is working**:
   - Play a video that requires transcoding
   - Check logs: `kubectl logs -n media -l app=plex | grep -i nvidia`

### 6. Overseerr Configuration

1. Access https://overseerr.internal.sever-it.com
2. **Sign in with Plex** account
3. Select your Plex server from the list
4. **Add Sonarr**:
   - Settings → Services → Sonarr
   - Server: `http://sonarr.media.svc.cluster.local:8989`
   - API Key: Get from Sonarr (Settings → General → API Key)
   - Root Folder: `/tv`
   - Quality Profile: Select preferred quality
   - Click "Test" then "Save"
5. **Add Radarr**:
   - Settings → Services → Radarr
   - Server: `http://radarr.media.svc.cluster.local:7878`
   - API Key: Get from Radarr (Settings → General → API Key)
   - Root Folder: `/movies`
   - Quality Profile: Select preferred quality
   - Click "Test" then "Save"
6. **Configure Notifications** (optional):
   - Settings → Notifications
   - Add Discord, Slack, Email, etc.

### 7. Using Overseerr for Requests

**Request Workflow**:
```
User → Overseerr → Browse/Search → Request
         ↓
   Sonarr/Radarr → Prowlarr → Find Content
         ↓
    qBittorrent → Download (via VPN)
         ↓
  Automatic Import → Plex Library
         ↓
    Notification → User Watches
```

**To Request Content**:
1. Browse or search for movies/TV shows in Overseerr
2. Click "Request" button
3. Select quality and seasons (for TV)
4. Submit request
5. Get notified when available in Plex

## Troubleshooting

### VPN Not Working

Check Gluetun logs:
```bash
kubectl logs -n media -l app=gluetun -c gluetun --tail 50
```

Verify VPN IP:
```bash
kubectl exec -n media -c qbittorrent \
  $(kubectl get pod -n media -l app=gluetun -o jsonpath='{.items[0].metadata.name}') \
  -- curl -s ifconfig.me
```

### Certificate Not Ready

Wait 2-3 minutes for Let's Encrypt DNS challenge:
```bash
kubectl get certificates -n media
kubectl describe certificate <cert-name> -n media
```

### App Not Accessible

Check ingress and service:
```bash
kubectl describe ingressroute <app-name> -n media
kubectl get svc <app-name> -n media
```

### NFS Mount Issues

Verify NFS share exists on TrueNAS:
```bash
ssh root@192.168.2.30 "showmount -e"
```

Check PV/PVC status:
```bash
kubectl get pv media-nfs
kubectl get pvc -n media media-nfs
```

### GPU Not Working in Plex

Check GPU is allocated to pod:
```bash
kubectl describe pod -n media -l app=plex | grep nvidia.com/gpu
```

Verify NVIDIA device plugin is running:
```bash
kubectl get pods -n default -l app.kubernetes.io/name=nvidia-device-plugin
```

Check Plex transcoding logs:
```bash
kubectl logs -n media -l app=plex | grep -i nvidia
```

If GPU not visible:
```bash
# Label node
kubectl label node <node-name> nvidia.com/gpu.present=true

# Check node resources
kubectl describe node <node-name> | grep nvidia.com/gpu
```

### Overseerr Can't Connect to Sonarr/Radarr

Verify services are accessible:
```bash
# From Overseerr pod
kubectl exec -n media -l app=overseerr -- curl -s http://sonarr.media.svc.cluster.local:8989/api/v3/system/status

kubectl exec -n media -l app=overseerr -- curl -s http://radarr.media.svc.cluster.local:7878/api/v3/system/status
```

Check API keys are correct in Overseerr configuration.

## Security Considerations

1. **VPN**: All download traffic routes through VPN (verified by IP check)
2. **TLS**: All web interfaces secured with Let's Encrypt certificates
3. **Secrets**: VPN credentials stored in SOPS-encrypted Secret
4. **Network Isolation**: qBittorrent cannot bypass VPN (network namespace sharing)
5. **Authentication**: Change default passwords immediately after deployment

## Storage Solution Notes

This deployment uses a **static NFS PV** instead of dynamic provisioning due to compatibility issues:

- **iSCSI CSI**: Incompatible with Talos Linux's minimal filesystem (lacks `/usr/bin/env` for chroot operations)
- **NFS CSI**: TrueNAS SCALE 25.04 API schema changes broke democratic-csi dynamic provisioning
- **Static NFS**: Manual NFS share creation with static PV/PVC binding (works reliably)

All applications use subPath mounts on the shared NFS volume for efficient resource usage.

## Future Enhancements

- [x] Plex Media Server with GPU transcoding ✅
- [x] Overseerr for request management ✅
- [ ] Bazarr for subtitle management
- [ ] Tautulli for Plex statistics and monitoring
- [ ] Readarr for book/audiobook management
- [ ] Lidarr for music management
- [ ] Plex Meta Manager for collections and metadata
- [ ] Notifiarr for advanced notifications
