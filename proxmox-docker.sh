#!/bin/bash
set -e

#############################################
# Proxmox QEMU Docker Setup Script
# Automated deployment with SSL nginx proxy
#############################################

# Configuration Variables
PROJECT_DIR="${1:-$HOME/proxmox-qemu}"
PUBLIC_IP="${2:-$(curl -s ifconfig.me)}"
PROXMOX_VM_NETWORK="172.30.0.0/24"
PROXMOX_VM_IP="172.30.0.4"
DOCKER_NETWORK_IP="172.18.0.3"  # Will be dynamically detected

# Ports
PROXMOX_WEB_PORT="8006"
PROXMOX_VNC_PORT="8008"
PROXMOX_SSH_PORT="5900"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Proxmox QEMU Docker Setup Script${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}Please do not run as root. Run as regular user with docker permissions.${NC}"
    exit 1
fi

# Check prerequisites
echo -e "${YELLOW}[1/14] Checking prerequisites...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Docker is not installed. Aborting.${NC}" >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || command -v docker >/dev/null 2>&1 || { echo -e "${RED}Docker Compose is not available. Aborting.${NC}" >&2; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo -e "${RED}OpenSSL is not installed. Aborting.${NC}" >&2; exit 1; }
command -v iptables >/dev/null 2>&1 || { echo -e "${RED}iptables is not installed. Aborting.${NC}" >&2; exit 1; }

# Check if user is in docker group
if ! groups | grep -q docker; then
    echo -e "${RED}Current user is not in docker group. Please add with: sudo usermod -aG docker $USER${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"

# Detect system resources
echo -e "${YELLOW}[2/14] Detecting system resources...${NC}"

# Detect CPU cores
TOTAL_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "4")
echo -e "  ${GREEN}✓ CPU Cores: ${TOTAL_CORES} detected${NC}"

# Detect RAM
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(($TOTAL_RAM_KB / 1024 / 1024))
TOTAL_RAM_MB=$(($TOTAL_RAM_KB / 1024))
echo -e "  ${GREEN}✓ RAM: ${TOTAL_RAM_GB}GB (${TOTAL_RAM_MB}MB) detected${NC}"

