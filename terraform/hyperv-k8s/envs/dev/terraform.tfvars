env_name = "dev"

golden_vhdx_path = "D:/automation/packer/ubuntu26-hyperv/output-ubuntu26-hyperv/Virtual Hard Disks/ubuntu26-hyperv-packer.vhdx"
vm_root_path     = "D:/automation/hyperv-k8s-vms/dev"

hyperv_switch_name = "hyper-v-switch"
start_vms          = true

master_memory_mb = 4096
worker_memory_mb = 4096

ssh_public_key_path  = "C:/Users/User/.ssh/id_ed25519.pub"
ssh_private_key_path = "C:/Users/User/.ssh/id_ed25519"

ansible_inventory_path = "D:/automation/ansible/inventory/dev.yml"
inventory_wait_seconds = 360
