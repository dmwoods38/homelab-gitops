# Hardware Monitoring and Alerting

This document outlines hardware monitoring requirements and implementation tasks for the homelab cluster.

## Critical Hardware to Monitor

### 1. Storage (TrueNAS)

**What to Monitor:**
- **SMART Status**: Disk health, pending sectors, reallocated sectors
- **Disk Temperature**: Prevent overheating (critical > 60°C, warning > 50°C)
- **ZFS Pool Health**: Scrub status, pool errors, degraded vdevs
- **Disk I/O Errors**: Read/write errors, checksum errors
- **Pool Capacity**: Alert before running out of space (warning > 80%, critical > 90%)
- **Scrub Status**: Last scrub date, scrub errors

**TrueNAS Built-in Monitoring:**
- Dashboard → Reports → Disk, Network, CPU, Memory
- Storage → Disks → SMART tests (configure weekly short test, monthly long test)
- Storage → Pools → Scrub tasks (configure monthly)
- System Settings → Alert Services → Email, Slack, etc.

### 2. Kubernetes Nodes (Talos Linux)

**What to Monitor:**
- **Node Status**: Ready/NotReady, memory pressure, disk pressure
- **CPU Usage**: Per-node CPU utilization
- **Memory Usage**: Available memory, memory pressure
- **Disk Usage**: Root filesystem, ephemeral storage
- **Network I/O**: Dropped packets, errors
- **Kubelet Health**: Kubelet status, pod evictions

**Talos-Specific:**
- **etcd Health**: Cluster health, leader elections, latency
- **Kernel Messages**: `dmesg` for hardware errors
- **System Logs**: via `talosctl logs`

### 3. GPU (NVIDIA)

**What to Monitor:**
- **GPU Temperature**: Critical > 85°C, warning > 75°C
- **GPU Utilization**: Usage percentage
- **GPU Memory**: Used vs available
- **Power Draw**: Watts consumed
- **ECC Errors**: Memory errors (if supported)
- **Throttling**: Thermal or power throttling events

**Current Status:**
- GPU present on node: `talos-qtx-4mi`
- Driver version: 535.247.01
- Used by: Plex for hardware transcoding

### 4. Network Equipment

**What to Monitor:**
- **Switch/Router Status**: Uptime, link status
- **Link Errors**: CRC errors, collisions
- **Bandwidth Usage**: Per-interface traffic
- **DHCP/DNS**: Service availability

## Implementation Tasks

### Priority 1: TrueNAS SMART and ZFS Monitoring

**Goal:** Email alerts for disk failures and ZFS issues

**Tasks:**
1. [ ] Configure SMART tests on all disks
   - Short test: Weekly
   - Long test: Monthly
   - Location: Storage → Disks → SMART Tests

2. [ ] Configure ZFS scrub schedule
   - Frequency: Monthly
   - Location: Storage → Pools → Scrub Tasks

3. [ ] Configure email alerts
   - System Settings → Alert Services
   - Add email destination
   - Test alert delivery

4. [ ] Enable critical alerts:
   - Disk SMART failures
   - Pool degraded/offline
   - High disk temperature (> 55°C)
   - Pool capacity (> 80%)
   - Scrub errors

**Expected Notifications:**
- `SMART error detected on disk sdX`
- `Pool 'default' is degraded`
- `Disk sdX temperature 62°C exceeds threshold`
- `Pool 'default' is 85% full`
- `ZFS scrub completed with errors`

### Priority 2: Kubernetes Node Monitoring (Prometheus + Grafana)

**Goal:** Visualize cluster health and resource usage

**Tasks:**
1. [ ] Deploy kube-prometheus-stack
   - Includes: Prometheus, Grafana, Alertmanager
   - Monitors: Nodes, pods, containers, API server

2. [ ] Configure Prometheus node-exporter on Talos
   - Talos Extension: Already built-in
   - Expose metrics via `talosctl dashboard` or scrape

