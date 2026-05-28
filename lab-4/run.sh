#!/bin/bash
set -euo pipefail

#DOCKER_REGISTRY="yourregistry"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

git clone https://github.com/den-vasyliev/agentregistry-inventory.git $SCRIPT_DIR/inventory/agentregistry-inventory || true
cd $SCRIPT_DIR/inventory/agentregistry-inventory
echo "==> Installing AgentRegistry..."
helm upgrade --install agentregistry-inventory ./charts/agentregistry -n agentregistry --create-namespace
echo "==> AgentRegistry installed"

kubectl apply -f $SCRIPT_DIR/inventory/inventory-autodiscover.yaml
echo "==> Inventory autodiscover applied"


##### MCP Governance #####
# # Build
# cd $SCRIPT_DIR/mcpg/mcp-security-governance/
# docker build -t $DOCKER_REGISTRY/mcp-governance-controller:latest --platform linux/amd64 ./controller
# docker build -t $DOCKER_REGISTRY/mcp-governance-dashboard:latest --platform linux/amd64 ./dashboard

# # Push
# docker push $DOCKER_REGISTRY/mcp-governance-controller:latest
# docker push $DOCKER_REGISTRY/mcp-governance-dashboard:latest




echo "==> Installing MCP Governance..."
git clone https://github.com/techwithhuz/mcp-security-governance.git "${SCRIPT_DIR}/mcpg/mcp-security-governance" 2>/dev/null || true
cd "${SCRIPT_DIR}/mcpg/mcp-security-governance"

# Helm does not upgrade CRDs on `helm upgrade` — re-apply so fields like spec.aiAgent exist
echo "==> Upgrading MCP Governance CRDs..."
kubectl apply -f ./charts/mcp-governance/crds/

helm upgrade --install mcp-governance ./charts/mcp-governance \
  --create-namespace \
  --namespace mcp-governance \
  --set controller.image.repository=$DOCKER_REGISTRY/mcp-governance-controller \
  --set controller.image.pullPolicy=Always \
  --set dashboard.image.repository=$DOCKER_REGISTRY/mcp-governance-dashboard \
  --set dashboard.image.pullPolicy=Always \
  --set dashboard.service.type=ClusterIP \
  --set dashboard.service.nodePort=null \
  --set samples.install=true 
echo "==> MCP Governance installed"

kubectl apply -f $SCRIPT_DIR/mcpg/mcp-governance-policy.yaml
echo "==> MCP Governance policy applied"



#################### QDRANT ####################
helm repo add qdrant https://qdrant.github.io/qdrant-helm
helm repo update
helm upgrade -i qdrant qdrant/qdrant --namespace qdrant --create-namespace
echo "==> QDRANT installed"
