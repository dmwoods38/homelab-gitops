# etcd Monitoring

This directory contains etcd monitoring resources for Prometheus.

## What's Included

- **etcd-service.yaml**: Service and Endpoints to expose etcd metrics
- **etcd-servicemonitor.yaml**: ServiceMonitor for Prometheus to scrape etcd
- **etcd-prometheusrule.yaml**: Prometheus alerting rules for etcd health

## Alerts Configured

### Database Size
- **Warning**: Database > 2GB
- **Critical**: Database > 4GB

### Memory Usage
- **Warning**: Memory > 4GB
- **Critical**: Memory > 8GB

### Performance
- Slow fsync (> 500ms)
- Slow backend commits (> 250ms)
- High failed proposals

### Health
- No leader
- Insufficient quorum
- Database fragmentation > 50%

## Deployment

1. First, deploy kube-prometheus-stack (installs Prometheus CRDs)
2. Then deploy this monitoring app
3. Access Grafana to view etcd dashboards
4. Configure Alertmanager notifications as needed

## Viewing Metrics

Once deployed, you can:
- View etcd metrics in Grafana
- Query etcd metrics in Prometheus: `etcd_mvcc_db_total_size_in_bytes`
- Check alerts in Alertmanager

## Preventing Future Issues

These alerts will notify you when:
- etcd database grows too large (before it causes problems)
- Memory usage is excessive
- Disk performance is degraded
- Cluster health is compromised