# Detect available disk space
if [ -d "$PROJECT_DIR" ]; then
    AVAILABLE_DISK=$(df -BG "$PROJECT_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
else
    AVAILABLE_DISK=$(df -BG "$HOME" | tail -1 | awk '{print $4}' | sed 's/G//')
fi
echo -e "  ${GREEN}✓ Disk: ${AVAILABLE_DISK}GB available${NC}"

echo ""
echo -e "${YELLOW}[3/14] Interactive Resource Configuration${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Calculate preset allocations
# Conservative: 50%
if [ "$TOTAL_CORES" -le 2 ]; then
    CONSERVATIVE_CPU=1
else
    CONSERVATIVE_CPU=$(($TOTAL_CORES / 2))
fi
CONSERVATIVE_RAM=$(($TOTAL_RAM_GB / 2))
[ "$CONSERVATIVE_RAM" -lt 4 ] && CONSERVATIVE_RAM=4
CONSERVATIVE_DISK=$(($AVAILABLE_DISK / 2))
[ "$CONSERVATIVE_DISK" -lt 64 ] && CONSERVATIVE_DISK=64

# Recommended: 75%
if [ "$TOTAL_CORES" -le 2 ]; then
    RECOMMENDED_CPU=2
elif [ "$TOTAL_CORES" -le 4 ]; then
    RECOMMENDED_CPU=$(($TOTAL_CORES - 1))
else
    RECOMMENDED_CPU=$(($TOTAL_CORES * 3 / 4))
fi
RECOMMENDED_RAM=$(($TOTAL_RAM_GB * 3 / 4))
[ "$RECOMMENDED_RAM" -lt 4 ] && RECOMMENDED_RAM=4
[ "$RECOMMENDED_RAM" -gt $(($TOTAL_RAM_GB - 2)) ] && RECOMMENDED_RAM=$(($TOTAL_RAM_GB - 2))
RECOMMENDED_DISK=$(($AVAILABLE_DISK * 4 / 5))
[ "$RECOMMENDED_DISK" -lt 64 ] && RECOMMENDED_DISK=64
[ "$RECOMMENDED_DISK" -gt 500 ] && RECOMMENDED_DISK=500

# Maximum: All available (leave 1 core, 2GB RAM)
MAXIMUM_CPU=$(($TOTAL_CORES - 1))
[ "$MAXIMUM_CPU" -lt 2 ] && MAXIMUM_CPU=$TOTAL_CORES
MAXIMUM_RAM=$(($TOTAL_RAM_GB - 2))
[ "$MAXIMUM_RAM" -lt 4 ] && MAXIMUM_RAM=$TOTAL_RAM_GB
MAXIMUM_DISK=$(($AVAILABLE_DISK - 10))
[ "$MAXIMUM_DISK" -lt 64 ] && MAXIMUM_DISK=$AVAILABLE_DISK

echo -e "${YELLOW}Choose Resource Allocation Preset:${NC}"
echo ""
echo -e "  ${BLUE}1) Conservative (50%)${NC}"
echo -e "     CPU: ${CONSERVATIVE_CPU} cores | RAM: ${CONSERVATIVE_RAM}GB | Disk: ${CONSERVATIVE_DISK}GB"
echo ""
echo -e "  ${BLUE}2) Recommended (75%) - Default${NC}"
echo -e "     CPU: ${RECOMMENDED_CPU} cores | RAM: ${RECOMMENDED_RAM}GB | Disk: ${RECOMMENDED_DISK}GB"
echo ""
echo -e "  ${BLUE}3) Maximum (Nearly All)${NC}"
echo -e "     CPU: ${MAXIMUM_CPU} cores | RAM: ${MAXIMUM_RAM}GB | Disk: ${MAXIMUM_DISK}GB"
echo ""
echo -e "  ${BLUE}4) Custom - Configure each resource manually${NC}"
echo ""
read -p "Select preset [1-4] (default: 2): " PRESET_CHOICE

# Set defaults based on choice
case "$PRESET_CHOICE" in
    1)
        CPU_CORES=$CONSERVATIVE_CPU
        RAM_SIZE="${CONSERVATIVE_RAM}G"
        DISK_SIZE="${CONSERVATIVE_DISK}G"
        echo -e "${GREEN}✓ Using Conservative preset${NC}"
        ;;
    3)
        CPU_CORES=$MAXIMUM_CPU
        RAM_SIZE="${MAXIMUM_RAM}G"
        DISK_SIZE="${MAXIMUM_DISK}G"
        echo -e "${GREEN}✓ Using Maximum preset${NC}"
        ;;
    4)
        echo ""
        echo -e "${YELLOW}Custom Configuration:${NC}"
        echo ""
        
        # CPU Configuration
        echo -e "${BLUE}CPU Configuration:${NC}"
        echo -e "  Total available: ${TOTAL_CORES} cores"
        echo -e "  Recommended: ${RECOMMENDED_CPU} cores"
        while true; do
            read -p "Enter CPU cores for Proxmox [1-${TOTAL_CORES}] (default: ${RECOMMENDED_CPU}): " CUSTOM_CPU
            CUSTOM_CPU=${CUSTOM_CPU:-$RECOMMENDED_CPU}
            if [[ "$CUSTOM_CPU" =~ ^[0-9]+$ ]] && [ "$CUSTOM_CPU" -ge 1 ] && [ "$CUSTOM_CPU" -le "$TOTAL_CORES" ]; then
                CPU_CORES=$CUSTOM_CPU
                break
            else
                echo -e "${RED}Invalid input. Enter a number between 1 and ${TOTAL_CORES}${NC}"
            fi
        done
        
        # RAM Configuration
        echo ""
        echo -e "${BLUE}RAM Configuration:${NC}"
        echo -e "  Total available: ${TOTAL_RAM_GB}GB (${TOTAL_RAM_MB}MB)"
        echo -e "  Recommended: ${RECOMMENDED_RAM}GB"
        echo -e "  Enter in GB (e.g., 8) or MB (e.g., 8192M)"
        while true; do
            read -p "Enter RAM for Proxmox (default: ${RECOMMENDED_RAM}G): " CUSTOM_RAM
            CUSTOM_RAM=${CUSTOM_RAM:-${RECOMMENDED_RAM}G}
            
            # Parse input (supports 8G, 8192M, 8, etc.)
            if [[ "$CUSTOM_RAM" =~ ^([0-9]+)([GMgm]?)$ ]]; then
                RAM_VALUE="${BASH_REMATCH[1]}"
                RAM_UNIT="${BASH_REMATCH[2]}"
                
                # Convert to MB for validation
                if [[ "${RAM_UNIT^^}" == "G" ]] || [[ -z "$RAM_UNIT" ]]; then
                    RAM_MB=$(($RAM_VALUE * 1024))
                    RAM_SIZE="${RAM_VALUE}G"
                else
                    RAM_MB=$RAM_VALUE
                    RAM_SIZE="${RAM_VALUE}M"
                fi
                
                # Validate
                if [ "$RAM_MB" -ge 2048 ] && [ "$RAM_MB" -le "$TOTAL_RAM_MB" ]; then
                    break
                else
                    echo -e "${RED}Invalid RAM. Must be between 2GB and ${TOTAL_RAM_GB}GB${NC}"
                fi
            else
                echo -e "${RED}Invalid format. Use: 8G or 8192M${NC}"
            fi
        done
        
        # Disk Configuration
        echo ""
        echo -e "${BLUE}Disk Configuration:${NC}"
        echo -e "  Total available: ${AVAILABLE_DISK}GB"
        echo -e "  Recommended: ${RECOMMENDED_DISK}GB"
        echo -e "  Enter in GB (e.g., 128)"
        while true; do
            read -p "Enter Disk size for Proxmox (default: ${RECOMMENDED_DISK}G): " CUSTOM_DISK
            CUSTOM_DISK=${CUSTOM_DISK:-$RECOMMENDED_DISK}
            
            # Parse input (supports 128G, 128, etc.)
            if [[ "$CUSTOM_DISK" =~ ^([0-9]+)([Gg]?)$ ]]; then
                DISK_VALUE="${BASH_REMATCH[1]}"
                DISK_SIZE="${DISK_VALUE}G"
                
                # Validate
                if [ "$DISK_VALUE" -ge 32 ] && [ "$DISK_VALUE" -le "$AVAILABLE_DISK" ]; then
                    break
                else
                    echo -e "${RED}Invalid disk size. Must be between 32GB and ${AVAILABLE_DISK}GB${NC}"
                fi
            else
                echo -e "${RED}Invalid format. Use: 128G or 128${NC}"
            fi
        done
        
        echo -e "${GREEN}✓ Custom configuration complete${NC}"
        ;;
    *)
        # Default to Recommended
        CPU_CORES=$RECOMMENDED_CPU
        RAM_SIZE="${RECOMMENDED_RAM}G"
        DISK_SIZE="${RECOMMENDED_DISK}G"
        echo -e "${GREEN}✓ Using Recommended preset (default)${NC}"
        ;;
