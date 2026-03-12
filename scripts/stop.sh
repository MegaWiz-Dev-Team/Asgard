#!/bin/bash
# 🏰 Asgard — Stop all services
echo "🛑 Stopping Asgard AI Platform..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"
docker compose --profile full down
echo "✅ All services stopped."
