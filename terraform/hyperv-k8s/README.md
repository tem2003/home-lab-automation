# Terraform Hyper-V K8s VM Factory

Creates Hyper-V VMs for Kubernetes clusters from a golden VHDX image, injects per-VM NoCloud identity, starts guests, and writes an Ansible inventory from discovered IPs.

## Layout

```
terraform/hyperv-k8s/
  modules/env/          # shared VM factory for one environment
  scripts/              # create / destroy / seed / inventory
  envs/dev/             # day-to-day lab
  envs/stable/          # longer-lived / “known good” lab
```

Each `envs/<name>/` directory is its own Terraform root with:

- separate state
- `terraform.tfvars` auto-loaded (no `-var-file` needed)

## Deploy (dev)

```powershell
cd <repo-root>\terraform\hyperv-k8s\envs\dev
terraform init
terraform apply
```

## Deploy (stable)

```powershell
cd <repo-root>\terraform\hyperv-k8s\envs\stable
terraform init
terraform apply
```

## Destroy

```powershell
cd <repo-root>\terraform\hyperv-k8s\envs\dev
terraform destroy
```

## What this creates (per env)

- `cluster1`: 1 master + 2 workers
- `cluster2`: 1 master + 2 workers

VM names: `<env>-<cluster>-master-1`, `<env>-<cluster>-worker-N`.

## Notes

- Golden VHDX, VM root, inventory, and SSH key paths default to this git clone (`<repo>/packer/...`, `<repo>/hyperv-k8s-vms/<env>`, `~/.ssh/id_ed25519`). Override in `terraform.tfvars` or via `deploy-lab.ps1` `-var` only if needed.
- Golden VHDX is never modified; each VM gets a copy plus a NoCloud seed ISO.
- Edit `envs/<name>/terraform.tfvars` for memory, switch name, etc.
- After apply with `start_vms = true`, inventory is written under `ansible/inventory/<env>.yml`.
