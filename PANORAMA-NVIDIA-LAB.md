# Panorama — NVIDIA AI Infrastructure Lab

> Uma jornada de **infraestrutura de IA** construída numa única GPU de notebook (NVIDIA RTX 3050 6GB, Ampere `sm_86`) — do kernel CUDA cru à AI Factory orquestrada em Kubernetes, medindo e validando cada etapa.
>
> Objetivo: aprofundar arquitetura NVIDIA + Dell PowerEdge XE, preparar a certificação **NCA-AIIO** e provar, na prática, o conceito de **IA Privada on-premise**.

---

## TL;DR

Em ~3,5 semanas (≈1h/dia), saí de "quero estudar infra de IA" para um **lab de AI Factory funcional, versionado e documentado**, que serve a três frentes ao mesmo tempo:

1. **Estudo** — intuição profunda para a certificação NVIDIA NCA-AIIO (conceitual).
2. **Carreira** — credibilidade técnica como PM de implantação de infra de IA.
3. **Produto** — prova de conceito do tier "IA Privada (LGPD)".

| Métrica de destaque | Resultado |
|---|---|
| Speedup matmul GPU vs CPU (1024³) | **675x** |
| Otimização de kernel (register blocking) | **7,9% → 36,9%** do pico FP32 |
| Referência cuBLAS | **5,2 TFLOP/s · 59,5% do pico · 9,7x vs naive** |
| LLM jurídico local (`qwen2.5:7b`) | **27,8 tok/s · 84% GPU** |
| Fractional GPU (time-slicing) | **1 GPU física → 4 fatias**, 3 pods simultâneos |
| Footprint da observabilidade | **321 MB de RAM** (vs ~2–4 GB do Docker Desktop) |

---

## Linha do tempo

| Fase | Marco |
|---|---|
| **Plano** | Objetivo de carreira + roadmap de estudos (AI Infra → CUDA/HPC → Orquestração → Agentic) |
| **Arquitetura XE** | Estudo do PowerEdge XE7740 (inferência) vs XE9680 (treino, HGX/NVLink) |
| **Bring-up** | CUDA 13.3 + MSVC compilando; RTX 3050 confirmada como lab principal |
| **Fundamentos CUDA** | Tour de 5 programas (threads, specs, matmul, pinned memory, streams) |
| **Deep dive HPC** | Tiling → register blocking → cuBLAS; profiling com Nsight Compute |
| **LLM aplicado** | POC de IA Jurídica Privada local (Ollama + extração JSON estruturado) |
| **AI Factory F1** | Observabilidade (Prometheus + Grafana + nvidia exporter) |
| **AI Factory F2** | Orquestração (k3s + GPU) + GPU time-slicing |
| **AI Factory F3** | LLM serving no K8s (Ollama) + gateway OpenAI-compatível (LiteLLM) |
| **Estudo NCA-AIIO** | Study pack publicado (XE, topologia, sizing, questões) |

---

## Eixo 1 — CUDA / HPC: o ciclo *medir → diagnosticar → otimizar → validar*

Pasta: **[cuda-lab/](cuda-lab/)** · 8 programas.

A peça central foi a jornada de otimização da multiplicação de matrizes, percorrendo o ciclo completo de engenharia de performance e **provando cada passo com o Nsight Compute**:

| Programa | Resultado | Lição |
|---|---|---|
| [`matmul.cu`](cuda-lab/matmul.cu) | **675x** GPU vs CPU | paralelismo massivo |
| [`matmul_tiled.cu`](cuda-lab/matmul_tiled.cu) | 1,3–1,6x · **7,9%** do pico | shared memory / data reuse |
| [`matmul_regblock.cu`](cuda-lab/matmul_regblock.cu) | **36,9%** do pico (4,64x vs tiled) | register blocking desafoga o pipeline MIO |
| [`cublas_matmul.cu`](cuda-lab/cublas_matmul.cu) | **59,5%** do pico (9,7x vs naive) | biblioteca otimizada = teto prático |
| [`pinned_memory.cu`](cuda-lab/pinned_memory.cu) | ~1,1x | pinned destrava async, não cria banda |
| [`streams_overlap.cu`](cuda-lab/streams_overlap.cu) | 0,96–1,06x | overlap só com transfer≈compute (1 copy engine) |

**Diagnóstico Nsight (matmul tiled):** não era limitado por ocupação (11,85/12 warps) nem por DRAM (55%), mas pelo **pipeline MIO saturado de loads de shared memory** (Mem Pipes Busy 96,8%). O register blocking (micro-tile 4×4 reusando dados em registradores) validou o diagnóstico, levando o kernel de 7,9% → 36,9% do pico.

```
% do pico FP32 (RTX 3050 ≈ 8,9 TFLOP/s)
Naive            ▇ 6,1%
Tiled            ▇ 7,9%
Register block   ▇▇▇▇▇▇▇ 36,9%
cuBLAS           ▇▇▇▇▇▇▇▇▇▇▇ 59,5%
```

**Conceitos:** hierarquia de memória · arithmetic intensity · roofline model · register blocking · diagnóstico de gargalo (MIO vs DRAM vs ocupação).

---

## Eixo 2 — Mini AI Factory "in a box"

Pasta: **[ai-factory/](ai-factory/)**.

Réplica da **arquitetura e do stack** de uma AI Factory em escala de 1 GPU — tudo construído e provado ponta a ponta:

