# Lab 02 — GPU como recurso no Slurm (GRES) no BCM

> Como o scheduler de uma AI Factory trata GPU: um recurso **consumível** que jobs pedem (`--gres=gpu:N`), o scheduler aloca e isola (`CUDA_VISIBLE_DEVICES`). Simulado num head node **sem GPU física**, usando GRES "no papel" — e a armadilha que isso revela.

**O que este lab prova:** que a mecânica de alocação de GPU do Slurm é a mesma com ou sem placa física; como o BCM expõe GRES via *configuration overlay*; e a regra (não óbvia) de que **o Slurm recusa GPU sem device file**.

---

## Cenário

Head node BCM, sem GPU física. Objetivo: fazer o Slurm acreditar que há **2 GPUs** e observar o scheduler alocá-las. É exatamente o modelo de uma fábrica de IA — só que aqui a GPU é simulada.

```mermaid
graph LR
    J1["job --gres=gpu:1"] -->|CUDA_VISIBLE_DEVICES=0| G0["GPU 0"]
    J2["job --gres=gpu:1"] -->|CUDA_VISIBLE_DEVICES=1| G1["GPU 1"]
    J3["job --gres=gpu:1"] -.->|PENDING (Resources)| WAIT["fila"]
    subgraph NODE["bcm11-headnode — gres=gpu:2"]
        G0
        G1
    end
    style G0 fill:#76b900,color:#000
    style G1 fill:#76b900,color:#000
    style WAIT fill:#ff6b6b,color:#000
```

---

## Passo 1 — O Slurm já é GPU-aware

O BCM configurou o Slurm para entender GPU, mas nenhum nó anuncia uma:

```
# slurm.conf
GresTypes=gpu
AccountingStorageTRES=gres/gpu

# gres.conf
(vazio)
```

---

## Passo 2 — Definir a GPU via configuration overlay

GRES é uma propriedade do role `slurmclient`, dentro do submode `genericresources`:

```
cmsh
 % configurationoverlay
 % use slurm-client
 % roles ; use slurmclient
 % genericresources
 % add gpu
 % set count 2
 % commit
```

O BCM regenera o `gres.conf`:
```
NodeName=bcm11-headnode,node001 Name=gpu Count=2
```

---

## Passo 3 — A armadilha: Slurm recusa GPU "file-less"

Após configurar, o nó **não** ficou disponível:

```
$ scontrol show node bcm11-headnode
State=IDLE+DRAIN+INVALID_REG
Reason=gres/gpu count reported lower than configured (0 < 2)

$ (slurmd log)
warning: Ignoring file-less GPU gpu:(null) from final GRES list
```

**Descoberta-chave:** diferente de GRES genéricos, o tipo `gpu` **exige um device file**. Sem ele, o `slurmd` registra `gpu:0`, que não bate com o `gpu:2` do `slurm.conf` → estado `INVALID_REG`.

---

## Passo 4 — Device files fake + apontar o File

Criamos 2 device files (major 195 = nvidia) e apontamos o GRES para eles:

```bash
mknod /dev/nvidia0 c 195 0
mknod /dev/nvidia1 c 195 1
```
```
# no role slurmclient -> genericresources -> use gpu:
set file /dev/nvidia[0-1]
commit
```

`gres.conf` resultante (agora válido):
```
NodeName=bcm11-headnode,node001 Name=gpu Count=2 File=/dev/nvidia[0-1]
```

> ⚠️ **Pegadinha operacional:** ao reiniciar o `slurmd`, pode aparecer `Address already in use (port 6818)` por um `slurmd` órfão. Limpeza: `pkill -9 slurmd; systemctl reset-failed slurmd; systemctl start slurmd`.

Agora o nó fica **IDLE** com `gres=gpu:2` e `CfgTRES=...gres/gpu=2`.

---

## Passo 5 — Job pede 1 GPU → roda e recebe a GPU

```bash
#SBATCH --gres=gpu:1
echo "GPU alocada: $CUDA_VISIBLE_DEVICES"
```
```
No de execucao : bcm11-headnode
GPU alocada    : 0           ← Slurm fez o binding da GPU 0 ao job!
```

O `CUDA_VISIBLE_DEVICES=0` é a prova de que o Slurm **isola** a GPU — mesmo sendo fake, a mecânica de binding é real. Num nó real, é assim que dois jobs no mesmo servidor não brigam pela mesma placa.

---

## Passo 6 — Pedir mais GPU do que existe → rejeitado

```
$ sbatch --gres=gpu:3 ...
error: Batch job submission failed: Requested node configuration is not available
```

Pedir 3 GPUs num nó de 2 é **rejeitado na submissão** (impossível de satisfizer), diferente de um job que *pendura* esperando recurso temporariamente ocupado.

---

## Passo 7 — O comportamento de fábrica de IA: GPUs como recurso consumível

Três jobs, cada um pedindo 1 GPU, com só 2 disponíveis:

```
$ squeue -o "%.6i %.8j %.8T %.10b %R"
 JOBID     NAME    STATE TRES_PER_N NODELIST(REASON)
    11      g-c  PENDING gres/gpu:1 (Resources)        ← espera GPU liberar
     9      g-a  RUNNING gres/gpu:1 bcm11-headnode      ← usa GPU 0
    10      g-b  RUNNING gres/gpu:1 bcm11-headnode      ← usa GPU 1
```

**2 rodam, 1 espera** — o scheduler trata GPU exatamente como uma fábrica de IA: recurso finito alocado entre experimentos concorrentes. Troque "2 GPUs fake" por "8× H100" e é um worker node de produção.

---

## Relevância

| Conceito exercitado | AI Factory / NCA-AIIO |
|---|---|
| `GresTypes=gpu`, `gres.conf` | configuração de GPU no scheduler |
| GRES via configuration overlay | modelo de gestão do BCM |
| `gpu` exige device File | troubleshooting de nó GPU drenado |
| `--gres=gpu:N` | requisição de GPU por job |
| `CUDA_VISIBLE_DEVICES` | isolamento/binding de GPU |
| PENDING por `(Resources)` | fila de GPU numa fábrica de IA |

A única diferença para produção: as GPUs são reais e o job roda PyTorch em vez de `sleep`. A **lógica de scheduling é idêntica**.

---

## Notas e reversão

- Os device files `/dev/nvidia0,1` **não sobrevivem a reboot** — recrie com `mknod` (ou um hook de boot) ao religar.
- Reverter a GPU fake:
  ```
  cmsh % configurationoverlay; use slurm-client; roles; use slurmclient
       % genericresources; remove gpu; commit
  ```
