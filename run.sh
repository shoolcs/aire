#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${ROOT}/lab-2/models/run.sh"
bash "${ROOT}/lab-2/agents/run.sh"
