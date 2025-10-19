#!/usr/bin/env bash

# Carrega arquivo .secrets
if [ -f ".secrets" ]; then
    source .secrets
else
    echo "Erro: Arquivo .secrets não encontrado!" >&2
    exit 1
fi

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
  else
    RUNNING=$(docker inspect -f '{{.State.Running}}' onos 2>/dev/null)
    if [ "$RUNNING" = "true" ]; then
      echo "Container ONOS já está rodando."
    else
      echo "Container ONOS existe mas está parado. Iniciando..."
      docker start onos >/dev/null
      echo "Container ONOS iniciado."
    fi
  fi
  pause
}

# Função para parar o container ONOS
stop_onos_container() {
  echo "Parando container ONOS..."
  if docker ps -q -f name=onos >/dev/null; then
    docker stop onos >/dev/null
    echo "Container ONOS parado."
  else
    echo "Container ONOS não está rodando."
  fi
  pause
}

# Função para obter IP do ONOS
get_onos_ip() {
  docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' onos 2>/dev/null
}

# Função para mostrar o IP do container ONOS
show_controller_ip() {
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando ou IP não encontrado."
  else
    echo "IP do controlador ONOS: $CONTROLLER_IP"
  fi
  pause
}

# Credenciais REST e SSH (.secrets)
USER="$ONOS_USER"
PASS="$ONOS_PASS"
SSH_USER="$ONOS_SSH_USER"
SSH_PASS="$ONOS_SSH_PASS"

WEB_GUI_PORT=8181
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
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Ativando aplicações ONOS via REST API..."
  for app in "${apps[@]}"; do
    echo -n "Ativando $app ... "
    curl -s -X POST -u $USER:$PASS http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/v1/applications/$app/active >/dev/null
    echo "OK"
  done
  echo "Todas as aplicações ativadas."
  pause
}

# Função para abrir Firefox na Web GUI
open_firefox() {
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Abrindo Firefox na Web GUI do ONOS..."
  firefox "http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/ui" &
  pause
}

show_gui_link() {
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando."
  else
    echo "http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/ui"
  fi
  pause
}

# Função para conectar via SSH ao Karaf
# Função para conectar via SSH ao Karaf
ssh_karaf() {
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Conectando via SSH ao Karaf (usuário: $SSH_USER)..."
  echo ""

  # Executa o SSH e captura saída e código de retorno
  ssh -p $SSH_PORT "$SSH_USER@$CONTROLLER_IP"
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

# Função para enviar JSON com nomes amigáveis via REST
apirest_friendlynames_json() {
    CONTROLLER_IP=$(get_onos_ip)
    if [[ -z $CONTROLLER_IP ]]; then
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
        http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/v1/network/configuration \
        -d @localtest-netcfg.json)

    if [[ "$RESPONSE" -ge 200 && "$RESPONSE" -lt 300 ]]; then
        echo "JSON enviado com sucesso!"
    else
        echo "Falha ao enviar JSON. Código HTTP: $RESPONSE"
    fi
    pause
}

# Função para mostrar hosts atuais no ONOS
show_onos_hosts() {
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Obtendo lista de hosts registrados no ONOS..."
  echo ""

  # Usa jq se estiver disponível para formatação
  if command -v jq >/dev/null 2>&1; then
    curl -s -u "$USER:$PASS" http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/v1/hosts | jq
  else
    curl -s -u "$USER:$PASS" http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/v1/hosts
  fi

  pause
}

