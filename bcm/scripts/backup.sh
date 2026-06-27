#!/bin/bash
# backup.sh — backup da configuracao de um head node BCM 11
#
# IMPORTANTE (descoberta de campo):
#   O BCM 11 REMOVEU o comando 'cmsh -c "configurationdump"' que existia
#   em versoes anteriores. Os guias antigos ainda mostram ele — nao funciona.
#
#   No BCM 11 a configuracao do cluster vive no banco MySQL do CMDaemon
#   (database "cmdaemon"). O backup correto e um mysqldump desse banco,
#   complementado por um snapshot textual do cmsh.
#
# Uso (rode como root no head node):
#   bash backup.sh [diretorio_de_saida]
#
# Saida: um .tar.gz com o dump SQL + o snapshot do cmsh.

set -euo pipefail

OUT_DIR="${1:-/root/bcm-backup}"
CMD_CONF="/cm/local/apps/cmd/etc/cmd.conf"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="${OUT_DIR}/bcm-backup-${STAMP}"
mkdir -p "${WORK}"

echo "[1/3] Snapshot do cmsh -> snapshot.txt"
SNAP_CMDS="$(mktemp)"
cat > "${SNAP_CMDS}" <<'EOF'
device list
device status
category list
softwareimage list
network list
partition list
quit
EOF
cmsh -f "${SNAP_CMDS}" > "${WORK}/snapshot.txt" 2>&1 || true
rm -f "${SNAP_CMDS}"

echo "[2/3] Dump do banco do CMDaemon -> cmdaemon.sql"
# Le as credenciais do cmd.conf (NUNCA hardcode a senha aqui).
DB_HOST="$(awk '/^DBHost/  {print $3}' "${CMD_CONF}" | tr -d '"=;')"
DB_USER="$(awk '/^DBUser/  {print $3}' "${CMD_CONF}" | tr -d '"=;')"
DB_PASS="$(awk '/^DBPass/  {print $3}' "${CMD_CONF}" | tr -d '"=;')"
DB_NAME="$(awk '/^DBName/  {print $3}' "${CMD_CONF}" | tr -d '"=;')"

# MYSQL_PWD evita a senha aparecer na lista de processos / logs.
MYSQL_PWD="${DB_PASS}" mysqldump --single-transaction \
  -h "${DB_HOST}" -u "${DB_USER}" "${DB_NAME}" > "${WORK}/cmdaemon.sql"

echo "[3/3] Empacotando -> ${WORK}.tar.gz"
tar czf "${WORK}.tar.gz" -C "${OUT_DIR}" "$(basename "${WORK}")"
rm -rf "${WORK}"

echo "OK -> ${WORK}.tar.gz"
ls -lh "${WORK}.tar.gz"

# Estatisticas rapidas (sanity check)
echo "--- resumo ---"
TABLES="$(zcat "${WORK}.tar.gz" 2>/dev/null | grep -c 'CREATE TABLE' || true)"
echo "Backup gerado. Restaure num head node de mesma versao com mysql < cmdaemon.sql"
