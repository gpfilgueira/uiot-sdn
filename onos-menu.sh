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

# Função auxiliar para pausar
pause() {
  echo ""
  read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
}

# Função para iniciar ou criar o container ONOS
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
      echo "Container ONOS existe mas está parado. Iniciando..."
      docker start onos >/dev/null
      echo "Container ONOS iniciado."
      log_action "Iniciou container ONOS"
    fi
  fi
  pause
}

# Função para parar o container ONOS com confirmação
stop_onos_container() {
  echo ""
  read -p "Tem certeza que deseja parar o ONOS? (s/N): " CONFIRM
  case "$CONFIRM" in
    [sS]|[sS][iI][mM])
      echo "Parando container ONOS..."
      if [[ -n $(docker ps -q -f name=onos) ]]; then
        docker stop onos >/dev/null
        echo "Container ONOS parado."
        log_action "Parou container ONOS"
      else
        echo "Container ONOS não está rodando."
      fi
      ;;
    *)
      echo "Operação cancelada."
      ;;
  esac
  pause
}

# Quick restart (restart_onos_container)
restart_onos_container() {
  read -p "Deseja reiniciar o ONOS? (s/N): " CONFIRM
  case "$CONFIRM" in
    [sS]|[sS][iI][mM])
      echo "Reiniciando container ONOS..."
      if [[ -n $(docker ps -a -q -f name=onos) ]]; then
        docker restart onos >/dev/null
        echo -e "${GREEN}ONOS reiniciado com sucesso.${RESET}"
        log_action "Reiniciou container ONOS"
      else
        echo "Container ONOS não existe. Use a opção de iniciar para criar." 
      fi
      ;;
    *)
      echo "Operação cancelada."
      ;;
  esac
  pause
}

# Função para obter IP do ONOS
# Controller endpoint configuration
CONTROLLER_HOST="${CONTROLLER_HOST:-}"
CONTROLLER_PORT="${CONTROLLER_PORT:-8181}"
get_controller_host() {
    if [[ -n "$CONTROLLER_HOST" ]]; then
        echo "$CONTROLLER_HOST"
    else
        docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' onos
    fi
}

# Barra de status
show_status_header() {
  clear
  echo "=========================================="
  echo "       ONOS Controller - Menu            "
  echo "=========================================="

  LOCAL_HOST=$(get_controller_host)

  # REMOTE MODE (explicit host set)
  if [[ -n "$CONTROLLER_HOST" ]]; then
    echo -e "Status: ${CYAN}REMOTO${RESET}   | Host: $CONTROLLER_HOST:$CONTROLLER_PORT"
    echo "------------------------------------------"
    echo ""
    return
  fi

  # LOCAL MODE (Docker-based)
  if ! docker inspect onos >/dev/null 2>&1; then
    echo -e "Status: ${RED}NÃO EXISTE${RESET} | Container: onos"
  else
    RUNNING=$(docker inspect -f '{{.State.Running}}' onos 2>/dev/null)

    if [[ "$RUNNING" = "true" ]]; then
      echo -e "Status: ${GREEN}RODANDO${RESET}   | IP: $LOCAL_HOST:$CONTROLLER_PORT"
    else
      echo -e "Status: ${YELLOW}PARADO${RESET}    | Container existe"
    fi
  fi

  echo "------------------------------------------"
  echo ""
}

# -----------------------------
# Submenus e funções existentes
# -----------------------------

# Função para mostrar o IP do container ONOS
show_controller_ip() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando ou IP não encontrado."
  else
    echo "IP do controlador ONOS: $CONTROLLER_HOST"
  fi
  pause
}

# Credenciais REST e SSH (.secrets)
USER="$ONOS_USER"
PASS="$ONOS_PASS"
SSH_USER="$ONOS_SSH_USER"
SSH_PASS="$ONOS_SSH_PASS"

SSH_PORT=8101