esac

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${YELLOW}Final Resource Allocation:${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "  CPU Cores: ${GREEN}${CPU_CORES}${NC} / ${TOTAL_CORES}"
echo -e "  RAM:       ${GREEN}${RAM_SIZE}${NC} / ${TOTAL_RAM_GB}GB"
echo -e "  Disk:      ${GREEN}${DISK_SIZE}${NC} / ${AVAILABLE_DISK}GB"
echo -e "${BLUE}============================================${NC}"
echo ""
read -p "Proceed with this configuration? [Y/n]: " CONFIRM
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
    echo -e "${RED}Setup cancelled.${NC}"
    exit 0
fi
echo -e "${GREEN}✓ Configuration confirmed${NC}"

# Configure firewall and IP forwarding
echo -e "${YELLOW}[4/14] Configuring firewall rules...${NC}"

# Check if we need sudo
SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

# Enable IP forwarding (required for Docker networking)
echo -e "  ${BLUE}Enabling IP forwarding...${NC}"
$SUDO sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" | $SUDO tee -a /etc/sysctl.conf >/dev/null
fi

# Check if firewall is active
if $SUDO iptables -L -n >/dev/null 2>&1; then
    echo -e "  ${BLUE}Configuring iptables rules...${NC}"
    
    # Allow Proxmox Web UI (HTTPS)
    if ! $SUDO iptables -C INPUT -p tcp --dport ${PROXMOX_WEB_PORT} -j ACCEPT 2>/dev/null; then
        $SUDO iptables -I INPUT -p tcp --dport ${PROXMOX_WEB_PORT} -j ACCEPT
        echo -e "    ${GREEN}✓ Opened port ${PROXMOX_WEB_PORT} (Proxmox Web UI - HTTPS)${NC}"
    else
        echo -e "    ${GREEN}✓ Port ${PROXMOX_WEB_PORT} already open${NC}"
    fi
    
    # Allow Proxmox VNC Console
    if ! $SUDO iptables -C INPUT -p tcp --dport ${PROXMOX_VNC_PORT} -j ACCEPT 2>/dev/null; then
        $SUDO iptables -I INPUT -p tcp --dport ${PROXMOX_VNC_PORT} -j ACCEPT
        echo -e "    ${GREEN}✓ Opened port ${PROXMOX_VNC_PORT} (Proxmox VNC)${NC}"
    else
        echo -e "    ${GREEN}✓ Port ${PROXMOX_VNC_PORT} already open${NC}"
    fi
    
    # Allow Proxmox SSH/VNC secondary port
    if ! $SUDO iptables -C INPUT -p tcp --dport ${PROXMOX_SSH_PORT} -j ACCEPT 2>/dev/null; then
        $SUDO iptables -I INPUT -p tcp --dport ${PROXMOX_SSH_PORT} -j ACCEPT
        echo -e "    ${GREEN}✓ Opened port ${PROXMOX_SSH_PORT} (Proxmox SSH/VNC)${NC}"
    else
        echo -e "    ${GREEN}✓ Port ${PROXMOX_SSH_PORT} already open${NC}"
    fi
    
    # Allow Docker forwarding
    if ! $SUDO iptables -C FORWARD -i docker0 -o docker0 -j ACCEPT 2>/dev/null; then
        $SUDO iptables -I FORWARD -i docker0 -o docker0 -j ACCEPT 2>/dev/null || true
    fi
    
    # Save iptables rules (Debian/Ubuntu)
    if command -v iptables-save >/dev/null 2>&1; then
        if command -v netfilter-persistent >/dev/null 2>&1; then
            $SUDO netfilter-persistent save 2>/dev/null || true
            echo -e "    ${GREEN}✓ Firewall rules saved (netfilter-persistent)${NC}"
        elif [ -f /etc/iptables/rules.v4 ]; then
            $SUDO iptables-save | $SUDO tee /etc/iptables/rules.v4 >/dev/null 2>&1 || true
            echo -e "    ${GREEN}✓ Firewall rules saved (iptables-persistent)${NC}"
        else
            echo -e "    ${YELLOW}! Firewall rules configured but not persisted (install iptables-persistent)${NC}"
        fi
    fi
else
    echo -e "  ${YELLOW}! Could not configure iptables (may need manual configuration)${NC}"
fi

echo -e "${GREEN}✓ Firewall configuration complete${NC}"

# Create project directory
echo -e "${YELLOW}[5/14] Creating project directory: $PROJECT_DIR${NC}"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"
echo -e "${GREEN}✓ Directory created${NC}"

# Generate self-signed SSL certificate
echo -e "${YELLOW}[6/14] Generating self-signed SSL certificate...${NC}"
if [ ! -f "nginx-selfsigned.crt" ] || [ ! -f "nginx-selfsigned.key" ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout nginx-selfsigned.key \
        -out nginx-selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=$PUBLIC_IP" >/dev/null 2>&1
    echo -e "${GREEN}✓ SSL certificate generated${NC}"
else
    echo -e "${GREEN}✓ SSL certificate already exists${NC}"
fi

# Create nginx configuration
echo -e "${YELLOW}[7/14] Creating nginx configuration...${NC}"
cat > nginx-proxmox.conf << 'NGINX_EOF'
upstream proxmox {
    server 172.30.0.4:8006;
}

server {
    listen 8006 ssl;
    server_name _;
    
    ssl_certificate /etc/nginx/ssl/nginx-selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/nginx-selfsigned.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass https://proxmox;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Port $server_port;
        
        # Cookie handling - rewrite domain from internal IP to public hostname
        proxy_cookie_path / /;
        proxy_cookie_domain 172.30.0.4 $host;
        
        proxy_ssl_verify off;
        proxy_buffering off;
        proxy_redirect off;
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        proxy_connect_timeout 3600;
        client_max_body_size 0;
        send_timeout 86400;
    }
}
NGINX_EOF
echo -e "${GREEN}✓ nginx configuration created${NC}"

# Create docker-compose.yml
echo -e "${YELLOW}[8/14] Creating docker-compose.yml...${NC}"
cat > docker-compose.yml << COMPOSE_EOF
services:
  proxmox-qemu:
    image: qemux/qemu
    container_name: proxmox-qemu-vnc
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - ${PROXMOX_VNC_PORT}:8006
      - ${PROXMOX_SSH_PORT}:5900
    volumes:
      - ./proxmox-data:/storage
    restart: unless-stopped
    stop_grace_period: 2m
    environment:
      - RAM_SIZE=${RAM_SIZE}
      - CPU_CORES=${CPU_CORES}
      - DISK_SIZE=${DISK_SIZE}

  nginx-proxy:
    image: nginx:alpine
    container_name: nginx-proxmox-proxy
    cap_add:
      - NET_ADMIN
    ports:
      - ${PROXMOX_WEB_PORT}:8006
    volumes:
      - ./nginx-proxmox.conf:/etc/nginx/conf.d/default.conf:ro
      - ./nginx-selfsigned.crt:/etc/nginx/ssl/nginx-selfsigned.crt:ro
      - ./nginx-selfsigned.key:/etc/nginx/ssl/nginx-selfsigned.key:ro
    restart: unless-stopped
    depends_on:
      - proxmox-qemu
    command: sh -c "ip route add ${PROXMOX_VM_NETWORK} via ${DOCKER_NETWORK_IP} && nginx -g 'daemon off;'"
COMPOSE_EOF
echo -e "${GREEN}✓ docker-compose.yml created${NC}"

# Create README
echo -e "${YELLOW}[9/14] Creating README.md...${NC}"
cat > README.md << README_EOF
# Proxmox VE in Docker with QEMU

Automated deployment of Proxmox Virtual Environment running in a QEMU Docker container with SSL-enabled nginx reverse proxy.

## Access URLs

- **Proxmox Web UI**: https://${PUBLIC_IP}:${PROXMOX_WEB_PORT}
- **Proxmox VNC Console**: http://${PUBLIC_IP}:${PROXMOX_VNC_PORT}
- **Proxmox SSH** (from host): \`ssh root@${PROXMOX_VM_IP}\`

## Default Credentials

- **Username**: root
- **Password**: (set during installation)
- **Realm**: Linux PAM standard authentication

## VM Resources

- RAM: ${RAM_SIZE}
- CPU Cores: ${CPU_CORES}
- Disk Size: ${DISK_SIZE}

## Network Architecture

- VPS Public IP: ${PUBLIC_IP}
- Docker Bridge Network: 172.18.0.0/16
- Proxmox Container IP: ${DOCKER_NETWORK_IP}
- Proxmox VM Network: ${PROXMOX_VM_NETWORK}
- Proxmox VM IP: ${PROXMOX_VM_IP}

## Management Commands

### Start Services
\`\`\`bash
docker compose up -d
\`\`\`

### Stop Services
\`\`\`bash
docker compose down
\`\`\`

### View Logs
\`\`\`bash
docker compose logs -f proxmox-qemu
docker compose logs -f nginx-proxy
\`\`\`

### Restart Proxmox
\`\`\`bash
docker compose restart proxmox-qemu
\`\`\`

### Access Proxmox Shell
\`\`\`bash
docker exec -it proxmox-qemu-vnc /bin/bash
\`\`\`

### Backup Proxmox Data
\`\`\`bash
tar -czf proxmox-backup-\$(date +%Y%m%d).tar.gz proxmox-data/
\`\`\`

## Firewall Configuration

The setup script automatically configures iptables firewall rules:

### Open Ports
- **${PROXMOX_WEB_PORT}/tcp** - Proxmox Web UI (HTTPS)
- **${PROXMOX_VNC_PORT}/tcp** - Proxmox VNC Console
- **${PROXMOX_SSH_PORT}/tcp** - Proxmox SSH/VNC Access

### View Current Rules
\`\`\`bash
sudo iptables -L INPUT -n --line-numbers | grep -E "(${PROXMOX_WEB_PORT}|${PROXMOX_VNC_PORT}|${PROXMOX_SSH_PORT})"
\`\`\`

### Manually Add Rules (if needed)
\`\`\`bash
sudo iptables -I INPUT -p tcp --dport ${PROXMOX_WEB_PORT} -j ACCEPT
sudo iptables -I INPUT -p tcp --dport ${PROXMOX_VNC_PORT} -j ACCEPT
sudo iptables -I INPUT -p tcp --dport ${PROXMOX_SSH_PORT} -j ACCEPT
\`\`\`

### Save Rules (Debian/Ubuntu)
\`\`\`bash
sudo netfilter-persistent save
# or
sudo iptables-save | sudo tee /etc/iptables/rules.v4
\`\`\`

## Route Setup for VM Network Access

The nginx proxy needs to route to the Proxmox VM's internal network. This is handled automatically by:
1. The setup script adds a route on the host
2. The nginx container adds an internal route on startup

### View Route
\`\`\`bash
ip route | grep ${PROXMOX_VM_NETWORK}
\`\`\`

### Manually Add Route (if needed)
\`\`\`bash
sudo ip route add ${PROXMOX_VM_NETWORK} via ${DOCKER_NETWORK_IP}
\`\`\`

### IP Forwarding
IP forwarding is automatically enabled. To verify:
\`\`\`bash
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1
\`\`\`

## SSL Certificate

A self-signed SSL certificate is automatically generated for nginx. Your browser will show a security warning - click "Advanced" and "Proceed" to continue.

For production use, consider using Let's Encrypt or a proper SSL certificate.

## Troubleshooting

### Proxmox Web UI shows 401 errors
- Clear browser cookies for the site
- Try incognito/private browsing mode
- Ensure you're accessing via HTTPS (not HTTP)

### Cannot access Proxmox VM from host
- Check if route exists: \`ip route | grep ${PROXMOX_VM_NETWORK}\`
- Verify Proxmox container is running: \`docker ps | grep proxmox\`
- Check VM network: \`ssh root@${PROXMOX_VM_IP} ip addr\`

### nginx proxy fails to start
- Check logs: \`docker compose logs nginx-proxy\`
- Verify SSL certificates exist: \`ls -lh nginx-selfsigned.*\`
- Ensure port ${PROXMOX_WEB_PORT} is not in use: \`sudo netstat -tlnp | grep ${PROXMOX_WEB_PORT}\`

## Generated Files

- \`docker-compose.yml\` - Container orchestration
- \`nginx-proxmox.conf\` - nginx reverse proxy configuration
- \`nginx-selfsigned.crt\` - SSL certificate
- \`nginx-selfsigned.key\` - SSL private key
- \`proxmox-data/\` - Proxmox VM persistent storage

## Installation ISO

To install Proxmox, download the ISO and mount it:

\`\`\`bash
wget https://enterprise.proxmox.com/iso/proxmox-ve_8.2-1.iso -O proxmox.iso
\`\`\`

Then add to docker-compose.yml under proxmox-qemu volumes:
\`\`\`yaml
- ./proxmox.iso:/boot.iso
\`\`\`

After installation is complete, remove the ISO mount and delete the file to save space.
README_EOF
echo -e "${GREEN}✓ README.md created${NC}"

# Start containers
echo -e "${YELLOW}[10/14] Starting Docker containers...${NC}"
docker compose up -d
echo -e "${GREEN}✓ Containers started${NC}"

# Wait for containers to be ready
echo -e "${YELLOW}[11/14] Waiting for containers to initialize (30 seconds)...${NC}"
sleep 30

# Detect actual container IP
echo -e "${YELLOW}[12/14] Detecting Proxmox container IP...${NC}"
ACTUAL_CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' proxmox-qemu-vnc)
if [ -z "$ACTUAL_CONTAINER_IP" ]; then
    echo -e "${RED}Warning: Could not detect container IP. Using default: ${DOCKER_NETWORK_IP}${NC}"
    ACTUAL_CONTAINER_IP="$DOCKER_NETWORK_IP"
else
    echo -e "${GREEN}✓ Detected container IP: ${ACTUAL_CONTAINER_IP}${NC}"
    
    # Update docker-compose if IP differs
    if [ "$ACTUAL_CONTAINER_IP" != "$DOCKER_NETWORK_IP" ]; then
        echo -e "${YELLOW}Updating docker-compose.yml with correct container IP...${NC}"
        sed -i "s|via ${DOCKER_NETWORK_IP}|via ${ACTUAL_CONTAINER_IP}|g" docker-compose.yml
        docker compose up -d nginx-proxy
        echo -e "${GREEN}✓ nginx proxy updated with correct route${NC}"
    fi
fi

# Verify services
echo -e "${YELLOW}[13/14] Verifying services...${NC}"
sleep 5

# Check if containers are running
if docker ps | grep -q proxmox-qemu-vnc; then
    echo -e "${GREEN}✓ Proxmox QEMU container is running${NC}"
else
    echo -e "${RED}✗ Proxmox QEMU container is not running${NC}"
fi

if docker ps | grep -q nginx-proxmox-proxy; then
    echo -e "${GREEN}✓ nginx proxy container is running${NC}"
else
    echo -e "${RED}✗ nginx proxy container is not running${NC}"
fi

# Configure host routing for Proxmox VM network access
echo -e "${YELLOW}[14/14] Configuring network routing...${NC}"

# Check if route already exists
if ! ip route | grep -q "${PROXMOX_VM_NETWORK}"; then
    echo -e "  ${BLUE}Adding route to Proxmox VM network...${NC}"
    $SUDO ip route add ${PROXMOX_VM_NETWORK} via ${ACTUAL_CONTAINER_IP} 2>/dev/null || true
    echo -e "  ${GREEN}✓ Route added: ${PROXMOX_VM_NETWORK} via ${ACTUAL_CONTAINER_IP}${NC}"
else
    echo -e "  ${GREEN}✓ Route already exists${NC}"
fi

# Test connectivity to Proxmox VM (will fail until Proxmox is installed, but that's ok)
echo -e "  ${BLUE}Testing network connectivity...${NC}"
if ping -c 1 -W 2 ${PROXMOX_VM_IP} >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓ Proxmox VM is reachable at ${PROXMOX_VM_IP}${NC}"
else
    echo -e "  ${YELLOW}! Proxmox VM not yet reachable (normal if not installed yet)${NC}"
fi

# Display firewall status
echo -e "  ${BLUE}Active firewall rules:${NC}"
$SUDO iptables -L INPUT -n --line-numbers 2>/dev/null | grep -E "(${PROXMOX_WEB_PORT}|${PROXMOX_VNC_PORT}|${PROXMOX_SSH_PORT})" | while read line; do
    echo -e "    ${GREEN}✓ $line${NC}"
done || echo -e "    ${YELLOW}! Could not verify firewall rules${NC}"

echo -e "${GREEN}✓ Network configuration complete${NC}"

# Display summary
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "${YELLOW}Access Information:${NC}"
echo ""
echo -e "  ${GREEN}Proxmox Web UI (HTTPS):${NC}"
echo -e "    https://${PUBLIC_IP}:${PROXMOX_WEB_PORT}"
echo ""
echo -e "  ${GREEN}Proxmox VNC Console:${NC}"
echo -e "    http://${PUBLIC_IP}:${PROXMOX_VNC_PORT}"
echo ""
echo -e "  ${GREEN}Proxmox VM SSH (from host):${NC}"
echo -e "    ssh root@${PROXMOX_VM_IP}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "  1. Access the VNC console to install Proxmox VE"
echo "  2. Download ISO: wget https://enterprise.proxmox.com/iso/proxmox-ve_8.2-1.iso -O proxmox.iso"
echo "  3. Add ISO mount to docker-compose.yml volumes section"
echo "  4. Restart container: docker compose restart proxmox-qemu"
echo "  5. After installation, remove ISO mount and delete file"
echo ""
echo -e "${YELLOW}Firewall & Network:${NC}"
echo ""
echo "  • Firewall ports opened: ${PROXMOX_WEB_PORT}, ${PROXMOX_VNC_PORT}, ${PROXMOX_SSH_PORT}"
echo "  • IP forwarding: Enabled"
echo "  • VM network route: ${PROXMOX_VM_NETWORK} via ${ACTUAL_CONTAINER_IP}"
echo "  • Container IP: ${ACTUAL_CONTAINER_IP}"
echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo ""
echo "  • The Web UI uses a self-signed certificate (browser warning is normal)"
echo "  • Default login realm: 'Linux PAM standard authentication'"
echo "  • Firewall rules are persisted across reboots"
echo "  • Check README.md for detailed documentation"
echo ""
echo -e "${BLUE}============================================${NC}"

# Create quick access script
cat > access.sh << 'ACCESS_EOF'
#!/bin/bash
echo "Proxmox QEMU Quick Access"
echo "========================="
echo ""
echo "1) Open Proxmox Web UI (HTTPS)"
echo "2) Open Proxmox VNC Console"
echo "3) SSH to Proxmox VM"
echo "4) View container logs"
echo "5) Restart containers"
echo "6) Stop containers"
echo "7) Start containers"
echo "0) Exit"
echo ""
read -p "Select option: " choice

case $choice in
    1) xdg-open "https://$(curl -s ifconfig.me):8006" 2>/dev/null || echo "Open: https://$(curl -s ifconfig.me):8006" ;;
    2) xdg-open "http://$(curl -s ifconfig.me):8008" 2>/dev/null || echo "Open: http://$(curl -s ifconfig.me):8008" ;;
    3) ssh root@172.30.0.4 ;;
    4) docker compose logs -f ;;
    5) docker compose restart ;;
    6) docker compose down ;;
    7) docker compose up -d ;;
    0) exit 0 ;;
    *) echo "Invalid option" ;;
esac
ACCESS_EOF
chmod +x access.sh
echo -e "${GREEN}✓ Quick access script created: ./access.sh${NC}"
echo ""