3. [ ] Create Grafana dashboards:
   - Node resource usage (CPU, memory, disk)
   - Pod resource usage per namespace
   - Persistent volume usage
   - Network I/O

4. [ ] Configure Alertmanager for email notifications:
   - Node down
   - High CPU usage (> 90% for 5 minutes)
   - High memory usage (> 90% for 5 minutes)
   - Disk space low (< 10% free)
   - Pod crash loops

**Installation:**
```bash
# Add Prometheus Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.hosts[0]=grafana.internal.sever-it.com \
  --set prometheus.ingress.enabled=true \
  --set prometheus.ingress.hosts[0]=prometheus.internal.sever-it.com
```

### Priority 3: GPU Monitoring (NVIDIA DCGM Exporter)

**Goal:** Monitor NVIDIA GPU health and utilization

**Tasks:**
1. [ ] Deploy NVIDIA DCGM Exporter
   - Exports GPU metrics to Prometheus
   - Installation: Helm chart or manifest

2. [ ] Create Grafana dashboard for GPU:
   - Temperature
   - Utilization
   - Memory usage
   - Power consumption

3. [ ] Configure alerts:
   - GPU temperature > 80°C
   - GPU memory exhausted
   - GPU throttling detected

**Installation:**
```bash
# Deploy NVIDIA DCGM Exporter
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/dcgm-exporter/main/dcgm-exporter.yaml

# Or via Helm
helm repo add gpu-helm-charts https://nvidia.github.io/dcgm-exporter/helm-charts
helm install dcgm-exporter gpu-helm-charts/dcgm-exporter --namespace monitoring
```

### Priority 4: Application-Level Monitoring

**Goal:** Monitor media stack applications

**Tasks:**
1. [ ] Configure Exportarr (Prometheus exporters for *arr apps)
   - Exports Sonarr, Radarr, Prowlarr metrics
   - Monitors: Queue size, failed downloads, disk space

2. [ ] Monitor Plex with Tautulli
   - Track: Active streams, bandwidth, user activity
   - Alerts: Transcoding failures, library scan errors

3. [ ] Monitor qBittorrent
   - Track: Active torrents, download/upload speed
   - Alerts: No active downloads (stale VPN?)

**Exportarr Installation:**
```bash
# Deploy Exportarr for Sonarr
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: exportarr-sonarr
  namespace: media
spec:
  replicas: 1
  selector:
    matchLabels:
      app: exportarr-sonarr
  template:
    metadata:
      labels:
        app: exportarr-sonarr
    spec:
      containers:
      - name: exportarr
        image: ghcr.io/onedr0p/exportarr:latest
        env:
        - name: URL
          value: "http://sonarr.media.svc.cluster.local:8989"
        - name: APIKEY
          value: "<sonarr-api-key>"  # Get from Sonarr Settings → General
        - name: PORT
          value: "9707"
        ports:
        - containerPort: 9707
EOF
```

### Priority 5: Email Notification Setup

**Goal:** Centralized email notifications for all alerts

**Tasks:**
1. [ ] Choose email provider:
   - Option 1: Gmail with app-specific password
   - Option 2: SendGrid API
   - Option 3: Mailgun API
   - Option 4: Self-hosted SMTP (Postfix)

2. [ ] Configure SMTP in TrueNAS
3. [ ] Configure Alertmanager email receiver
4. [ ] Test email delivery for all alert types

**Alertmanager Email Configuration:**
```yaml
# alertmanager-config.yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_from: 'homelab-alerts@yourdomain.com'
  smtp_auth_username: 'your-email@gmail.com'
  smtp_auth_password: '<app-specific-password>'

route:
  group_by: ['alertname', 'cluster', 'service']
  receiver: 'email-alerts'

receivers:
- name: 'email-alerts'
  email_configs:
  - to: 'your-email@gmail.com'
    headers:
      Subject: '[HOMELAB] {{ .GroupLabels.alertname }}'
```