# Lista de aplicações para ativar via REST
apps=(
  "org.onosproject.openflow-message"
  "org.onosproject.ofagent"
  "org.onosproject.openflow-base"
  "org.onosproject.openflow"
  "org.onosproject.workflow.ofoverlay"
  "org.onosproject.fwd"
)

# Função para ativar apps via REST API
activate_apps() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Ativando aplicações ONOS via REST API..."
  for app in "${apps[@]}"; do
    echo -n "Ativando $app ... "
    curl -s -X POST -u $USER:$PASS http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/applications/$app/active >/dev/null
    echo "OK"
  done
  echo "Todas as aplicações ativadas."
  log_action "Ativou apps via REST"
  pause
}

# Função para abrir Firefox na Web GUI
open_firefox() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Abrindo Firefox na Web GUI do ONOS..."
  firefox "http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/ui" &
  pause
}

show_gui_link() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando."
  else
    echo "http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/ui"
  fi
  pause
}

# Função para conectar via SSH ao Karaf
ssh_karaf() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Conectando via SSH ao Karaf (usuário: $SSH_USER)..."
  echo ""

  # Executa o SSH e captura saída e código de retorno
  ssh -p $SSH_PORT "$SSH_USER@$CONTROLLER_HOST"
  EXIT_CODE=$?

  if [[ $EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "## A conexão SSH falhou (código $EXIT_CODE). ##"
    echo "Provavelmente é o erro de chave de host."
    echo ""
    echo "Mensagem acima contém o comando sugerido pelo SSH para corrigir."
    echo "Você pode copiá-lo agora antes de retornar ao menu."
    echo ""
    read -n 1 -s -r -p "Pressione qualquer tecla para voltar ao menu..."
  fi
}

# Função para mostrar hosts atuais no ONOS
show_onos_hosts() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Obtendo lista de hosts registrados no ONOS..."
  echo ""

  # Usa jq se estiver disponível para formatação
  if command -v jq >/dev/null 2>&1; then
    curl -s -u "$USER:$PASS" http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/hosts | jq
  else
    curl -s -u "$USER:$PASS" http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/hosts
  fi

  pause
}

# Função para listar hosts e bloquear um selecionado
block_onos_host() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "Erro: jq é necessário para esta função."
    pause
    return
  fi

  echo "Obtendo hosts..."
  HOSTS_JSON=$(curl -s -u "$USER:$PASS" http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/hosts)

  HOST_COUNT=$(echo "$HOSTS_JSON" | jq '.hosts | length')
  if [[ $HOST_COUNT -eq 0 ]]; then
    echo "Nenhum host encontrado."
    pause
    return
  fi

  echo ""
  echo "=== Hosts Detectados ==="
  for ((i=0; i<HOST_COUNT; i++)); do
    MAC=$(echo "$HOSTS_JSON" | jq -r ".hosts[$i].mac")
    IP=$(echo "$HOSTS_JSON" | jq -r ".hosts[$i].ipAddresses[0]")
    echo "$((i+1))) MAC: $MAC | IP: $IP"
  done
  echo ""

  read -p "Escolha o host para BLOQUEAR: " CHOICE
  if ! [[ $CHOICE =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > HOST_COUNT )); then
    echo "Escolha inválida."
    pause
    return
  fi

  SELECTED_MAC=$(echo "$HOSTS_JSON" | jq -r ".hosts[$((CHOICE-1))].mac")

  echo ""
  echo "Bloqueando MAC: $SELECTED_MAC"
  echo ""

  # GET ALL SWITCHES
  DEVICES=$(curl -s -u "$USER:$PASS" http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/devices | jq -r '.devices[].id')

  for DEVICE in $DEVICES; do
    echo "→ Aplicando bloqueio no switch $DEVICE"

    # BLOCK OUTGOING (SRC)
    FLOW_SRC=$(jq -n \
      --arg device "$DEVICE" \
      --arg mac "$SELECTED_MAC" \
      '{
        priority: 65000,
        isPermanent: true,
        deviceId: $device,
        selector: {
          criteria: [
            { type: "ETH_SRC", mac: $mac }
          ]
        },
        treatment: { instructions: [] }
      }')

    curl -s -u "$USER:$PASS" \
      -X POST \
      -H "Content-Type: application/json" \
      -d "$FLOW_SRC" \
      http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/flows/$DEVICE >/dev/null

    # BLOCK INCOMING (DST)
    FLOW_DST=$(jq -n \
      --arg device "$DEVICE" \
      --arg mac "$SELECTED_MAC" \
      '{
        priority: 65000,
        isPermanent: true,
        deviceId: $device,
        selector: {
          criteria: [
            { type: "ETH_DST", mac: $mac }
          ]
        },
        treatment: { instructions: [] }
      }')

    curl -s -u "$USER:$PASS" \
      -X POST \
      -H "Content-Type: application/json" \
      -d "$FLOW_DST" \
      http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/flows/$DEVICE >/dev/null
  done

  echo ""
  echo -e "${GREEN}Host completamente bloqueado em todos os switches.${RESET}"
  log_action "Bloqueou host globalmente $SELECTED_MAC"

  pause
}

