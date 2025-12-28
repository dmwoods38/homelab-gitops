# Agent Development Guide

This document helps AI agents (Claude Code) maintain context across sessions and provides guidelines for smooth development workflow.

**Last Updated**: 2025-12-07
**Current Session**: Completed media stack deployment with static NFS storage

---

## Current System State

### Infrastructure Status
- **Cluster**: Talos Linux v1.11.5, Kubernetes v1.34.1, single-node at 192.168.2.20
- **GitOps**: ArgoCD deployed and self-managing
- **Storage**: Static NFS PV (1Ti) for media stack (democratic-csi has compatibility issues with Talos)
- **Monitoring**: Prometheus + Grafana with etcd metrics
- **Load Balancer**: MetalLB functional with L2 mode
- **Ingress**: Traefik with cert-manager (Let's Encrypt + Cloudflare DNS)
- **Secrets**: SOPS with Age encryption throughout
- **Applications**: Media management stack (Gluetun + qBittorrent + *arr) deployed and running

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

**Status**: ✅ COMPLETED - Media Stack Fully Deployed

**What Was Accomplished**:
- ✅ Identified root cause: democratic-csi incompatible with Talos Linux minimal filesystem
  - iSCSI: Node operations use SSH/chroot expecting `/usr/bin/env` (doesn't exist on Talos)
  - NFS: TrueNAS SCALE 25.04 API schema changes broke democratic-csi dynamic provisioning
- ✅ Created workaround: Manual NFS share with static PV/PVC (1Ti volume)
- ✅ Deployed complete media stack:
  - Gluetun VPN proxy (configured with commercial VPN provider)
  - qBittorrent download client (sidecar in Gluetun pod, all traffic through VPN)
  - Prowlarr indexer manager
  - Sonarr TV show automation
  - Radarr movie automation
- ✅ Configured Traefik ingress with TLS certificates for all services
- ✅ Verified VPN routing (qBittorrent traffic routes through VPN successfully)
- ✅ Documented solution and architecture in platform/media/README.md
- ✅ All applications running and accessible via HTTPS

**Storage Solution**:
- Manual NFS share created on TrueNAS via API
- Static PV/PVC binding instead of dynamic provisioning
- All apps use subPath mounts on shared 1Ti NFS volume
- Directory structure: gluetun/, qbittorrent/, prowlarr/, sonarr/, radarr/, downloads/, tv/, movies/

**Access URLs** (all with TLS):
- qBittorrent: https://qbittorrent.internal.sever-it.com
- Prowlarr: https://prowlarr.internal.sever-it.com
- Sonarr: https://sonarr.internal.sever-it.com
- Radarr: https://radarr.internal.sever-it.com

**Next Session Recommendations**:
1. Configure applications (add indexers, connect download clients)
2. Consider Plex deployment when GPU node available
3. Monitor storage usage on NFS share
4. Future: Investigate Talos-compatible CSI drivers as alternative to democratic-csi

---

## Priority Tasks

### P0 - Critical (Do First)
None currently - system is stable

### P1 - High Priority (Deploy ASAP - Time to enjoy the cluster!)
- [x] **Gluetun VPN Proxy + *arr Media Stack** ✅ COMPLETED (2025-12-07)
  - ✅ Deployed Gluetun as VPN proxy (commercial provider)
  - ✅ Deployed qBittorrent as sidecar with Gluetun (all traffic through VPN)
  - ✅ Deployed Prowlarr for indexer management
  - ✅ Deployed Sonarr for TV shows
  - ✅ Deployed Radarr for movies
  - ✅ Storage: Static NFS PV (1Ti) with subPath mounts
  - ✅ Ingress: Traefik routes with TLS certificates
  - ⏳ Configuration: Apps need initial setup (indexers, download clients)
  - ⏳ Plex: Deploy later when GPU node available

- [ ] **One-Button Deployment Script** (Can work on alongside media stack)
  - Create `bootstrap.sh` that installs ArgoCD and deploys everything
  - Implement App of Apps pattern
  - Migrate democratic-csi to Kustomize + KSOPS
  - Goal: Fresh cluster to full deployment with one command

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

- [ ] **Plex Media Server** (Blocked on GPU node)
  - Requires: Node with GPU for transcoding
  - Node scheduling: Use taints, tolerations, node affinity
  - Storage: Large NFS PVC for media library (shared with *arr stack)
  - Ingress: Remote access configuration
  - Future: Dedicated worker node with GPU

- [ ] **OpenBao (Secrets Management)**
  - Deploy OpenBao (HashiCorp Vault fork) for secrets management
  - Consider migration path from SOPS or hybrid approach
  - Integration with applications for dynamic secrets
  - HA configuration with Raft storage on TrueNAS

### P3 - Low Priority (Nice to have)

- [ ] **Automated Security Scanning (Repo-level)**
  - GitHub Actions or similar for scanning
  - SAST (Static Application Security Testing) for manifests
  - Secret scanning (prevent accidental commits)
  - Dependency vulnerability scanning
  - IaC security scanning (checkov, tfsec, etc.)

- [ ] **Automated Version Bumping**
  - Dependabot or Renovate for Helm charts
  - Automated PRs for new versions
  - Integration with ArgoCD auto-sync policies
  - Testing strategy for automated updates

- [ ] **In-Cluster Security Services**
  - Falco for runtime security monitoring
  - Trivy operator for vulnerability scanning
  - kube-bench for CIS benchmark compliance
  - Network policies enforcement
  - Pod Security Standards/Admission
  - Consider: Tetragon for eBPF-based security observability

- [ ] External Secrets Operator (alternative to SOPS)
- [ ] Add worker nodes to cluster
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

### Why static NFS PV instead of democratic-csi for media stack?
- **Decision**: Use manual NFS share with static PV/PVC for media storage
- **Rationale**:
  - democratic-csi iSCSI driver incompatible with Talos (chroot operations expect `/usr/bin/env`)
  - democratic-csi NFS driver broken with TrueNAS SCALE 25.04 API changes
  - Static PV is simple, reliable, and works perfectly for shared media storage
  - Bypasses CSI complexity entirely
- **Tradeoffs**: Manual NFS share creation, no dynamic provisioning, but acceptable for media use case
- **Date**: 2025-12-07
- **Note**: democratic-csi still used for other storage needs when not on Talos nodes

---

## Application Stack Planning

### Media Stack Architecture (Gluetun + *arr + Plex)

**Overall Design**:
```
Internet → Gluetun VPN → Download Client → Storage (NFS)
                       ↓
                   *arr Apps (manage downloads)
                       ↓
                Media Library (NFS PVC)
                       ↓
                 Plex (serve media)
```

**Gluetun VPN Proxy**:
- Purpose: Route torrent traffic through VPN
- Deployment: Single pod or sidecar pattern
- Configuration: VPN provider credentials (SOPS encrypted)
- Network: Pod with VPN connection, other containers connect through it
- Considerations: Kill switch, DNS leak protection, port forwarding

***arr Stack**:
- **Sonarr**: TV show management
- **Radarr**: Movie management
- **Prowlarr**: Indexer management (central for all *arr apps)
- **Bazarr**: Subtitles management (optional)
- Storage: Small PVCs for config, large shared NFS for media
- Networking: Access download client through Gluetun
- Ingress: Traefik with authentication (basic auth or OAuth)

**Download Client** (qBittorrent/Transmission):
- Must run in same network namespace as Gluetun
- Storage: Downloads directory on NFS (shared with *arr apps)
- Configuration: Watch directories for *arr apps

**Plex**:
- Storage: Read-only access to media library NFS
- Transcoding: Requires GPU (Intel QuickSync or NVIDIA)
- Node Scheduling:
  ```yaml
  nodeSelector:
    gpu: "true"
  tolerations:
  - key: "gpu"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
  ```
- Ingress: Remote access (plex.tv or custom domain)
- Consider: Hardware detection, device permissions

**Storage Layout**:
```
NFS PVC: media-library (e.g., 5TB)
├── movies/
├── tv/
├── downloads/
│   ├── complete/
│   └── incomplete/
└── ...

Each *arr app: Small PVC for config (1-5GB)
```

**Deployment Order**:
1. Create NFS PVCs (media-library, download configs)
2. Deploy Gluetun (verify VPN connection)
3. Deploy download client (verify through Gluetun)
4. Deploy Prowlarr (configure indexers)
5. Deploy Sonarr/Radarr (configure Prowlarr + download client)
6. Deploy Plex (later, when GPU node available)

### OpenBao (Secrets Management)

**Purpose**: Alternative/complement to SOPS for runtime secrets

**Architecture Considerations**:
- **Storage**: Raft integrated storage on TrueNAS iSCSI PVC
- **HA**: 3-pod deployment for quorum (future, when multi-node)
- **Unsealing**: Auto-unseal vs manual (security tradeoff)
- **Integration**:
  - External Secrets Operator to sync secrets to K8s
  - Direct API access for applications
  - Injector sidecars for pod-level secrets

**Migration Strategy**:
- Phase 1: Deploy OpenBao alongside SOPS
- Phase 2: Migrate application secrets (database passwords, API keys)
- Phase 3: Keep SOPS for infrastructure secrets (Age keys, certificates)
- Hybrid approach: SOPS for GitOps, OpenBao for dynamic secrets

**Secret Types**:
- Database credentials (dynamic, short-lived)
- API tokens (rotated regularly)
- Certificates (manage PKI)
- Encryption keys

### Security Services Stack

**Falco (Runtime Security)**:
- Detects anomalous behavior (unexpected syscalls, file access, etc.)
- Rules for container best practices
- Integration with Prometheus/AlertManager
- Consider: eBPF vs kernel module driver

**Trivy Operator**:
- Automated vulnerability scanning of:
  - Container images
  - Kubernetes manifests
  - IaC configurations
- CRDs: VulnerabilityReport, ConfigAuditReport
- Integration: View in Grafana dashboards

**kube-bench**:
- CIS Kubernetes Benchmark compliance
- Run as CronJob (daily/weekly)
- Reports stored in logs or exported to monitoring

**Network Policies**:
- Start with audit mode (log, don't enforce)
- Default deny all, explicitly allow needed traffic
- Separate namespaces for different trust levels
- Consider: Cilium for advanced networking (future)

**Pod Security**:
- Pod Security Standards: Restricted profile
- Pod Security Admission: Enforce at namespace level
- Audit existing workloads before enforcement

### Repository Security Automation

**GitHub Actions Workflows**:

**SAST (Static Analysis)**:
- Tools: kubesec, kube-score, checkov
- Run on: Pull requests, scheduled
- Fail on: High/critical issues

**Secret Scanning**:
- Tools: gitleaks, truffleHog
- Pre-commit hooks (local)
- CI checks (GitHub Actions)
- Block commits with secrets

**Dependency Scanning**:
- Renovate or Dependabot for:
  - Helm chart versions
  - Container image tags
  - GitHub Actions versions
- Auto-merge: Patch versions (with tests)
- Manual review: Minor/major versions

**Version Bumping Strategy**:
- Renovate dashboard for visibility
- Group updates: Same application, same PR
- Testing: ArgoCD preview/staging namespace
- Rollback: Git revert, ArgoCD sync

**Example Workflow**:
```yaml
name: Security Scan
on: [pull_request, push]
jobs:
  scan:
    - name: Run kubesec
    - name: Run gitleaks
    - name: Run checkov
    - name: Trivy IaC scan
```

---

## Development Patterns & Guidelines

### ⚠️ CRITICAL: Never Make Destructive System Changes Without Verification ⚠️

**MANDATORY RULES** - These prevent catastrophic cluster failures:

1. **NEVER modify containerd/CRI runtime configs without verifying binaries exist first**
   - ❌ BAD: Adding `BinaryName: "/usr/bin/nvidia-container-runtime"` without checking file exists
   - ✅ GOOD: `talosctl -n 192.168.2.20 ls /usr/bin/nvidia-container-runtime` FIRST
   - **Why**: Broken containerd config = node can't boot, total cluster failure

2. **NEVER run `talosctl reset` or destructive commands without EXPLICIT user approval**
   - ❌ BAD: Running `talosctl reset` to "fix" a problem
   - ✅ GOOD: Ask user "Reset will WIPE ALL DATA including etcd. Confirm Y/N?"
   - **Why**: Reset wipes disk partitions, destroys cluster completely

3. **NEVER patch machine configs without understanding the impact**
   - ❌ BAD: Patching system configs based on assumptions
   - ✅ GOOD: Read Talos docs, verify approach, ask user before applying
   - **Why**: Bad machine config can brick the node, require reinstall

4. **NEVER assume a problem exists without testing first**
   - ❌ BAD: "GPU not working" → immediately try to fix
   - ✅ GOOD: Test GPU is actually broken first: `kubectl exec pod -- nvidia-smi`
   - **Why**: "Fixing" working systems breaks them

5. **ALWAYS verify backups exist before risky operations**
   - ❌ BAD: Proceeding with destructive changes without checking backups
   - ✅ GOOD: `talosctl -n 192.168.2.20 ls /var/lib/etcd-snapshots` to verify backups exist
   - **Why**: No backups + destructive change = unrecoverable data loss

6. **STOP and rollback after first mistake - don't compound errors**
   - ❌ BAD: Config breaks containerd → try 5 different "fixes" → wipe cluster
   - ✅ GOOD: Config breaks containerd → immediately revert config → node recovers
   - **Why**: Panic-driven debugging makes things exponentially worse

7. **ASK before any operation that could cause downtime**
   - Operations requiring approval: `talosctl reset`, `talosctl upgrade`, machine config changes, etcd operations
   - ✅ GOOD: "This requires a reboot and will cause ~5min downtime. Proceed?"
   - **Why**: User needs to know about service interruptions

8. **NEVER delete namespaces, PVCs, or storage without explicit confirmation**
   - ❌ BAD: `kubectl delete namespace media` to "clean up"
   - ❌ BAD: `kubectl delete pvc` without asking about data backup
   - ✅ GOOD: "This PVC contains data. Have you backed it up? Confirm deletion Y/N?"
   - **Why**: Data loss is unrecoverable

9. **NEVER modify network configs (MetalLB, Traefik, DNS) without testing first**
   - ❌ BAD: Changing MetalLB IP pool that could conflict with DHCP
   - ❌ BAD: Modifying Traefik entrypoints without understanding impact
   - ✅ GOOD: Test config in staging, ask user about network layout
   - **Why**: Network issues can lock user out of entire cluster

10. **NEVER perform etcd operations (snapshot, restore, defrag) during active use**
    - ❌ BAD: Running `etcd defrag` while cluster is under load
    - ❌ BAD: Restoring etcd snapshot without confirming current state is bad
    - ✅ GOOD: "Defrag will briefly pause etcd. Is now a good time?"
    - **Why**: etcd operations can cause cluster-wide outages

11. **NEVER upgrade Kubernetes or Talos without version compatibility verification**
    - ❌ BAD: Upgrading Talos 1.8 → 2.0 without checking breaking changes
    - ❌ BAD: Upgrading K8s 1.30 → 1.31 without checking workload compatibility
    - ✅ GOOD: Check upgrade docs, ask user about maintenance window
    - **Why**: Incompatible upgrades can brick the cluster

12. **NEVER delete or modify SOPS encryption keys**
    - ❌ BAD: Modifying `.sops.yaml` age keys
    - ❌ BAD: Deleting `~/.config/sops/age/keys.txt`
    - ✅ GOOD: Never touch encryption keys unless explicitly asked
    - **Why**: Losing keys = all encrypted secrets become unrecoverable

13. **NEVER force push to git or delete branches without confirmation**
    - ❌ BAD: `git push --force` to fix a mistake
    - ❌ BAD: `git branch -D` to clean up old branches
    - ✅ GOOD: Use `git revert` for mistakes, ask before deleting branches
    - **Why**: Force push can lose work, deleted branches can't be recovered

14. **NEVER modify TrueNAS storage (datasets, shares, zvols) via API without confirmation**
    - ❌ BAD: Deleting NFS shares that workloads depend on
    - ❌ BAD: Modifying ZFS dataset properties without understanding impact
    - ✅ GOOD: Ask "This will modify storage config. Have workloads been drained?"
    - **Why**: Storage changes can cause data loss or corruption

15. **NEVER revoke or delete TLS certificates in production**
    - ❌ BAD: Deleting cert-manager Certificate resources
    - ❌ BAD: Revoking Let's Encrypt certs without replacement ready
    - ✅ GOOD: Always have new cert before removing old one
    - **Why**: Breaks HTTPS access to all services immediately

16. **If something is working, DO NOT "fix" it without confirming it's actually broken**
    - ❌ BAD: "Subtitles not working well" → assume GPU broken → destroy cluster
    - ✅ GOOD: "Let me test if GPU transcoding is actually working first"
    - **Why**: Making assumptions destroys working systems

17. **NEVER delete backups (etcd snapshots, database dumps, config backups)**
    - ❌ BAD: Deleting old etcd snapshots to "free up space"
    - ❌ BAD: Removing backup CronJobs because "they're taking up resources"
    - ✅ GOOD: Backups are sacred - never delete without explicit user request
    - **Why**: Backups are the only disaster recovery option

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
6. **Verify binaries/files exist** before referencing them in configs
7. **Ask user for approval** before any destructive or risky operations

### ⚠️ CRITICAL: Never Commit Secrets or Credentials ⚠️

**MANDATORY RULES** - Violation requires immediate credential rotation:

1. **NEVER include actual credentials in documentation**
   - ❌ BAD: `root_token: s.wh72MLXFxoN69Qmsvfca3TKm`
   - ✅ GOOD: `root_token: <ROOT_TOKEN_FROM_BACKUP>`
   - ❌ BAD: `API_KEY: 2-w9S8Dlb6lowTJL8mQCI...`
   - ✅ GOOD: `API_KEY: <TRUENAS_API_KEY>`

2. **ALWAYS use placeholders in examples**
   - Wrap placeholders in angle brackets: `<PLACEHOLDER>`
   - Be specific: `<OPENBAO_ROOT_TOKEN>` not just `<TOKEN>`
   - Add context: `<UNSEAL_KEY_1>`, `<UNSEAL_KEY_2>`, etc.

3. **Pre-commit verification checklist**:
   ```bash
   # Before committing ANY documentation or config:
   git diff                    # Review all changes
   git diff | grep -i token    # Search for "token"
   git diff | grep -i key      # Search for "key"
   git diff | grep -i password # Search for "password"
   git diff | grep -i secret   # Search for "secret"
   git diff | grep -E "[0-9a-zA-Z]{20,}" # Look for long strings
   ```

4. **Examples that REQUIRE placeholders**:
   - OpenBao unseal keys, root tokens, auth tokens
   - TrueNAS API keys, SSH keys
   - Database passwords, API credentials
   - VPN credentials, auth tokens
   - Any value from `~/openbao-keys.yaml`, `~/.ssh/`, or SOPS files

5. **If you accidentally commit a secret**:
   - STOP immediately, do NOT push
   - If already pushed: `git revert` immediately
   - Rotate ALL exposed credentials (tokens, keys, passwords)
   - Document incident in `SECURITY-INCIDENT-YYYY-MM-DD.md`
   - Update this file with lessons learned

6. **Safe documentation practices**:
   - Show command syntax with placeholders
   - Reference where to find actual values: "Get token from ~/openbao-keys.yaml"
   - Use environment variables in examples: `bao login $ROOT_TOKEN`
   - Never copy-paste from actual systems into documentation

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

### Session 5: Media Stack Deployment (Dec 7, 2025)
**Task**: Deploy Gluetun + qBittorrent + *arr media management stack
**Problem**: democratic-csi incompatible with Talos Linux
  - iSCSI: SSH/chroot node operations expect `/usr/bin/env` (doesn't exist on Talos)
  - NFS: TrueNAS SCALE 25.04 API schema changes broke dynamic provisioning
**Solution**: Bypassed CSI entirely with manual NFS share and static PV/PVC
  - Created NFS share via TrueNAS API
  - Static PV (1Ti) with PVC binding
  - All apps use subPath mounts on shared volume
  - Deployed Gluetun with qBittorrent sidecar (VPN routing verified)
  - Deployed Prowlarr, Sonarr, Radarr with Traefik ingress + TLS
**Key Learning**: Sometimes the simple solution (static PV) is better than fighting with complex dynamic provisioning

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
