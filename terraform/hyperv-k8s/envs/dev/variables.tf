variable "env_name" {
  description = "Environment name used in VM naming and paths."
  type        = string
  default     = "dev"
}

variable "clusters" {
  description = "Cluster definitions for this environment."
  type = map(object({
    master_count = number
    worker_count = number
  }))
  default = {
    cluster1 = {
      master_count = 1
      worker_count = 2
    }
    cluster2 = {
      master_count = 1
      worker_count = 2
    }
  }
}

variable "hyperv_switch_name" {
  type    = string
  default = "hyper-v-switch"
}

variable "golden_vhdx_path" {
  description = "Absolute path to the golden VHDX created by Packer."
  type        = string
}

variable "vm_root_path" {
  description = "Folder where this env's per-VM disks/configs are created."
  type        = string
  default     = "D:/automation/hyperv-k8s-vms/dev"
}

variable "master_memory_mb" {
  type    = number
  default = 4096
}

variable "master_cpu_count" {
  type    = number
  default = 2
}

variable "worker_memory_mb" {
  type    = number
  default = 4096
}

variable "worker_cpu_count" {
  type    = number
  default = 2
}

variable "generation" {
  type    = number
  default = 2
}

variable "start_vms" {
  type    = bool
  default = true
}

variable "ssh_public_key_path" {
  type    = string
  default = ""
}

variable "ssh_private_key_path" {
  type    = string
  default = ""
}

variable "ansible_inventory_path" {
  type    = string
  default = ""
}

variable "inventory_wait_seconds" {
  type    = number
  default = 360
}