# Função para listar hosts e desbloquear um selecionado
unblock_onos_host() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "Erro: jq é necessário para esta função."
    pause
    return
  fi

  echo "Obtendo hosts..."
  HOSTS_JSON=$(curl -s -u "$USER:$PASS" http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/hosts)

  HOST_COUNT=$(echo "$HOSTS_JSON" | jq '.hosts | length')
  if [[ $HOST_COUNT -eq 0 ]]; then
    echo "Nenhum host encontrado."
    pause
    return
  fi

  echo ""
  echo "=== Hosts Detectados ==="
  for ((i=0; i<HOST_COUNT; i++)); do
    MAC=$(echo "$HOSTS_JSON" | jq -r ".hosts[$i].mac")
    IP=$(echo "$HOSTS_JSON" | jq -r ".hosts[$i].ipAddresses[0]")
    echo "$((i+1))) MAC: $MAC | IP: $IP"
  done
  echo ""

  read -p "Escolha o host para DESBLOQUEAR: " CHOICE
  if ! [[ $CHOICE =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > HOST_COUNT )); then
    echo "Escolha inválida."
    pause
    return
  fi

  SELECTED_MAC=$(echo "$HOSTS_JSON" | jq -r ".hosts[$((CHOICE-1))].mac")

  echo ""
  echo "Removendo bloqueios para MAC: $SELECTED_MAC"
  echo ""

  # GET ALL FLOWS
  FLOWS_JSON=$(curl -s -u "$USER:$PASS" http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/flows)

  # FILTER matching flows (priority + MAC)
  MATCHING=$(echo "$FLOWS_JSON" | jq -r \
      --arg mac "$SELECTED_MAC" \
      '.flows[]
  | select(.priority == 65000)
  | select(
      any(.selector.criteria[]?;
      (.type=="ETH_SRC" and .mac==$mac) or
      (.type=="ETH_DST" and .mac==$mac)
  )
)
| "\(.deviceId) \(.id)"')

if [[ -z "$MATCHING" ]]; then
    echo "Nenhum bloqueio encontrado para este host."
      pause
      return
  fi

  echo "Flows de bloqueio encontrados:"
  echo "$MATCHING"
  echo ""

  # DELETE flows
  while read -r DEVICE FLOW_ID; do
      [[ -z "$DEVICE" || -z "$FLOW_ID" ]] && continue

      echo "→ Removendo flow $FLOW_ID de $DEVICE"

      curl -s -u "$USER:$PASS" \
          -X DELETE \
          http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/flows/$DEVICE/$FLOW_ID >/dev/null

  done <<< "$MATCHING"

  echo ""
  echo -e "${GREEN}Host desbloqueado com sucesso.${RESET}"
  log_action "Desbloqueou host $SELECTED_MAC"

  pause
}

