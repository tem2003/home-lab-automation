variable "env_name" {
  type = string
}

variable "clusters" {
  type = map(object({
    master_count = number
    worker_count = number
  }))
}

variable "hyperv_switch_name" {
  type = string
}

variable "golden_vhdx_path" {
  type = string
}

variable "vm_root_path" {
  type = string
}

variable "scripts_dir" {
  description = "Absolute path to shared Hyper-V scripts (create/destroy/seed)."
  type        = string
}

variable "master_memory_mb" {
  type = number
}

variable "master_cpu_count" {
  type = number
}

variable "worker_memory_mb" {
  type = number
}

variable "worker_cpu_count" {
  type = number
}

variable "generation" {
  type = number
}

variable "start_vms" {
  type = bool
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key injected into each VM NoCloud seed."
  type        = string
  default     = ""
}
