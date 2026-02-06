#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# disk.sh - Disk Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# Configures virtual disk storage for the Windows guest
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

# Environment variable defaults
: "${STORAGE:="/storage"}"      # Storage directory
: "${DISK_SIZE:="64G"}"         # Virtual disk size
: "${DISK_FMT:="qcow2"}"        # Disk format: qcow2, raw
: "${DISK_IO:="native"}"        # I/O mode: native, threads
: "${DISK_CACHE:="none"}"       # Cache mode: none, writeback, writethrough
: "${DISK_DISCARD:="unmap"}"    # Discard mode: unmap, ignore

DISK_FILE="${STORAGE}/data.qcow2"

# ═══════════════════════════════════════════════════════════════════════════════
# Initialize Disk
# ═══════════════════════════════════════════════════════════════════════════════

init_disk() {
    local disk_path="$1"
    local disk_size="$2"
    local disk_fmt="$3"
    
    # Create storage directory
    mkdir -p "$(dirname "$disk_path")" 2>/dev/null || true
    
    # Check if disk already exists
    if [[ -f "$disk_path" ]]; then
        info "Using existing disk: ${disk_path}"
        return 0
    fi
    
    info "Creating virtual disk: ${disk_path} (${disk_size})..."
    
    case "${disk_fmt,,}" in
        "qcow2")
            qemu-img create -f qcow2 "$disk_path" "$disk_size" 2>/dev/null
            ;;
        "raw")
            qemu-img create -f raw "$disk_path" "$disk_size" 2>/dev/null
            ;;
        *)
            qemu-img create -f qcow2 "$disk_path" "$disk_size" 2>/dev/null
            ;;
    esac
    
    if [[ ! -f "$disk_path" ]]; then
        error "Failed to create disk: ${disk_path}"
        return 1
    fi
    
    info "Disk created successfully"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Build Disk Arguments
# ═══════════════════════════════════════════════════════════════════════════════

build_disk_args() {
    local disk_path="$1"
    local disk_args=""
    
    # Detect disk format
    local fmt="${DISK_FMT}"
    if [[ -f "$disk_path" ]]; then
        fmt=$(qemu-img info "$disk_path" 2>/dev/null | grep "file format" | awk '{print $3}' || echo "${DISK_FMT}")
    fi
    
    # Build drive arguments
    disk_args="-drive file=${disk_path},format=${fmt},if=virtio,cache=${DISK_CACHE},discard=${DISK_DISCARD}"
    
    echo "$disk_args"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Check if Disk Has Data
# ═══════════════════════════════════════════════════════════════════════════════

hasDisk() {
    [[ -f "$DISK_FILE" ]] && [[ -s "$DISK_FILE" ]]
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize disk
if ! init_disk "${DISK_FILE}" "${DISK_SIZE}" "${DISK_FMT}"; then
    error "Failed to initialize disk!"
fi

# Build disk arguments
DISK_ARGS=$(build_disk_args "${DISK_FILE}")
ARGS+=" ${DISK_ARGS}"

info "Disk configured: ${DISK_FILE} (${DISK_SIZE})"

return 0