# Função para listar todos os flows que não são de core (versão detalhada)
list_non_core_flows() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Obtendo lista de flows não-core..."
  echo ""

  FLOW_JSON=$(curl -s -u "$USER:$PASS" http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/flows)

  if ! command -v jq >/dev/null 2>&1; then
    echo "Erro: jq é necessário para esta função."
    pause
    return
  fi

  NON_CORE=$(echo "$FLOW_JSON" | jq '[.flows[] | select(.appId != "org.onosproject.core")]')

  COUNT=$(echo "$NON_CORE" | jq 'length')
  if [[ $COUNT -eq 0 ]]; then
    echo "Nenhum flow não-core encontrado."
    pause
    return
  fi

  echo "=== Flows não-core detectados ==="
  for ((i=0; i<COUNT; i++)); do
    ID=$(echo "$NON_CORE" | jq -r ".[$i].id")
    APP=$(echo "$NON_CORE" | jq -r ".[$i].appId")
    SWITCH=$(echo "$NON_CORE" | jq -r ".[$i].deviceId")
    PRIORITY=$(echo "$NON_CORE" | jq -r ".[$i].priority")
    echo "$((i+1))) ID: $ID  |  App: $APP  |  Switch: $SWITCH  |  Priority: $PRIORITY"
  done
  echo "==============================="
  echo ""

  # Armazena o JSON temporário para possível deleção posterior
  echo "$NON_CORE" > /tmp/onos_noncore_flows.json
  pause
}

confirm_action() {
  read -p "$1 (s/N): " CONFIRM
  case "$CONFIRM" in
    [sS]|[sS][iI][mM]) return 0 ;;
    *) echo "Operação cancelada."; return 1 ;;
  esac
}

# Função para deletar flows não-core selecionados
delete_noncore_flows() {
    local HOST
    HOST=$(get_controller_host) || {
        echo -e "${RED}Erro: não foi possível obter o host do controller.${RESET}"
        return 1
    }

    confirm_action "Deseja realmente apagar todos os flows não-core?" || return
    echo -e "${CYAN}Apagando flows não-core...${RESET}"

    # Coleta (deviceId + flowId)
    local FLOWS
    FLOWS=$(curl -s -u "$USER:$PASS" \
        "http://$HOST:$CONTROLLER_PORT/onos/v1/flows" | \
        jq -r '.flows[]
            | select(.appId != "org.onosproject.core" and .state != "REMOVED")
            | "\(.deviceId) \(.id)"')

    if [[ -z "$FLOWS" ]]; then
        echo -e "${YELLOW}Nenhum flow não-core encontrado.${RESET}"
        return
    fi

    # Deleta cada flow corretamente (deviceId + flowId)
    while read -r device id; do
        [[ -z "$device" || -z "$id" ]] && continue

        curl -s -u "$USER:$PASS" -X DELETE \
            "http://$HOST:$CONTROLLER_PORT/onos/v1/flows/$device/$id" >/dev/null

    done <<< "$FLOWS"

    echo -e "${GREEN}Flows não-core removidos.${RESET}"

    # Pequeno delay para consistência
    sleep 2

    # Mostra estado atual após limpeza
    echo -e "${CYAN}Flows restantes:${RESET}"
    curl -s -u "$USER:$PASS" \
        "http://$HOST:$CONTROLLER_PORT/onos/v1/flows" | \
        jq '.flows[]
            | select(.appId != "org.onosproject.core")
            | {device: .deviceId, id: .id, app: .appId, state: .state}'
}

# ---------------------------
# Funções de netcfg
# ---------------------------

# Função para enviar netcfg JSON via api REST
send_netcfg() {
    CONTROLLER_HOST=$(get_controller_host)
    if [[ -z $CONTROLLER_HOST ]]; then
        echo "ONOS não está rodando. Inicie o container primeiro."
        pause
        return
    fi

    if [[ ! -f network-cfg.json ]]; then
        echo "Você precisa ter um arquivo 'network-cfg.json' no mesmo diretório que este script!"
        pause
        return
    fi

    echo "Enviando network-cfg.json para ONOS via REST API..."
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -u "$USER:$PASS" -X POST \
        -H "Content-Type: application/json" \
        http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/network/configuration/ \
        -d @network-cfg.json)

    if [[ "$RESPONSE" -ge 200 && "$RESPONSE" -lt 300 ]]; then
        echo "JSON enviado com sucesso!"
        log_action "Enviou network-cfg.json"
    else
        echo "Falha ao enviar JSON. Código HTTP: $RESPONSE"
    fi

    pause
}

