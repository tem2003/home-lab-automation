variable "env_name" {
  description = "Environment key in lab-environments.json. Selects VM names, memory, and inventory path."
  type        = string
}

variable "golden_vhdx_path" {
  description = "Absolute path to the Packer golden VHDX. Empty = <repo>/packer/ubuntu26-hyperv/output-ubuntu26-hyperv/.../ubuntu26-hyperv-packer.vhdx"
  type        = string
  default     = ""
}

variable "vm_root_path" {
  description = "Folder for this env's per-VM disks/configs. Empty = <repo>/hyperv-k8s-vms/<env_name>"
  type        = string
  default     = ""
}

variable "master_memory_mb" {
  description = "Override catalog master VM RAM (MB). Null uses lab-environments.json."
  type        = number
  default     = null
}

variable "master_cpu_count" {
  description = "Override catalog master vCPU count. Null uses lab-environments.json defaults."
  type        = number
  default     = null
}

variable "worker_memory_mb" {
  description = "Override catalog worker VM RAM (MB). Null uses lab-environments.json."
  type        = number
  default     = null
}

variable "worker_cpu_count" {
  description = "Override catalog worker vCPU count. Null uses lab-environments.json defaults."
  type        = number
  default     = null
}

variable "hyperv_switch_name" {
  description = "Override catalog Hyper-V switch name. Null uses lab-environments.json defaults."
  type        = string
  default     = null
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
