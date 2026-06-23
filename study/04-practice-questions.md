# Banco de questões NCA-AIIO (geradas pela AI Factory + corrigidas)

Questões geradas pelo LLM local (`qwen2.5:7b`) e **revisadas/corrigidas** com fontes oficiais. Onde o modelo errou, o erro está anotado — treina o olhar crítico que a prova exige.

## Tópicos por domínio (referência rápida)

**Essential AI Knowledge (38%)** — stack de software NVIDIA; AI vs ML vs DL; treino vs inferência; fatores da adoção de IA; casos de uso/indústrias; ciclo de vida de desenvolvimento; **GPU vs CPU**.

**AI Infrastructure (40%)** — requisitos de hardware por caso de treino; escalar GPU; energia/cooling; **on-prem vs nuvem**; componentes de cluster acelerado; requisitos de facility; **redes para IA**; protocolos/conceitos de rede; opções de rede de alta velocidade; **propósito do DPU**.

**AI Operations (22%)** — gestão/monitoramento de data center de IA; **orquestração e job scheduling**; medidas/critérios de **monitoramento de GPU**; **virtualização** de infraestrutura acelerada.

## Questões (com gabarito e correções)

**1. NVLink vs NVSwitch** — Qual descreve corretamente a relação?
- A) NVSwitch é uma versão mais lenta do NVLink
- B) NVLink é o link direto GPU↔GPU; **NVSwitch é o switch que escala o NVLink para muitas GPUs (all-to-all)** ✅
- C) São a mesma tecnologia
- D) NVSwitch substitui o InfiniBand entre nós

> 🛠️ *Correção:* a IA tratou como "NVLink mais rápido que NVSwitch" — errado. São **complementares** (scale-up).

**2. InfiniBand** — Principal função em infraestrutura de IA?
- A) Conexão Ethernet redundante
- B) **Alta vazão e baixa latência entre servidores (scale-out)** ✅
- C) Gerência remota
- D) Autenticação de dispositivos

**3. MIG (Multi-Instance GPU)** — O que é?
- A) Uma técnica de transferência entre GPUs
- B) **Particiona 1 GPU física em até 7 instâncias isoladas (memória + compute)** ✅
- C) Migração de função GPU→CPU
- D) Redução do tamanho dos dados

> 🛠️ *Correção:* a IA inventou a sigla ("Multipurpose Graphics..."). **MIG = Multi-Instance GPU.** Diferente de time-slicing (que NÃO isola).

**4. BlueField DPU** — Qual NÃO é função do DPU?
- A) Offload de rede/storage
- B) Segurança e isolamento
- C) **Executar o forward pass do modelo (compute de IA)** ✅ (não é função do DPU)
- D) Acelerar GPUDirect RDMA

**5. NVIDIA Base Command Manager (BCM)** — O que é?
- A) **Software da NVIDIA para provisionar e gerenciar o cluster (do bare-metal ao cluster pronto)** ✅
- B) OpenStack/VMware vSphere
- C) Configurador de preferências da GPU
- D) Sistema de backup

> 🛠️ *Correção:* a IA disse "OpenStack/vSphere" — errado. **BCM é o gerenciador próprio da NVIDIA** (ex-Bright Computing).

**6. Treino vs inferência** — Qual afirmação está correta?
- A) Ambos têm os mesmos requisitos de hardware
- B) **Treino é throughput-bound (muitas GPUs, semanas); inferência é latência/concorrência-bound** ✅
- C) Inferência precisa de mais GPUs que o treino
- D) Treino não precisa de rede entre nós

## Como usar este banco
Gere mais questões na sua AI Factory local e **sempre valide** — o processo *gerar → revisar → corrigir* é o melhor estudo. Prompt sugerido:
> "Gere 5 questões de múltipla escolha estilo NCA-AIIO sobre [tópico], com gabarito e explicação de 1 linha."
