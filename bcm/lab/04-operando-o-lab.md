# Lab 04 — Operando o cluster: o que quebra, por quê, e como diagnosticar

> Os labs 01–03 mostram o cluster funcionando. Este mostra o que acontece **entre** os labs: o serviço que não sobe, o nó que drena sozinho, o SSH que recusa conexão, o job que o scheduler rejeita sem explicar. São falhas reais de um BCM 11 sobre Ubuntu 24.04, com a causa raiz de cada uma.

**Por que este documento existe:** a documentação de produto ensina o caminho feliz. O tempo real de operação vai embora em sintomas que ninguém escreveu. Cada item aqui custou de 20 minutos a 1 hora para diagnosticar.

Ambiente: head node BCM 11 em VM (VirtualBox), 4 GB RAM, host Windows.

---

## Índice rápido

| # | Sintoma | Camada |
|---|---|---|
| 1 | Portal web nunca sobe; `cmd.service` em loop `activating → failed` | CMDaemon |
| 2 | `ssh: Connection refused` mesmo com a VM rodando | Rede / host |
| 3 | Nó vira `DRAIN` sozinho depois de mexer na VM | Slurm |
| 4 | `sbatch` recusa o script: "does not look like a batch script" | Encoding |
| 5 | GPUs somem a cada reboot | GRES |
| 6 | `slurmd` não reinicia: "Address already in use" | Slurm |
| 7 | `sacct` rejeita o intervalo de tempo | Slurm |
| 8 | Login recusado no portal | Autenticação |

---

## 1. CMDaemon em loop: `activating → failed`, portal nunca abre

**Sintoma.** Após o boot, `systemctl is-active cmd` alterna entre `activating` e `failed`. A porta 8081 nunca abre. O log mostra a inicialização indo bem — certificados, monitoring, licença — e então:

```
cmd: [   DB    ] Info: EntityStorageController::load, start, verbose: 0
cmd: [   CMD   ] Info: Received SIGTERM. About to exit.
```

**Causa raiz.** O `cmd.service` tem `ExecStartPost=wait_cmd`, um script que faz **55 tentativas** aguardando o daemon ficar pronto, sob `TimeoutSec=120`. O `EntityStorageController::load` carrega ~648 tabelas do banco; num disco lento isso passa de 95 s. O systemd mata o processo **no meio da carga** — e reinicia, entrando em loop. O log de `Start for the: 6 time since boot` é a assinatura.

**Diagnóstico decisivo.** Não é falta de RAM. Verifique antes de assumir:

```bash
free -m          # se há memória livre e swap zerado, não é RAM
cat /proc/loadavg
grep -c "EntityStorageController::load" /var/log/cmdaemon   # quantas tentativas
```

**Correção (persistente).**

```bash
# 1. mais tempo para o systemd
mkdir -p /etc/systemd/system/cmd.service.d
printf '[Service]\nTimeoutStartSec=900\n' > /etc/systemd/system/cmd.service.d/timeout.conf

# 2. mais tentativas para o wait_cmd
cp /cm/local/apps/cmd/sbin/wait_cmd /cm/local/apps/cmd/sbin/wait_cmd.bak
sed -i 's/^retries=55/retries=600/' /cm/local/apps/cmd/sbin/wait_cmd

systemctl daemon-reload
systemctl reset-failed cmd
systemctl start cmd --no-block
```

Depois disso o serviço fica em `activating` por 4–5 minutos e **conclui**. Confirmação:

```bash
systemctl is-active cmd                                        # active
curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:8081/base-view/   # 200
```

> **Lição transferível:** um `ExecStartPost` com número fixo de tentativas é um timeout disfarçado. Em qualquer serviço que carregue estado grande no boot, esse contador é o primeiro suspeito — não a memória.

---

## 2. `ssh: Connection refused` com a VM rodando

**Sintoma.** A VM está `running`, o port forward existe, e mesmo assim:

```
ssh: connect to host localhost port 2222: Connection refused
banner exchange: Connection to UNKNOWN port -1: Connection refused
```

