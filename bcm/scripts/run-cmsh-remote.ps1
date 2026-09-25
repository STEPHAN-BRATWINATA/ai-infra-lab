# run-cmsh-remote.ps1 — executa um script cmsh num head node BCM via SSH (PowerShell/Windows)
#
# Por que existe:
#   - Operar o BCM pela janela do VirtualBox e ruim (sem copiar/colar, layout de
#     teclado, sem Alt+Tab). O jeito profissional e via SSH com chave.
#   - O cliente SSH do Windows nao cola bem em sessao interativa, entao executamos
#     comandos cmsh a partir de um arquivo (.cmsh), de forma nao-interativa.
#   - Usa 'cmsh -f' (e nao 'cmsh -c') por causa do bug de resolucao de host em
#     sessao sem TTY. Ver ../notes/troubleshooting.md.
#
# Pre-requisito: chave SSH ja autorizada no head node, e port forward 2222 -> 22.
#
# Uso:
#   .\run-cmsh-remote.ps1 -CmshFile .\audit.cmsh
#   .\run-cmsh-remote.ps1 -CmshFile .\audit.cmsh -KeyPath "$env:USERPROFILE\.ssh\bcm_lab" -Port 2222

param(
  [Parameter(Mandatory=$true)][string]$CmshFile,
  [string]$KeyPath = "$env:USERPROFILE\.ssh\bcm_lab",
  [string]$HostName = "127.0.0.1",
  [int]$Port = 2222,
  [string]$User = "root"
)

if (-not (Test-Path $CmshFile)) { Write-Error "Arquivo cmsh nao encontrado: $CmshFile"; exit 1 }

$remoteTmp = "/tmp/_remote_$(Get-Random).cmsh"

# 1) Envia o arquivo de comandos
scp -i $KeyPath -P $Port -o StrictHostKeyChecking=no $CmshFile "${User}@${HostName}:$remoteTmp"

# 2) Executa via 'cmsh -f' e limpa
$cmd = "cmsh -f $remoteTmp 2>&1; rm -f $remoteTmp"
ssh -i $KeyPath -p $Port -o StrictHostKeyChecking=no "${User}@${HostName}" $cmd
