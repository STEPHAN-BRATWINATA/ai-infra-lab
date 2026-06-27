# BCM 11 — descobertas de campo e troubleshooting

Notas reais de uma instalação e operação do BCM 11.0 (Ubuntu 24.04) em lab.
São coisas que **não estão (ou estão erradas) nos guias** e que custaram tempo para descobrir — exatamente o tipo de conhecimento que diferencia operação na prática.

---

## <a name="backup"></a>1. O backup do BCM 11 mudou — `configurationdump` foi removido

Guias e respostas antigas mandam fazer:

```
cmsh -c "configurationdump -j /root/backup.json"
```

**No BCM 11 esse comando não existe mais.** O `cmsh` responde `Command not found: configurationdump` (ou `Illegal option: j`).

A configuração do cluster agora vive no **banco MySQL do CMDaemon** (database `cmdaemon`). O backup correto é:

1. **mysqldump** do banco `cmdaemon` (credenciais em `/cm/local/apps/cmd/etc/cmd.conf`: `DBHost/DBUser/DBPass/DBName`)
2. Um **snapshot textual** do `cmsh` para auditoria legível

Ver [`scripts/backup.sh`](../scripts/backup.sh). Num lab típico o dump tem ~650 tabelas e centenas de inserts — é a config inteira do cluster.

> Boa prática: o `cmd.conf` contém a senha do banco em texto. Trate o arquivo e qualquer dump como sensíveis — não versione, não cole em prints públicos.

---

## 2. `cmsh -c` falha via SSH não-interativo — use `cmsh -f`

Ao rodar comandos via SSH sem TTY (ex.: automação a partir do Windows):

```
ssh root@host 'cmsh -c "device list"'
```

falha com:

```
CMMain::verifyAPI, rpc: Couldn't resolve host name.
Not connected!
Command not found: device
```

…mesmo com a rede 100% ok (hostname resolve, NIC interna UP, CMDaemon ativo).

**Workaround confiável:** colocar os comandos num arquivo e usar `cmsh -f`:

```bash
cat > /tmp/cmds.cmsh <<'EOF'
device list
quit
EOF
cmsh -f /tmp/cmds.cmsh
```

O modo `-f` conecta corretamente ao CMDaemon. Ver [`scripts/run-cmsh-remote.ps1`](../scripts/run-cmsh-remote.ps1).

---

## 3. User Portal exige a barra final na URL

O User Portal responde em `https://<head>:8081/userportal` mas **sem a barra final** retorna `301 Moved Permanently` — e alguns navegadores interpretam o redirect como timeout/404.

```
https://localhost:8081/userportal      ->  301 (pode parecer "não carrega")
https://localhost:8081/userportal/     ->  200 OK
```

Sempre acesse **com a barra**: `https://<head>:8081/userportal/`

O CMDaemon escuta em `8080` e `8081`.

---

## 4. Mapeamento de NICs vem invertido no instalador

No instalador do BCM 11 (tela *Head node interfaces*), o pré-preenchimento associou as redes às interfaces erradas. Numa VM VirtualBox com NIC1=NAT e NIC2=internal:

- `enp0s3` = adaptador 1 = NAT → deve ser **externalnet** (DHCP)
- `enp0s8` = adaptador 2 = internal → deve ser **internalnet** (`10.141.255.254`)

O instalador veio com isso trocado. **Confira e corrija** antes de prosseguir — errar aqui faz o head node ficar sem internet e o PXE provisionar na rede errada.

---

## 5. Operar via SSH com chave (não pela janela da VM)

Operar pela console gráfica do VirtualBox é improdutivo (sem copiar/colar, layout de teclado divergente, sem Alt+Tab). O jeito profissional é o mesmo de produção: **SSH com chave**.

```powershell
# gerar a chave (uma vez)
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\bcm_lab -N '""'

# autorizar na VM (digita a senha do root uma unica vez)
ssh -p 2222 root@localhost "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys" < $env:USERPROFILE\.ssh\bcm_lab.pub

# dali em diante, sem senha:
ssh -i $env:USERPROFILE\.ssh\bcm_lab -p 2222 root@localhost "hostname"
```

Em VM com NAT, exponha as portas do host:

```powershell
VBoxManage controlvm <vm> natpf1 "ssh,tcp,127.0.0.1,2222,,22"
VBoxManage controlvm <vm> natpf1 "baseview,tcp,127.0.0.1,8081,,8081"
```

---

## 6. Notas de recurso (lab em host pequeno)

- O head node BCM é pesado para um host de 16 GB. Rode a VM com **5–6 GB** e feche navegadores antes.
- Sob pressão de RAM o boot pode dar `soft lockup` (CPU stuck) no initramfs — um power-off + power-on limpo costuma resolver.
- PXE boot real de um compute node exige uma **segunda VM** simultânea — inviável em 16 GB. O `node001` fica definido (`DOWN, unassigned`) e o fluxo é entendido conceitualmente.
