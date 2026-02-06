#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# config.sh - Final QEMU Configuration Assembly
# ═══════════════════════════════════════════════════════════════════════════════
# This script finalizes QEMU arguments after all other components have run
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

# Environment variable defaults
: "${DEBUG:="N"}"               # Enable debug output

# ═══════════════════════════════════════════════════════════════════════════════
# Additional QEMU Options
# ═══════════════════════════════════════════════════════════════════════════════

# RTC configuration (use UTC)
ARGS+=" -rtc base=utc,clock=host"

# Disable USB tablet for better mouse performance with VNC
ARGS+=" -usb -device usb-tablet"

# Add random number generator for better entropy in guest
ARGS+=" -object rng-random,id=rng0,filename=/dev/urandom"
ARGS+=" -device virtio-rng-pci,rng=rng0"

# Enable QEMU guest agent virtio channel (if guest tools are installed)
ARGS+=" -chardev socket,path=/var/run/qga.sock,server=on,wait=off,id=qga0"
ARGS+=" -device virtio-serial-pci"
ARGS+=" -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"

# ═══════════════════════════════════════════════════════════════════════════════
# Debug Output
# ═══════════════════════════════════════════════════════════════════════════════

if [[ "${DEBUG}" == [Yy1]* ]]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "                      FINAL QEMU CONFIGURATION"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "ARGS:"
    echo "$ARGS" | tr ' ' '\n' | grep -v '^$' | sed 's/^/  /'
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
fi

return 0
