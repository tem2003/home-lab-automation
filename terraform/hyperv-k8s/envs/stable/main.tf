locals {
  scripts_dir    = abspath("${path.root}/../../scripts")
  inventory_path = trimspace(var.ansible_inventory_path) != "" ? var.ansible_inventory_path : abspath("${path.root}/../../../../ansible/inventory/${var.env_name}.yml")
}

module "env" {
  source = "../../modules/env"

  env_name           = var.env_name
  clusters           = var.clusters
  hyperv_switch_name = var.hyperv_switch_name
  golden_vhdx_path   = var.golden_vhdx_path
  vm_root_path       = var.vm_root_path
  scripts_dir        = local.scripts_dir

  master_memory_mb = var.master_memory_mb
  master_cpu_count = var.master_cpu_count
  worker_memory_mb = var.worker_memory_mb
  worker_cpu_count = var.worker_cpu_count

  generation          = var.generation
  start_vms           = var.start_vms
  ssh_public_key_path = var.ssh_public_key_path
}

resource "null_resource" "ansible_inventory" {
  count = var.start_vms ? 1 : 0

  triggers = {
    vm_names             = join(",", module.env.vm_names)
    inventory_path       = local.inventory_path
    ssh_private_key_path = var.ssh_private_key_path
    wait_seconds         = tostring(var.inventory_wait_seconds)
    discover_script      = "${local.scripts_dir}/discover-inventory.ps1"
    env_id               = md5(join(",", module.env.vm_names))
  }

  depends_on = [module.env]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = <<-EOT
      $names = @(${join(", ", [for n in module.env.vm_names : "\"${n}\""])})
      & "${local.scripts_dir}/discover-inventory.ps1" `
        -VmNames $names `
        -OutputPath "${local.inventory_path}" `
        -SshPrivateKeyPath "${var.ssh_private_key_path}" `
        -WaitSeconds ${var.inventory_wait_seconds}
    EOT
  }
}
