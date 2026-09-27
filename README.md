# Hyper-V dual-cluster Kubernetes + multi-primary Istio lab

Automated lab on a Windows Hyper-V host:

1. **Packer** — Ubuntu golden VHDX with containerd + kubeadm packages ([`packer/ubuntu26-hyperv`](packer/ubuntu26-hyperv))
2. **Terraform** — clone VMs for `cluster1` + `cluster2`, NoCloud identity, Ansible inventory ([`terraform/hyperv-k8s`](terraform/hyperv-k8s))
3. **Ansible** — kubeadm, Flannel, Istio multi-primary, smoke apps ([`ansible`](ansible))

```powershell
cd D:\automation
.\scripts\deploy-lab.ps1
```

Full docs: [`docs/multi-cluster-istio.md`](docs/multi-cluster-istio.md).
