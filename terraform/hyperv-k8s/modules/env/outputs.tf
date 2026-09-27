output "vm_names" {
  value = keys(local.nodes)
}

output "vm_specs" {
  value = local.nodes
}
