#!/bin/bash
# Aplica todos os manifests da mini AI Factory na ordem correta.
# Rode dentro do WSL como root:
#   wsl -u root bash /mnt/c/Users/Steph/ai-factory/k8s/apply-all.sh
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
DIR="$(cd "$(dirname "$0")" && pwd)"
for f in 00-runtimeclass 01-timeslicing-config 02-device-plugin 03-ollama 04-litellm; do
  echo "== aplicando $f.yaml =="
  sed 's/\r$//' "$DIR/$f.yaml" | k3s kubectl apply -f -   # sed remove CR (arquivos vem do Windows)
done
echo ""
echo "== estado =="
k3s kubectl get nodes -o "jsonpath={.items[0].metadata.name}{': nvidia.com/gpu='}{.items[0].status.capacity.nvidia\.com/gpu}{\"\n\"}"
k3s kubectl get deploy,svc -l app=ollama
echo ""
echo "Testar inferencia:  curl http://localhost:31434/api/generate -d '{\"model\":\"qwen2.5:1.5b\",\"prompt\":\"ola\",\"stream\":false}'"
