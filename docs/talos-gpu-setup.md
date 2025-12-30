# Talos NVIDIA GPU Setup Guide

**Last Updated:** 2025-12-29
**Status:** ✅ Working on node .20 (192.168.2.20)

## ⚠️ CRITICAL: Kernel Modules Required

**If you skip Step 1.1, the node will be stuck in "booting" stage forever!**

The NVIDIA kernel modules patch is **mandatory** for the nvidia driver to load. Without it:
- ext-nvidia-persistenced service waits forever for `/sys/bus/pci/drivers/nvidia`
- Node shows `STAGE=booting` even though `READY=true`
- Kubernetes shows node as Ready but Talos never reaches "running" state

Always apply the kernel modules patch BEFORE or immediately AFTER applying NVIDIA factory image.

## Prerequisites
- Talos cluster running v1.11.5
- NVIDIA GPU installed in node (currently only .20 has GPU)
- Access to talosctl and kubectl

## Step 1: Update Machine Config with NVIDIA Support

The machine config needs three key additions:

### 1.1 Kernel Modules (CRITICAL - REQUIRED)
```yaml
machine:
  kernel:
    modules:
      - name: nvidia
      - name: nvidia_uvm
      - name: nvidia_drm
      - name: nvidia_modeset
  sysctls:
    net.core.bpf_jit_harden: 1  # CRITICAL: Required for nvidia-container-runtime BPF device filtering
```

**⚠️ The sysctl `net.core.bpf_jit_harden: 1` is MANDATORY** - without it, nvidia-container-runtime's BPF device filtering will fail with "load program: invalid argument" errors and no containers using the nvidia runtime will start.

### 1.2 Factory Image with NVIDIA Extensions
```yaml
machine:
  install:
    image: factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.5
```

This schematic includes:
- `nonfree-kmod-nvidia-lts` (535.247.01)
- `nvidia-container-toolkit-lts` (535.247.01)
- `iscsi-tools`

### 1.3 Containerd NVIDIA Runtime Configuration
```yaml
machine:
  files:
    - path: /etc/cri/conf.d/20-customization.part
      op: create
      content: |
        [plugins]
          [plugins."io.containerd.grpc.v1.cri"]
            [plugins."io.containerd.grpc.v1.cri".containerd]
              [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
                  privileged_without_host_devices = false
                  runtime_engine = ""
                  runtime_root = ""
                  runtime_type = "io.containerd.runc.v2"
                  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
                    BinaryName = "/usr/bin/nvidia-container-runtime"
```

**Note:** The nvidia-container-toolkit extension automatically creates `/etc/cri/conf.d/10-nvidia-container-runtime.part` with the correct runtime config, but adding the custom file ensures it's explicitly configured.

## Step 2: Apply Configuration and Upgrade

### 2.1 Apply the Updated Machine Config
```bash
# Decrypt SOPS-encrypted config if needed
sops -d talos/machine-configs/controlplane1.sops.yaml > /tmp/controlplane1.yaml

# Apply config (may require --insecure if certs are invalid)
talosctl apply-config --nodes 192.168.2.20 --file /tmp/controlplane1.yaml
```

### 2.2 Upgrade Node with NVIDIA Image
```bash
talosctl --nodes 192.168.2.20 upgrade \
  --image factory.talos.dev/installer/4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50:v1.11.5 \
  --preserve
```

Wait for node to reboot (~2-3 minutes).

### 2.3 Apply NVIDIA Runtime Patch (if not in machine config)
```bash
# Create patch file
cat > /tmp/nvidia-runtime-patch.yaml <<EOF
machine:
  files:
    - path: /etc/cri/conf.d/20-customization.part
      op: create
      content: |
        [plugins]
          [plugins."io.containerd.grpc.v1.cri"]
            [plugins."io.containerd.grpc.v1.cri".containerd]
              [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
                [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
                  privileged_without_host_devices = false
                  runtime_engine = ""
                  runtime_root = ""
                  runtime_type = "io.containerd.runc.v2"
                  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
                    BinaryName = "/usr/bin/nvidia-container-runtime"
EOF

# Apply patch (triggers reboot)
talosctl --nodes 192.168.2.20 patch machineconfig --patch @/tmp/nvidia-runtime-patch.yaml
```

Wait for reboot (~2-3 minutes).

## Step 3: Verify NVIDIA Extensions

```bash
# Check installed extensions
talosctl --nodes 192.168.2.20 get extensions

# Expected output:
# nonfree-kmod-nvidia-lts        535.247.01-v1.11.5
# nvidia-container-toolkit-lts   535.247.01-v1.17.8

# Verify kernel modules loaded
talosctl --nodes 192.168.2.20 read /proc/modules | grep nvidia

# Check driver version
talosctl --nodes 192.168.2.20 read /proc/driver/nvidia/version

# Verify GPU device nodes
talosctl --nodes 192.168.2.20 list /dev | grep nvidia
# Should see: nvidia0, nvidiactl, nvidia-uvm, etc.

# Check containerd runtime config
talosctl --nodes 192.168.2.20 read /etc/cri/conf.d/10-nvidia-container-runtime.part
```

## Step 4: Deploy NVIDIA RuntimeClass

```bash
kubectl apply -f talos/manifests/nvidia-runtimeclass.yaml
```

Contents of `nvidia-runtimeclass.yaml`:
```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
```

## Step 5: Deploy NVIDIA Device Plugin

**CRITICAL:** The device plugin MUST use the `nvidia` RuntimeClass to access GPU libraries.

