env_name = "dev"

# Paths default to the git repo root (and ~/.ssh for keys). Override only if needed:
# golden_vhdx_path       = "D:/other/path/ubuntu26-hyperv-packer.vhdx"
# vm_root_path           = "D:/other/hyperv-k8s-vms/dev"
# ssh_public_key_path    = "C:/Users/you/.ssh/id_ed25519.pub"
# ssh_private_key_path   = "C:/Users/you/.ssh/id_ed25519"
# ansible_inventory_path = "D:/other/ansible/inventory/dev.yml"

hyperv_switch_name = "hyper-v-switch"
start_vms          = true

# Defaults; override via deploy-lab.ps1 -MasterMemoryMb / -WorkerMemoryMb (or terraform -var).
master_memory_mb = 4096
worker_memory_mb = 4096

inventory_wait_seconds = 360