# Backup do netcfg (salva em arquivo de backup)
backup_netcfg() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Impossível fazer backup."
    return 1
  fi
  BACKUP_FILE="netcfg-backup-$(date +%Y%m%d-%H%M%S).json"
  curl -s -u "$USER:$PASS" "http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/network/configuration" > "$BACKUP_FILE"
  if [[ $? -eq 0 ]]; then
    echo "Backup salvo em $BACKUP_FILE"
    log_action "Backup netcfg em $BACKUP_FILE"
    return 0
  else
    echo "Falha ao salvar backup de netcfg."
    return 1
  fi
}

# Restore do netcfg (enviar arquivo JSON para ONOS)
restore_netcfg() {
  FILE="$1"
  if [[ -z "$FILE" || ! -f "$FILE" ]]; then
    echo "Uso: restore_netcfg <arquivo.json>"
    return 1
  fi
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando. Impossível restaurar."
    return 1
  fi

  echo "Enviando $FILE para ONOS (restore netcfg)..."
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -u "$USER:$PASS" -X POST \
    -H "Content-Type: application/json" \
    http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/network/configuration \
    -d @$FILE)

  if [[ "$RESPONSE" -ge 200 && "$RESPONSE" -lt 300 ]]; then
    echo "Restauração enviada com sucesso."
    log_action "Restaurou netcfg a partir de $FILE"
    return 0
  else
    echo "Falha ao restaurar. Código HTTP: $RESPONSE"
    return 1
  fi
}

# Mostra netcfg
show_netcfg() {
    CONTROLLER_HOST=$(get_controller_host)
    if [[ -z $CONTROLLER_HOST ]]; then
        echo "ONOS não está rodando. Inicie o container primeiro."
        pause
        return
    fi

    echo "Obtendo configuração atual do ONOS (network-cfg)..."
    echo ""

    if command -v jq >/dev/null 2>&1; then
        curl -s -u "$USER:$PASS" \
            http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/network/configuration | jq
    else
        curl -s -u "$USER:$PASS" \
            http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/network/configuration
    fi

    pause
}

# Deleta completamente a configuração de rede (netcfg wipe-out)
delete_netcfg() {
    CONTROLLER_HOST=$(get_controller_host)
    if [[ -z $CONTROLLER_HOST ]]; then
        echo "ONOS não está rodando. Inicie o container primeiro."
        pause
        return
    fi

    echo ""
    read -p "Tem certeza que deseja APAGAR toda a configuração (network-cfg)? (s/N): " CONFIRM
    case "$CONFIRM" in
        [sS]|[sS][iI][mM])
            echo "Criando backup antes do wipe..."
            backup_netcfg || echo "Falha ao criar backup (prosseguindo com delete)."

            echo "Removendo configuração de rede do ONOS..."
            RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
                -u "$USER:$PASS" \
                -X DELETE \
                http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/network/configuration)

            if [[ "$RESPONSE" -ge 200 && "$RESPONSE" -lt 300 ]]; then
                echo "Configuração de rede removida com sucesso!"
                log_action "Apagou network-cfg (wipe-out)"
            else
                echo "Falha ao apagar configuração. Código HTTP: $RESPONSE"
            fi
            ;;
        *)
            echo "Operação cancelada."
            ;;
    esac

    pause
}

