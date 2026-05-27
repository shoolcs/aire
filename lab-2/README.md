# Lab 2 — Local model + kagent + MCP (Kubernetes tools)

[← Back to aire](../README.md)

## Goals

1. Run a **local LLM** (Ollama + `qwen2.5:7b`) on the host.
2. Register it in the cluster as a kagent `**ModelConfig`**.
3. Deploy a **declarative `Agent`** that uses the model and calls **MCP tools** for Kubernetes (`kagent-tool-server`).

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Host (Ubuntu + Docker + GPU, e.g. RTX 4070)                │
│  Ollama :11434  ←── ModelConfig (provider: Ollama)          │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTP (host LAN IP, not 127.0.0.1)
┌───────────────────────────▼─────────────────────────────────┐
│  KinD / abox cluster                                        │
│  agentgateway (Gateway :80) ──► kagent UI /api              │
│  kagent-controller ──► Agent "first-agent"                  │
│       └── MCP ──► RemoteMCPServer "kagent-tool-server"      │
│                    └── kagent-tools (k8s_* tools)           │
└─────────────────────────────────────────────────────────────┘
```

---

## Lab 2 layout


| Path                      | Purpose                                            |
| ------------------------- | -------------------------------------------------- |
| `models/modelconfig.yaml` | `ModelConfig` → Ollama, model `qwen2.5:7b`         |
| `models/run.sh`           | Apply ModelConfig; start/pull Ollama               |
| `agents/first-agent.yaml` | Declarative agent + K8s MCP tool allow-list        |
| `agents/run.sh`           | Apply the Agent                                    |
| `screenshots/`            | Lab evidence (KinD, Flux, gateway, kagent, Ollama) |


**Important:** in `models/modelconfig.yaml`, `spec.ollama.host` must be reachable **from kagent pods** (host LAN IP, e.g. `http://192.168.88.32:11434`, not `127.0.0.1`).

---

## MCP tools on `first-agent`

The agent references `RemoteMCPServer/kagent-tool-server` (from the kagent Helm chart) and allows:

- `k8s_get_resources`
- `k8s_get_cluster_configuration`
- `k8s_get_available_api_resources`
- `k8s_describe_resource`
- `k8s_check_service_connectivity`

In the manifest this is `spec.declarative.tools` with `type: McpServer`.

---

## Quick start

Prerequisite: **abox** is already running (`make run`).

```bash
cd aire   # repository root

# 1. Set the host IP for Ollama
vim lab-2/models/modelconfig.yaml

# 2. Model + agent
bash run.sh
```

Step by step:

```bash
bash lab-2/models/run.sh
bash lab-2/agents/run.sh
```

---

## Verify

```bash
kubectl get modelconfig,agent -n kagent
kubectl get remotemcpserver -n kagent
kubectl get gateway,httproute -A
kubectl get svc -n agentgateway-system
```

Open the **kagent UI** via the gateway LoadBalancer (KinD + cloud-provider-kind often exposes host port `32768`):

```bash
curl -I http://127.0.0.1:32768/
```

In the UI, select **first-agent** and ask about the cluster (e.g. pods in `kagent`, Gateway status).

---

## Environment variables (`models/run.sh`)


| Variable       | Default         | Description             |
| -------------- | --------------- | ----------------------- |
| `OLLAMA_NAME`  | `ollama`        | Docker container name   |
| `OLLAMA_IMAGE` | `ollama/ollama` | Ollama image            |
| `OLLAMA_MODEL` | `qwen2.5:7b`    | Model for `ollama pull` |


---

## Troubleshooting


| Issue                         | What to check                                                                                   |
| ----------------------------- | ----------------------------------------------------------------------------------------------- |
| `unknown field "spec.url"`    | In v1alpha2 use `spec.ollama.host`, not `spec.url`                                              |
| Agent cannot reach Ollama     | From a pod: `curl http://<host-ip>:11434/api/tags`                                              |
| MCP tools not invoked         | `kubectl get remotemcpserver kagent-tool-server -n kagent`; model must support function calling |
| `docker: name already in use` | `docker rm -f ollama`, then re-run `lab-2/models/run.sh`                                        |
| `too many open files` (KinD)  | Increase `fs.inotify.max_user_watches` and `ulimit -n` on the host                              |


---

## Screenshots

The `screenshots/` directory includes:

- KinD / abox cluster
- Flux
- agentgateway
- kagent UI
- local model (Ollama)

---

## References

- [kagent — Ollama provider](https://www.kagent.dev/docs/kagent/supported-providers/ollama)
- [kagent — first MCP tool](https://kagent.dev/docs/kagent/getting-started/first-mcp-tool)

