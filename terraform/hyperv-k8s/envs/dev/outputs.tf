output "vm_names" {
  description = "VM names in this environment."
  value       = module.env.vm_names
}

output "vm_specs" {
  description = "Node role/cluster metadata."
  value       = module.env.vm_specs
}

output "ansible_inventory_path" {
  description = "Path to generated Ansible inventory (when start_vms is true)."
  value       = var.start_vms ? local.inventory_path : null
}

output "env_name" {
  value = var.env_name
}
