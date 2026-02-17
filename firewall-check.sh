#!/bin/bash

#############################################
# Proxmox Docker Firewall Management Script
#############################################

# Configuration
PROXMOX_WEB_PORT="8006"
PROXMOX_VNC_PORT="8008"
PROXMOX_SSH_PORT="5900"
PROXMOX_VM_NETWORK="172.30.0.0/24"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check sudo
SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Proxmox Docker Firewall Check${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check IP forwarding
echo -e "${YELLOW}[1] IP Forwarding Status:${NC}"
if sysctl net.ipv4.ip_forward | grep -q "= 1"; then
    echo -e "  ${GREEN}✓ Enabled${NC}"
else
    echo -e "  ${RED}✗ Disabled${NC}"
    echo -e "  ${BLUE}To enable: sudo sysctl -w net.ipv4.ip_forward=1${NC}"
fi
echo ""

# Check firewall rules
echo -e "${YELLOW}[2] Firewall Rules:${NC}"
for port in $PROXMOX_WEB_PORT $PROXMOX_VNC_PORT $PROXMOX_SSH_PORT; do
    if $SUDO iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; then
        echo -e "  ${GREEN}✓ Port $port is OPEN${NC}"
    else
        echo -e "  ${RED}✗ Port $port is CLOSED${NC}"
        echo -e "    ${BLUE}To open: sudo iptables -I INPUT -p tcp --dport $port -j ACCEPT${NC}"
    fi
done
echo ""

# Check routing
echo -e "${YELLOW}[3] Network Routes:${NC}"
if ip route | grep -q "$PROXMOX_VM_NETWORK"; then
    ROUTE=$(ip route | grep "$PROXMOX_VM_NETWORK")
    echo -e "  ${GREEN}✓ Route exists: ${ROUTE}${NC}"
else
    echo -e "  ${RED}✗ No route to Proxmox VM network${NC}"
    
    # Try to detect container IP
    if command -v docker >/dev/null 2>&1; then
        CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' proxmox-qemu-vnc 2>/dev/null)
        if [ -n "$CONTAINER_IP" ]; then
            echo -e "  ${BLUE}To add route: sudo ip route add $PROXMOX_VM_NETWORK via $CONTAINER_IP${NC}"
        else
            echo -e "  ${BLUE}Container not running. Start it first.${NC}"
        fi
    fi
fi
echo ""

# Check Docker containers
echo -e "${YELLOW}[4] Docker Containers:${NC}"
if command -v docker >/dev/null 2>&1; then
    if docker ps | grep -q proxmox-qemu-vnc; then
        CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' proxmox-qemu-vnc)
        echo -e "  ${GREEN}✓ Proxmox QEMU container is running${NC}"
        echo -e "    Container IP: ${CONTAINER_IP}"
    else
        echo -e "  ${RED}✗ Proxmox QEMU container is not running${NC}"
    fi
    
    if docker ps | grep -q nginx-proxmox-proxy; then
        echo -e "  ${GREEN}✓ nginx proxy container is running${NC}"
    else
        echo -e "  ${RED}✗ nginx proxy container is not running${NC}"
    fi
else
    echo -e "  ${RED}✗ Docker not found${NC}"
fi
echo ""

# Network connectivity test
echo -e "${YELLOW}[5] Connectivity Test:${NC}"
if ping -c 1 -W 2 172.30.0.4 >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓ Can reach Proxmox VM (172.30.0.4)${NC}"
else
    echo -e "  ${YELLOW}! Cannot reach Proxmox VM (may not be installed yet)${NC}"
fi
echo ""

# Port listening check
echo -e "${YELLOW}[6] Port Listening Status:${NC}"
for port in $PROXMOX_WEB_PORT $PROXMOX_VNC_PORT $PROXMOX_SSH_PORT; do
    if $SUDO netstat -tlnp 2>/dev/null | grep -q ":$port "; then
        echo -e "  ${GREEN}✓ Port $port is listening${NC}"
    else
        echo -e "  ${YELLOW}! Port $port is not listening${NC}"
    fi
done
echo ""

# Quick fix option
echo -e "${YELLOW}[7] Quick Actions:${NC}"
echo ""
echo "  a) Enable IP forwarding"
echo "  b) Open all firewall ports"
echo "  c) Add VM network route"
echo "  d) Apply all fixes"
echo "  s) Show detailed iptables rules"
echo "  q) Quit"
echo ""
read -p "Select action (or press Enter to exit): " action

case $action in
    a)
        echo -e "${BLUE}Enabling IP forwarding...${NC}"
        $SUDO sysctl -w net.ipv4.ip_forward=1
        if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.ip_forward=1" | $SUDO tee -a /etc/sysctl.conf >/dev/null
        fi
        echo -e "${GREEN}✓ Done${NC}"
        ;;
    b)
        echo -e "${BLUE}Opening firewall ports...${NC}"
        for port in $PROXMOX_WEB_PORT $PROXMOX_VNC_PORT $PROXMOX_SSH_PORT; do
            if ! $SUDO iptables -C INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null; then
                $SUDO iptables -I INPUT -p tcp --dport $port -j ACCEPT
                echo -e "${GREEN}✓ Opened port $port${NC}"
            else
                echo -e "${YELLOW}Port $port already open${NC}"
            fi
        done
        if command -v netfilter-persistent >/dev/null 2>&1; then
            $SUDO netfilter-persistent save
            echo -e "${GREEN}✓ Rules saved${NC}"
        fi
        ;;
    c)
        if command -v docker >/dev/null 2>&1; then
            CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' proxmox-qemu-vnc 2>/dev/null)
            if [ -n "$CONTAINER_IP" ]; then
                if ! ip route | grep -q "$PROXMOX_VM_NETWORK"; then
                    echo -e "${BLUE}Adding route...${NC}"
                    $SUDO ip route add $PROXMOX_VM_NETWORK via $CONTAINER_IP
                    echo -e "${GREEN}✓ Route added${NC}"
                else
                    echo -e "${YELLOW}Route already exists${NC}"
                fi
            else
                echo -e "${RED}Container not running${NC}"
            fi
        fi
        ;;
    d)
        echo -e "${BLUE}Applying all fixes...${NC}"
        # IP forwarding
        $SUDO sysctl -w net.ipv4.ip_forward=1
        if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
            echo "net.ipv4.ip_forward=1" | $SUDO tee -a /etc/sysctl.conf >/dev/null
        fi
        # Firewall
        for port in $PROXMOX_WEB_PORT $PROXMOX_VNC_PORT $PROXMOX_SSH_PORT; do
            $SUDO iptables -I INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
        done
        if command -v netfilter-persistent >/dev/null 2>&1; then
            $SUDO netfilter-persistent save 2>/dev/null || true
        fi
        # Route
        if command -v docker >/dev/null 2>&1; then
            CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' proxmox-qemu-vnc 2>/dev/null)
            if [ -n "$CONTAINER_IP" ] && ! ip route | grep -q "$PROXMOX_VM_NETWORK"; then
                $SUDO ip route add $PROXMOX_VM_NETWORK via $CONTAINER_IP 2>/dev/null || true
            fi
        fi
        echo -e "${GREEN}✓ All fixes applied${NC}"
        ;;
    s)
        echo ""
        echo -e "${BLUE}Detailed iptables rules:${NC}"
        $SUDO iptables -L INPUT -n -v --line-numbers | grep -E "(Chain|${PROXMOX_WEB_PORT}|${PROXMOX_VNC_PORT}|${PROXMOX_SSH_PORT})"
        ;;
    *)
        echo -e "${BLUE}Exiting...${NC}"
        ;;
esac

echo ""
echo -e "${BLUE}============================================${NC}"
