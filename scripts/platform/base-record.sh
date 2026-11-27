#!/bin/bash
# Check that Docker is not running with TCP enabled, which is a security risk and writes the build record to 
# /opt/ai-services/base-manifest.json. 
# The script is intended to run only inside the disposable base build VM and will remove the marker file at the end.

set -euo pipefail

MARKER=/etc/ai-base-build
OUTPUT_DIR=/opt/ai-services
OUT=${OUTPUT_DIR}/base-manifest.json

if [[ ! -f "$MARKER" ]]; then
    echo "ERROR: $MARKER not found. The script only runs inside the AI Services base build VM." >&2
    exit 1
fi

# Check if Docker is running with TCP enabled, which is not allowed for security reasons. 
# It must listen only on its local socket.
if ss -ltnp | grep -q dockerd; then
    echo "ERROR: Docker is running with TCP enabled on port :" >&2
    ss -ltnp | grep dockerd >&2
    exit 1
fi

DEBIAN_VERSION=$(cat /etc/debian_version)
DOCKER_VERSION=$(docker version --format '{{.Server.Version}}')

mkdir -p "$OUTPUT_DIR"

# python3 script to generate the base-manifest.json file with build information
python3 - "$OUT" "$DEBIAN_VERSION" "$DOCKER_VERSION" <<'EOF'
import json
import sys
import time
out, debian_version, docker_version = sys.argv[1:4]
record = {
    "built": time.strftime("%Y-%m-%d %H:%M:%S"),
    "debian_version": debian_version,
    "docker_version": docker_version,
    "docker_tcp": False, 
}
with open(out, "w") as f:
    json.dump(record, f, indent=2)
    f.write("\n")
EOF
chmod 644 "$OUT"
cat "$OUT"

# Cleanup marker file to prevent re-running the script in the same VM
rm -f "$MARKER"