terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.87.0"
    }
  }
}

variable "api_token" {}

provider "proxmox" {
  endpoint = "https://192.168.4.59:8006/"
  api_token = var.api_token
  insecure = true
  ssh {
    agent = true
    username = "terraform"
  }
}

locals {
  node = "oa"
  file_storage = "local"
  vm_storage = "oa-rz2"
  vm_name = "debian13-k8s"
  vm_count = 3
  vm_start = 0
  hostnames = {
    for i in range(local.vm_count) :
    i + local.vm_start => {
      hostname = "${local.vm_name}-${i + local.vm_start}"
    }
  }
  user = "k8s"
}

resource "proxmox_virtual_environment_download_file" "debian13_cloud_image" {
  content_type = "import"
  node_name    = local.node
  datastore_id = local.file_storage
  url          = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

variable "ssh_pub" {}

resource "proxmox_virtual_environment_file" "cloud_init_user" {
  
  content_type = "snippets"
  node_name    = local.node
  datastore_id = local.file_storage

  source_raw {
    data = templatefile("cloud-init/user.yaml", {
      user = local.user
      ssh_pub = trimspace(var.ssh_pub)
    })
    file_name = "cloud-init-user-${local.vm_name}.yaml"
  }
}

resource "proxmox_virtual_environment_file" "cloud_init_meta" {
  
  for_each = local.hostnames
  content_type = "snippets"
  node_name    = local.node
  datastore_id = local.file_storage

  source_raw {
    data = templatefile("cloud-init/meta.yaml", {
      hostname = each.value.hostname
    })
    file_name = "cloud-init-meta-${each.value.hostname}.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "debian13_vm" {
  
  for_each = local.hostnames
  vm_id  = 800 + each.key
  name = each.value.hostname
  node_name = local.node # required
  
  scsi_hardware = "virtio-scsi-single"
  disk {
    interface    = "scsi0"
    datastore_id = local.vm_storage
    import_from  = proxmox_virtual_environment_download_file.debian13_cloud_image.id
    iothread     = true
    size         = 8
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1024
  }
  
  network_device {
    bridge = "vmbr0"
  }
  
  # should be true if qemu agent is not installed / enabled on the VM
  # stop_on_destroy = true

  agent {
    enabled = true
  }

  # --- Cloud-init ---
  initialization {
    
    type = "nocloud"
    
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user.id
    meta_data_file_id = proxmox_virtual_environment_file.cloud_init_meta[each.key].id
  }
}
