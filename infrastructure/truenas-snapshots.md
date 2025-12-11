# TrueNAS Snapshot Configuration

**Note**: TrueNAS snapshot tasks are configured via the TrueNAS API and are not stored in this repository. This document serves as documentation of the current configuration.

## Configured Snapshot Tasks

### Media Dataset (default/media)

**Daily Snapshots**
- **Schedule**: Daily at 02:00
- **Retention**: 7 days
- **Naming**: `auto-%Y%m%d-%H%M`
- **Purpose**: Daily backup of media library (1.46 TB)

**Weekly Snapshots**
- **Schedule**: Sundays at 03:00
- **Retention**: 4 weeks
- **Naming**: `weekly-%Y%m%d-%H%M`
- **Purpose**: Long-term media backup

### SMB Share Dataset (default/smb-share)

**Recursive**: Yes (includes all PVCs: OpenBao, app configs)

**4-Hourly Snapshots**
- **Schedule**: Every 4 hours (00:00, 04:00, 08:00, 12:00, 16:00, 20:00)
- **Retention**: 24 hours
- **Naming**: `hourly-%Y%m%d-%H%M`
- **Purpose**: Frequent backups of critical data (OpenBao vault, application configs)

**Weekly Snapshots**
- **Schedule**: Sundays at 03:30
- **Retention**: 4 weeks
- **Naming**: `weekly-%Y%m%d-%H%M`
- **Purpose**: Long-term backup of configs and vault

## Manual Snapshot Commands

### Create Manual Snapshot

```bash
# Media dataset
ssh root@192.168.2.30 "zfs snapshot default/media@manual-$(date +%Y%m%d-%H%M)"

# SMB share (recursive)
ssh root@192.168.2.30 "zfs snapshot -r default/smb-share@manual-$(date +%Y%m%d-%H%M)"
```

### List Snapshots

```bash
# Media snapshots
ssh root@192.168.2.30 "zfs list -t snapshot -r default/media"

# SMB share snapshots (includes OpenBao)
ssh root@192.168.2.30 "zfs list -t snapshot -r default/smb-share"
```

### Restore from Snapshot

```bash
# Rollback to snapshot (DESTRUCTIVE - loses all changes after snapshot)
ssh root@192.168.2.30 "zfs rollback default/media@<SNAPSHOT_NAME>"

# Copy specific file from snapshot (safer)
ssh root@192.168.2.30 "cp /mnt/default/media/.zfs/snapshot/<SNAPSHOT_NAME>/<FILE_PATH> /mnt/default/media/<FILE_PATH>"
```

## Recreating Snapshot Tasks

If snapshot tasks are lost or need to be recreated on a new TrueNAS instance:

```bash
# Get TrueNAS API key from SOPS
TRUENAS_API_KEY=$(sops -d argo/apps/democratic-csi-nfs.sops.yaml | grep apiKey | awk '{print $2}')

# Create daily media snapshot task
curl -k -X POST "https://192.168.2.30/api/v2.0/pool/snapshottask" \
  -H "Authorization: Bearer $TRUENAS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "dataset": "default/media",
    "recursive": false,
    "lifetime_value": 7,
    "lifetime_unit": "DAY",
    "naming_schema": "auto-%Y%m%d-%H%M",
    "schedule": {
      "minute": "0",
      "hour": "2",
      "dom": "*",
      "month": "*",
      "dow": "*"
    },
    "enabled": true
  }'

# Create 4-hourly smb-share snapshot task
curl -k -X POST "https://192.168.2.30/api/v2.0/pool/snapshottask" \
  -H "Authorization: Bearer $TRUENAS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "dataset": "default/smb-share",
    "recursive": true,
    "lifetime_value": 24,
    "lifetime_unit": "HOUR",
    "naming_schema": "hourly-%Y%m%d-%H%M",
    "schedule": {
      "minute": "0",
      "hour": "*/4",
      "dom": "*",
      "month": "*",
      "dow": "*"
    },
    "enabled": true
  }'

# Create weekly media snapshot task
curl -k -X POST "https://192.168.2.30/api/v2.0/pool/snapshottask" \
  -H "Authorization: Bearer $TRUENAS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "dataset": "default/media",
    "recursive": false,
    "lifetime_value": 4,
    "lifetime_unit": "WEEK",
    "naming_schema": "weekly-%Y%m%d-%H%M",
    "schedule": {
      "minute": "0",
      "hour": "3",
      "dom": "*",
      "month": "*",
      "dow": "0"
    },
    "enabled": true
  }'

# Create weekly smb-share snapshot task
curl -k -X POST "https://192.168.2.30/api/v2.0/pool/snapshottask" \
  -H "Authorization: Bearer $TRUENAS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "dataset": "default/smb-share",
    "recursive": true,
    "lifetime_value": 4,
    "lifetime_unit": "WEEK",
    "naming_schema": "weekly-%Y%m%d-%H%M",
    "schedule": {
      "minute": "30",
      "hour": "3",
      "dom": "*",
      "month": "*",
      "dow": "0"
    },
    "enabled": true
  }'
```

## Verify Configuration

```bash
# List all snapshot tasks
curl -k "https://192.168.2.30/api/v2.0/pool/snapshottask" \
  -H "Authorization: Bearer $TRUENAS_API_KEY" | jq '.'
```

## Protected Data

Snapshot tasks protect:
- **1.46 TB media library** (movies, TV shows)
- **OpenBao vault data** (secrets, unseal keys)
- **Application configs** (Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent, Overseerr, Plex)

## Snapshot Schedule Summary

| Dataset | Frequency | Retention | Total Snapshots |
|---------|-----------|-----------|-----------------|
| default/media | Daily | 7 days | ~7 snapshots |
| default/media | Weekly | 4 weeks | ~4 snapshots |
| default/smb-share | 4-hourly | 24 hours | ~6 snapshots |
| default/smb-share | Weekly | 4 weeks | ~4 snapshots |

**Total**: ~21 snapshots maintained at any given time
