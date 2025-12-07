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

# 5. Create TLS certificates
kubectl apply -f certificates.yaml

# 6. Configure ingress
kubectl apply -f ingress.yaml
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

- [ ] Plex Media Server (requires GPU node for transcoding)
- [ ] Bazarr for subtitle management
- [ ] Overseerr for request management
- [ ] Tautulli for Plex statistics
- [ ] Readarr for book management
- [ ] Lidarr for music management
