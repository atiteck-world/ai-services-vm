# packer/

Packer templates for the VM images.

## Base Image (`base.pkr.hcl`)

One VM disk will be shared by all student VMs. it contains no weaknesses and flags. each student VM is a small copy-on-write disk on top of it (built later)

### Requirements

Linux with KVM (`/dev/kvm` readable and writable for your user), QEMU, Packer 1.10 or newer, about 4.5 GB free RAM
and 15 GB free disk. The first build downloads the Debian ISO (about 650 MB).

### Build

From the project root:

    packer init packer/qemu-plugin.pkr.hcl        # installs the QEMU plugin
    mkdir -p output/base
    packer build packer/base.pkr.hcl 2>&1 | tee output/base-build.log

This can takes about 10-20 minutes with a cached ISO. If `output/base-vm/` is left over from an earlier build, delete it first.

### Results

- `output/base-vm/ai_base.qcow2`: the base disk (4.2 GB so far)
- `output/base/base-manifest.json`: `built` (time in the VM, UTC), `debian_version`, `docker_version`,
  `docker_tcp` (always `false`; otherwise the build fails)

Both are in `output/` and never committed.