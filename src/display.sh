#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# display.sh - Display/VGA Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# Configures QEMU display output for VNC access via noVNC
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

# Environment variable defaults
: "${DISPLAY_MODE:="std"}"      # VGA mode: std, qxl, virtio-vga, cirrus
: "${VNC_PORT:="5900"}"         # VNC server port
: "${NOVNC_PORT:="8006"}"       # noVNC websocket port
: "${VNC_PASSWORD:=""}"         # VNC password (empty = no password)
: "${SCREEN:="0"}"              # VNC display number
: "${DISPLAY_RES:=""}"          # Display resolution (e.g., 1920x1080)
: "${GPU_MEMORY:=""}"           # Video memory size for QXL (e.g., 256)

# noVNC/websockify PID file for idempotent restarts
WEBSOCKIFY_PID="/var/run/websockify.pid"

# ═══════════════════════════════════════════════════════════════════════════════
# VGA Device Configuration
# ═══════════════════════════════════════════════════════════════════════════════

build_vga_args() {
    local mode="${1:-std}"
    local vga_args=""
    
    case "${mode,,}" in
        "std" | "standard")
            # Standard VGA - most stable, recommended for installation
            vga_args="-vga std"
            info "VGA mode: std (Standard VGA - most stable)"
            ;;
        "qxl")
            # QXL - better performance with SPICE, decent with VNC
            vga_args="-vga qxl"
            if [[ -n "${GPU_MEMORY}" ]]; then
                # Add QXL memory configuration
                vga_args+=" -global qxl-vga.vram_size=$((GPU_MEMORY * 1024 * 1024))"
            fi
            info "VGA mode: qxl (QXL/SPICE optimized)"
            ;;
        "virtio" | "virtio-vga")
            # VirtIO VGA - best performance but requires guest drivers
            vga_args="-vga virtio"
            info "VGA mode: virtio-vga (requires VirtIO drivers)"
            ;;
        "cirrus")
            # Cirrus VGA - legacy compatibility
            vga_args="-vga cirrus"
            warn "VGA mode: cirrus (legacy, may have issues with modern Windows)"
            ;;
        "none")
            # No VGA - headless mode
            vga_args="-vga none"
            info "VGA mode: none (headless)"
            ;;
        *)
            # Default to std for unknown modes
            warn "Unknown DISPLAY_MODE '${mode}', defaulting to 'std'"
            vga_args="-vga std"
            ;;
    esac
    
    echo "$vga_args"
}

# ═══════════════════════════════════════════════════════════════════════════════
# VNC Configuration
# ═══════════════════════════════════════════════════════════════════════════════

build_vnc_args() {
    local display="${SCREEN:-0}"
    local vnc_args=""
    
    # VNC listens on localhost only (websockify handles external access)
    vnc_args="-display vnc=127.0.0.1:${display}"
    
    # Add password protection if configured
    if [[ -n "${VNC_PASSWORD}" ]]; then
        vnc_args+=",password=on"
        info "VNC password protection: ENABLED"
    fi
    
    # Add keyboard/mouse grab settings for better UX
    vnc_args+=",keyboard=on"
    
    echo "$vnc_args"
}

# ═══════════════════════════════════════════════════════════════════════════════
# noVNC/Websockify Management
# ═══════════════════════════════════════════════════════════════════════════════

stop_websockify() {
    # Kill any existing websockify process
    if [[ -f "${WEBSOCKIFY_PID}" ]]; then
        local pid
        pid=$(cat "${WEBSOCKIFY_PID}" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            info "Stopping existing websockify (PID: $pid)..."
            kill -TERM "$pid" 2>/dev/null || true
            sleep 1
            kill -KILL "$pid" 2>/dev/null || true
        fi
        rm -f "${WEBSOCKIFY_PID}"
    fi
    
    # Also kill any stray websockify processes on our ports
    pkill -f "websockify.*:${NOVNC_PORT}" 2>/dev/null || true
}

start_websockify() {
    local vnc_port="$((5900 + ${SCREEN:-0}))"
    local novnc_web="/usr/share/novnc/"
    local novnc_alt="/usr/share/noVNC/"
    
    # Find noVNC web directory
    if [[ -d "${novnc_alt}" ]]; then
        novnc_web="${novnc_alt}"
    fi
    
    if [[ ! -d "${novnc_web}" ]]; then
        error "noVNC web directory not found!"
        return 1
    fi
    
    # Stop any existing websockify
    stop_websockify
    
    # Check if port is already in use
    if ss -lntp 2>/dev/null | grep -q ":${NOVNC_PORT} "; then
        warn "Port ${NOVNC_PORT} is already in use, attempting to free it..."
        fuser -k "${NOVNC_PORT}/tcp" 2>/dev/null || true
        sleep 1
    fi
    
    info "Starting noVNC websockify on port ${NOVNC_PORT}..."
    
    # Start websockify in background
    websockify \
        --web="${novnc_web}" \
        --wrap-mode=ignore \
        0.0.0.0:"${NOVNC_PORT}" \
        127.0.0.1:"${vnc_port}" \
        > /var/log/websockify.log 2>&1 &
    
    local ws_pid=$!
    echo "$ws_pid" > "${WEBSOCKIFY_PID}"
    
    # Wait a moment and verify it started
    sleep 1
    if ! kill -0 "$ws_pid" 2>/dev/null; then
        error "Failed to start websockify!"
        cat /var/log/websockify.log 2>/dev/null || true
        return 1
    fi
    
    info "noVNC ready at http://0.0.0.0:${NOVNC_PORT}/vnc.html"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Display Health Check
# ═══════════════════════════════════════════════════════════════════════════════

display_healthcheck() {
    local novnc_url="http://127.0.0.1:${NOVNC_PORT}/vnc.html"
    
    if curl -sI "${novnc_url}" 2>/dev/null | grep -q "200"; then
        return 0
    fi
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Build VGA arguments
VGA_ARGS=$(build_vga_args "${DISPLAY_MODE}")
ARGS+=" ${VGA_ARGS}"

# Build VNC arguments
VNC_ARGS=$(build_vnc_args)
ARGS+=" ${VNC_ARGS}"

# Start noVNC/websockify (delayed start after QEMU)
# This is handled by the boot sequence, we just prepare the function
info "Display configured: VNC on :${SCREEN}, noVNC on port ${NOVNC_PORT}"

return 0
