# Agent Development Guide

This document helps AI agents (Claude Code) maintain context across sessions and provides guidelines for smooth development workflow.

**Last Updated**: 2025-12-06
**Current Session**: Completed democratic-csi setup and comprehensive documentation

---

## Current System State

### Infrastructure Status
- **Cluster**: Talos Linux v1.11.5, Kubernetes v1.34.1, single-node at 192.168.2.20
- **GitOps**: ArgoCD deployed and self-managing
- **Storage**: democratic-csi (iSCSI + NFS) working with TrueNAS SCALE 25.04.2.1
- **Monitoring**: Prometheus + Grafana with etcd metrics
- **Load Balancer**: MetalLB functional with L2 mode
- **Ingress**: Traefik with cert-manager (Let's Encrypt + Cloudflare DNS)
- **Secrets**: SOPS with Age encryption throughout

### Services Requiring Manual Steps
Due to SOPS encryption in Application manifests:
- **democratic-csi-iscsi**: `sops -d argo/apps/democratic-csi-iscsi.sops.yaml > /tmp/democratic-csi-iscsi.yaml && kubectl apply -f /tmp/democratic-csi-iscsi.yaml`
- **democratic-csi-nfs**: `sops -d argo/apps/democratic-csi-nfs.sops.yaml > /tmp/democratic-csi-nfs.yaml && kubectl apply -f /tmp/democratic-csi-nfs.yaml`
- **cert-manager secrets**: `sops -d platform/cert-manager/secret-cloudflare-api-token.sops.yaml | kubectl apply -f -`

### What's Working
- ✅ Talos cluster stable and healthy
- ✅ etcd monitoring and defragmentation procedures
- ✅ Storage provisioning (iSCSI block + NFS shared)
- ✅ All platform services deployed
- ✅ TLS certificates automated
- ✅ SOPS encryption for all secrets

### Known Issues
1. **ArgoCD SOPS Limitation**: KSOPS plugin only works with Kustomize, not Application manifests
2. **Manual Deployment Steps**: democratic-csi requires kubectl apply after SOPS decryption
3. **No App of Apps**: Applications not organized with dependency management

---

## Current Session Focus

**Status**: ✅ COMPLETED - Ready for next session

**What Was Done**:
- Fixed democratic-csi by switching from API to SSH-based drivers
- Configured SSH access to TrueNAS with passphrase-less key
- Created proper ZFS datasets for storage provisioning
- SOPS-encrypted all credentials (SSH keys, API keys)
- Tested and verified iSCSI + NFS provisioning
- Created comprehensive README with full setup documentation
- Updated Future Improvements with one-button deployment goal

**Next Session Should**:
- Check current state: `kubectl get pods -A` to verify all services healthy
- Review this AGENTS.md for context
- Look at Priority Tasks below
- Update "Current Session Focus" section with new work

---

## Priority Tasks

### P0 - Critical (Do First)
None currently - system is stable

### P1 - High Priority (Near-term goals)
- [ ] **One-Button Deployment Script**
  - Create `bootstrap.sh` that installs ArgoCD and deploys everything
  - Implement App of Apps pattern
  - Migrate democratic-csi to Kustomize + KSOPS
  - Goal: Fresh cluster to full deployment with one command

- [ ] **ArgoCD Full Self-Management**
  - ArgoCD should manage itself from initial deployment
  - No manual Application.yaml applies after bootstrap
  - All SOPS decryption automated via KSOPS

### P2 - Medium Priority (Important improvements)
- [ ] **etcd Automated Backups**
  - Schedule regular snapshots to TrueNAS
  - Retention policy (keep 7 daily, 4 weekly, 12 monthly)
  - Test restore procedure

- [ ] **Monitoring Improvements**
  - Configure Prometheus AlertManager
  - Set up notifications (email/Slack/Discord)
  - Alert on etcd database size > 2GB
  - Alert on certificate expiration < 30 days

- [ ] **Persistent Storage for Grafana**
  - Use democratic-csi PVC for dashboards
  - Backup dashboard JSON to git

### P3 - Low Priority (Nice to have)
- [ ] External Secrets Operator (alternative to SOPS)
- [ ] Add worker nodes to cluster
- [ ] Application deployment (databases, services, etc.)
- [ ] Disaster recovery runbook with procedures

---

## Technical Decisions Log

### Why SSH-based democratic-csi drivers instead of API?
- **Decision**: Use `freenas-iscsi` and `freenas-nfs` (SSH) instead of `freenas-api-iscsi` and `freenas-api-nfs`
- **Rationale**:
  - API drivers are marked "experimental" in democratic-csi docs
  - API drivers failed to detect TrueNAS SCALE 25.04.2.1 correctly
  - SSH drivers are stable and mature
  - Hybrid SSH+HTTP configuration works well (SSH for ZFS, HTTP for API operations)
- **Tradeoffs**: Requires SSH key management, but worth it for stability
- **Date**: 2025-12-06

### Why SOPS with Age instead of other secret solutions?
- **Decision**: Use SOPS with Age encryption for all secrets
- **Rationale**:
  - Age is simple, modern encryption (vs GPG complexity)
  - SOPS integrates with git workflows naturally
  - Can encrypt specific fields or entire files
  - Works with ArgoCD via KSOPS (for Kustomize resources)
- **Tradeoffs**: Manual kubectl apply needed for Application manifests, but fixable with Kustomize migration
- **Date**: Prior to these sessions

### Why single-node cluster?
- **Decision**: Run Talos as single-node with control-plane + workloads
- **Rationale**:
  - Homelab resource constraints
  - Simpler management
  - Still production-grade OS (Talos)
- **Tradeoffs**: No HA, but acceptable for homelab
- **Required Fixes**: Remove MetalLB exclusion label (see talos/patches/remove-lb-exclusion-label.yaml)
- **Date**: Initial cluster setup

### Why Talos Linux over other distributions?
- **Decision**: Use Talos Linux instead of kubeadm/k3s/etc
- **Rationale**:
  - Immutable, minimal attack surface
  - API-driven configuration (no SSH into nodes)
  - Designed for Kubernetes (no general-purpose OS overhead)
  - Excellent upgrade story
- **Tradeoffs**: Learning curve, different debugging approach
- **Date**: Initial cluster setup

---

## Development Patterns & Guidelines

### Before Starting Any Work
1. **Read this file first** - Get context on current state and priorities
2. **Check cluster health**: `kubectl get nodes && kubectl get pods -A`
3. **Review recent commits**: `git log --oneline -10` to understand what changed
4. **Update "Current Session Focus"** with what you're working on

### When Making Changes
1. **Test in /tmp first** - Don't apply directly to cluster without testing
2. **SOPS encrypt before committing** - Never commit unencrypted secrets
3. **Verify encryption worked**: `grep -i "enc\[" <file>` should show encrypted data
4. **Document decisions** - Add to Technical Decisions Log for non-obvious choices
5. **Update README** if user-facing procedures change

### Before Running Out of Credits
**CRITICAL**: If you notice you're approaching token limits:
1. **Update "Current Session Focus"** with current state and next steps
2. **Commit any work in progress** with clear commit message about state
3. **Note in this file** what was partially completed
4. **List next immediate steps** for resume

### Git Commit Guidelines
- Use descriptive commit messages with context
- Include "why" not just "what" in extended descriptions
- Always add co-author: `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`
- For major changes, include Claude Code attribution

### SOPS Usage Patterns
```bash
# Decrypt for viewing
sops -d path/to/file.sops.yaml

# Decrypt for applying
sops -d path/to/file.sops.yaml > /tmp/file.yaml
kubectl apply -f /tmp/file.yaml

# Encrypt new file
sops -e -i path/to/file.sops.yaml

# Edit encrypted file
sops path/to/file.sops.yaml
```

### Common Workflows

#### Deploying democratic-csi (current manual process)
```bash
# iSCSI
sops -d argo/apps/democratic-csi-iscsi.sops.yaml > /tmp/democratic-csi-iscsi.yaml
kubectl apply -f /tmp/democratic-csi-iscsi.yaml

# NFS
sops -d argo/apps/democratic-csi-nfs.sops.yaml > /tmp/democratic-csi-nfs.yaml
kubectl apply -f /tmp/democratic-csi-nfs.yaml

# Verify
kubectl get pods -n democratic-csi
# Should show 6/6 Ready for both controllers
```

#### Checking etcd Health
```bash
# View metrics in Grafana
kubectl port-forward -n monitoring svc/grafana 3000:80
# Open http://localhost:3000 -> etcd dashboard

# Check database size
talosctl -n 192.168.2.20 etcd status

# Defragment if needed (database > 2GB)
talosctl -n 192.168.2.20 etcd defragment
```

#### Testing Storage Provisioning
```bash
# Create test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-storage
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: truenas-iscsi  # or truenas-nfs
  resources:
    requests:
      storage: 1Gi
EOF

# Verify
kubectl get pvc test-storage
# Should show "Bound"

# Cleanup
kubectl delete pvc test-storage
```

---

## Agent Resume Instructions

### When Resuming a Session

1. **Read "Current Session Focus"** section above
2. **Check git status**: `git status` and `git log --oneline -5`
3. **Verify cluster health**: `kubectl get nodes && kubectl get pods -A`
4. **Look for any failing pods**: `kubectl get pods -A | grep -v Running | grep -v Completed`
5. **Ask user**: "What would you like to work on?" or continue from "Current Session Focus"

### Critical Things to Check Before Changes

- **Never commit unencrypted secrets** - Always verify with `git diff` before committing
- **Don't modify Talos configs** without understanding full context (see talos/README.md)
- **Check ArgoCD sync status** before manual kubectl apply: `kubectl get applications -n argocd`
- **Test SOPS decryption** works before assuming file is correct: `sops -d <file>`

### Common Pitfalls to Avoid

1. **Don't use API drivers for democratic-csi** - Always use SSH-based (`freenas-iscsi`, `freenas-nfs`)
2. **Don't forget ZFS CLI paths** - TrueNAS SCALE uses `/usr/sbin/zfs` not `/usr/local/sbin/zfs`
3. **Don't use zvols as dataset parents** - Must be filesystems (check with `zfs get type <dataset>`)
4. **Don't apply SOPS files directly** - Always decrypt first
5. **Don't assume ArgoCD can decrypt Application manifests** - It can't; need Kustomize + KSOPS

### When You're Stuck

1. **Check the README** - Comprehensive troubleshooting section
2. **Check recent git commits** - Solution might be in commit messages
3. **Check logs**: `kubectl logs -n <namespace> <pod> --tail=50`
4. **Check this file** - Look in Technical Decisions for context
5. **Ask user** - Don't spin wheels, get clarification

---

## Session History Summary

### Session 1: etcd Crisis (Dec 4-5, 2025)
**Problem**: 12GB etcd database, cluster degraded
**Solution**: Emergency defragmentation, Prometheus monitoring, Grafana dashboards
**Key Learning**: Monitor `etcd_mvcc_db_total_size_in_bytes`, defrag at 2-3GB

### Session 2: democratic-csi Setup (Dec 5-6, 2025)
**Problem**: democratic-csi failing with SCALE detection errors
**Root Causes**:
- Experimental API drivers don't detect SCALE properly
- Wrong ZFS paths (FreeBSD vs Linux)
- Invalid parent dataset (zvol instead of filesystem)
**Solution**: SSH-based drivers, proper ZFS configuration, created filesystem datasets
**Key Learning**: Stable beats experimental; always verify dataset types

### Session 3: Talos Integration (Dec 6, 2025)
**Task**: Merge Talos configs into main repo
**Solution**: Created talos/ directory, encrypted configs, updated SOPS rules
**Key Learning**: Separation of full-file vs field-level encryption

### Session 4: Documentation (Dec 6, 2025)
**Task**: Comprehensive README and this AGENTS.md
**Solution**: 570-line README, complete troubleshooting, this agent guide
**Key Learning**: Document everything while context is fresh

---

## Quick Reference

### Key File Locations
- **Talos configs**: `talos/machine-configs/*.sops.yaml` (encrypted)
- **ArgoCD apps**: `argo/apps/*.yaml` (some SOPS encrypted)
- **Platform services**: `platform/*/`
- **SOPS config**: `.sops.yaml`
- **Age key**: `~/.config/sops/age/keys.txt` (never commit!)
- **TrueNAS SSH key**: `~/.ssh/truenas_csi` (never commit!)

### Important IPs & Hostnames
- **Talos node**: 192.168.2.20 (sever-it01)
- **Kubernetes API**: 192.168.2.20:6443
- **TrueNAS**: 192.168.2.30
- **MetalLB pool**: 192.168.2.100-192.168.2.110

### Storage Datasets on TrueNAS
- **iSCSI**: `default/k8s-pv/iscsi` (parent for zvols)
- **iSCSI snapshots**: `default/k8s-pv/iscsi-snapshots`
- **NFS**: `default/smb-share` (shared storage)
- **Old/unused**: `default/k8s-pv/talos-iscsi-share` (zvol - don't use)

### Key Metrics to Monitor
- `etcd_mvcc_db_total_size_in_bytes` - etcd database size (alert > 2GB)
- `etcd_server_has_leader` - etcd leader status
- `up{job="kube-etcd"}` - etcd endpoint health

---

## Notes for Future Sessions

### When Implementing One-Button Deployment
- Study cert-manager pattern for Kustomize + KSOPS (it works correctly)
- Create `platform/democratic-csi/` with:
  - `kustomization.yaml`
  - `ksops-secret-generator.yaml` (for SSH key and API key)
  - `democratic-csi-iscsi.yaml` (non-encrypted values)
  - `democratic-csi-nfs.yaml` (non-encrypted values)
- Update Application manifests to reference Kustomize resources
- Test thoroughly before removing old pattern

### When Adding AlertManager
- Use PVC for alert state persistence
- Configure routes for different severity levels
- Start with email, add webhook integrations later
- Alert on: etcd size, cert expiration, pod crashes, node issues

### When Scaling to Multi-Node
- Worker configs already exist: `talos/machine-configs/worker.sops.yaml`
- Remove single-node assumptions (MetalLB label removal)
- Consider pod topology spread constraints
- Update democratic-csi for multi-attach if needed

---

**Remember**: This file is your context. Update it at major milestones and before running out of credits. Your future self (or next session) will thank you!