# Função para listar hosts e bloquear um selecionado
block_onos_host() {
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Obtendo lista de hosts do ONOS..."
  HOSTS_JSON=$(curl -s -u "$USER:$PASS" http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/v1/hosts)

  # Verifica se jq está instalado
  if ! command -v jq >/dev/null 2>&1; then
    echo "Erro: jq é necessário para esta função."
    pause
    return
  fi

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
    LOC=$(echo "$HOSTS_JSON" | jq -r ".hosts[$i].locations[0].elementId")
    PORT=$(echo "$HOSTS_JSON" | jq -r ".hosts[$i].locations[0].port")
    echo "$((i+1))) MAC: $MAC  |  IP: $IP  |  Local: $LOC/$PORT"
  done
  echo "========================"
  echo ""

  read -p "Digite o número do host que deseja BLOQUEAR: " CHOICE
  if ! [[ $CHOICE =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > HOST_COUNT )); then
    echo "Escolha inválida."
    pause
    return
  fi

  SELECTED_MAC=$(echo "$HOSTS_JSON" | jq -r ".hosts[$((CHOICE-1))].mac")
  SELECTED_IP=$(echo "$HOSTS_JSON" | jq -r ".hosts[$((CHOICE-1))].ipAddresses[0]")
  LOCATION_SWITCH=$(echo "$HOSTS_JSON" | jq -r ".hosts[$((CHOICE-1))].locations[0].elementId")
  LOCATION_PORT=$(echo "$HOSTS_JSON" | jq -r ".hosts[$((CHOICE-1))].locations[0].port")

  echo ""
  echo "Bloqueando host:"
  echo "  MAC: $SELECTED_MAC"
  echo "  IP:  $SELECTED_IP"
  echo "  Local: $LOCATION_SWITCH/$LOCATION_PORT"
  echo ""

  read -p "Digite o VLAN ID (ou pressione Enter para ignorar): " VLAN_ID

  # Monta o JSON do fluxo
  if [[ -n $VLAN_ID ]]; then
    FLOW_JSON=$(jq -n \
      --arg switch "$LOCATION_SWITCH" \
      --arg mac "$SELECTED_MAC" \
      --arg vlan "$VLAN_ID" \
      '{
        priority: 64000,
        isPermanent: true,
        deviceId: $switch,
        selector: {
          criteria: [
            { type: "ETH_DST", mac: $mac },
            { type: "VLAN_VID", vlanId: ($vlan | tonumber) }
          ]
        },
        treatment: { instructions: [] }
      }'
    )
  else
    FLOW_JSON=$(jq -n \
      --arg switch "$LOCATION_SWITCH" \
      --arg mac "$SELECTED_MAC" \
      '{
        priority: 64000,
        isPermanent: true,
        deviceId: $switch,
        selector: {
          criteria: [
            { type: "ETH_DST", mac: $mac }
          ]
        },
        treatment: { instructions: [] }
      }'
    )
  fi

  # Envia o flow para o endpoint correto (sem ?appId=)
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$USER:$PASS" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$FLOW_JSON" \
    http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/v1/flows/$LOCATION_SWITCH)

  if [[ "$RESPONSE" -ge 200 && "$RESPONSE" -lt 300 ]]; then
    echo "✅ Host bloqueado com sucesso!"
  else
    echo "❌ Falha ao enviar flow. Código HTTP: $RESPONSE"
  fi

  pause
}
#
# Função para listar todos os flows que não são de core
list_non_core_flows() {
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Obtendo lista de flows instalados no ONOS..."
  echo ""

  FLOWS_JSON=$(curl -s -u "$USER:$PASS" http://$CONTROLLER_IP:$WEB_GUI_PORT/onos/v1/flows)

  if ! command -v jq >/dev/null 2>&1; then
    echo "Erro: jq é necessário para esta função."
    pause
    return
  fi

  # Filtra apenas flows cujo appId NÃO começa com "org.onosproject.core"
  NON_CORE=$(echo "$FLOWS_JSON" | jq '.flows[] | select(.appId | startswith("org.onosproject.core") | not)')

  if [[ -z "$NON_CORE" ]]; then
    echo "Nenhum flow não-core encontrado."
    pause
    return
  fi

  echo "=== Flows Não-Core ==="
  echo "$FLOWS_JSON" | jq -r '
    .flows[]
    | select(.appId | startswith("org.onosproject.core") | not)
    | "Device: \(.deviceId) | App: \(.appId) | Priority: \(.priority) | State: \(.state)\n  Selector: \(.selector.criteria)\n"'
  echo "======================="
  pause
}

# Menu interativo (reorganizado)
while true; do
  clear
  echo "=========================================="
  echo "        ONOS Controller - Menu"
  echo "=========================================="
  echo ""
  echo "1) Iniciar controladora ONOS"
  echo "2) Parar ONOS"
  echo "3) Mostrar IP do controlador ONOS"
  echo "4) Ativar aplicações ONOS (REST API)"
  echo "5) Enviar network-cfg.json via REST API"
  echo "6) Mostrar link da Web GUI"
  echo "7) Abrir Web GUI no Firefox"
  echo "8) Conectar via SSH ao Karaf"
  echo "9) Mostrar hosts atuais (REST API)"
  echo "10) Bloquear um host (REST API)"
  echo "11) Listar flows não-core (REST API)"
  echo ""
  echo "q) Sair (ONOS continua ativo)"
  echo ""
  echo -n "Escolha uma opção: "
  read -r option

  case $option in
    1) start_onos_container ;;
    2) stop_onos_container ;;
    3) show_controller_ip ;;
    4) activate_apps ;;
    5) apirest_friendlynames_json ;;
    6) show_gui_link ;;
    7) open_firefox ;;
    8) ssh_karaf ;;
    9) show_onos_hosts ;;
    10) block_onos_host ;;
    11) list_non_core_flows ;;
    q) echo "Saindo..."; exit 0 ;;
    *) echo "Opção inválida."; pause ;;
  esac
done
