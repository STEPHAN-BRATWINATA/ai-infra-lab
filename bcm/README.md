# NVIDIA Base Command Manager (BCM) — lab de provisionamento

> A camada de **provisionamento e gestão de cluster** de uma AI Factory, instalada e operada em escala de lab numa VM local — a peça que faltava no [mini AI Factory](../ai-factory/) deste repositório.

O BCM (ex-Bright Cluster Manager) é o que provisiona o head node, faz PXE boot dos compute/worker nodes, gerencia imagens de software, sobe o workload manager (Slurm/Kubernetes) e monitora o cluster. É o stack que a NVIDIA e a Dell usam para entregar AI Factories prontas.

Este diretório documenta a instalação do **BCM 11.0 (Ubuntu 24.04)** num head node de laboratório, os scripts de operação, e — o mais valioso — as **descobertas de campo** que não estão nos guias.

> 📖 **[Deep dive técnico completo →](DEEP-DIVE.md)** — topologia, arquitetura interna, hardware detalhado (lab → PowerEdge), a jornada de instalação e todas as descobertas, com diagramas.

## Por que isto importa

| Camada da AI Factory | Neste repo |
|---|---|
| Compute / GPU | [`cuda-lab/`](../cuda-lab/) — kernels, otimização, Nsight |
| Orquestração + serving | [`ai-factory/`](../ai-factory/) — k3s + GPU + Ollama |
| **Provisionamento / gestão de cluster** | **`bcm/`** ← você está aqui |

BCM é tópico nomeado da certificação **NVIDIA NCA-AIIO** (domínio de Operações). Fazer a instalação na mão dá a intuição que o material teórico não dá.

## Topologia do lab

```
                 Host Windows (VirtualBox)
   +-------------------------------------------------+
   |   VM: head node (Ubuntu 24.04 + BCM 11.0)       |
   |                                                 |
   |   enp0s3  -> externalnet  (NAT, DHCP, internet) |
   |   enp0s8  -> internalnet  (10.141.255.254/16)   |
   |             rede de provisioning / PXE          |
   |                                                 |
   |   node001 (definido, aguardando PXE boot)       |
   +-------------------------------------------------+
```

- **externalnet**: interface de NAT, pega DHCP, dá internet ao head node
- **internalnet**: rede privada `10.141.0.0/16`, o head node é `.255.254`, os nós provisionam por PXE
- **Workload manager**: Slurm
- **Network topology**: Type 1 (nós na rede interna privada)

> ⚠️ Nesta VM não há GPU (sem passthrough), então o foco é **provisionamento e gestão**, não compute. O compute de GPU está coberto no [`cuda-lab/`](../cuda-lab/).

## Conteúdo deste diretório

- [`DEEP-DIVE.md`](DEEP-DIVE.md) — deep dive técnico com topologia, hardware e arquitetura
- [`lab/`](lab/) — laboratórios práticos passo a passo (executados de verdade):
  - [`01-slurm-end-to-end.md`](lab/01-slurm-end-to-end.md) — do job que pendura ao sweep de hiperparâmetros
- [`scripts/`](scripts/) — scripts de operação (auditoria, backup) prontos para reuso
- [`notes/`](notes/) — descobertas de campo e troubleshooting real

## O que foi exercitado

- ✅ Instalação completa do head node (bare-metal, a partir do ISO)
- ✅ Configuração correta de rede (externalnet/internalnet, mapeamento de NICs)
- ✅ Operação via `cmsh` (o shell de gestão do BCM)
- ✅ Backup real da configuração (ver [nota sobre backup](notes/troubleshooting.md#backup))
- ✅ Acesso ao User Portal (web UI)
- ✅ Operação remota via SSH com chave (padrão de produção)

## Aviso

BCM é software proprietário NVIDIA (licença gratuita até 8 aceleradores por sistema, para uso próprio: avaliação, educação, demos). Este diretório contém apenas **scripts genéricos e notas de aprendizado** — nenhuma configuração proprietária, credencial ou dump de banco é versionado aqui.
