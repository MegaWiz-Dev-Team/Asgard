#!/bin/bash
set -euo pipefail

echo "🛡️ Installing macOS Native Vector for Heimdall Log Forwarding..."

# Install vector if it doesn't exist
if ! command -v vector &> /dev/null; then
    echo "📦 Vector not found. Installing via Homebrew..."
    brew tap timberio/tap
    brew install vector
else
    echo "✅ Vector is already installed."
fi

# Usually brew puts config at /usr/local/etc/vector/vector.toml or /opt/homebrew/etc/vector/vector.toml
# Homebrew on Apple Silicon uses /opt/homebrew
if [[ -d "/opt/homebrew" ]]; then
    VECTOR_CONFIG_DIR="/opt/homebrew/etc/vector"
else
    VECTOR_CONFIG_DIR="/usr/local/etc/vector"
fi

mkdir -p "$VECTOR_CONFIG_DIR"

echo "📝 Generating Heimdall Vector Config..."
cat << 'EOF' > "$VECTOR_CONFIG_DIR/vector.toml"
[sources.heimdall_logs]
type = "file"
include = [
  "/Users/mimir/Developer/Heimdall/logs/*.log"
]
read_from = "beginning"

[sinks.opensearch]
type = "elasticsearch"
inputs = ["heimdall_logs"]
endpoints = ["https://localhost:30920"]
mode = "bulk"
auth.strategy = "basic"
auth.user = "admin"
auth.password = "admin"
tls.verify_certificate = false
tls.verify_hostname = false
EOF

echo "🚀 Restarting Vector macOS Service..."
brew services restart vector

echo "✅ Heimdall Log Streaming configured! Logs are flowing to Týr (localhost:30920)."
