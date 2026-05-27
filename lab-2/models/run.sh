#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLLAMA_NAME="${OLLAMA_NAME:-ollama}"
OLLAMA_IMAGE="${OLLAMA_IMAGE:-ollama/ollama}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:7b}"

echo "==> Applying ModelConfig..."
kubectl apply -f "${SCRIPT_DIR}/modelconfig.yaml"

echo "==> Ensuring Ollama container (${OLLAMA_NAME})..."
if docker ps -a --format '{{.Names}}' | grep -qx "${OLLAMA_NAME}"; then
  if ! docker ps --format '{{.Names}}' | grep -qx "${OLLAMA_NAME}"; then
    docker start "${OLLAMA_NAME}"
  fi
else
  docker run -d --name "${OLLAMA_NAME}" --gpus all \
    -p 11434:11434 \
    -v ollama_data:/root/.ollama \
    --restart unless-stopped \
    "${OLLAMA_IMAGE}"
fi

echo "==> Waiting for Ollama API..."
for _ in $(seq 1 60); do
  if curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -sf http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "ERROR: Ollama API not reachable at http://127.0.0.1:11434" >&2
  exit 1
fi

echo "==> Pulling model ${OLLAMA_MODEL}..."
docker exec "${OLLAMA_NAME}" ollama pull "${OLLAMA_MODEL}"

echo "==> Ollama models:"
curl -sS http://127.0.0.1:11434/api/tags
echo
echo "Done. ModelConfig applied; ${OLLAMA_MODEL} ready."

# nvidia-smi — optional: verify GPU usage while a model is loaded
