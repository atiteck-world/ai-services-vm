#!/bin/bash
# This script downloads the models into the base image, so a student VM needs no internet at runtime
#   - the chat model (TinyLlama)
#   - Open WebUI's built-in embedding model
# and writes /opt/ai-services/models.lock.
#
# Runs only inside the disposable base build VM (marker /etc/ai-base-build).
# Every temporary container binds its port to 127.0.0.1 and is removed afterwards.
set -euo pipefail

MARKER=/etc/ai-base-build
BASE=/opt/ai-services

if [[ ! -f "$MARKER" ]]; then
    echo "ERROR: $MARKER not found. This script only runs inside the AI Services base build VM." >&2
    exit 1
fi

# Read values from images.json and images.lock (written by base-images.sh)
spec()  { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$BASE/images.json" "$1"; }
image() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]][sys.argv[3]]["image"])' \
              "$BASE/images.lock" "$1" "$2"; }

CHAT_MODEL=$(spec chat_model)
EMBED_MODEL=$(spec embedding_model)
SHARED=$BASE/models/ollama
CACHE=$BASE/cache/open-webui

# Temporary containers and volume, removed on every exit (also after an error)
cleanup() {
    docker rm -f build-ollama build-webui >/dev/null 2>&1 || true
    docker volume rm build-webui-data >/dev/null 2>&1 || true
}
trap cleanup EXIT

# wait_for <url> <seconds>
wait_for() {
    local url=$1 limit=$2 start=$SECONDS
    until curl -s -o /dev/null --max-time 5 "$url"; do
        if (( SECONDS - start > limit )); then
            echo "ERROR: no answer from $url after $limit s" >&2
            return 1
        fi
        sleep 5
    done
    echo "  ready after $(( SECONDS - start )) s"
}

# ---- Chat model ------------------------------------------------------------------------

# ollama_up <state> <model folder>
ollama_up() {
    docker rm -f build-ollama >/dev/null 2>&1 || true
    docker run -d --name build-ollama -p 127.0.0.1:11434:11434 \
        -v "$2:/root/.ollama" "$(image ollama "$1")" >/dev/null
    wait_for http://127.0.0.1:11434/api/tags 300
}
ollama_down() { docker rm -f build-ollama >/dev/null 2>&1 || true; }

pull_chat_model() {
    echo "  pulling $CHAT_MODEL"
    curl -sf --max-time 3600 http://127.0.0.1:11434/api/pull \
        -d "{\"name\": \"$CHAT_MODEL\", \"stream\": false}" >/dev/null
}

# Succeeds only if the model answers a short prompt with some text
answers_prompt() {
    curl -sf --max-time 900 http://127.0.0.1:11434/api/generate \
        -d "{\"model\": \"$CHAT_MODEL\", \"prompt\": \"Say hello.\", \"stream\": false}" |
        python3 -c 'import json,sys; t=json.load(sys.stdin)["response"].strip(); assert t; print("  answer:", t[:80])'
}

install -d -m 0755 "$SHARED"
declare -A MODEL_DIR

# Pull once with the older version: newer Ollama reads older model files more likely than the reverse
echo "Chat model: pulling with Ollama (vulnerable)"
ollama_up vulnerable "$SHARED"
pull_chat_model
ollama_down

for state in vulnerable patched; do
    echo "Chat model: checking Ollama ($state) with the shared folder"
    ollama_up "$state" "$SHARED"
    if answers_prompt; then
        MODEL_DIR[$state]=$SHARED
        ollama_down
    else
        ollama_down
        own=$BASE/models/ollama-$state
        echo "  Ollama ($state) cannot use the shared files, pulling into $own"
        install -d -m 0755 "$own"
        ollama_up "$state" "$own"
        pull_chat_model
        answers_prompt
        ollama_down
        MODEL_DIR[$state]=$own
    fi
done

# ---- Embedding model (Open WebUI will download it at its first start) ----------------------

install -d -m 0755 "$CACHE"
for state in vulnerable patched; do
    echo "Embedding model: first start of Open WebUI ($state)"
    docker rm -f build-webui >/dev/null 2>&1 || true
    docker volume rm build-webui-data >/dev/null 2>&1 || true
    docker run -d --name build-webui -p 127.0.0.1:3000:8080 \
        -e WEBUI_SECRET_KEY=base-build-only \
        -e RAG_EMBEDDING_MODEL="$EMBED_MODEL" \
        -v build-webui-data:/app/backend/data \
        -v "$CACHE:/app/backend/data/cache" \
        "$(image open_webui "$state")" >/dev/null
    wait_for http://127.0.0.1:3000/health 1800
    docker rm -f build-webui >/dev/null
    docker volume rm build-webui-data >/dev/null
done

if [[ -z "$(find "$CACHE" -type d -name "*${EMBED_MODEL##*/}*" -print -quit)" ]]; then
    echo "ERROR: embedding model $EMBED_MODEL not found in $CACHE" >&2
    exit 1
fi

# ---- Lock file ---------------------------------------------------------------------------

python3 - "$CHAT_MODEL" "${MODEL_DIR[vulnerable]}" "${MODEL_DIR[patched]}" "$EMBED_MODEL" "$CACHE" \
    > "$BASE/models.lock" <<'EOF'
import hashlib, json, os, sys
chat_model, dir_vulnerable, dir_patched, embed_model, cache = sys.argv[1:]
name, _, tag = chat_model.partition(":")

def manifest_sha256(folder):
    path = os.path.join(folder, "models", "manifests", "registry.ollama.ai", "library", name, tag or "latest")
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()

def size_mib(folder):
    total = sum(os.path.getsize(os.path.join(d, f)) for d, _, files in os.walk(folder) for f in files)
    return round(total / 1048576)

print(json.dumps({
    "chat_model": chat_model,
    "ollama_model_dirs": {"vulnerable": dir_vulnerable, "patched": dir_patched},
    "shared_between_versions": dir_vulnerable == dir_patched,
    "chat_model_manifest_sha256": {
        "vulnerable": manifest_sha256(dir_vulnerable),
        "patched": manifest_sha256(dir_patched),
    },
    "embedding_model": embed_model,
    "open_webui_cache_dir": cache,
    "open_webui_cache_mib": size_mib(cache),
}, indent=2))
EOF

echo "Models locked in $BASE/models.lock:"
cat "$BASE/models.lock"