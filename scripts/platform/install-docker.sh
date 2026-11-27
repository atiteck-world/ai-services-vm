#!/bin/bash
# This script installs Docker CE from the official Docker repository on the AI Services base build VM. 
# It is intended to be run inside the VM and will not work outside of it.
# (https://docs.docker.com/engine/install/debian/)



set -euo pipefail

MARKER=/etc/ai-base-build
KEYRING=/etc/apt/keyrings/docker.gpg

if [[ ! -f "$MARKER" ]]; then
    echo "ERROR: $MARKER not found. The script only runs inside the AI Services base build VM." >&2
    exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# Tools needed for Docker installation.
apt-get update
apt-get install -y ca-certificates curl gnupg python3

# Add Docker's official GPG key and set up the stable repository.
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o "$KEYRING"
chmod a+r "$KEYRING"

# Add Docker repository for the current Debian version.
ARCH=$(dpkg --print-architecture)
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=$ARCH signed-by=$KEYRING] https://download.docker.com/linux/debian $CODENAME stable" > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose

systemctl enable docker.service
systemctl enable containerd.service

echo "Docker installed successfully. $(docker --version)"