**Causa raiz.** O port forward do VirtualBox é registrado em **IPv4** (`127.0.0.1`). O `localhost` resolve primeiro para **IPv6** (`::1`), onde não há nada escutando.

```
Forwarding(1)="ssh,tcp,127.0.0.1,2222,,22"    ← só IPv4
```

**Correção.** Usar o IP explícito, sempre:

```bash
ssh -i ~/.ssh/bcm_lab -p 2222 root@127.0.0.1
```

**Como confirmar em 5 segundos** (PowerShell):

```powershell
Test-NetConnection -ComputerName 127.0.0.1 -Port 2222 -InformationLevel Quiet   # True
Test-NetConnection -ComputerName localhost -Port 2222 -InformationLevel Quiet   # falha em ::1
```

---

## 3. Nó vira `DRAIN` depois de mexer na VM

**Sintoma.** Após reduzir a RAM da VM (4608 → 4096 MB), o nó parou de aceitar jobs:

```
State=IDLE+DRAIN
Reason=Low RealMemory (reported:3897 < 100.00% of configured:3955)
```

**Causa raiz.** O Slurm grava a memória do nó no momento do registro. Se o valor real cair abaixo do configurado, ele **drena o nó por segurança** — a premissa é que jobs dimensionados para aquela memória falhariam.

**Correção.** O BCM autocorrige o `RealMemory`, mas o nó **permanece drenado até um resume explícito**:

```bash
scontrol update nodename=bcm11-headnode state=resume
```

> **Regra operacional:** toda alteração de RAM ou CPU da VM exige um `resume` depois. Vale para qualquer redimensionamento de worker node — inclusive em nuvem, ao trocar o tipo de instância.

---

## 4. `sbatch` recusa o script: "does not look like a batch script"

**Sintoma.**

```
sbatch: error: This does not look like a batch script. The first
sbatch: error: line must start with #! followed by the path to an interpreter.
```

...em um arquivo cuja primeira linha é, visivelmente, `#!/bin/bash`.

**Causa raiz.** **BOM UTF-8.** O arquivo foi gerado no Windows e começa com os bytes `EF BB BF` antes do `#!`. O kernel não reconhece o shebang.

**Diagnóstico definitivo** — não confie no editor, olhe os bytes:

```bash
head -c 4 job.sh | od -An -tx1
# ef bb bf 23   ← BOM presente
# 23 21 2f 62   ← correto (#!/b)
```

**Correção.**

```bash
sed -i '1s/^\xEF\xBB\xBF//' *.sh
```

**Prevenção na origem** (PowerShell 5.1 grava BOM com `-Encoding utf8`):

```powershell
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($destino, $conteudo, $utf8NoBom)
```

---

## 5. GPUs somem a cada reboot

**Sintoma.** Depois de reiniciar, o nó volta com `gres/gpu` inválido e jobs com `--gres=gpu:1` não agendam.

**Causa raiz.** Os device files criados com `mknod` (ver [Lab 02](02-gpu-gres-slurm.md)) vivem no `/dev`, que é um **tmpfs** — recriado do zero a cada boot.

**Correção manual.**

```bash
[ -e /dev/nvidia0 ] || mknod /dev/nvidia0 c 195 0
[ -e /dev/nvidia1 ] || mknod /dev/nvidia1 c 195 1
```

**Correção permanente** — unit systemd que roda antes do `slurmd`:

```ini
# /etc/systemd/system/fake-gpu.service
[Unit]
Description=Device files de GPU simulada (lab)
Before=slurmd.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '[ -e /dev/nvidia0 ] || mknod /dev/nvidia0 c 195 0; [ -e /dev/nvidia1 ] || mknod /dev/nvidia1 c 195 1'
[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now fake-gpu.service
```

---

## 6. `slurmd` não reinicia: "Address already in use"

**Sintoma.**

```
slurmd: error: Unable to bind listen port (6818): Address already in use
```

**Causa raiz.** Um `slurmd` órfão continua segurando a porta — o systemd perdeu o rastro do processo.

**Correção.**

```bash
pkill -9 slurmd
systemctl reset-failed slurmd
systemctl start slurmd
```