# Health check do ONOS
check_onos_health() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo -e "${RED}ONOS offline ou IP não encontrado.${RESET}"
    pause
    return 1
  fi

  echo -e "${BLUE}Verificando integridade do ONOS em $CONTROLLER_HOST...${RESET}"
  echo ""

  # Tenta endpoint /system/health e guarda o código HTTP
  HTTP_CODE=$(curl -s -o /tmp/onos_health.json -w "%{http_code}" \
    -u "$USER:$PASS" "http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/system/health")

  # Se for 404 ou vazio, tenta fallback /system
  if [[ "$HTTP_CODE" -eq 404 || "$HTTP_CODE" -eq 0 ]]; then
    HTTP_CODE=$(curl -s -o /tmp/onos_health.json -w "%{http_code}" \
      -u "$USER:$PASS" "http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/system")
    echo -e "${YELLOW}Endpoint /system/health indisponível, usando /system...${RESET}"
  fi

  # Exibe status de acordo com o código HTTP
  if [[ "$HTTP_CODE" -eq 200 ]]; then
    echo -e "${GREEN}ONOS respondeu (HTTP 200)${RESET}"
  else
    echo -e "${RED}ONOS respondeu com erro HTTP $HTTP_CODE${RESET}"
  fi

  echo ""

  # Exibe conteúdo formatado se houver resposta válida
  if [[ -s /tmp/onos_health.json ]]; then
    if command -v jq >/dev/null 2>&1; then
      jq . /tmp/onos_health.json
    else
      cat /tmp/onos_health.json
    fi
  fi

  log_action "Checou health do ONOS (HTTP $HTTP_CODE)"
  echo ""
  pause
  return 0
}

# Exportar topologia
export_topology() {
  CONTROLLER_HOST=$(get_controller_host)
  if [[ -z $CONTROLLER_HOST ]]; then
    echo "ONOS não está rodando."
    pause
    return
  fi
  OUTPUT="onos-topology-$(date +%Y%m%d-%H%M%S).json"
  curl -s -u "$USER:$PASS" "http://$CONTROLLER_HOST:$CONTROLLER_PORT/onos/v1/topology" > "$OUTPUT"
  if [[ $? -eq 0 ]]; then
    echo "Topologia exportada em $OUTPUT"
    log_action "Exportou topologia em $OUTPUT"
  else
    echo "Falha ao exportar topologia."
  fi
  pause
}

# ---------------------------
# Submenus
# ---------------------------

submenu_management() {
  while true; do
    show_status_header
    echo "GERENCIAMENTO ONOS"
    echo "1) Iniciar controladora ONOS"
    echo "2) Mostrar IP do controlador ONOS"
    echo "3) Abrir Web GUI no Firefox"
    echo "4) Conectar via SSH ao Karaf"
    echo "k) Parar ONOS"
    echo "r) Reiniciar ONOS"
    echo "b) Voltar"
    echo "q) Sair (ONOS continua ativo)"
    echo ""
    read -rp "Escolha: " opt
    case $opt in
      1) start_onos_container ;;
      2) show_controller_ip ;;
      3) open_firefox ;;
      4) ssh_karaf ;;
      k) stop_onos_container ;;
      r) restart_onos_container ;;
      b) break ;;
      q) echo "Saindo..."; exit 0 ;;
      *) echo "Opção inválida."; pause ;;
    esac
  done
}

