#!/bin/bash
# 🏰 Asgard — Start the entire platform
# Usage: ./scripts/start.sh [--full]
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASGARD_DIR="$(dirname "$SCRIPT_DIR")"
DEVELOPER_DIR="$(dirname "$ASGARD_DIR")"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  🏰 ASGARD AI PLATFORM — Starting all services...   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Check repos exist
REQUIRED_REPOS=("Mimir" "Bifrost" "Fenrir" "Yggdrasil")
for repo in "${REQUIRED_REPOS[@]}"; do
    if [ ! -d "$DEVELOPER_DIR/$repo" ]; then
        echo -e "${RED}❌ Missing repo: $DEVELOPER_DIR/$repo${NC}"
        echo "   Clone it: git clone https://github.com/megacare-dev/$repo.git $DEVELOPER_DIR/$repo"
        exit 1
    fi
done
echo -e "${GREEN}✅ All repos found${NC}"

# Step 1: Remind about Heimdall
echo ""
echo -e "${YELLOW}🛡️  HEIMDALL (LLM Gateway) runs on HOST — start separately:${NC}"
echo "   cd $DEVELOPER_DIR/Heimdall && ./scripts/start.sh"
echo ""

# Step 2: Start Docker Compose
PROFILE_FLAG=""
if [ "$1" = "--full" ]; then
    echo -e "${BLUE}🏥 Starting with OpenEMR (full profile)...${NC}"
    PROFILE_FLAG="--profile full"
fi

cd "$ASGARD_DIR"
echo -e "${BLUE}🐳 Starting Docker Compose...${NC}"
docker compose $PROFILE_FLAG up -d

# Step 3: Wait for health
echo ""
echo -e "${BLUE}⏳ Waiting for services...${NC}"
sleep 5

# Run health check
"$SCRIPT_DIR/health.sh"

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║  🏰 ASGARD is running!                              ║"
echo "╠══════════════════════════════════════════════════════╣"
echo "║  🌳 Yggdrasil (Auth)    → http://localhost:8085     ║"
echo "║  🧠 Mimir Dashboard    → http://localhost:3001     ║"
echo "║  🧠 Mimir API          → http://localhost:3000     ║"
echo "║  ⚡ Bifrost             → http://localhost:8100     ║"
echo "║  🐺 Fenrir              → http://localhost:8200     ║"
echo "║  🛡️  Heimdall (HOST)    → http://localhost:8080     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
