# Overview
Homelab things, want to use Gitops, k8s and all the fancy things where possible.

## Issues
- Currently the argocd app isn't managing itself fully, it is deployed manually. Should get this under management.

## Troubleshooting

### MetalLB Not Announcing LoadBalancer IPs on Talos Control-Plane Nodes

**Symptom:** LoadBalancer services get assigned an IP address but have no hardware (MAC) address in ARP table, appearing as "(incomplete)". Services are unreachable.

**Root Cause:** Talos Linux automatically adds the `node.kubernetes.io/exclude-from-external-load-balancers` label to control-plane nodes (as of v1.8.0). This label instructs MetalLB and other load balancers to exclude these nodes from announcing services.

**Diagnosis:**
```bash
# Check if the exclusion label exists
kubectl get nodes --show-labels | grep exclude-from-external-load-balancers

# Check ARP table (should show "incomplete" if broken)
arp -n | grep <LOADBALANCER_IP>

# Verify MetalLB speaker logs show no announcements
kubectl logs -n metallb-system -l app.kubernetes.io/component=speaker
```

**Temporary Fix:**
```bash
# Remove the label (will be re-added by Talos on reboot/reconciliation)
kubectl label node <NODE_NAME> node.kubernetes.io/exclude-from-external-load-balancers-
```

**Permanent Fix (Talos Machine Config):**

If you're running a single-node cluster or want control-plane nodes to handle load balancer traffic, update your Talos machine config to prevent adding this label:

```yaml
machine:
  nodeLabels:
    # Remove or comment out this line from your control plane config
    # node.kubernetes.io/exclude-from-external-load-balancers: ""
```

Apply the config update:
```bash
talosctl apply-config -n <NODE_IP> -f <updated-config.yaml>
```

**Additional Configuration:**

The L2Advertisement also requires explicit interface specification in single-node setups:

```yaml
# platform/metallb/l2advertisement.yaml
spec:
  ipAddressPools:
    - traefik-pool
  interfaces:
    - enp3s0  # Specify the physical network interface
```

**References:**
- [Talos: Enable workers on control plane nodes](https://www.talos.dev/v1.11/talos-guides/howto/workers-on-controlplane/)
- [Talos Issue #9325: Can't remove exclude-from-external-load-balancers label](https://github.com/siderolabs/talos/issues/9325)
- [Fix LoadBalancer Services on Single Node Talos](https://www.robert-jensen.dk/posts/2025/fix-loadbalancer-services-not-working-on-single-node-talos-kubernetes-cluster/)
