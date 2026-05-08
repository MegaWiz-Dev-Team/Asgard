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

: "${HEIMDALL_LOG_DIR:?Set HEIMDALL_LOG_DIR to the absolute path of Heimdall's logs/ directory}"
: "${INDEXER_ENDPOINT:=https://localhost:30920}"
: "${INDEXER_USER:?Set INDEXER_USER for the OpenSearch/Wazuh indexer}"
: "${INDEXER_PASSWORD:?Set INDEXER_PASSWORD for the OpenSearch/Wazuh indexer}"

echo "📝 Generating Heimdall Vector Config..."
cat << EOF > "$VECTOR_CONFIG_DIR/vector.toml"
[sources.heimdall_logs]
type = "file"
include = [
  "${HEIMDALL_LOG_DIR}/*.log"
]
read_from = "beginning"

[sinks.opensearch]
type = "elasticsearch"
inputs = ["heimdall_logs"]
endpoints = ["${INDEXER_ENDPOINT}"]
mode = "bulk"
auth.strategy = "basic"
auth.user = "${INDEXER_USER}"
auth.password = "${INDEXER_PASSWORD}"
tls.verify_certificate = false
tls.verify_hostname = false
EOF

echo "🚀 Restarting Vector macOS Service..."
brew services restart vector

echo "✅ Heimdall Log Streaming configured! Logs are flowing to ${INDEXER_ENDPOINT}."
