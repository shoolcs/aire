# Lab 7 — Vin's Questions (AI infrastructure research)

[← Back to aire](../README.md)

## Goals

Answer **15 architecture questions** about agent reliability, gateways, versioning, MCP, FinOps, and inference — mapped to the **abox + aire** stack (KinD, Flux, agentgateway, kagent, Ollama).

This lab is **documentation only** (no `run.sh`). Use it after **[Lab 2](../lab-2/README.md)** and optionally **[Lab 4](../lab-4/README.md)**.

---

## Disclaimer

Answers are based on **public docs, kagent/agentgateway CRDs, and course cluster behavior** — not every path is validated on every cluster revision. Where noted, run `kubectl explain` on your installed CRDs before applying YAML. Treat production hardening (timeouts, failover, FinOps) as **follow-up work**, not something abox enables by default.

### Verification status (2026-05-27)

Checked against **kagent v0.7.23** ([`agent_types.go`](https://github.com/kagent-dev/kagent/blob/v0.7.23/go/api/v1alpha2/agent_types.go), [`modelconfig_types.go`](https://github.com/kagent-dev/kagent/blob/v0.7.23/go/api/v1alpha2/modelconfig_types.go), [`remotemcpserver_types.go`](https://github.com/kagent-dev/kagent/blob/v0.7.23/go/api/v1alpha2/remotemcpserver_types.go)), **abox** [`releases/kagent.yaml`](https://github.com/den-vasyliev/abox/blob/main/releases/kagent.yaml) / [`agentgateway.yaml`](https://github.com/den-vasyliev/abox/blob/main/releases/agentgateway.yaml), **agentgateway v2.2.1** docs, and **aire** Lab 2/4 manifests.

| Claim | Status |
|-------|--------|
| abox pins kagent **0.7.23**, agentgateway **v2.2.1** | **Confirmed** in abox HelmReleases |
| No `version` / run timeout on `Agent` CRD | **Confirmed** — `AgentStatus` only `observedGeneration` + `conditions` |
| `RequireApproval` on MCP tools | **Confirmed** — `McpServerTool.requireApproval` |
| `RemoteMCPServer.spec.timeout` | **Confirmed** — `*metav1.Duration` |
| Ollama `ModelConfig` has no timeout | **Confirmed** — `OllamaConfig` only `host` + `options` |
| OpenAI `ModelConfig` has `openAI.timeout` | **Confirmed** — `*int` on `OpenAIConfig` |
| `max_llm_calls` default **500** (ADK) | **Confirmed** — [ADK RunConfig](https://adk.dev/runtime/runconfig/) |
| `max_llm_calls` on `Agent` CRD | **Not exposed** — ADK/kagent runtime only |
| Controller `streaming.timeout` **600s** | **Confirmed** — kagent Helm `controller.streaming.timeout` |
| `AgentgatewayBackend.spec.ai.groups` failover | **Confirmed** — [agentgateway failover docs](https://agentgateway.dev/docs/kubernetes/main/llm/failover/) |
| `AgentgatewayPolicy` timeouts + backend health eviction | **Confirmed** — official docs |
| Metric `agentgateway_gen_ai_client_token_usage` | **Confirmed** — [cost tracking docs](https://agentgateway.dev/docs/kubernetes/latest/llm/cost-tracking/) |
| Lab 4 `requireAgentGateway: true` | **Confirmed** — [`mcp-governance-policy.yaml`](../lab-4/mcpg/mcp-governance-policy.yaml) |
| Lab 2 direct Ollama, MCP not via gateway | **Confirmed** — [`modelconfig.yaml`](../lab-2/models/modelconfig.yaml), `RemoteMCPServer` to `kagent-tools` |
| `ConnectionSafeMcpTool` in kagent 0.7.23 | **Unverified** — landed in [PR #1531](https://github.com/kagent-dev/kagent/pull/1531); check release notes / image tag |
| Example `AgentgatewayPolicy` retry block | **Verify** — run `kubectl explain agentgatewaypolicy.spec.traffic.retry` on cluster |
| Canary YAML targeting per-agent Services | **Partial** — abox routes `/api` → `kagent-controller:8083`; see Q7 |
| `ModelConfig.maxTokens` (top-level) | **Incorrect name** — use provider blocks (`openAI.maxTokens`, `anthropic.maxTokens`, …) |
| `first-agent` field `runtime: python` | **Not in CRD** — not in `DeclarativeAgentSpec` v0.7.23; may be stripped or rejected |

---

## Prerequisites

| Item | Notes |
|------|--------|
| [abox](https://github.com/den-vasyliev/abox) | `make run` — agentgateway v2.2.1, kagent 0.7.23 |
| [Lab 2](../lab-2/README.md) | `ModelConfig` → Ollama, `first-agent`, `RemoteMCPServer` |
| [Lab 4](../lab-4/README.md) | MCP governance, inventory (optional context) |

**Current lab posture:** one local model, MCP often **not** routed through agentgateway → governance may flag `requireAgentGateway: true`.

---

# A. Agent reliability

## 1. How could we handle "agent got stuck" scenarios?

**There is no kagent-native knob** on the `Agent` CRD for `maxIterations`, wall-clock `timeout`, or termination conditions (`DeclarativeAgentSpec` exposes `systemMessage`, `modelConfig`, `tools`, `stream`, `a2aConfig`, deployment fields — not run limits).

What bounds a run, layer by layer:

| Layer | Mechanism | Action for this course |
|-------|-----------|-------------------------|
| **ADK runtime** | `max_llm_calls` per run (default **500**); exceeding → `LlmCallsLimitExceededError`. **Not** on `Agent` CRD — ADK/kagent runtime only. No per-tool wall-clock timeout in ADK. | Avoid flaky MCP (retry loops burn the cap — [kagent#1531](https://github.com/kagent-dev/kagent/pull/1531)). |
| **Gateway** | **Real backstop** for hung model/MCP: request/backend timeouts on routes in front of LLM and MCP. | Not applied in abox today — highest-value hardening. |
| **MCP connect** | Python ADK default **5s** MCP session timeout; sidecar `MCPServer` cold starts often exceed it ([#1272](https://github.com/kagent-dev/kagent/issues/1272)). | Set `spec.timeout` on **`RemoteMCPServer`** (Lab 2: `kagent-tool-server`). |
| **Streaming / A2A** | `STREAMING_TIMEOUT` (default **600s**) on controller; MCP `invoke_agent` should use same ([PR #1617](https://github.com/kagent-dev/kagent/pull/1617)). | Tune Helm `controller.streaming.timeout` if agents time out in UI. |
| **Human gate** | `requireApproval` + `ask_user` for destructive tools ([HITL](https://kagent.dev/docs/kagent/examples/human-in-the-loop)). | Add `k8s_apply_manifest` / delete tools to `requireApproval` on `first-agent`. |
| **Kubernetes** | kagent renders a `Deployment` → **liveness probe**, `activeDeadlineSeconds` on Jobs, resource limits. | Patch deployment if runaway CPU from MCP retry loops. |

**Recommendation:** Treat stuck agents as a **transport** problem — gateway timeouts first, then MCP timeouts, then ADK/HITL.

---

## 2. Any automatic timeout / circuit breaker patterns from this framework?

**Not from kagent** — no retry/circuit-breaker fields on `Agent`. `ModelConfig` may expose provider-specific timeouts (e.g. OpenAI); **Ollama `ModelConfig` in Lab 2 has no timeout field**.

**From agentgateway (resilience layer), yes:**

- **Timeouts** — request timeout (full client lifecycle) and backend-request timeout via `HTTPRoute.spec.rules[].timeouts` or `AgentgatewayPolicy.spec.traffic.timeouts`.
- **Retries** — `attempts`, `backoff`, `codes` on route or policy.
- **Circuit-breaker equivalent** — **health eviction** on backends (`AgentgatewayPolicy.spec.backend.health` + CEL `unhealthyCondition`, e.g. `429` / `5xx`), not a separate Envoy circuit-breaker CRD in all chart versions.

```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata:
  name: llm-resilience
  namespace: kagent
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: kagent          # abox HTTPRoute in namespace kagent
  traffic:
    timeouts:
      request: 120s
    # retry: verify shape with kubectl explain agentgatewaypolicy.spec.traffic.retry
  backend:
    health:
      unhealthyCondition: "response.code == 429 || response.code >= 500"
      eviction:
        duration: 30s
        consecutiveFailures: 2
```

**State of abox cluster:** agentgateway does **path routing only** — no resilience policies applied yet. Gateway resource is `agentgateway-external`; dataplane Deployment is typically `agentgateway-proxy` (docs often use that name).

**Note:** `backend.health` targets an **LLM `AgentgatewayBackend`** in failover guides; for the kagent HTTPRoute example above, confirm `targetRefs` and policy scope with `kubectl explain` — MCP/LLM backends may need separate policies.

---

# B. Model routing & failover

## 3. How does kgateway handle model failover?

**abox ships agentgateway**, not kgateway AI routes. In **kgateway** mainline, Envoy **AI policy on TrafficPolicy is being removed** ([PR #12901](https://github.com/kgateway-dev/kgateway/pull/12901)).

**Failover today = agentgateway:**

1. `AgentgatewayBackend` with **`spec.ai.groups`** — ordered priority tiers.
2. `AgentgatewayPolicy` with **backend health** — evict unhealthy providers/models.
3. Next request uses the next group when the current tier is evicted.

Confirm CRD generation: `kubectl get crd | grep -E 'agentgateway|kgateway'` → expect `agentgateway.dev/v1alpha1` (`AgentgatewayBackend`, `AgentgatewayPolicy`).

[agentgateway failover docs](https://agentgateway.dev/docs/kubernetes/main/llm/failover/)

---

## 4. Can we automatically switch from OpenAI → Claude → local model?

**Yes — at the gateway**, not inside one `ModelConfig`.

Each kagent `ModelConfig` = **one** provider. Automatic switch = **`AgentgatewayBackend` groups** (OpenAI tier → Anthropic tier → OpenAI-compatible **local** vLLM/Ollama endpoint) + point kagent at the gateway:

```yaml
# Illustrative — verify fields with: kubectl explain agentgatewaybackend.spec
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata:
  name: llm-failover
  namespace: agentgateway-system
spec:
  ai:
    groups:
      - providers:
          - name: openai-primary
            openai:
              model: gpt-4.1
            policies:
              auth:
                secretRef:
                  name: openai-secret
      - providers:
          - name: anthropic-fallback
            anthropic:
              model: claude-sonnet-4-6
            policies:
              auth:
                secretRef:
                  name: anthropic-secret
      - providers:
          - name: local-ollama
            openai:
              model: qwen2.5:7b
              # OpenAI-compatible self-hosted endpoint — exact host/port/auth fields
              # depend on chart version; verify with kubectl explain
```

**Lab 2 today:** `spec.ollama.host` → **no** gateway failover until `ModelConfig` uses `openAI.baseUrl` (or equivalent) aimed at agentgateway.

**Verify** multi-provider + local tier YAML against your chart: `kubectl explain agentgatewaybackend.spec.ai.groups`

---

## 5. Could we seamlessly handle response formats from these providers?

**Mostly yes** via **OpenAI-compatible façade**: client sends `POST /v1/chat/completions`; gateway translates to Anthropic/Gemini/Bedrock/etc.

**Limits:** tool-call JSON shapes, streaming `usage`, and provider-only features (PDF, native Messages API) may need per-provider `ModelConfig` or passthrough routes. **Do not mix providers mid-session** without gateway normalization.

**Verdict:** Seamless for standard chat + tool loops through one gateway endpoint; verify each endpoint you enable.

---

# C. Agent lifecycle

## 6. Can we version the agents built from kagent?

**No `spec.version` on `Agent` CRD** — versioning is operational:

| Layer | How |
|-------|-----|
| **Git / manifests** | `lab-2/agents/first-agent.yaml` in git; PR review = version control |
| **CRD names** | `first-agent` vs `first-agent-v2` as separate resources |
| **ModelConfig** | Pin `spec.model` (e.g. `qwen2.5:7b`) — model change = behavior change |
| **BYO agents** | Container **image tag** = version |
| **A2A AgentCard** | Protocol `version` on the published Agent Card (skills live under `spec.declarative.a2aConfig.skills` — no `version` field on `A2AConfig` in kagent v0.7.23) |

**Recommendation:** git commit / tag = release version; keep Agent name stable or suffix `-v2` for breaking changes.

---

## 7. Any blue/green or canary deployment patterns for agents?

**Nothing kagent-native** — kagent renders `Deployment` + `Service` per declarative agent, but **abox routes all `/api` traffic to `kagent-controller:8083`**, which serves A2A at `/api/a2a/<namespace>/<agent>/`. Weighted canary on per-agent Services only works if you add routes that target those Services **and** they expose the same protocol/port the gateway expects.

**Practical patterns:**

| Pattern | Works with abox default route? |
|---------|-------------------------------|
| GitOps replace `Agent` manifest (new image / prompt) | **Yes** — simplest |
| Second `Agent` CR (`first-agent-v2`) + new A2A URL | **Yes** — clients choose URL |
| Weighted `HTTPRoute` to two agent Services | **Requires custom routes** — not the stock `kagent` HTTPRoute |
| BYO agent Deployment + weighted `backendRefs` | **Yes** — you own Service ports |

**Caveat:** A2A sessions are **stateful** — naive weight splitting can mix versions in one conversation; prefer **new sessions only** or session affinity.

[agentgateway traffic split](https://agentgateway.dev/docs/kubernetes/latest/traffic-management/traffic-split/)

---

# D. MCP tooling

## 8. What's the fastmcp-python framework?

**[FastMCP](https://gofastmcp.com)** — Python framework for MCP servers/clients; tools via decorators + type hints → JSON Schema.

```python
from fastmcp import FastMCP

mcp = FastMCP("Demo")

@mcp.tool
def add(a: int, b: int) -> int:
    """Add two numbers."""
    return a + b

if __name__ == "__main__":
    mcp.run()  # stdio default; or transport="http"
```

- **FastMCP 1.0** → core merged into official MCP Python SDK.
- **FastMCP 2.x/3.x** — standalone PyPI package (`pip install fastmcp`) with clients, auth, composition.

---

## 9. Is it the easiest path to MCP?

| Path | When |
|------|------|
| **RemoteMCPServer** (URL) | Easiest when a server already exists — **Lab 2** `kagent-tool-server` |
| **kagent `MCPServer` CRD** | Packaged stdio tools (`uvx`/`npx`) + agentgateway sidecar |
| **FastMCP** | Easiest for **custom Python** tools you author |
| **[kmcp](https://github.com/kagent-dev/kmcp)** | Scaffold → build → deploy `MCPServer` CR (stdio→HTTP bridge) |

**Authoring (Python):** FastMCP is the fastest. **Deploying on KinD:** Remote URL or `MCPServer` CRD before writing your own FastMCP server unless you need custom logic.

---

# E. FinOps

## 10. How much control can I have?

**Strong at agentgateway** (token/request limits, metrics, virtual keys); **weak on direct Ollama** (no cloud token bill — CapEx/GPU only).

| Layer | Control |
|-------|---------|
| **agentgateway** | `agentgateway_gen_ai_client_token_usage` metrics; token rate limits; budgets ([docs](https://agentgateway.dev/docs/kubernetes/main/llm/budget-limits/)) |
| **kagent** | Model choice, tool count; `max_llm_calls` via ADK (not Agent CRD) |
| **Lab 4 governance** | Policy scoring (`requireAgentGateway`, tool limits) — **governance, not billing** |

**No native $-budget** — convert tokens → cost in PromQL/dashboards.

**Lab 2 gap:** LLM traffic bypasses gateway → **no gateway FinOps** until ModelConfig points at agentgateway.

---

## 11. Token level / per agent level

- **Token level:** `AgentgatewayPolicy` → `traffic.rateLimit.local[].tokens` + `unit`; global RLS with `unit: Tokens`.
- **Per agent:** requires **per-agent HTTPRoute** or descriptor on `x-agent-id` / virtual key metadata — not automatic from `Agent` metadata alone.

---

## 12. Can I implement custom cost controls?

Yes — compose:

- Token rate limits (local/global)
- **Cost-based failover** (cheap models in tier 1 — [failover docs](https://agentgateway.dev/docs/kubernetes/main/llm/failover/))
- **promptGuard** / guardrails before model call
- ADK `max_llm_calls` + Lab 4 **MCPGovernancePolicy** ([`mcp-governance-policy.yaml`](../lab-4/mcpg/mcp-governance-policy.yaml))

---

## 13. Per-agent budgets or depth of token limits

- **Per-agent budget:** virtual keys — `apiKeyAuthentication` + global rate limit on `agent_id` metadata ([virtual keys](https://agentgateway.dev/docs/kubernetes/latest/llm/virtual-keys/)).
- **Depth:** (a) provider `maxTokens` (e.g. `spec.openAI.maxTokens`, `spec.anthropic.maxTokens` — **not** on Ollama); (b) ADK `max_llm_calls` per task (caps tool-loop cost).

---

# F. Inference serving (forward-looking)

## 14. Is vLLM suitable for agents with many back-and-forth tool calls, or single-shot?

**Both** — multi-turn agent loops are a main vLLM use case with **prefix caching** (stable growing prefix across tool turns; `--enable-prefix-caching` in vLLM V1). Each tool round is usually a **new HTTP request** → 15 tools ≈ 15 inference calls.

| Workload | Fit |
|----------|-----|
| Multi-turn + tools | Good with cache affinity + enough GPU memory |
| Single-shot / batch | Sweet spot for capacity planning |
| **Ollama (Lab 2)** | Fine for low concurrency; vLLM for throughput / multi-replica |

---

## 15. Does llm-d's scheduler help when an agent makes ~15 LLM calls?

**Yes** — for **self-hosted vLLM pools** behind Gateway API Inference Extension (EPP schedules by **KV-cache locality**, queue depth, session affinity). It **does not** reduce the number of agent LLM calls — that's ADK/prompt design.

**Not for:** direct OpenAI/Anthropic API (use agentgateway failover instead).

**abox today:** no InferencePool/EPP — forward-looking after vLLM replicas exist.

[llm-d inference scheduler](https://github.com/llm-d/llm-d-inference-scheduler)

---

## Gap summary (abox + aire)

| Concern | Today (after Lab 2/4) | To add |
|---------|----------------------|--------|
| Stuck / hung agents | MCP 5s risk; no gateway timeouts | `AgentgatewayPolicy` timeouts + retries; `RemoteMCPServer.timeout` |
| Failover (Q3–5) | Direct Ollama | `AgentgatewayBackend.groups`; ModelConfig → gateway |
| Versioning (Q6) | Git manifests | Tags + optional A2A `version` |
| Canary (Q7) | Single agent route | Weighted `HTTPRoute`; second `Agent` CR |
| FinOps (Q10–13) | Governance scoring only | Gateway token limits + metrics |
| Inference (Q14–15) | Host Ollama | vLLM + llm-d behind gateway (Phase 2) |

---

## Verify on your cluster

```bash
kubectl get crd | grep -E 'agentgateway|kagent'
kubectl explain agentgatewaybackend.spec.ai
kubectl explain agent.kagent.dev --api-version=kagent.dev/v1alpha2
kubectl get agent,modelconfig,remotemcpserver -n kagent
```

1. Confirm **agentgateway** CRD names match YAML in this doc.
2. Confirm kagent image includes `ConnectionSafeMcpTool` ([PR #1531](https://github.com/kagent-dev/kagent/pull/1531)) and set `RemoteMCPServer.spec.timeout` (e.g. `30s`).
3. Lab 4 governance: route MCP through agentgateway if `requireAgentGateway: true`.
4. Drop or fix `runtime: python` on [`first-agent.yaml`](../lab-2/agents/first-agent.yaml) if API server rejects unknown fields.

---

## Primary sources

- [agentgateway — failover](https://agentgateway.dev/docs/kubernetes/main/llm/failover/) · [rate limit](https://agentgateway.dev/docs/kubernetes/latest/llm/rate-limit/) · [virtual keys](https://agentgateway.dev/docs/kubernetes/latest/llm/virtual-keys/) · [timeouts](https://agentgateway.dev/docs/kubernetes/latest/resiliency/timeouts/request/)
- [kagent docs](https://kagent.dev/docs) · [HITL](https://kagent.dev/docs/kagent/examples/human-in-the-loop) · [kmcp](https://github.com/kagent-dev/kmcp)
- [Google ADK RunConfig](https://google.github.io/adk-docs/runtime/runconfig/)
- [FastMCP](https://gofastmcp.com) · [vLLM prefix caching](https://docs.vllm.ai/en/latest/features/automatic_prefix_caching.html) · [llm-d](https://llm-d.ai/)
- Course: [Lab 2](../lab-2/README.md) · [Lab 4](../lab-4/README.md) · [abox CODEBASE](https://github.com/den-vasyliev/abox/blob/main/CODEBASE.md)

**Reference lab (EKS variant):** [vidovgopol/abox-eks lab7.md](https://github.com/vidovgopol/abox-eks/blob/main/lab7/lab7.md)
