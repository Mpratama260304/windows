#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# memory.sh - Memory Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# Configures RAM allocation for the Windows guest
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

# Environment variable defaults
: "${RAM_SIZE:="4G"}"           # Guest RAM size
: "${BALLOON:="Y"}"             # Enable memory ballooning

# ═══════════════════════════════════════════════════════════════════════════════
# Parse Memory Size
# ═══════════════════════════════════════════════════════════════════════════════

parse_memory_size() {
    local size="$1"
    local bytes=0
    
    # Handle different formats: 4G, 4096M, 4096, etc.
    if [[ "$size" =~ ^([0-9]+)([GgMmKk]?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]^^}"
        
        case "$unit" in
            "G") bytes=$((num * 1024 * 1024 * 1024)) ;;
            "M") bytes=$((num * 1024 * 1024)) ;;
            "K") bytes=$((num * 1024)) ;;
            "")  bytes=$((num * 1024 * 1024)) ;; # Default MB
        esac
    else
        # Assume it's already in bytes or a valid QEMU format
        echo "$size"
        return 0
    fi
    
    # Convert to most readable format
    if (( bytes >= 1024*1024*1024 )); then
        echo "$((bytes / 1024 / 1024 / 1024))G"
    elif (( bytes >= 1024*1024 )); then
        echo "$((bytes / 1024 / 1024))M"
    else
        echo "$((bytes / 1024))K"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Check Available Memory
# ═══════════════════════════════════════════════════════════════════════════════

check_available_memory() {
    local requested="$1"
    local available_kb=0
    local requested_kb=0
    
    # Get available memory in KB
    if [[ -f /proc/meminfo ]]; then
        available_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    fi
    
    # Convert requested to KB
    if [[ "$requested" =~ ^([0-9]+)([GgMmKk]?)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]^^}"
        
        case "$unit" in
            "G") requested_kb=$((num * 1024 * 1024)) ;;
            "M") requested_kb=$((num * 1024)) ;;
            "K") requested_kb=$num ;;
            "")  requested_kb=$((num * 1024)) ;;
        esac
    fi
    
    # Warn if we're requesting more than 80% of available
    if (( requested_kb > available_kb * 80 / 100 )); then
        local available_g=$((available_kb / 1024 / 1024))
        warn "Requested RAM (${requested}) is more than 80% of available memory (${available_g}G)"
        warn "This may cause system instability. Consider reducing RAM_SIZE."
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Build Memory Arguments
# ═══════════════════════════════════════════════════════════════════════════════

build_memory_args() {
    local ram="${1:-4G}"
    local mem_args=""
    
    # Normalize RAM size
    ram=$(parse_memory_size "$ram")
    
    # Base memory configuration
    mem_args="-m ${ram}"
    
    echo "$mem_args"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Validate memory
check_available_memory "${RAM_SIZE}"

# Build memory arguments
MEM_ARGS=$(build_memory_args "${RAM_SIZE}")
ARGS+=" ${MEM_ARGS}"

# Add memory ballooning device
if [[ "${BALLOON}" == [Yy1]* ]]; then
    ARGS+=" -device virtio-balloon-pci,id=balloon0"
fi

info "Memory configured: ${RAM_SIZE}"

return 0
