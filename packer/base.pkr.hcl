# This is the base image of the AI Services VM
# It contains no weeknesses and flags. Student VMs are built on top of it as copy-on-write disks.
#
# Usage (build from the project root)
#   packer init packer/qemu-plugin.pkr.hcl
#   packer build packer/base.pkr.hcl
#
#
# Result
#   output/base-vm/ai_base.qcow2

variable "ssh_password" {
  type        = string
  default     = "TH3P455W0RD"
  description = "Password of the buld user vagrant"
}

source "qemu" "base" {
  iso_url      = "https://cdimage.debian.org/mirror/cdimage/archive/12.14.0/amd64/iso-cd/debian-12.14.0-amd64-netinst.iso"
  iso_checksum = "sha256:adfcbb50782af99d457467f9b38c9e0fb3b1b6e211e0202f099aa58874b3f923"

  output_directory = "${path.root}/../output/base-vm"
  vm_name          = "ai_base.qcow2"
  format           = "qcow2"
  disk_size        = "40G"
  disk_interface   = "virtio"

  cpus        = 4
  memory      = 4096
  accelerator = "kvm"
  headless    = true

  # Preseed server, bound to localhost only
  http_directory    = "${path.root}/http"
  http_bind_address = "127.0.0.1"
  http_port_min     = 9000
  http_port_max     = 9010

  # SSH into the build VM (forward bound to localhost)
  ssh_username     = "vagrant"
  ssh_password     = var.ssh_password
  ssh_timeout      = "40m"
  host_port_min    = 2000
  host_port_max    = 2010
  shutdown_command = "echo '${var.ssh_password}' | sudo -S /sbin/shutdown -hP now"

  vnc_bind_address = "127.0.0.1"

  qemuargs = [
    ["-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:{{ .SSHHostPort }}-:22"],
    ["-device", "virtio-net,netdev=net0"]
  ]

  boot_wait = "5s"
  boot_command = [
    "<down><tab>",
    "preseed/url=http://10.0.2.2:{{ .HTTPPort }}/suasploitable-exam-preseed.cfg ",
    "language=en locale=de_DE.UTF-8 ",
    "country=DE keymap=de ",
    "hostname=ai-services domain=example.com ",
    "<enter><wait>"
  ]
}

build {
  sources = ["source.qemu.base"]

  # Marker (the base scripts refuse to run on any machine without it)
  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    inline          = ["echo 'AI Services VM base build - disposable build VM' > /etc/ai-base-build"]
  }

  # Docker and the base packages from virtual-machines repo
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    scripts = [
      "${path.root}/../scripts/platform/install-docker.sh",
      "${path.root}/../scripts/platform/base-environment.sh"
    ]
  }

  # Image list for base-images.sh
  provisioner "file" {
    source      = "${path.root}/images.json"
    destination = "/tmp/images.json"
  }

  # container images, pinned by id.
  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    script          = "${path.root}/../scripts/platform/base-images.sh"
    timeout         = "4h"
  }

  # Models: TinyLlama for Ollama, the embedding model for Open WebUI
  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    script          = "${path.root}/../scripts/platform/base-models.sh"
    timeout         = "4h"
  }

  # Build record
  provisioner "shell" {
    execute_command = "echo '${var.ssh_password}' | sudo -S env {{ .Vars }} {{ .Path }}"
    script          = "${path.root}/../scripts/platform/base-record.sh"
  }

  # copy the build record to the host
  provisioner "file" {
    source      = "/opt/ai-services/base-manifest.json"
    destination = "${path.root}/../output/base/"
    direction   = "download"
  }
}