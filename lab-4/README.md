# Lab 4 — Agent inventory, MCP governance, and Qdrant

[← Back to aire](../README.md)

## Goals

1. Deploy **Agent Registry / inventory** ([agentregistry-inventory](https://github.com/den-vasyliev/agentregistry-inventory)) on top of the abox cluster.
2. **Discover** kagent resources (Agents, ModelConfigs, MCP servers) via `DiscoveryConfig`.
3. Install **MCP security governance** ([mcp-security-governance](https://github.com/techwithhuz/mcp-security-governance)) and apply an enterprise policy.
4. Optionally run **Qdrant** for vector storage (Helm chart).

This lab builds on **[Lab 2](../lab-2/README.md)** (kagent + Ollama + `first-agent`) and the **[abox](https://github.com/den-vasyliev/abox)** stack (KinD, Flux, agentgateway, kagent).

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  abox cluster (KinD)                                             │
│  agentgateway :80 ──► kagent (UI, /api, A2A)                       │
│  kagent: Agent, ModelConfig, RemoteMCPServer (kagent-tool-server)│
├──────────────────────────────────────────────────────────────────┤
│  agentregistry namespace                                         │
│  agentregistry-inventory (Helm) ──► DiscoveryConfig              │
│       scans kagent NS: Agent, ModelConfig, MCPServer, RemoteMCP  │
├──────────────────────────────────────────────────────────────────┤
│  mcp-governance namespace                                        │
│  mcp-governance controller + dashboard                           │
│  MCPGovernancePolicy (enterprise-mcp-policy)                     │
│       evaluates MCP routing, agentgateway, hardening, skills     │
├──────────────────────────────────────────────────────────────────┤
│  qdrant namespace (optional)                                     │
│  Qdrant vector DB (Helm)                                         │
└──────────────────────────────────────────────────────────────────┘
         ▲
         │ Ollama (host) — optional AI scoring in governance policy
```

---

## Lab 4 layout


| Path                                    | Purpose                                                 |
| --------------------------------------- | ------------------------------------------------------- |
| `run.sh`                                | Install inventory, governance, Qdrant                   |
| `inventory/inventory-autodiscover.yaml` | `DiscoveryConfig` for kagent namespace                  |
| `mcpg/mcp-governance-policy.yaml`       | Cluster `MCPGovernancePolicy` (Ollama AI agent enabled) |
| `mcpg/mcp-security-governance/`         | Cloned governance repo (Helm chart + CRDs)              |
| `inventory/agentregistry-inventory/`    | Cloned inventory repo (Helm chart)                      |
| `screenshots/`                          | Lab evidence                                            |


---

## Prerequisites

- **abox** cluster running (`make run` in abox repo).
- **Lab 2** applied (`ModelConfig`, `first-agent`) — recommended so inventory and governance have real targets.
- **kubectl**, **helm**, **git**, **docker** (if building custom governance images).
- **Ollama** on the host if using `aiAgent` in the governance policy (see `mcpg/mcp-governance-policy.yaml`).
- Set `DOCKER_REGISTRY` in `run.sh` when using custom controller/dashboard images (build section is commented out by default).

---

## Quick start

From the repo root (with `KUBECONFIG` pointing at abox):

```bash
cd lab-4
# Optional: export DOCKER_REGISTRY=youruser   # if using custom images
bash run.sh
```

What `run.sh` does:

1. Clone & `helm upgrade --install` **agentregistry-inventory** → namespace `agentregistry`.
2. Apply **DiscoveryConfig** `local-cluster-discovery`.
3. Clone & install **mcp-governance** → namespace `mcp-governance` (applies CRDs, then Helm).
4. Apply **MCPGovernancePolicy** `enterprise-mcp-policy`.
5. Install **Qdrant** → namespace `qdrant`.

---

## Verify

### Agent registry / inventory

```bash
kubectl get pods -n agentregistry
kubectl get discoveryconfig -n agentregistry
kubectl get agentcatalogs,mcpservercatalogs,modelcatalogs -A
```

UI (if exposed by the chart): check the agentregistry service / ingress per chart defaults.

### MCP governance

```bash
kubectl get pods -n mcp-governance
kubectl get mcpgovernancepolicies -n mcp-governance
kubectl get governanceevaluations -A
```

Port-forward dashboard (if enabled):

```bash
kubectl -n mcp-governance port-forward svc/mcp-governance-dashboard 3000:3000
# open http://127.0.0.1:3000
```

### Qdrant

```bash
kubectl get pods -n qdrant
kubectl -n qdrant port-forward svc/qdrant 6333:6333
curl http://127.0.0.1:6333/
```

### kagent + A2A Agent Card (Lab 2)

With `first-agent` and `a2aConfig` from [Lab 2](../lab-2/agents/first-agent.yaml):

```bash
kubectl -n kagent port-forward svc/kagent-controller 8083:8083
curl -sS http://127.0.0.1:8083/api/a2a/kagent/first-agent/.well-known/agent-card.json | jq .
```

Via agentgateway:

```bash
curl -sS http://<gateway-ip>/api/a2a/kagent/first-agent/.well-known/agent-card.json | jq .
```

---

## Governance policy notes

`mcpg/mcp-governance-policy.yaml` enables strict checks, including:

- `requireAgentGateway: true` — MCP traffic should go through **agentgateway**.
- `aiAgent` with **Ollama** at `http://192.168.88.32:11434` — update the IP for your host.

You may see findings such as:

> `RemoteMCPServer 'kagent-tool-server' not routed through agentgateway`

That is **expected** for the default Lab 2 setup: `kagent-tool-server` points at `http://kagent-tools.kagent:8084/mcp` (direct in-cluster), not through the gateway. The agent still works; governance flags it as non-compliant until you add `AgentgatewayBackend` + routes or relax `requireAgentGateway`.

---

## Custom images (optional)

Uncomment the Docker build/push block in `run.sh` for `linux/amd64`:

```bash
docker buildx build --platform linux/amd64 -t $DOCKER_REGISTRY/mcp-governance-controller:latest --load ./controller
docker buildx build --platform linux/amd64 -t $DOCKER_REGISTRY/mcp-governance-dashboard:latest --load ./dashboard
docker push ...
```

Then set `DOCKER_REGISTRY` before `bash run.sh`.

---

## Troubleshooting


| Issue                                                      | What to do                                                                                                                                                            |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec.aiAgent: field not declared in schema`               | CRD schema outdated. Run `kubectl replace -f mcpg/mcp-security-governance/charts/mcp-governance/crds/mcpgovernancepolicies.yaml --force` then re-apply policy / Helm. |
| `kubectl apply -k .../config/crd` fails (no kustomization) | Use `kubectl apply -f ./charts/mcp-governance/crds/` not `-k`.                                                                                                        |
| Helm release name already exists                           | Use `helm upgrade --install`, not `helm install`.                                                                                                                     |
| Governance AI cannot reach Ollama                          | Fix `ollamaEndpoint` in policy; test `curl http://<host>:11434/api/tags` from a pod.                                                                                  |
| Inventory empty                                            | Confirm `DiscoveryConfig` namespaces include `kagent` and resources exist (`kubectl get agents,modelconfigs -n kagent`).                                              |
| Clone already exists                                       | Safe — `run.sh` uses `git clone ... || true`. `cd` into repo and `git pull` if you need latest.                                                                       |


---

## Screenshots

Store evidence under `screenshots/`:

- `inventory.png` — agent registry / inventory UI
- `mcp-governance.png` — governance dashboard
- `mcp-governance-log.png` — controller / evaluation logs
- `qdrant.png` — Qdrant deployment
- `agent-card.png` — A2A Agent Card (Well-Known URI)

---

## Related

- [Lab 2 — Ollama + kagent + MCP](../lab-2/README.md)

