#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Applying Agent..."
kubectl apply -f "${SCRIPT_DIR}/first-agent.yaml"
