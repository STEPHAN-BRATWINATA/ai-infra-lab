# ai-infra-lab

Laboratório prático de **infraestrutura de IA**, do kernel CUDA à AI Factory — construído numa única GPU (NVIDIA RTX 3050 6GB Laptop).

Documenta uma jornada de aprendizado de infra de IA / HPC, alinhada à certificação **NVIDIA NCA-AIIO** (AI Infrastructure and Operations).

## 🧮 [cuda-lab/](cuda-lab/) — Fundamentos de CUDA e otimização de GPU
Do "Hello GPU" à otimização de multiplicação de matrizes, **medindo cada gargalo**:
- vector add, device query, matmul CPU vs GPU (speedup ~675x)
- pinned memory, streams/overlap, **shared-memory tiling**
- **register blocking** (7,9% → 36,9% do pico FP32) comparado ao **cuBLAS** (59,5%)
- análise de **roofline** e profiling com **Nsight Compute** (diagnóstico de gargalo MIO/load)

## 🏭 [ai-factory/](ai-factory/) — Mini AI Factory (Kubernetes + GPU)
Réplica em escala de 1 GPU de uma AI Factory:
- **[k8s/](ai-factory/k8s/)** — k3s + NVIDIA device plugin + **time-slicing** (fractional GPU, estilo Run:ai) + **LLM serving** (Ollama) exposto como Service
- **monitoring/** — Prometheus + Grafana observando a GPU em tempo real

## ⚙️ bcm/ — NVIDIA Base Command Manager + Slurm
Provisionamento e operação de cluster com o **BCM 11.0**, instalado num head node de lab (VirtualBox):
- [Lab 01](bcm/lab/01-slurm-end-to-end.md) — Slurm end-to-end: do job que pendura ao sweep de hiperparâmetros
- [Lab 02](bcm/lab/02-gpu-gres-slurm.md) — GPU como recurso no Slurm (GRES)
- [Lab 03](bcm/lab/03-multitenancy-preempcao.md) — Multi-tenancy e preempção: SLA entre tenants numa GPU compartilhada
- [Lab 04](bcm/lab/04-operando-o-lab.md) — Operando o cluster: o que quebra, por quê, e como diagnosticar
- [Montagem do lab](bcm/notes/lab-setup.md) · [troubleshooting](bcm/notes/troubleshooting.md) · [scripts](bcm/scripts/) de auditoria e backup — incluindo a descoberta de que o BCM 11 **trocou `configurationdump` por mysqldump**

## Stack
CUDA · Nsight Compute · Kubernetes (k3s) · NVIDIA Container Toolkit · Ollama · Prometheus · Grafana · **BCM 11 · Slurm · cmsh** · WSL2

## Conceitos demonstrados
Hierarquia de memória · arithmetic intensity · roofline model · register blocking · orquestração de GPU · RuntimeClass · device plugin · time-slicing vs MIG · model serving · observabilidade de GPU · **provisionamento de cluster · workload manager (Slurm) · GRES · preempção e SLA**
