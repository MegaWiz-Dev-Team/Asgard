#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  Export Asgard shared env vars for host-side services        ║
# ║  Usage: source scripts/env-export.sh                        ║
# ╚══════════════════════════════════════════════════════════════╝

ASGARD_ENV="${ASGARD_DIR:-$HOME/Developer/Asgard}/.env"

if [ ! -f "$ASGARD_ENV" ]; then
    echo "⚠️  Asgard .env not found at $ASGARD_ENV"
    echo "   Set ASGARD_DIR or ensure ~/Developer/Asgard/.env exists"
    return 1 2>/dev/null || exit 1
fi

# Export only the vars Heimdall needs
while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    key="${line%%=*}"
    case "$key" in
        HEIMDALL_*|EMBEDDING_*|EXTERNAL_MODEL_DIR|LOG_LEVEL|RUST_LOG)
            export "$line"
            ;;
    esac
done < "$ASGARD_ENV"

# Map Asgard var names to Heimdall .env names
export API_KEYS="${HEIMDALL_API_KEY:-}"
export LLM_MODEL="${HEIMDALL_MODEL:-}"
export BACKEND_ENGINE="${HEIMDALL_BACKEND_ENGINE:-mlx}"
export GATEWAY_PORT="${HEIMDALL_GATEWAY_PORT:-8080}"
export BACKEND_PORT="${HEIMDALL_BACKEND_PORT:-8081}"

echo "✅ Heimdall env loaded from $ASGARD_ENV"
