variable "cloud_image_url" {
  type        = string
  description = "Source media path for hyperv-iso (ISO or VHD/VHDX). Prefer file:///...vhdx for Ubuntu cloud images."
  default     = "https://cloud-images.ubuntu.com/releases/resolute/release/ubuntu-26.04-server-cloudimg-amd64.img"

  validation {
    condition     = can(regex("^(https?://|file:///)", var.cloud_image_url))
    error_message = "Cloud image URL must start with http://, https://, or file:///."
  }
}

variable "cloud_image_checksum" {
  type        = string
  description = "Checksum for cloud_image_url. Use 'none' only for trusted internal testing."
  default     = "none"
}

variable "vm_name" {
  type        = string
  description = "Temporary build VM name."
  default     = "ubuntu26-hyperv-packer"
}

variable "switch_name" {
  type        = string
  description = "Hyper-V virtual switch name."
  default     = "hyper-v-switch"
}

variable "generation" {
  type        = number
  description = "Hyper-V VM generation."
  default     = 2

  validation {
    condition     = contains([1, 2], var.generation)
    error_message = "Generation must be 1 or 2."
  }
}

variable "cpus" {
  type        = number
  description = "Number of vCPUs for the build VM."
  default     = 2
}

variable "memory" {
  type        = number
  description = "Build VM memory in MB."
  default     = 4096
}

variable "disk_size_mb" {
  type        = number
  description = "Disk size (MB) if Packer creates/expands a target disk. Source VHDX should already be resized via prepare-source-disk.ps1."
  default     = 40960
}

variable "output_directory" {
  type        = string
  description = "Directory for generated Hyper-V artifact output."
  default     = "output-ubuntu26-hyperv"
}

variable "artifact_suffix" {
  type        = string
  description = "Optional suffix appended to output artifact names."
  default     = ""
}

variable "nocloud_iso_relpath" {
  type        = string
  description = "Path to the cidata/NoCloud seed ISO, relative to this Packer directory (e.g. artifacts/nocloud-seed.iso). Build with scripts\\build-nocloud-seed.ps1."
  default     = "artifacts/nocloud-seed.iso"
}

variable "ssh_username" {
  type        = string
  description = "Linux user created by the Ubuntu cloud image (default ubuntu)."
  default     = "ubuntu"
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the PEM private key whose public key is in the NoCloud user-data. Used by Packer to provision and to match Terraform node access later."

  validation {
    condition     = length(trimspace(var.ssh_private_key_path)) > 0
    error_message = "Ssh private key path must be a non-empty path to a PEM file."
  }
}

variable "ssh_password" {
  type        = string
  description = "Optional SSH password (matches NoCloud debug password). Packer still needs guest IP via hv-kvp."
  default     = "TempDebug123!"
  sensitive   = true
}