- **Observabilidade** ([monitoring/](ai-factory/monitoring/)) — `nvidia_gpu_exporter` + Prometheus + Grafana. Demo de carga capturou a GPU saindo do ocioso: uso **0→95%**, potência **17→73 W**, VRAM **0→4225 MB**.
- **Orquestração** ([k8s/](ai-factory/k8s/)) — k3s + NVIDIA Container Toolkit + device plugin → node anuncia `nvidia.com/gpu: 1/1`. Pod CUDA rodou `nvidia-smi` **dentro do pod**.
- **Fractional GPU** — time-slicing (ConfigMap replicas:4) → **1 GPU → 4 fatias**; 3 pods simultâneos no mesmo UUID (análogo ao Run:ai).
- **Serving + Gateway** — Ollama como Deployment k8s (NodePort) + LiteLLM (API OpenAI-compatível).

**Lição de arquitetura (relevante para a cert):** `WSL2 + k3s + GPU` **não é resiliente a restart** — produção de verdade exige **bare-metal/datacenter**. A "token factory" estável saiu pelo Ollama nativo expondo a API OpenAI em `localhost:11434`.

---

## Eixo 3 — LLM aplicado: IA Privada (LGPD)

Com `qwen2.5:7b` 100% local: extração de dados estruturados (JSON) de petições jurídicas — todos os campos corretos (processo, partes, CPF/CNPJ, valores, prazo) a **27,8 tok/s · 84% GPU**. Lição medida: LLM é confiável para extração/resumo, mas **erra julgamento nuançado** → exige revisão humana. É a prova de conceito do tier "IA Privada on-premise" para nichos sensíveis (jurídico/saúde/financeiro).

---

## Eixo 4 — Estudo NCA-AIIO

Pasta: **[study/](study/)**.

Pesos da prova: **Infraestrutura de IA 40% · Conhecimento essencial 38% · Operações 22%**. A prova é **conceitual** (não cobra programar CUDA) — o lab serve de **intuição de arquiteto**, não de prep direto.

- [01 — PowerEdge XE](study/01-poweredge-xe.md)
- [02 — Arquitetura e topologia](study/02-architecture-and-topology.md) (leaf-spine, fluxo de inferência)
- [03 — Sizing de cluster](study/03-cluster-sizing.md) (70B, SU-256)
- [04 — Banco de questões](study/04-practice-questions.md)

Metodologia: **"IA gera, engenheiro valida"** — o LLM local gerou rascunhos; a revisão humana corrigiu os erros conceituais (sigla MIG, NVLink vs NVSwitch, energia, BCM ≠ OpenStack).

---

## Eixo 5 — NVIDIA Base Command Manager (provisionamento)

Pasta: **[bcm/](bcm/)**.

A camada que faltava: o **produto real de provisionamento** que a Dell e a NVIDIA usam para entregar AI Factories. Diferente das outras camadas (análogos open-source), aqui é o **BCM 11.0 de verdade**, instalado num head node de lab a partir do ISO oficial.

- Instalação completa bare-metal (rede Type 1, externalnet/internalnet, Slurm)
- Operação via `cmsh` e via User Portal (web UI)
- **Backup real** da config — e a descoberta de que o BCM 11 **removeu o `configurationdump`**: o backup correto agora é mysqldump do banco do CMDaemon
- Operação remota via SSH com chave (padrão de produção)

As [notas de troubleshooting](bcm/notes/troubleshooting.md) trazem descobertas que não estão nos guias (o backup via mysqldump, `cmsh -c` vs `cmsh -f`, `/userportal/` com barra, mapeamento de NICs invertido no instalador) — conhecimento de operador, não de manual.

---

## Relação com a AI Factory real (Dell + NVIDIA)

Cada camada do lab é o **análogo em escala 1-GPU** de um componente real de datacenter:

| Camada | Lab local (RTX 3050) | Equivalente real | Status |
|---|---|---|---|
| Provisionamento | **BCM 11 real** (head node + cmsh + Slurm) | Base Command Manager (Dell + NVIDIA) | ✅ **produto real instalado** |
| Orquestração | k3s + device plugin + time-slicing | Kubernetes/Slurm + BCM + Run:ai | ✅ provado |
| Serving | Ollama + LiteLLM | Triton / TensorRT / NIM | ✅ provado |
| Runtime | CUDA 13.3 + Container Toolkit | CUDA / NCCL / cuDNN / NGC | ✅ provado |
| Compute | RTX 3050 6GB (Ampere) | DGX/HGX H100 · XE9680 (treino) / XE7745 (inferência) | ✅ análogo |
| Observabilidade | Prometheus/Grafana + nvidia exporter | DCGM + DCGM-exporter | ✅ mesmo conceito |
| Storage / GDS | NVMe local (modo compat) | BOSS (OS) + NVMe raw (Tier 1) + PowerScale (Tier 2) + GDS | ⚠️ parcial |
| Rede | só conceito (1 GPU) | NVLink/NVSwitch · InfiniBand · RoCE v2 · DPU BlueField | ❌ teoria |

As duas camadas que o lab de 1 GPU **não** exercita — **storage GDS real** e **rede lossless (RoCE v2/InfiniBand)** — são cobertas pelo estudo conceitual. É a divisão certa: o lab ensina compute/orquestração/serving/observabilidade; a teoria cobre rede e storage de datacenter.

---

## Stack

CUDA · Nsight Compute · cuBLAS · Kubernetes (k3s) · NVIDIA Container Toolkit · NVIDIA device plugin · Ollama · LiteLLM · Prometheus · Grafana · WSL2

## Hardware

NVIDIA GeForce RTX 3050 6GB Laptop GPU (Ampere, compute 8.6) · 20 SMs · 2560 CUDA cores · ~168 GB/s · ~8,9 TFLOP/s FP32 (pico teórico)
