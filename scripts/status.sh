#!/usr/bin/env bash
# ============================================
# 🏰 Asgard AI Platform — Quick Status Check
# ============================================
# Shortcut for: ./scripts/start.sh --status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/start.sh" --status
