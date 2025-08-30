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
ssh_karaf() {
  CONTROLLER_IP=$(get_onos_ip)
  if [[ -z $CONTROLLER_IP ]]; then
    echo "ONOS não está rodando. Inicie o container primeiro."
    pause
    return
  fi

  echo "Conectando via SSH ao Karaf (usuário: $SSH_USER)..."
  ssh -p $SSH_PORT $SSH_USER@$CONTROLLER_IP
}

# Menu interativo
while true; do
  clear
  echo "=========================================="
  echo "       ONOS Controller - Menu        "
  echo "=========================================="
  echo ""
  echo "1) Iniciar controladora ONOS"
  echo "2) Mostrar IP do controlador ONOS"
  echo "3) Ativar aplicações ONOS (REST API)"
  echo "4) Mostrar link da Web GUI"
  echo "5) Abrir Web GUI no Firefox"
  echo "6) Conectar via SSH ao Karaf"
  echo "7) Parar ONOS"
  echo "q) Sair (ONOS continua ativo)"
  echo ""
  echo -n "Escolha uma opção: "
  read -r option

  case $option in
    1) start_onos_container ;;
    2) show_controller_ip ;;
    3) activate_apps ;;
    4) show_gui_link ;;
    5) open_firefox ;;
    6) ssh_karaf ;; # sem pause, pq o ssh já toma a tela
    7) stop_onos_container ;;
    q) echo "Saindo..."; exit 0 ;;
    *) echo "Opção inválida."; pause ;;
  esac
done
