locals {
  repo_root   = abspath("${path.root}/../..")
  scripts_dir = replace(abspath("${path.root}/scripts"), "\\", "/")

  catalog_path = replace("${local.repo_root}/lab-environments.json", "\\", "/")
  catalog      = jsondecode(file(local.catalog_path))
  defaults     = local.catalog.defaults
  env_known    = contains(keys(local.catalog.environments), var.env_name)
  env_config   = local.env_known ? local.catalog.environments[var.env_name] : null

  master_memory_mb   = coalesce(var.master_memory_mb, try(local.env_config.master_memory_mb, null), local.defaults.master_memory_mb)
  worker_memory_mb   = coalesce(var.worker_memory_mb, try(local.env_config.worker_memory_mb, null), local.defaults.worker_memory_mb)
  master_cpu_count   = coalesce(var.master_cpu_count, local.defaults.master_cpu_count)
  worker_cpu_count   = coalesce(var.worker_cpu_count, local.defaults.worker_cpu_count)
  hyperv_switch_name = coalesce(var.hyperv_switch_name, local.defaults.hyperv_switch_name)
  clusters           = local.defaults.clusters

  golden_vhdx_path = (
    trimspace(var.golden_vhdx_path) != ""
    ? var.golden_vhdx_path
    : replace(
      "${local.repo_root}/packer/ubuntu26-hyperv/output-ubuntu26-hyperv/Virtual Hard Disks/ubuntu26-hyperv-packer.vhdx",
      "\\", "/"
    )
  )

  vm_root_path = (
    trimspace(var.vm_root_path) != ""
    ? var.vm_root_path
    : replace("${local.repo_root}/hyperv-k8s-vms/${var.env_name}", "\\", "/")
  )

  inventory_path = (
    trimspace(var.ansible_inventory_path) != ""
    ? var.ansible_inventory_path
    : replace("${local.repo_root}/ansible/inventory/${var.env_name}.yml", "\\", "/")
  )

  ssh_public_key_path = (
    trimspace(var.ssh_public_key_path) != ""
    ? var.ssh_public_key_path
    : replace(pathexpand("~/.ssh/id_ed25519.pub"), "\\", "/")
  )

  ssh_private_key_path = (
    trimspace(var.ssh_private_key_path) != ""
    ? var.ssh_private_key_path
    : replace(pathexpand("~/.ssh/id_ed25519"), "\\", "/")
  )
}

resource "terraform_data" "env_guard" {
  lifecycle {
    precondition {
      condition     = local.env_known
      error_message = "env_name \"${var.env_name}\" is not in lab-environments.json. Add it with scripts/new-lab-env.ps1."
    }
    precondition {
      condition     = terraform.workspace == var.env_name
      error_message = "Terraform workspace \"${terraform.workspace}\" does not match env_name \"${var.env_name}\". Run: terraform workspace select ${var.env_name}"
    }
  }
}

module "env" {
  source = "./modules/env"

  env_name           = var.env_name
  clusters           = local.clusters
  hyperv_switch_name = local.hyperv_switch_name
  golden_vhdx_path   = local.golden_vhdx_path
  vm_root_path       = local.vm_root_path
  scripts_dir        = local.scripts_dir

  master_memory_mb = local.master_memory_mb
  master_cpu_count = local.master_cpu_count
  worker_memory_mb = local.worker_memory_mb
  worker_cpu_count = local.worker_cpu_count

  generation          = var.generation
  start_vms           = var.start_vms
  ssh_public_key_path = local.ssh_public_key_path
}

resource "null_resource" "ansible_inventory" {
  count = var.start_vms ? 1 : 0

  triggers = {
    vm_names             = join(",", module.env.vm_names)
    inventory_path       = local.inventory_path
    ssh_private_key_path = local.ssh_private_key_path
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
        -SshPrivateKeyPath "${local.ssh_private_key_path}" `
        -WaitSeconds ${var.inventory_wait_seconds}
    EOT
  }
}