### Priority 6: Hardware Event Monitoring (Advanced)

**Goal:** Catch hardware failures early

**Tasks:**
1. [ ] Monitor system logs for hardware errors
   - Use `talosctl logs` or centralized logging (Loki)
   - Alert on: Memory errors, disk I/O errors, PCIe errors

2. [ ] Deploy Kubernetes event exporter
   - Exports k8s events to Prometheus
   - Alert on: Node NotReady, Pod Evicted, Persistent Volume issues

3. [ ] Monitor network interface errors
   - Track: Dropped packets, CRC errors
   - Alert on: Sustained packet loss

## Alert Severity Levels

**CRITICAL** (Immediate action required):
- Disk SMART failure detected
- ZFS pool degraded or offline
- Node down or NotReady
- Out of disk space (< 5% free)
- GPU temperature > 85°C
- Plex transcoding completely failed

**WARNING** (Investigate soon):
- Disk temperature > 50°C
- Pool capacity > 80%
- High CPU/memory usage (> 90% for 10+ minutes)
- GPU temperature > 75°C
- Failed downloads in Sonarr/Radarr
- Certificate expiring in < 7 days

**INFO** (Informational):
- ZFS scrub completed successfully
- System updates available
- Backup completed
- New content added to library

## Monitoring Dashboard Overview

**Recommended Dashboard Layout:**

1. **Infrastructure Health** (Top Priority)
   - TrueNAS: Pool status, disk health, capacity
   - Kubernetes: Node status, pod count, resource usage
   - GPU: Temperature, utilization, memory

2. **Application Health**
   - Media Stack: All pods running, VPN connected
   - Download Queue: Active downloads, queue size
   - Plex: Active streams, transcode sessions

3. **Performance Metrics**
   - CPU/Memory usage per node
   - Network bandwidth
   - Disk I/O

4. **Alerts**
   - Active alerts
   - Recent alert history
   - Silenced alerts

## Quick Diagnostic Commands

**Check TrueNAS SMART Status:**
```bash
ssh root@192.168.2.30 "smartctl -a /dev/sda"
ssh root@192.168.2.30 "zpool status"
```

**Check Kubernetes Node Health:**
```bash
kubectl top nodes
kubectl describe node <node-name>
talosctl dashboard
```

**Check GPU Status:**
```bash
kubectl exec -n media -l app=plex -- nvidia-smi
```

**Check Disk Usage on NFS:**
```bash
kubectl exec -n media -l app=sonarr -- df -h /tv
kubectl exec -n media -l app=radarr -- df -h /movies
```

## Testing Alerts

After configuring monitoring, test each alert type:

```bash
# Test TrueNAS email alerts
# Go to System Settings → Alert Services → Test

# Test Prometheus/Alertmanager email
# Manually trigger an alert or use amtool
kubectl exec -n monitoring alertmanager-xxx -- amtool alert add test_alert

# Test Kubernetes events
# Create a failing pod
kubectl run test-fail --image=invalid-image --namespace media
```

## Future Enhancements

- [ ] Integrate with Uptime Kuma for external monitoring
- [ ] Set up Loki for centralized log aggregation
- [ ] Add Slack/Discord webhooks for critical alerts
- [ ] Monitor internet connectivity and speed
- [ ] Monitor power consumption (if UPS supports SNMP)
- [ ] Add PagerDuty integration for on-call alerts
- [ ] Create custom alert runbooks in Grafana

## References

- **Prometheus Best Practices:** https://prometheus.io/docs/practices/alerting/
- **TrueNAS Alerting:** https://www.truenas.com/docs/core/uireference/system/alertsettings/
- **NVIDIA DCGM:** https://github.com/NVIDIA/dcgm-exporter
- **Exportarr:** https://github.com/onedr0p/exportarr
- **Talos Monitoring:** https://www.talos.dev/latest/learn-more/monitoring/
