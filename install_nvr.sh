#!/bin/bash

################################################################################
# NVR Installation Script
# Installs and configures the NVR service for automatic startup
################################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}   NVR Service Installation${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Verify that nvr.sh exists
if [ ! -f "nvr.sh" ]; then
    echo -e "${RED}Error: nvr.sh not found in current directory${NC}"
    exit 1
fi

# 1. Copy script to home directory
echo -e "${YELLOW}[1/6]${NC} Copying nvr.sh to home directory..."
cp nvr.sh ~/nvr.sh
chmod +x ~/nvr.sh
echo -e "${GREEN}Script copied${NC}\n"

# 2. Copy service file
echo -e "${YELLOW}[2/6]${NC} Installing systemd service..."
sudo cp nvr.service /etc/systemd/system/nvr.service
sudo chmod 644 /etc/systemd/system/nvr.service
echo -e "${GREEN}Service file installed${NC}\n"

# 3. Reload systemd
echo -e "${YELLOW}[3/6]${NC} Reloading systemd daemon..."
sudo systemctl daemon-reload
echo -e "${GREEN}Systemd reloaded${NC}\n"

# 4. Enable service at boot
echo -e "${YELLOW}[4/6]${NC} Enabling automatic startup..."
sudo systemctl enable nvr.service
echo -e "${GREEN}Service enabled at boot${NC}\n"

# 5. Verify configuration
echo -e "${YELLOW}[5/6]${NC} Verifying configuration..."
if systemctl is-enabled nvr.service >/dev/null 2>&1; then
    echo -e "${GREEN}Service configured correctly${NC}\n"
else
    echo -e "${RED}Configuration error${NC}\n"
    exit 1
fi

# 6. Ask if starting now
echo -e "${YELLOW}[6/6]${NC} Starting service..."
read -p "Do you want to start the service now? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo systemctl start nvr.service
    sleep 2
    sudo systemctl status nvr.service --no-pager
    echo -e "\n${GREEN}Service started${NC}"
else
    echo -e "${YELLOW}Service not started${NC}"
    echo -e "  To start manually: ${YELLOW}sudo systemctl start nvr${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}   Installation completed!${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "Useful commands:"
echo "  - Start:           sudo systemctl start nvr"
echo "  - Stop:            sudo systemctl stop nvr"
echo "  - Restart:         sudo systemctl restart nvr"
echo "  - Status:          sudo systemctl status nvr"
echo "  - Logs:            sudo journalctl -u nvr -f"
echo "  - Disable at boot: sudo systemctl disable nvr"
echo ""
echo "  - Direct script:   ~/nvr.sh {start|stop|status|cleanup|merge}"
echo ""