# Terraform Hyper-V K8s VM Factory

Creates Hyper-V VMs for Kubernetes clusters from a golden VHDX image, injects per-VM NoCloud identity, starts guests, and writes an Ansible inventory from discovered IPs.

Environments are defined in [`lab-environments.json`](../../lab-environments.json) at the repo root. This directory is one Terraform root. Each environment is a workspace (`terraform.tfstate.d/<env>/terraform.tfstate`) so state stays separate.

## Layout

```
terraform/hyperv-k8s/
  main.tf               # shared root; reads lab-environments.json
  modules/env/          # VM factory for the selected environment
  scripts/              # create / destroy / seed / inventory
```

`dev` and `stable` are catalog entries, not directories. Add another environment with `scripts/new-lab-env.ps1`, then deploy that name.

## Deploy

From the repo root, `scripts/deploy-lab.ps1 -TfEnv <name>` selects the workspace and applies. Manually:

```powershell
cd <repo-root>\terraform\hyperv-k8s
terraform init
terraform workspace select dev
terraform apply -var=env_name=dev
```

`terraform workspace new <name>` creates a workspace the first time. `deploy-lab.ps1` does that when the workspace is missing. The workspace name and `-var=env_name` must be the same value. Applying a different name in an existing workspace is rejected so that environment's VMs are not destroyed.

## Destroy

```powershell
cd <repo-root>\terraform\hyperv-k8s
terraform workspace select dev
terraform destroy -var=env_name=dev
```

Or `.\scripts\destroy-lab.ps1 -TfEnv dev`.

## What this creates (per env)

- `cluster1`: 1 master + 2 workers (counts come from catalog `defaults.clusters`)
- `cluster2`: 1 master + 2 workers

VM names: `<env>-<cluster>-master-1`, `<env>-<cluster>-worker-N`.

Pod CIDRs, service CIDRs, and Istio network names are per environment in the catalog. Ansible reads that file; Terraform does not apply them.

## Notes

- Golden VHDX, VM root, inventory, and SSH key paths default to this git clone (`<repo>/packer/...`, `<repo>/hyperv-k8s-vms/<env>`, `~/.ssh/id_ed25519`). Override with `terraform -var` or `deploy-lab.ps1` only if needed.
- Memory and CPU come from `lab-environments.json` (`defaults`, then the environment entry). `deploy-lab.ps1 -MasterMemoryMb` / `-WorkerMemoryMb` override the catalog for that apply. A memory change updates VM triggers, and the next apply recreates those VMs.
- Golden VHDX is never modified; each VM gets a copy plus a NoCloud seed ISO.
- After apply with `start_vms = true`, inventory is written to `ansible/inventory/<env>.yml`.
- The first apply on a migrated workspace adds `terraform_data.env_guard` (catalog name check) and leaves existing VMs in place.