---

## 7. `sacct` rejeita o intervalo de tempo

**Sintoma.**

```
$ sacct --starttime now-15minutes
Invalid time specification (pos=5): now-15minutes
```

**Causa.** Nem toda build aceita a sintaxe relativa. Usar a forma absoluta:

```bash
sacct -S today --format=JobID,JobName%16,State,Elapsed,AllocTRES%22 | grep -Ev 'extern|\.batch'
```

> O `grep -v` remove os passos internos (`.batch`, `.extern`) que o Slurm cria para cada job e que poluem a leitura.

---

## 8. Login recusado no portal

**Sintoma.** `root` + senha correta é rejeitado. No log:

```
cmd: [  JSON   ] Info: jsonservice: unable to login using username/password supplied
```

**Duas causas distintas — diagnostique qual é.**

**a) Interface errada.** O BCM serve **duas** aplicações na mesma porta:

```bash
for p in /base-view/ /userportal/; do
  echo "$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8081$p)  $p"
done
```

| Caminho | Público |
|---|---|
| `/base-view/` | **administração** — é onde o `root` opera |
| `/userportal/` | usuário final do cluster (ver os próprios jobs) |

O User Portal é para contas de cluster. Se `cmsh -c 'user; list'` volta vazio, **não existe usuário para logar ali** — e tentar com `root` falha por design.

**b) Senha realmente divergente.** Redefina com a ferramenta do próprio BCM:

```bash
cm-change-passwd
```

Ela troca, em sequência, as senhas de: root do head node, root das software images, root do node installer e **do MySQL**. A do MySQL é a delicada — ela reescreve as credenciais em `/cm/local/apps/cmd/etc/cmd.conf`. **Interromper no meio pode deixar o CMDaemon sem conseguir abrir o banco.** Verifique depois:

```bash
systemctl is-active cmd mysql
```

---

## Apêndice — diagnóstico em uma chamada

Operar remotamente é caro em ida-e-volta. Um único comando que responde tudo:

```bash
ssh -i ~/.ssh/bcm_lab -p 2222 root@127.0.0.1 '
echo "cmd=$(systemctl is-active cmd)"
ss -ltn | grep -q ":8081" && echo "portal=UP" || echo "portal=down"
echo "gpudev=$([ -e /dev/nvidia0 ] && [ -e /dev/nvidia1 ] && echo ok || echo FALTANDO)"
echo "gres=$(scontrol show node bcm11-headnode | grep -o "Gres=gpu:[0-9]*" | head -1)"
echo "no=$(sinfo -h -n bcm11-headnode -o "%t")"
echo "fila=$(squeue -h | wc -l)"'
```

Saída de um cluster saudável:

```
cmd=active
portal=UP
gpudev=ok
gres=Gres=gpu:2
no=idle
fila=0
```

`no=inval` ou `no=drain` aponta direto para o item 3; `gpudev=FALTANDO` para o item 5; `portal=down` com `cmd=active` significa que o CMDaemon ainda está carregando (item 1) — espere antes de reiniciar.

---

## Nota sobre o ambiente virtualizado

Rodar o head node numa VM impõe uma restrição que não existe em bare metal: **a RAM do host tem de acomodar a VM inteira de uma vez.**

Medições neste lab (host de 16 GB, VM de 4,6 GB):

| RAM livre no host | Resultado |
|---|---|
| 5,3 GB (folga 0,7 GB) | VM sobe, mas o host cai para 0,9 GB e entra em thrashing; SSH para de responder |
| 2,8 GB | Restore trava; SSH mudo por mais de 4 minutos |
| 5,9 GB com VM de 4,0 GB (folga 1,9 GB) | Estável |

**Regra derivada:** exigir `RAM_da_VM + ~1,9 GB` livres antes de ligar. E `savestate` — que preserva o CMDaemon de pé e evita os 4–5 minutos do item 1 — **não escapa dessa conta**: o restore realoca a mesma memória de uma vez.

Reduzir a VM (medindo o uso real dentro dela antes) costuma render mais que otimizar o host. Só lembre do item 3 depois.
