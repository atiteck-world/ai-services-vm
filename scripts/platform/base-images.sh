#!/bin/bash
set -euo pipefail

MARKER=/etc/ai-base-build
BASE=/opt/ai-services
SPEC=/tmp/images.json

if [ ! -f "$MARKER" ]; then
    echo "ERROR: $MARKER not found. This script only runs inside the AI Services base build VM."
    exit 1
fi

install -d -m 0755 "$BASE"
cp "$SPEC" "$BASE/images.json"

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT
python3 - "$BASE/images.json" > "$LIST" <<'EOF'
import json, sys
spec = json.load(open(sys.argv[1]))
for service, image in spec["images"].items():
    for state in ("vulnerable", "patched"):
        if image.get(state):
            print(service, state, f"{image['repository']}:{image[state]}")
EOF

while read -r service state image; do
    echo "Pulling $image ($service, $state)"
    for try in 1 2 3; do
        if docker pull -q "$image"; then
            break
        fi
        if [[ $try -eq 3 ]]; then
            echo "Failed to pull $image after 3 attempts, aborting."
            exit 1
        fi
        echo "Failed to pull $image, retrying in 30 seconds (attempt $try of 3)..."
        sleep 30
    done
done < "$LIST"

python3 - "$LIST" "$BASE/images.lock" <<'EOF'
import json, sys, subprocess
lock = {}
for line in open(sys.argv[1]):
    service, state, image = line.strip().split()
    out = subprocess.run(["docker", "image", "inspect", image], capture_output=True, text=True, check=True)

    info = json.loads(out.stdout)[0]
    lock.setdefault(service, {})[state] = {
        "image": image,
        "id": info["Id"],
        "repo_digests": info.get("RepoDigests", []),
        "size_mb": round(info["Size"] / 1048576),
    }
print(json.dumps(lock, indent=2))
EOF

echo "Base images pulled and locked in $BASE/images.lock"
cat "$BASE/images.lock"