# Mini AI Factory — Kubernetes + GPU (k3s no WSL2)

Réplica em escala de 1 GPU de uma **AI Factory**: um LLM servido na GPU, orquestrado
por Kubernetes, exposto como serviço e com GPU compartilhada (fractional GPU).
Roda numa RTX 3050 6GB via k3s dentro do WSL2 (Ubuntu).

## Arquitetura (camadas de uma AI Factory)
| Camada | Componente aqui |
|---|---|
| Compute (GPU) | RTX 3050 (passthrough WSL2) |
| Runtime | NVIDIA Container Toolkit + runtime `nvidia` |
| Orquestração | k3s (Kubernetes 1 nó) |
| GPU agendável | NVIDIA device plugin (`nvidia.com/gpu`) |
| Fractional GPU | time-slicing (1 GPU → 4 fatias) — análogo do Run:ai |
| Inferência/serving | Ollama (Deployment) |
| Endpoint | Service NodePort `:31434` (a "API de tokens") |
| Observabilidade | Prometheus + Grafana (no host, lê a GPU física) |

## Arquivos
- `00-runtimeclass.yaml` — RuntimeClass `nvidia`
- `01-timeslicing-config.yaml` — ConfigMap de time-slicing (replicas: 4)
- `02-device-plugin.yaml` — DaemonSet do device plugin
- `03-ollama.yaml` — Deployment + Service do Ollama
- `apply-all.sh` — aplica tudo na ordem

## Pré-requisitos (já configurados nesta máquina)
- WSL2 + Ubuntu, GPU visível (`wsl nvidia-smi`)
- NVIDIA Container Toolkit instalado no Ubuntu
- k3s instalado (runtime nvidia auto-detectado)

## Como usar
```bash
# aplicar tudo (dentro do WSL, como root)
wsl -u root bash /mnt/c/Users/Steph/ai-factory/k8s/apply-all.sh

# baixar um modelo no pod do Ollama
wsl -u root bash -c "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; k3s kubectl exec deploy/ollama -- ollama pull qwen2.5:1.5b"

# testar inferência via o Service do Kubernetes
wsl -u root bash -c "curl -s http://localhost:31434/api/generate -d '{\"model\":\"qwen2.5:1.5b\",\"prompt\":\"ola\",\"stream\":false}'"

# ver uso de GPU pelo modelo
wsl -u root bash -c "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; k3s kubectl exec deploy/ollama -- ollama ps"
```

## Gestão de recursos
- O cluster roda enquanto o WSL estiver ativo. Para liberar RAM: `wsl --shutdown`.
- A RAM do WSL está limitada em `C:\Users\Steph\.wslconfig` (8 GB).

## Conceitos demonstrados (certificação NCA-AIIO)
Orquestração de GPU, RuntimeClass, device plugin, time-slicing vs MIG,
serving de modelos, observabilidade de GPU.
