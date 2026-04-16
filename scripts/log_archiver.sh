#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Asgard Log Archiver
# Rotates and compresses logs from internal storage
# to the T7 Shield external SSD to save space and 
# comply with ISO 27001 retention standard.
# ============================================

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
ARCHIVE_DIR="/Volumes/T7 Shield/Asgard-Archives/Heimdall-Logs"
LOG_DIR="/Users/mimir/Developer/Heimdall/logs"

# Ensure the archive directory exists
mkdir -p "$ARCHIVE_DIR"

echo "🧹 Starting Log Archiver at $(date)"

# Function to rotate a log using "copytruncate" technique
# This is safe for running processes that do not close file handles.
rotate_log() {
    local log_file="$1"
    local base_name=$(basename "$log_file")
    
    if [[ -f "$log_file" ]]; then
        local target_archived_file="$ARCHIVE_DIR/${base_name}.${TIMESTAMP}.log"
        
        # 1. Copy the current content to T7
        cp "$log_file" "$target_archived_file"
        
        # 2. Truncate the original file down to zero without breaking the file handle
        > "$log_file"
        
        # 3. Compress the archive on the T7 to save space (results in .log.gz)
        gzip -9 "$target_archived_file"
        
        echo "✅ Archived and compressed: $base_name"
    else
        echo "⚠️ Log file not found: $log_file"
    fi
}

# Rotate all .log files in the Heimdall logs directory
for file in "$LOG_DIR"/*.log; do
    # Only process files that exist
    if [[ -f "$file" ]]; then
        rotate_log "$file"
    fi
done

# (Optional) Delete archives older than 365 days (1 year retention)
find "$ARCHIVE_DIR" -type f -name "*.gz" -mtime +365 -exec rm {} \;

echo "🎉 Log archiving complete at $(date)"
