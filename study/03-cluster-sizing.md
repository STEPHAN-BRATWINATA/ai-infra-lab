# Dimensionamento de clusters — estudos de caso

Dois exercícios de dimensionamento gerados pela AI Factory local e **corrigidos** (o modelo erra a escala — lição central do domínio **AI Infrastructure**).

## Caso 1 — Treinar (pré-treino) um LLM denso de 70B

### Memória (a IA acertou)
Pesos + gradientes + estados do otimizador Adam, precisão mista ≈ **16–18 bytes/parâmetro**:
```
70e9 × 17 bytes ≈ 1,2 TB  (só os estados; + ativações)
```
Por isso o modelo **não cabe** numa GPU → **paralelismo 3D** (tensor intra-nó via NVLink + pipeline + data entre nós via InfiniBand).

### ❌ O erro da IA: "1,2 TB ÷ 80 GB = ~15 GPUs, 2 nós"
Isso confunde *caber os pesos* com *pré-treinar de verdade*. **Pré-treino é throughput-bound.**

### ✅ A conta correta — FLOPs de treino
```
FLOPs ≈ 6 × params × tokens = 6 × 70e9 × 15e12 ≈ 6,3 × 10^24 FLOPs
H100 ≈ 400 TFLOP/s efetivos (MFU ~40%)
→ ~4–6 milhões de H100-horas   (bate com os ~6,4M citados p/ Llama-3-70B)
```
| Tarefa | GPUs realistas | Nós (8 GPU) | Tempo |
|---|---|---|---|
| Pré-treino do zero (15T tokens) | **~2.000–8.000 H100/H200** | 256–1.000+ | semanas a meses |
| (só p/ caber na memória) | ~16–32 | 2–4 | ⚠️ levaria anos — inviável |
| Full fine-tuning | ~32–128 | 4–16 | dias |
| LoRA / PEFT | ~8–16 | 1–2 | horas–dias |

**Storage:** dataset (dezenas de TB tokenizados, corpus bruto em PBs) + checkpoints (~0,5–1,5 TB cada) → **FS paralelo multi-PB**, não 150 GB.

## Caso 2 — Projetar uma Scalable Unit (SU) de 256 GPUs

| Item | IA disse | ✅ Correto |
|---|---|---|
| Nós | 32 | 32 (256÷8) ✔ |
| **Energia** | "76,8 kW" (300W/GPU) | **~350–450 kW** — GPUs de treino = 700W (H100) a 1000W (B200); nó de 8 GPU ≈ 10–14 kW |
| **Rede IB** | "7 leaf + 8 spine" | **~8 leaf + 4 spine** Quantum-2 (64×400G), fat-tree rail-optimized; + fabrics separados de storage e gestão |
| **Racks** | "10 servidores/rack" | **~4–8 racks líquidos** ou **1 Dell IR7000** integrado |
| **Storage** | "40–80 TB" | **centenas de TB a PB** (dataset + checkpoints) |
| **Refrigeração** | fórmula inventada | **DLC (líquido direto) obrigatório** a esta densidade |

> Esta SU corrigida = **1 Scalable Unit do DGX SuperPOD** (32 nós × 8 GPU). Na Dell = **Integrated Rack (IR5000/IR7000)** com 32× XE9680/9712.

## Lições para a prova
- **Treino**: throughput-bound → dimensione por **FLOPs/tempo**, não por memória.
- **Inferência**: latência/concorrência-bound → dimensione por **req/s, KV cache e SLA de latência**.
- **Energia/cooling** escalam com a densidade → alta densidade exige **DLC** (tópico de *facility requirements*).
- Sempre **valide os números** que uma IA gera — ela tende a subdimensionar energia, rede e storage.
