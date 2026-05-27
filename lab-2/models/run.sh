#!/bin/bash
kubectl apply -f modelconfig.yaml -n kagent
docker run -d --name ollama --gpus all \
  -p 11434:11434 \
  -v ollama_data:/root/.ollama \
  --restart unless-stopped \
  ollama/ollama 
sleep 3
docker exec -it ollama ollama pull qwen2.5:7b && curl http://127.0.0.1:11434/api/tags && echo "Model pulled"
# nvidia-smi to check if the GPU is being used