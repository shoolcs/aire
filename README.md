# aire

Course lab repository for **AI infrastructure on Kubernetes**: local clusters, gateways, agents, models, and MCP tools.

The cluster and base stack are provisioned in the companion repo **[abox](https://github.com/den-vasyliev/abox)** (`make run` — KinD, Flux, agentgateway, kagent). **aire** holds lab manifests and scripts applied on top of that stack.

---

## Repository layout


| Path                        | Description                                         |
| --------------------------- | --------------------------------------------------- |
| `[lab-2/](lab-2/README.md)` | Lab 2: local model (Ollama), kagent, Kubernetes MCP |
| `[lab-4/](lab-4/README.md)` | Lab 4: agent inventory, MCP governance, Qdrant      |
| `run.sh`                    | Run Lab 2 (model + agent) from the repo root        |
| `lab-4/run.sh`              | Run Lab 4 (inventory + governance + Qdrant)         |


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
| **Lab 4** | Agent inventory + MCP governance + Qdrant          | [lab-4/README.md](lab-4/README.md) |


Quick start (after abox is up):

```bash
# Lab 2
bash run.sh

# Lab 4
bash lab-4/run.sh
```

---