submenu_interactions() {
  while true; do
    show_status_header
    echo "INTERAÇÕES REST / HOSTS / FLOWS"
    echo "1) Ativar aplicações ONOS (REST API)"
    echo "2) Enviar network-cfg.json via REST API"
    echo "3) Mostrar configuração atual (netcfg)"
    echo "4) Apagar configuração (wipe-out netcfg)"
    echo "5) Restaurar configuração (restore netcfg de arquivo)"
    echo "6) Fazer backup do netcfg"
    echo "7) Mostrar link da Web GUI"
    echo "8) Mostrar hosts atuais (REST API)"
    echo "9) Bloquear um host (REST API)"
    echo "10) Desbloquear um host (REST API)"
    echo "11) Exportar topologia"
    echo "12) Listar flows não-core (REST API)"
    echo "13) Deletar flows não-core (REST API)"
    echo "14) Health-check do ONOS"
    echo "b) Voltar"
    echo "q) Sair (ONOS continua ativo)"
    echo ""
    read -rp "Escolha: " opt
    case $opt in
      1) activate_apps ;;
      2) send_netcfg ;;
      3) show_netcfg ;;
      4) delete_netcfg ;;
      5) 
         read -rp "Arquivo JSON para restaurar: " F && restore_netcfg "$F" ;;
      6) backup_netcfg ;;
      7) show_gui_link ;;
      8) show_onos_hosts ;;
      9) block_onos_host ;;
      10) unblock_onos_host ;;
      11) export_topology ;;
      12) list_non_core_flows ;;
      13) delete_noncore_flows ;;
      14) check_onos_health ;;
      b) break ;;
      q) echo "Saindo..."; exit 0 ;;
      *) echo "Opção inválida."; pause ;;
    esac
  done
}

# ---------------------------
# Modo sem menu (flags) - permite chamadas diretas
# ---------------------------

print_usage() {
  cat <<EOF
Uso: $0 [OPÇÃO]
Opções disponíveis (modo sem menu):
  --backup-ncfg               : Faz backup do netcfg e salva arquivo
  --restore-ncfg <arquivo>    : Restaura netcfg a partir do arquivo JSON
  --show-ncfg                 : Mostra netcfg atual
  --delete-ncfg               : Apaga network-cfg (wipe-out) com backup
  --export-topology           : Exporta topologia para arquivo JSON
  --health                    : Faz health-check do ONOS
  --restart                   : Reinicia o container ONOS
  --start                     : Inicia/cria o container ONOS
  --stop                      : Para o container ONOS
  --list-flows                : Lista flows não-core
  --delete-flows              : Deleta flows não-core
  --show-hosts                : Mostra hosts
  --help                      : Mostra esta ajuda
EOF
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    --backup-ncfg) backup_netcfg; exit $? ;;
    --restore-ncfg) restore_netcfg "$2"; exit $? ;;
    --show-ncfg) show_netcfg; exit 0 ;;
    --delete-ncfg) delete_netcfg; exit 0 ;;
    --export-topology) export_topology; exit 0 ;;
    --health) check_onos_health; exit 0 ;;
    --restart) docker restart onos && echo "ONOS reiniciado" || echo "Falha ao reiniciar"; exit 0 ;;
    --start) start_onos_container; exit 0 ;;
    --stop) stop_onos_container; exit 0 ;;
    --list-flows) list_non_core_flows; exit 0 ;;
    --delete-flows) delete_noncore_flows; exit 0 ;;
    --show-hosts) show_onos_hosts; exit 0 ;;
    --help) print_usage; exit 0 ;;
    *) echo "Opção desconhecida: $1"; print_usage; exit 1 ;;
  esac
fi

# ---------------------------
# Menu principal
# ---------------------------
while true; do
  show_status_header
  echo "1) Gerenciamento do ONOS"
  echo "2) Interações REST / Hosts / Flows"
  echo "q) Sair (ONOS continua ativo)"
  echo ""
  read -rp "Escolha uma opção: " option

  case $option in
    1) submenu_management ;;
    2) submenu_interactions ;;
    q) echo "Saindo..."; exit 0 ;;
    *) echo "Opção inválida."; pause ;;
  esac
done
