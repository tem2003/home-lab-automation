locals {
  node_specs = flatten([
    for cluster_name, cfg in var.clusters : concat(
      [
        for i in range(cfg.master_count) : {
          name      = "${var.env_name}-${cluster_name}-master-${i + 1}"
          role      = "master"
          cluster   = cluster_name
          memory_mb = var.master_memory_mb
          cpu_count = var.master_cpu_count
        }
      ],
      [
        for i in range(cfg.worker_count) : {
          name      = "${var.env_name}-${cluster_name}-worker-${i + 1}"
          role      = "worker"
          cluster   = cluster_name
          memory_mb = var.worker_memory_mb
          cpu_count = var.worker_cpu_count
        }
      ]
    )
  ])

  nodes = { for n in local.node_specs : n.name => n }
}

resource "null_resource" "hyperv_vm" {
  for_each = local.nodes

  triggers = {
    vm_name              = each.value.name
    env_name             = var.env_name
    cluster_name         = each.value.cluster
    role                 = each.value.role
    switch_name          = var.hyperv_switch_name
    golden_vhdx_path     = var.golden_vhdx_path
    vm_root_path         = var.vm_root_path
    memory_mb            = tostring(each.value.memory_mb)
    cpu_count            = tostring(each.value.cpu_count)
    generation           = tostring(var.generation)
    ssh_public_key_path  = var.ssh_public_key_path
    create_script_path   = "${var.scripts_dir}/create-hyperv-vm.ps1"
    destroy_script       = "${var.scripts_dir}/destroy-hyperv-vm.ps1"
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = <<-EOT
      & "${self.triggers.create_script_path}" `
        -VmName "${self.triggers.vm_name}" `
        -SwitchName "${self.triggers.switch_name}" `
        -GoldenVhdxPath "${self.triggers.golden_vhdx_path}" `
        -VmRootPath "${self.triggers.vm_root_path}" `
        -Role "${self.triggers.role}" `
        -Cluster "${self.triggers.cluster_name}" `
        -EnvName "${self.triggers.env_name}" `
        -SshPublicKeyPath "${self.triggers.ssh_public_key_path}" `
        -MemoryMb ${self.triggers.memory_mb} `
        -CpuCount ${self.triggers.cpu_count} `
        -Generation ${self.triggers.generation} `
        -StartVm:${var.start_vms ? "$true" : "$false"}
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = <<-EOT
      & "${self.triggers.destroy_script}" `
        -VmName "${self.triggers.vm_name}" `
        -VmRootPath "${self.triggers.vm_root_path}"
    EOT
  }
}
