#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# network.sh - Network Configuration with RDP Support
# ═══════════════════════════════════════════════════════════════════════════════
# Configures QEMU networking for the Windows guest with RDP port forwarding
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

# Environment variable defaults
: "${NETWORK:="user"}"          # Network mode: user, bridge, passt, slirp
: "${RDP_PORT:="3389"}"         # RDP external port
: "${RDP_PORT_ALT:="13389"}"    # Alternative RDP port
: "${DHCP:="N"}"                # Use DHCP (for bridge mode)
: "${NET_DEVICE:="e1000"}"      # Network card: e1000, virtio-net, rtl8139
: "${MAC_ADDRESS:=""}"          # Custom MAC address
: "${HOST_PORTS:=""}"           # Additional port forwards (format: "host:guest,host:guest")
: "${IP:=""}"                   # Static IP (for bridge mode)

# Network state variables
VM_NET_DEV=""
VM_NET_IP=""
VM_NET_BRIDGE=""

# ═══════════════════════════════════════════════════════════════════════════════
# User Mode Networking (Default - Best Docker Compatibility)
# ═══════════════════════════════════════════════════════════════════════════════

build_user_network() {
    local netdev_args=""
    local device_args=""
    local hostfwd=""
    
    # Base netdev configuration
    netdev_args="user,id=net0"
    
    # ─────────────────────────────────────────────────────────────────────────
    # RDP Port Forwarding
    # ─────────────────────────────────────────────────────────────────────────
    # Primary RDP port
    hostfwd+=",hostfwd=tcp::${RDP_PORT}-:3389"
    hostfwd+=",hostfwd=udp::${RDP_PORT}-:3389"
    
    # Alternative RDP port (for cases where 3389 is blocked)
    if [[ "${RDP_PORT}" != "${RDP_PORT_ALT}" ]]; then
        hostfwd+=",hostfwd=tcp::${RDP_PORT_ALT}-:3389"
    fi
    
    # ─────────────────────────────────────────────────────────────────────────
    # SMB/Samba Sharing
    # ─────────────────────────────────────────────────────────────────────────
    hostfwd+=",hostfwd=tcp::445-:445"
    hostfwd+=",hostfwd=tcp::139-:139"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Additional Custom Port Forwards
    # ─────────────────────────────────────────────────────────────────────────
    if [[ -n "${HOST_PORTS}" ]]; then
        IFS=',' read -ra ports_array <<< "${HOST_PORTS}"
        for port_map in "${ports_array[@]}"; do
            if [[ "$port_map" =~ ^([0-9]+):([0-9]+)$ ]]; then
                hostfwd+=",hostfwd=tcp::${BASH_REMATCH[1]}-:${BASH_REMATCH[2]}"
            fi
        done
    fi
    
    netdev_args+="${hostfwd}"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Guest DNS Configuration
    # ─────────────────────────────────────────────────────────────────────────
    netdev_args+=",net=192.168.1.0/24"
    netdev_args+=",host=192.168.1.1"
    netdev_args+=",dns=192.168.1.1"
    netdev_args+=",dhcpstart=192.168.1.100"
    
    # Add Samba share access for file sharing
    netdev_args+=",smb=/shared"
    
    # ─────────────────────────────────────────────────────────────────────────
    # Network Device Configuration
    # ─────────────────────────────────────────────────────────────────────────
    device_args="-device ${NET_DEVICE},netdev=net0"
    
    # Add custom MAC address if specified
    if [[ -n "${MAC_ADDRESS}" ]]; then
        device_args+=",mac=${MAC_ADDRESS}"
    fi
    
    echo "-netdev ${netdev_args} ${device_args}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Bridge Mode Networking (Requires Host Bridge Setup)
# ═══════════════════════════════════════════════════════════════════════════════

build_bridge_network() {
    local netdev_args=""
    local device_args=""
    local bridge="${VM_NET_BRIDGE:-br0}"
    
    netdev_args="bridge,id=net0,br=${bridge}"
    
    device_args="-device ${NET_DEVICE},netdev=net0"
    if [[ -n "${MAC_ADDRESS}" ]]; then
        device_args+=",mac=${MAC_ADDRESS}"
    fi
    
    echo "-netdev ${netdev_args} ${device_args}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Generate MAC Address
# ═══════════════════════════════════════════════════════════════════════════════

generate_mac() {
    # Generate a random locally-administered MAC address
    local mac=""
    mac=$(printf '52:54:00:%02X:%02X:%02X' \
        $((RANDOM % 256)) \
        $((RANDOM % 256)) \
        $((RANDOM % 256)))
    echo "$mac"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Network Cleanup (called on shutdown)
# ═══════════════════════════════════════════════════════════════════════════════

closeNetwork() {
    # Cleanup any bridge interfaces we created
    if [[ -n "${VM_NET_DEV}" ]] && ip link show "${VM_NET_DEV}" &>/dev/null; then
        ip link set "${VM_NET_DEV}" down 2>/dev/null || true
        ip link delete "${VM_NET_DEV}" 2>/dev/null || true
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Network Initialization
# ═══════════════════════════════════════════════════════════════════════════════

init_network() {
    # Generate MAC address if not provided
    if [[ -z "${MAC_ADDRESS}" ]]; then
        MAC_ADDRESS=$(generate_mac)
    fi
    
    # Create shared directory if it doesn't exist
    mkdir -p /shared 2>/dev/null || true
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Initialize network
init_network

# Build network arguments based on mode
case "${NETWORK,,}" in
    "user" | "slirp")
        NET_ARGS=$(build_user_network)
        info "Network mode: User (SLIRP) - RDP on port ${RDP_PORT}"
        ;;
    "bridge")
        NET_ARGS=$(build_bridge_network)
        info "Network mode: Bridge (${VM_NET_BRIDGE:-br0})"
        ;;
    "passt")
        # Passt networking (newer, better performance)
        NET_ARGS="-netdev stream,id=net0,addr.type=unix,addr.path=/tmp/passt.sock -device ${NET_DEVICE},netdev=net0"
        info "Network mode: Passt"
        ;;
    "none")
        NET_ARGS=""
        warn "Network mode: None (no networking)"
        ;;
    *)
        warn "Unknown network mode '${NETWORK}', defaulting to user mode"
        NET_ARGS=$(build_user_network)
        ;;
esac

# Add network arguments to QEMU
if [[ -n "${NET_ARGS}" ]]; then
    ARGS+=" ${NET_ARGS}"
fi

# Log connection info
info "RDP will be available on ports: ${RDP_PORT}/tcp, ${RDP_PORT}/udp"
if [[ "${RDP_PORT}" != "${RDP_PORT_ALT}" ]]; then
    info "Alternative RDP port: ${RDP_PORT_ALT}/tcp"
fi

return 0
