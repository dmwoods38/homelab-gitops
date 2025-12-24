# Talos Linux Configuration

This directory contains Talos Linux machine configurations, patches, and Kubernetes manifests for the homelab cluster.

## Directory Structure

```
talos/
├── machine-configs/     # SOPS-encrypted machine configurations
│   ├── controlplane1.sops.yaml
│   └── worker.sops.yaml
├── patches/             # Machine configuration patches
│   ├── installer-patch.yaml
│   ├── gpu-patch.yaml
│   ├── remove-lb-exclusion-label.yaml
│   └── networking-README.md
└── manifests/           # Kubernetes manifests for Talos-specific resources
    └── nvidia-runtimeclass.yaml
```

## Machine Configurations

The machine configuration files in `machine-configs/` are **fully encrypted with SOPS** using Age encryption. They contain sensitive information including:

- Machine tokens and certificates
- Cluster CA keys
- Service account keys
- etcd certificates
- API server certificates

### Viewing Machine Configs

To view or edit an encrypted machine config:

```bash
# View decrypted content
sops -d talos/machine-configs/controlplane1.sops.yaml

# Edit encrypted file (will decrypt, open editor, then re-encrypt)
sops talos/machine-configs/controlplane1.sops.yaml
```

### Applying Machine Configs

To apply a machine configuration to a node:

```bash
# Decrypt and apply to a node
sops -d talos/machine-configs/controlplane1.sops.yaml | \
  talosctl apply-config -n 192.168.2.20 --file -
```

## Patches

### installer-patch.yaml

Custom Talos installer image that includes:
- NVIDIA drivers (non-free)
- Container toolkit
- iSCSI initiator tools

Apply during initial installation or upgrades:

```bash
talosctl gen config my-cluster https://controlplane:6443 \
  --config-patch @talos/patches/installer-patch.yaml
```

### gpu-patch.yaml

Kernel modules and sysctls for NVIDIA GPU support:
- nvidia
- nvidia_uvm
- nvidia_drm
- nvidia_modeset

Apply to nodes with GPUs:

```bash
talosctl patch machineconfig -n <NODE_IP> -p @talos/patches/gpu-patch.yaml
```

### remove-lb-exclusion-label.yaml

Removes the `node.kubernetes.io/exclude-from-external-load-balancers` label from control-plane nodes. This is required for single-node clusters or when control-plane nodes need to announce MetalLB LoadBalancer IPs in L2 mode.

See `patches/networking-README.md` for detailed troubleshooting and application instructions.

Apply to control-plane nodes:

```bash
talosctl patch machineconfig -n <NODE_IP> -p @talos/patches/remove-lb-exclusion-label.yaml
```

### etcd-optimization.yaml

Optimizes etcd performance and prevents database bloat:
- Enables automatic compaction every 5 minutes
- Increases quota to 4GB (from default 2GB)
- Prevents etcd corruption and degradation over time

Apply to control-plane nodes:

```bash
talosctl patch machineconfig -n <NODE_IP> -p @talos/patches/etcd-optimization.yaml
```

**Note:** etcd will apply these settings on next restart. A weekly defragmentation CronJob is also deployed in `platform/kube-system/etcd-defrag-cronjob.yaml` for additional maintenance.

## Manifests

### nvidia-runtimeclass.yaml

Kubernetes RuntimeClass for NVIDIA GPU workloads. Deploy this after applying the GPU patch to nodes:

```bash
kubectl apply -f talos/manifests/nvidia-runtimeclass.yaml
```

Then reference it in pods that need GPU access:

```yaml
spec:
  runtimeClassName: nvidia
  containers:
  - name: gpu-app
    image: nvidia/cuda:latest
```

## Talos Cluster Information

**Cluster Name:** sever-it01
**Control Plane Endpoint:** https://192.168.2.20:6443
**Talos Version:** v1.11.5
**Kubernetes Version:** v1.34.1

**Node:** talos-qtx-4mi (192.168.2.20)
- Role: Control Plane + Worker (allowSchedulingOnControlPlanes: true)
- Install Disk: /dev/nvme0n1
- Features: KubePrism enabled (port 7445), hostDNS enabled

## Encryption

Machine configurations are encrypted using SOPS with Age encryption. The encryption configuration is defined in `.sops.yaml` at the repository root:

```yaml
creation_rules:
  # Talos machine configs - encrypt the entire file
  - path_regex: 'talos/machine-configs/.*\.sops\.yaml$'
    age:
      - "age1033ld5gtn23xsz9lateded3kpssp62hkhjq9vs3jza3ad63uggnsqw5xhd"
```

**Important:** Keep your Age private key safe! It's required to decrypt these configurations. The private key should be stored securely and never committed to the repository.

## Common Operations

### Generate New Machine Config

To generate a new machine config (e.g., for adding a worker node):

```bash
# Generate config
talosctl gen config sever-it01 https://192.168.2.20:6443 \
  --output-types worker \
  --output worker.yaml \
  --config-patch @talos/patches/installer-patch.yaml

# Encrypt it
sops -e worker.yaml > talos/machine-configs/worker-new.sops.yaml
rm worker.yaml
```

### Update Talos Version

To upgrade Talos:

```bash
# Check current version
talosctl version -n 192.168.2.20

# Upgrade (example to v1.11.6)
talosctl upgrade -n 192.168.2.20 \
  --image factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.6
```

### Apply Patches Without Rebooting

Most patches can be applied without a reboot:

```bash
talosctl patch machineconfig -n 192.168.2.20 \
  -p @talos/patches/gpu-patch.yaml
```

Check if reboot is required:

```bash
talosctl get machineconfig -n 192.168.2.20
```

## Security Notes

- **Never commit `talosconfig`** - This file contains admin credentials for the cluster
- **Machine configs contain secrets** - Always encrypt before committing
- **Rotate secrets regularly** - Consider regenerating tokens and certificates periodically
- **Backup your Age key** - Without it, you cannot decrypt your machine configs

## References

- [Talos Documentation](https://www.talos.dev/)
- [Talos Factory](https://factory.talos.dev/) - Custom installer images
- [SOPS Documentation](https://github.com/getsops/sops)
- [Age Encryption](https://github.com/FiloSottile/age)
