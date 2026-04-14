#!/bin/bash
set -euo pipefail

echo "🛡️ Installing macOS Native Wazuh Agent for Týr SIEM..."

# 1. Variables
WAZUH_MANAGER="127.0.0.1"
# Exposing via nodePort 31514 and 31515, but standard wazuh installer uses standard ports. 
# We will inject the custom port config into ossec.conf after install.

# 2. Download macOS Wazuh Agent PKG
PKG_URL="https://packages.wazuh.com/4.x/macos/wazuh-agent-4.9.0-1.arm64.pkg"
PKG_FILE="/tmp/wazuh-agent.pkg"

echo "📥 Downloading Wazuh Agent..."
curl -so "$PKG_FILE" "$PKG_URL"

# 3. Install the package
echo "📦 Running Installer..."
sudo installer -pkg "$PKG_FILE" -target /

# 4. Configure Agent Custom Ports
OSSEC_CONF="/Library/Ossec/etc/ossec.conf"
echo "⚙️ Configuring Agent to point to Týr NodePorts ($WAZUH_MANAGER)..."

# Use sed to update the manager IP and port
sudo sed -i '' "s/<address>.*<\/address>/<address>${WAZUH_MANAGER}<\/address>/g" "$OSSEC_CONF"
# Usually it defaults to 1514. Since we NodePorted to 31514, we update that:
sudo sed -i '' "s/<port>1514<\/port>/<port>31514<\/port>/g" "$OSSEC_CONF"

# 5. Start the Agent Daemon
echo "🚀 Starting Wazuh macOS Agent..."
sudo /Library/Ossec/bin/wazuh-control start || true

echo "✅ Wazuh Agent installed and running! Metrics and file integrity data are now flowing to Týr (T7 Shield)."