Create `nvidia-device-plugin.yaml`:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      runtimeClassName: nvidia  # REQUIRED: Provides access to NVIDIA libraries
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      priorityClassName: "system-node-critical"
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.17.0
        name: nvidia-device-plugin-ctr
        args:
          - "--pass-device-specs=true"
          - "--device-list-strategy=envvar"
          - "--device-discovery-strategy=nvml"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/lib/kubelet/device-plugins
```

Deploy:
```bash
kubectl apply -f nvidia-device-plugin.yaml
```

### 5.1 Verify Device Plugin

```bash
# Check pod is running
kubectl get pods -n kube-system | grep nvidia

# Check logs (should see "Starting GRPC server" and "Registered device plugin")
kubectl logs -n kube-system -l name=nvidia-device-plugin-ds

# Verify GPU resource is advertised
kubectl describe node | grep nvidia.com/gpu
# Should show: nvidia.com/gpu: 1
```

## Step 6: Deploy GPU Workloads

Example Plex deployment with GPU:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plex
  namespace: media
spec:
  replicas: 1
  template:
    spec:
      runtimeClassName: nvidia  # Use NVIDIA runtime
      containers:
      - name: plex
        image: linuxserver/plex:latest
        env:
        - name: NVIDIA_VISIBLE_DEVICES
          value: "all"
        - name: NVIDIA_DRIVER_CAPABILITIES
          value: "all"
        resources:
          requests:
            nvidia.com/gpu: "1"
          limits:
            nvidia.com/gpu: "1"
```

## Troubleshooting

### ⚠️ Node Stuck in "booting" Stage (Most Common Issue)

**Symptom:**
```bash
talosctl --nodes 192.168.2.20 get machinestatus
# Shows: STAGE=booting, READY=true

kubectl get nodes
# Shows: STATUS=Ready

# But node never progresses to "running"
```

**Check if it's the nvidia issue:**
```bash
# Check service status
talosctl --nodes 192.168.2.20 services | grep nvidia
# Shows: ext-nvidia-persistenced   Waiting   ?   Waiting for file "/sys/bus/pci/drivers/nvidia" to exist

# Check if modules are loaded
talosctl --nodes 192.168.2.20 read /proc/modules | grep nvidia
# If empty or error, modules aren't loaded
```

**Root Cause:**
NVIDIA kernel modules not configured in machine config. The ext-nvidia-persistenced service waits forever for the nvidia driver, preventing boot completion.

**Fix:**
1. Apply kernel modules patch:
   ```bash
   cat > /tmp/nvidia-kernel-modules-patch.yaml <<'EOF'
   machine:
     kernel:
       modules:
         - name: nvidia
         - name: nvidia_uvm
         - name: nvidia_drm
         - name: nvidia_modeset
   EOF

   talosctl --nodes 192.168.2.20 patch machineconfig --patch @/tmp/nvidia-kernel-modules-patch.yaml
   ```

2. Reboot to load modules:
   ```bash
   talosctl --nodes 192.168.2.20 reboot
   ```

3. Verify modules loaded:
   ```bash
   talosctl --nodes 192.168.2.20 read /proc/modules | grep nvidia
   # Should show: nvidia, nvidia_uvm, nvidia_drm, nvidia_modeset
   ```

4. Verify node reached "running":
   ```bash
   talosctl --nodes 192.168.2.20 get machinestatus
   # Should show: STAGE=running, READY=true
   ```

5. Verify service started:
   ```bash
   talosctl --nodes 192.168.2.20 services | grep nvidia
   # Should show: ext-nvidia-persistenced   Running
   ```

**Prevention:**
Always include kernel modules in the initial machine config (see Step 1.1).

### Device Plugin Shows "No devices found"
- Check if device plugin is using `runtimeClassName: nvidia`
- Verify NVIDIA libraries exist: `talosctl list --recurse /usr/local/glibc/usr/lib | grep libnvidia-ml`
- Check device plugin logs for specific errors

### Pod Shows "Insufficient nvidia.com/gpu"
- Verify device plugin registered: `kubectl describe node | grep nvidia.com/gpu`
- Check device plugin is Running: `kubectl get pods -n kube-system | grep nvidia`

### Container Fails with "read-only file system" Error
- Ensure pod is using `runtimeClassName: nvidia`
- Don't manually mount `/usr/lib` or other system paths - let the nvidia runtime handle it

### NVML Error or Library Not Found
- Device plugin must use `runtimeClassName: nvidia` to access GPU libraries
- The nvidia runtime automatically injects libraries from `/usr/local/glibc/usr/lib`

## Files Modified/Created
- `talos/machine-configs/controlplane1.sops.yaml` - Updated with GPU support
- `talos/patches/gpu-patch.yaml` - Kernel modules patch
- `talos/patches/installer-patch.yaml` - Factory image with NVIDIA extensions
- `talos/manifests/nvidia-runtimeclass.yaml` - RuntimeClass definition
- `/tmp/nvidia-device-plugin.yaml` - Device plugin DaemonSet

## Key Learnings
1. The NVIDIA device plugin **MUST** run with `runtimeClassName: nvidia` to access GPU libraries
2. Don't manually mount NVIDIA libraries - the runtime handles this automatically
3. The nvidia-container-toolkit extension includes all necessary binaries in `/usr/local/bin/`
4. GPU libraries are in `/usr/local/glibc/usr/lib/` on Talos
5. The factory image schematic `4ba64c429e0aa252d716a668cf66b056b6ee3805f0ee0d7258a3a71e81df8e50` includes NVIDIA + iSCSI support
