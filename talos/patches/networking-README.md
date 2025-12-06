# Talos Networking Patches

This directory contains Talos machine configuration patches related to networking, particularly for MetalLB load balancer integration.

## MetalLB L2 Advertisement Issue

### Problem

**Symptom:** LoadBalancer services get assigned IP addresses from MetalLB but are unreachable. The ARP table shows the IP as "(incomplete)" with no hardware (MAC) address.

**Root Cause:** Starting in Talos v1.8.0, the `node.kubernetes.io/exclude-from-external-load-balancers` label is automatically added to control-plane nodes. This label instructs load balancers like MetalLB to exclude these nodes from announcing services, which prevents L2 ARP announcements.

### Diagnosis

```bash
# 1. Check if the exclusion label exists on your nodes
kubectl get nodes --show-labels | grep exclude-from-external-load-balancers

# 2. Check ARP table for your LoadBalancer IP (should show "incomplete" if broken)
arp -n | grep <LOADBALANCER_IP>

# 3. Verify MetalLB has assigned the IP but isn't announcing it
kubectl get svc -n <namespace> <service-name>
kubectl get servicel2statuses -A  # Should be empty if not announcing

# 4. Check MetalLB speaker logs
kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker
```

### Solution

#### Temporary Fix

Remove the label manually (will be re-added by Talos on reboot or reconciliation):

```bash
kubectl label node <NODE_NAME> node.kubernetes.io/exclude-from-external-load-balancers-
```

#### Permanent Fix (Recommended)

Apply the Talos machine config patch to permanently remove the label:

```bash
# Apply the patch to your control-plane node(s)
talosctl -n <NODE_IP> patch machineconfig -p @networking/remove-lb-exclusion-label.yaml
```

The patch will:
- Remove the `node.kubernetes.io/exclude-from-external-load-balancers` label from the machine config
- Apply without requiring a reboot
- Persist across reboots and upgrades

#### Alternative: Edit Base Config

You can also edit your base control plane configuration file (e.g., `core/controlplane1.yaml`) and comment out or remove the nodeLabels section:

```yaml
machine:
  nodeLabels:
    # Commented out to allow MetalLB L2 announcements on control-plane nodes
    # node.kubernetes.io/exclude-from-external-load-balancers: ""
```

Then generate and apply a new config:

```bash
talosctl apply-config -n <NODE_IP> -f core/controlplane1.yaml
```

### Verification

After applying the fix, verify it worked:

```bash
# 1. Confirm label is removed from machine config
talosctl -n <NODE_IP> get machineconfig -o yaml | grep -A 5 "nodeLabels"

# 2. Confirm label is not on the node
kubectl get node <NODE_NAME> -o jsonpath='{.metadata.labels}' | jq 'has("node.kubernetes.io/exclude-from-external-load-balancers")'
# Should return: false

# 3. Check ARP table - should now show the hardware address
arp -n | grep <LOADBALANCER_IP>
# Should show: <IP>    ether   <MAC_ADDRESS>   C   <interface>

# 4. Test connectivity
curl -I http://<LOADBALANCER_IP>
```

### Additional MetalLB L2 Configuration

For single-node setups, you may also need to explicitly specify the network interface in your L2Advertisement:

```yaml
# In your GitOps repo: platform/metallb/l2advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: traefik-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - traefik-pool
  interfaces:
    - enp3s0  # Specify the physical network interface
```

Find your physical interface name with:
```bash
talosctl -n <NODE_IP> get links | grep -E "TYPE.*ether" | grep -v "veth\|cni\|flannel"
```

## References

- [Talos: Enable workers on control plane nodes](https://www.talos.dev/v1.11/talos-guides/howto/workers-on-controlplane/)
- [Talos Issue #9325: Can't remove exclude-from-external-load-balancers label](https://github.com/siderolabs/talos/issues/9325)
- [Talos Issue #8749: Automatically add well-known labels on controlplane nodes](https://github.com/siderolabs/talos/issues/8749)
- [Fix LoadBalancer Services on Single Node Talos](https://www.robert-jensen.dk/posts/2025/fix-loadbalancer-services-not-working-on-single-node-talos-kubernetes-cluster/)
- [MetalLB Troubleshooting](https://metallb.universe.tf/troubleshooting/)

## Applied Patches

Patches that have been applied to the cluster:

- **2025-12-05**: Applied `remove-lb-exclusion-label.yaml` to node `talos-qtx-4mi` (192.168.2.20) to enable MetalLB L2 announcements
