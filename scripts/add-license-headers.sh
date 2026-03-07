#!/bin/bash
# add-license-headers.sh — Add AGPL-3.0 headers to source files
# Usage: ./scripts/add-license-headers.sh [directory]

set -euo pipefail

DIRECTORY="${1:-.}"
YEAR=$(date +%Y)

# ============================================================
# Rust header (.rs files)
# ============================================================
RUST_HEADER="// Asgard AI Platform
// Copyright (C) ${YEAR} MegaCare Dev
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
"

# ============================================================
# Python header (.py files)
# ============================================================
PYTHON_HEADER="# Asgard AI Platform
# Copyright (C) ${YEAR} MegaCare Dev
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
"

# ============================================================
# TypeScript/JavaScript header (.ts, .tsx, .js, .jsx files)
# ============================================================
TS_HEADER="/*
 * Asgard AI Platform
 * Copyright (C) ${YEAR} MegaCare Dev
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */
"

add_header() {
    local file="$1"
    local header="$2"
    
    # Skip if already has AGPL header
    if grep -q "GNU Affero General Public License" "$file" 2>/dev/null; then
        echo "  SKIP (already has header): $file"
        return
    fi
    
    # Skip empty files
    if [ ! -s "$file" ]; then
        echo "  SKIP (empty): $file"
        return
    fi
    
    # Handle shebang lines
    local first_line
    first_line=$(head -1 "$file")
    
    if [[ "$first_line" == "#!"* ]]; then
        # Preserve shebang, add header after it
        local rest
        rest=$(tail -n +2 "$file")
        echo "$first_line" > "$file"
        echo "" >> "$file"
        echo "$header" >> "$file"
        echo "$rest" >> "$file"
    else
        # Add header at the top
        local content
        content=$(cat "$file")
        echo "$header" > "$file"
        echo "$content" >> "$file"
    fi
    
    echo "  ADDED: $file"
}

echo "🏰 Asgard AGPL-3.0 License Header Tool"
echo "========================================"
echo "Directory: $DIRECTORY"
echo ""

# Process Rust files
echo "🦀 Processing Rust files (.rs)..."
find "$DIRECTORY" -name "*.rs" -not -path "*/target/*" -not -path "*/vendor/*" | while read -r file; do
    add_header "$file" "$RUST_HEADER"
done

# Process Python files
echo ""
echo "🐍 Processing Python files (.py)..."
find "$DIRECTORY" -name "*.py" -not -path "*/__pycache__/*" -not -path "*/venv/*" -not -path "*/.venv/*" | while read -r file; do
    add_header "$file" "$PYTHON_HEADER"
done

# Process TypeScript/JavaScript files
echo ""
echo "📜 Processing TypeScript/JavaScript files (.ts, .tsx, .js, .jsx)..."
find "$DIRECTORY" -\( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \) \
    -not -path "*/node_modules/*" -not -path "*/.next/*" -not -path "*/dist/*" | while read -r file; do
    add_header "$file" "$TS_HEADER"
done

echo ""
echo "✅ Done! Remember to review changes before committing."
echo "   git diff --stat"
