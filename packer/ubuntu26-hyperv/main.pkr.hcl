packer {
  required_version = ">= 1.11.0"

  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = ">= 1.1.0"
    }
  }
}

locals {
  vm_name_effective = trimspace(var.artifact_suffix) == "" ? var.vm_name : "${var.vm_name}-${var.artifact_suffix}"
  nocloud_iso_abs   = abspath("${path.root}/${var.nocloud_iso_relpath}")
}

source "hyperv-iso" "ubuntu26" {
  vm_name          = local.vm_name_effective
  generation       = var.generation
  switch_name      = var.switch_name
  cpus             = var.cpus
  memory           = var.memory
  disk_size        = var.disk_size_mb
  output_directory = var.output_directory

  # NoCloud: secondary DVD with user-data (ssh_authorized_keys) for the Ubuntu cloud image.
  secondary_iso_images = [local.nocloud_iso_abs]

  boot_wait = "30s"
  # First boot: cloud-config + package updates can take several minutes.
  ssh_timeout         = "25m"
  ssh_handshake_attempts = 50
  # Allow console/password fallback if key timing races cloud-init (debug password in nocloud/user-data).
  ssh_password        = var.ssh_password
  shutdown_command     = "sudo /sbin/shutdown -P now"
  shutdown_timeout     = "15m"
  enable_secure_boot   = false
  differencing_disk    = false
  skip_compaction      = false
  communicator         = "ssh"
  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_path

  iso_url      = var.cloud_image_url
  iso_checksum = var.cloud_image_checksum
}

build {
  name    = "ubuntu26-hyperv"
  sources = ["source.hyperv-iso.ubuntu26"]

  # Keep golden image minimal. Kubernetes prereqs are installed later by Ansible.
  # Generalize the disk for cloneable Terraform/Hyper-V node templates.
  provisioner "shell" {
    script = "${path.root}/scripts/finalize-template.sh"
  }

  post-processor "manifest" {
    output = "${var.output_directory}/manifest.json"
  }
}
