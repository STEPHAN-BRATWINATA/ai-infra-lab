# NCA-AIIO Study Pack — AI Infrastructure & Operations

Material de estudo para a certificação **NVIDIA-Certified Associate: AI Infrastructure and Operations (NCA-AIIO)**, construído a partir de exploração prática numa mini **AI Factory** local (ver [`../ai-factory`](../ai-factory)) e da análise do spec sheet dos servidores **Dell PowerEdge XE**.

## 🧪 Metodologia: "a AI Factory gera, o arquiteto valida"
Boa parte deste material foi **gerada por um LLM local** (Ollama `qwen2.5:7b`, rodando na própria infraestrutura via API OpenAI-compatível) e depois **revisada e corrigida** com fontes oficiais. Os erros do modelo estão **documentados de propósito** — porque saber identificá-los *é* a competência central da certificação (ex.: confundir "caber o modelo na memória" com "throughput de pré-treino", ou inventar a sigla do MIG).

> A IA acelera o rascunho; o engenheiro valida. Esse é o fio condutor de todo o pacote.

## 📊 Domínios da prova
| Domínio | Peso | Foco |
|---|---|---|
| **Essential AI Knowledge** | 38% | stack de software NVIDIA, AI/ML/DL, treino vs inferência, GPU vs CPU |
| **AI Infrastructure** | 40% | hardware, redes (InfiniBand/NVLink/DPU), storage, energia/cooling, cluster |
| **AI Operations** | 22% | gestão/monitoramento (DCGM, BCM), orquestração (Slurm/K8s), MIG, virtualização |

## 📚 Índice
1. [PowerEdge XE — comparativo, cenários e clientes](01-poweredge-xe.md)
2. [Arquitetura de AI Factory — camadas, topologias e fluxo de inferência](02-architecture-and-topology.md)
3. [Dimensionamento de clusters e estudos de caso](03-cluster-sizing.md)
4. [Banco de questões NCA-AIIO (geradas + corrigidas)](04-practice-questions.md)

## 🔑 Conceitos-chave (resumo rápido)
- **Scale-up** = comunicação *dentro* do nó via **NVLink/NVSwitch** (8 GPUs agindo quase como uma).
- **Scale-out** = comunicação *entre* nós via **InfiniBand NDR** (leaf-spine) + **GPUDirect RDMA** + **BlueField DPU**.
- **Paralelismo 3D** = tensor (intra-nó) × pipeline × data (entre nós) — como modelos grandes são treinados.
- **Time-slicing vs MIG**: time-slicing = compartilhamento por tempo *sem isolamento*; MIG = partição de *hardware* isolada (só GPUs de datacenter).
- **Treino é throughput-bound** (trilhões de tokens); **inferência é latência/concorrência-bound**.
- **Token factory**: a inferência exposta como API OpenAI-compatível, com contagem de tokens (billing).

*Construído por Stephan Bratawinata · validado manualmente · LLM local como ferramenta de estudo.*
