#!/usr/bin/env bash

# ===============================
#  ONOS Management Script
#  Foco: clareza, usabilidade e estrutura hierárquica
# ===============================

# === Carrega arquivo .secrets ===
if [ -f ".secrets" ]; then
    source .secrets
else
    echo "Erro: Arquivo .secrets não encontrado!" >&2
    exit 1
fi

# === Cores ===
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

# === Funções auxiliares ===
pause() {
    read -rp "Pressione Enter para continuar..."
}

confirm_action() {
    read -rp "$1 (s/N): " confirm
    [[ $confirm == [sS] ]] || return 1
}

check_onos_running() {
    docker ps --filter "name=onos" --format '{{.Names}}' | grep -q "onos"
}

show_status() {
    clear
    echo -e "${BOLD}==========================================${RESET}"
    echo -e "${BOLD}   ONOS Management Interface${RESET}"
    echo -e "${BOLD}==========================================${RESET}"
    echo

    if check_onos_running; then
        ONOS_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' onos)
        echo -e "Status: ${GREEN}RODANDO${RESET}"
        echo -e "IP: ${CYAN}${ONOS_IP}${RESET}"
    else
        echo -e "Status: ${RED}PARADO${RESET}"
        echo -e "IP: ${YELLOW}N/D${RESET}"
    fi

    echo -e "Containers ativos: $(docker ps -q | wc -l)"
    echo
}

# === Funções principais ===

start_onos() {
    if check_onos_running; then
        echo -e "${YELLOW}O ONOS já está em execução.${RESET}"
        return
    fi
    echo -e "${CYAN}Iniciando o container ONOS...${RESET}"
    docker run -d --name onos --net=onos-net --ip 172.18.0.2 onosproject/onos
    echo -e "${GREEN}ONOS iniciado com sucesso.${RESET}"
}

stop_onos() {
    if ! check_onos_running; then
        echo -e "${YELLOW}O ONOS não está rodando.${RESET}"
        return
    fi
    confirm_action "Tem certeza de que deseja parar o ONOS?" || return
    echo -e "${CYAN}Parando o container ONOS...${RESET}"
    docker stop onos && docker rm onos
    echo -e "${GREEN}ONOS parado e removido.${RESET}"
}

show_ip() {
    if check_onos_running; then
        docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' onos
    else
        echo -e "${YELLOW}ONOS não está em execução.${RESET}"
    fi
}

open_gui() {
    if check_onos_running; then
        xdg-open "http://172.18.0.2:8181/onos/ui" >/dev/null 2>&1 &
        echo -e "${GREEN}Abrindo interface web do ONOS...${RESET}"
    else
        echo -e "${YELLOW}ONOS não está em execução.${RESET}"
    fi
}

connect_ssh() {
    if check_onos_running; then
        docker exec -it onos /bin/bash -c "ssh -p 8101 karaf@localhost"
    else
        echo -e "${YELLOW}ONOS não está em execução.${RESET}"
    fi
}

activate_apps() {
    echo -e "${CYAN}Ativando aplicações padrão...${RESET}"
    curl -u "$ONOS_USER:$ONOS_PASS" -X POST http://172.18.0.2:8181/onos/v1/applications/org.onosproject.fwd/active
    curl -u "$ONOS_USER:$ONOS_PASS" -X POST http://172.18.0.2:8181/onos/v1/applications/org.onosproject.openflow/active
    echo -e "${GREEN}Aplicações ativadas.${RESET}"
}

send_network_cfg() {
    if [ -f "network-cfg.json" ]; then
        echo -e "${CYAN}Enviando network-cfg.json...${RESET}"
        curl -u "$ONOS_USER:$ONOS_PASS" -X POST \
            -H "Content-Type: application/json" \
            http://172.18.0.2:8181/onos/v1/network/configuration/ \
            -d @network-cfg.json
        echo -e "${GREEN}Configuração enviada.${RESET}"
    else
        echo -e "${RED}Arquivo network-cfg.json não encontrado.${RESET}"
    fi
}

