#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# entry.sh - Windows VM Container Entrypoint
# ═══════════════════════════════════════════════════════════════════════════════
# This is the main entrypoint for the Windows container with nested
# virtualization support. It orchestrates the VM initialization and launch.
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

: "${APP:="Windows"}"
: "${PLATFORM:="x64"}"
: "${BOOT_MODE:="windows"}"
: "${SUPPORT:="https://github.com/dockur/windows"}"

# Initialize ARGS variable for QEMU arguments
ARGS=""

cd /run

# ═══════════════════════════════════════════════════════════════════════════════
# Initialization Phase
# ═══════════════════════════════════════════════════════════════════════════════

. start.sh      # Startup hook
. utils.sh      # Load functions
. reset.sh      # Initialize system
. server.sh     # Start webserver
. define.sh     # Define versions
. mido.sh       # Download Windows
. install.sh    # Run installation

# ═══════════════════════════════════════════════════════════════════════════════
# QEMU Configuration Phase
# ═══════════════════════════════════════════════════════════════════════════════

. disk.sh       # Initialize disks
. display.sh    # Initialize graphics (VNC/noVNC)
. network.sh    # Initialize network (RDP forwarding)
. samba.sh      # Configure samba shares
. boot.sh       # Configure UEFI/BIOS boot
. proc.sh       # Initialize processor (KVM, VMX/SVM, Hyper-V)
. power.sh      # Configure shutdown
. memory.sh     # Configure memory allocation
. config.sh     # Finalize QEMU arguments
. finish.sh     # Finish initialization

trap - ERR

version=$(qemu-system-x86_64 --version | head -n 1 | cut -d '(' -f 1 | awk '{ print $NF }')
info "Booting ${APP}${BOOT_DESC} using QEMU v$version..."

{ qemu-system-x86_64 ${ARGS:+ $ARGS} >"$QEMU_OUT" 2>"$QEMU_LOG"; rc=$?; } || :
(( rc != 0 )) && error "$(<"$QEMU_LOG")" && exit 15

terminal
( sleep 30; boot ) &
tail -fn +0 "$QEMU_LOG" --pid=$$ 2>/dev/null &
cat "$QEMU_TERM" 2> /dev/null | tee "$QEMU_PTY" | \
sed -u -e 's/\x1B\[[=0-9;]*[a-z]//gi' \
-e 's/\x1B\x63//g' -e 's/\x1B\[[=?]7l//g' \
-e '/^$/d' -e 's/\x44\x53\x73//g' \
-e 's/failed to load Boot/skipped Boot/g' \
-e 's/0): Not Found/0)/g' & wait $! || :

sleep 1 & wait $!
[ ! -f "$QEMU_END" ] && finish 0
