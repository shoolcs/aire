# aire

Course lab repository for **AI infrastructure on Kubernetes**: local clusters, gateways, agents, models, and MCP tools.

The cluster and base stack are provisioned in the companion repo **[abox](https://github.com/den-vasyliev/abox)** (`make run` — KinD, Flux, agentgateway, kagent). **aire** holds lab manifests and scripts applied on top of that stack.

---

## Repository layout


| Path                        | Description                                         |
| --------------------------- | --------------------------------------------------- |
| `[lab-2/](lab-2/README.md)` | Lab 2: local model (Ollama), kagent, Kubernetes MCP |
| `run.sh`                    | Run Lab 2 (model + agent) from the repo root        |


New labs are added as `lab-N/` directories, each with its own `README.md`.

---

## Prerequisites (general)

- A running **abox** cluster (`make run` in the abox repo)
- **kubectl** with cluster access (context e.g. `kind-abox`)
- **Docker** on the host (for local models in the relevant labs)
- Optional GPU: NVIDIA driver + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

On the lab machine, the KinD API is often available at `127.0.0.1:38885` (see `docker ps` for the control-plane port mapping).

Remote access: SSH tunnel to the API port + kubeconfig with `server: https://127.0.0.1:<port>`.

---

## Labs


| Lab       | Topic                                              | Documentation                      |
| --------- | -------------------------------------------------- | ---------------------------------- |
| **Lab 2** | Ollama + ModelConfig + declarative Agent + K8s MCP | [lab-2/README.md](lab-2/README.md) |


Quick start for Lab 2 (after abox is up):

```bash
bash run.sh
```

---