show_hosts() {
    curl -s -u "$ONOS_USER:$ONOS_PASS" http://172.18.0.2:8181/onos/v1/hosts | jq .
}

block_host() {
    read -rp "Digite o MAC ou IP do host a bloquear: " TARGET
    echo -e "${CYAN}Bloqueando ${TARGET}...${RESET}"
    curl -u "$ONOS_USER:$ONOS_PASS" -X POST \
        http://172.18.0.2:8181/onos/v1/flows/org.onosproject.cli \
        -H "Content-Type: application/json" \
        -d "{\"priority\":40000,\"timeout\":0,\"isPermanent\":true,\"deviceId\":\"of:0000000000000001\",\"treatment\":{},\"selector\":{\"criteria\":[{\"type\":\"ETH_SRC\",\"mac\":\"${TARGET}\"}]}}"
    echo -e "${GREEN}Host bloqueado.${RESET}"
}

list_noncore_flows() {
    echo -e "${CYAN}Listando flows não-core...${RESET}"
    curl -s -u "$ONOS_USER:$ONOS_PASS" http://172.18.0.2:8181/onos/v1/flows | jq '.flows[] | select(.appId != "org.onosproject.core")'
}

delete_noncore_flows() {
    confirm_action "Deseja realmente apagar todos os flows não-core?" || return
    echo -e "${CYAN}Apagando flows não-core...${RESET}"
    curl -s -u "$ONOS_USER:$ONOS_PASS" http://172.18.0.2:8181/onos/v1/flows | \
        jq -r '.flows[] | select(.appId != "org.onosproject.core") | .id' | \
        while read -r id; do
            curl -u "$ONOS_USER:$ONOS_PASS" -X DELETE "http://172.18.0.2:8181/onos/v1/flows/$id"
        done
    echo -e "${GREEN}Flows não-core removidos.${RESET}"
}

# === Menus ===

menu_main() {
    while true; do
        show_status
        echo -e "${BOLD}Menu principal:${RESET}"
        echo "1) Gerenciamento ONOS"
        echo "2) Interações REST / Hosts / Flows"
        echo "q) Sair"
        echo
        read -rp "Escolha uma opção: " opt

        case $opt in
            1) menu_gerenciamento ;;
            2) menu_interacoes ;;
            q|Q) echo "Saindo..."; exit 0 ;;
            *) echo -e "${RED}Opção inválida.${RESET}"; sleep 1 ;;
        esac
    done
}

menu_gerenciamento() {
    while true; do
        show_status
        echo -e "${BOLD}Gerenciamento do ONOS:${RESET}"
        echo "1) Iniciar ONOS"
        echo "2) Parar ONOS"
        echo "3) Mostrar IP"
        echo "4) Abrir Web GUI"
        echo "5) Conectar via SSH (Karaf)"
        echo "b) Voltar"
        echo
        read -rp "Escolha uma opção: " opt

        case $opt in
            1) start_onos; pause ;;
            2) stop_onos; pause ;;
            3) show_ip; pause ;;
            4) open_gui; pause ;;
            5) connect_ssh; pause ;;
            b|B) break ;;
            *) echo -e "${RED}Opção inválida.${RESET}"; sleep 1 ;;
        esac
    done
}

menu_interacoes() {
    while true; do
        show_status
        echo -e "${BOLD}Interações e REST API:${RESET}"
        echo "1) Ativar Aplicações ONOS"
        echo "2) Enviar network-cfg.json"
        echo "3) Mostrar Hosts"
        echo "4) Bloquear Host"
        echo "5) Listar Flows não-core"
        echo "6) Deletar Flows não-core"
        echo "b) Voltar"
        echo
        read -rp "Escolha uma opção: " opt

        case $opt in
            1) activate_apps; pause ;;
            2) send_network_cfg; pause ;;
            3) show_hosts; pause ;;
            4) block_host; pause ;;
            5) list_noncore_flows; pause ;;
            6) delete_noncore_flows; pause ;;
            b|B) break ;;
            *) echo -e "${RED}Opção inválida.${RESET}"; sleep 1 ;;
        esac
    done
}

# === Execução ===
menu_main
