#!/usr/bin/env bash

# ===============

# ONOS Controller

# ===============

# Carrega arquivo .secrets

if [ -f ".secrets" ]; then
source .secrets
else
echo "Erro: Arquivo .secrets não encontrado!" >&2
exit 1
fi

# ---------------------------

# Cores (usadas em mensagens)

# ---------------------------

RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

# ------------

# Log de ações

# ------------

LOGFILE="onos-actions.log"
log_action() {
echo "$(date '+%Y-%m-%d %H:%M:%S') | $(whoami) | $1" >> "$LOGFILE"
}

pause() {
echo ""
read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
}

# ---------------------------

# Controller config

# ---------------------------

CONTROLLER_HOST="${CONTROLLER_HOST:-}"
CONTROLLER_PORT="${CONTROLLER_PORT:-8181}"

get_controller_host() {
if [[ -n "$CONTROLLER_HOST" ]]; then
echo "$CONTROLLER_HOST"
return 0
fi

```
docker inspect onos >/dev/null 2>&1 || return 1

docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' onos
```

}

# ---------------------------

# Docker lifecycle

# ---------------------------

start_onos_container() {
echo "Verificando estado do container ONOS..."

if ! docker inspect onos >/dev/null 2>&1; then
echo "Container ONOS não existe. Criando..."
docker run -d -t -p 6653:6653 -p 8181:8181 -p 8101:8101 -p 5005:5005 -p 9876:9876 -p 830:830 --name onos onosproject/onos:2.7-latest
log_action "Criou container ONOS"
else
RUNNING=$(docker inspect -f '{{.State.Running}}' onos 2>/dev/null)
if [ "$RUNNING" = "true" ]; then
echo "Container ONOS já está rodando."
else
docker start onos >/dev/null
echo "Container ONOS iniciado."
log_action "Iniciou container ONOS"
fi
fi
pause
}

stop_onos_container() {
read -p "Tem certeza que deseja parar o ONOS? (s/N): " CONFIRM
case "$CONFIRM" in
[sS]*)
if [[ -n $(docker ps -q -f name=onos) ]]; then
docker stop onos >/dev/null
echo "Container ONOS parado."
log_action "Parou container ONOS"
else
echo "Container ONOS não está rodando."
fi
;;
*) echo "Cancelado." ;;
esac
pause
}

restart_onos_container() {
read -p "Deseja reiniciar o ONOS? (s/N): " CONFIRM
case "$CONFIRM" in
[sS]*)
if [[ -n $(docker ps -a -q -f name=onos) ]]; then
docker restart onos >/dev/null
echo -e "${GREEN}ONOS reiniciado.${RESET}"
log_action "Reiniciou ONOS"
else
echo "Container não existe."
fi
;;
esac
pause
}

# ---------------------------

# Status

# ---------------------------

show_status_header() {
clear
echo "=========================================="
echo "       ONOS Controller - Menu            "
echo "=========================================="

if [[ -n "$CONTROLLER_HOST" ]]; then
echo -e "Status: ${CYAN}REMOTO${RESET} | $CONTROLLER_HOST:$CONTROLLER_PORT"
echo "------------------------------------------"
echo ""
return
fi

if ! docker inspect onos >/dev/null 2>&1; then
echo -e "${RED}NÃO EXISTE${RESET}"
else
RUNNING=$(docker inspect -f '{{.State.Running}}' onos 2>/dev/null)
if [[ "$RUNNING" = "true" ]]; then
HOST=$(get_controller_host)
echo -e "${GREEN}RODANDO${RESET} | $HOST:$CONTROLLER_PORT"
else
echo -e "${YELLOW}PARADO${RESET}"
fi
fi

echo "------------------------------------------"
echo ""
}

# ---------------------------

# Credenciais

# ---------------------------

USER="$ONOS_USER"
PASS="$ONOS_PASS"
SSH_USER="$ONOS_SSH_USER"
SSH_PORT=8101

# ---------------------------

# REST examples (fixed)

# ---------------------------

activate_apps() {
HOST=$(get_controller_host) || { echo "ONOS offline"; pause; return; }

for app in 
org.onosproject.openflow 
org.onosproject.fwd
do
curl -s -X POST -u "$USER:$PASS" 
"http://$HOST:$CONTROLLER_PORT/onos/v1/applications/$app/active" >/dev/null
done

echo "Apps ativadas"
pause
}

show_onos_hosts() {
HOST=$(get_controller_host) || { echo "ONOS offline"; pause; return; }

curl -s -u "$USER:$PASS" 
"http://$HOST:$CONTROLLER_PORT/onos/v1/hosts" | jq

pause
}

# ---------------------------

# Flow delete (correct API)

# ---------------------------

delete_noncore_flows() {
HOST=$(get_controller_host) || {
echo -e "${RED}Erro ao obter controller${RESET}"
return 1
}

read -p "Apagar flows não-core? (s/N): " CONFIRM
[[ ! "$CONFIRM" =~ ^[sS] ]] && return

FLOWS=$(curl -s -u "$USER:$PASS" 
"http://$HOST:$CONTROLLER_PORT/onos/v1/flows" | 
jq -r '.flows[]
| select(.appId != "org.onosproject.core" and .state != "REMOVED")
| "(.deviceId) (.id)"')

while read -r device id; do
[[ -z "$device" ]] && continue

```
curl -s -u "$USER:$PASS" -X DELETE \
  "http://$HOST:$CONTROLLER_PORT/onos/v1/flows/$device/$id" >/dev/null
```

done <<< "$FLOWS"

echo "Flows removidos"
}

# ---------------------------

# Menu

# ---------------------------

while true; do
show_status_header
echo "1) Start ONOS"
echo "2) Stop ONOS"
echo "3) Restart ONOS"
echo "4) Show Hosts"
echo "5) Activate Apps"
echo "6) Delete Flows"
echo "q) Quit"

read -rp "> " opt

case $opt in
1) start_onos_container ;;
2) stop_onos_container ;;
3) restart_onos_container ;;
4) show_onos_hosts ;;
5) activate_apps ;;
6) delete_noncore_flows ;;
q) exit 0 ;;
esac
done
