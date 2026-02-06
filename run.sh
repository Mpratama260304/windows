#!/usr/bin/env bash
#
# run.sh - Windows Nested Virtualization Container Launcher
#
# This script validates the environment and starts the Windows VM container
# with nested virtualization support enabled.
#
set -Eeuo pipefail

# Configuration defaults
: "${CONTAINER_NAME:=windows-nested}"
: "${WINDOWS_VERSION:=11}"
: "${RAM_SIZE:=8G}"
: "${CPU_CORES:=4}"
: "${DISK_SIZE:=64G}"
: "${WIN_PASSWORD:=Anonymous263}"
: "${STORAGE_PATH:=./storage}"
: "${VNC_PORT:=8006}"
: "${RDP_PORT:=3389}"
: "${DEBUG:=N}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    [[ "$DEBUG" == [Yy1]* ]] && echo -e "${BLUE}[DEBUG]${NC} $1"
}

banner() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║     Windows Nested Virtualization Container                       ║"
    echo "║     Supports Android Emulator / Hyper-V / WHPX                    ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo ""
}

# Check if KVM is available
check_kvm() {
    log_info "Checking KVM availability..."
    
    if [ ! -e /dev/kvm ]; then
        log_error "/dev/kvm not found!"
        log_error "KVM is required for hardware acceleration."
        echo ""
        echo "Possible solutions:"
        echo "  1. Enable virtualization in BIOS/UEFI (VT-x for Intel, AMD-V for AMD)"
        echo "  2. Load KVM kernel modules: sudo modprobe kvm kvm_intel (or kvm_amd)"
        echo "  3. Check if running inside a VM - nested virtualization must be enabled"
        echo ""
        return 1
    fi
    
    if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
        log_error "/dev/kvm exists but is not readable/writable!"
        echo ""
        echo "Fix permissions:"
        echo "  sudo chmod 666 /dev/kvm"
        echo "  # Or add user to kvm group: sudo usermod -aG kvm \$USER"
        echo ""
        return 1
    fi
    
    log_info "✓ KVM is available and accessible"
    return 0
}

# Check nested virtualization parameter
check_nested() {
    log_info "Checking nested virtualization support..."
    
    local nested_intel="/sys/module/kvm_intel/parameters/nested"
    local nested_amd="/sys/module/kvm_amd/parameters/nested"
    local nested_status=""
    local vendor=""
    
    if [ -f "$nested_intel" ]; then
        vendor="Intel"
        nested_status=$(cat "$nested_intel" 2>/dev/null || echo "N")
    elif [ -f "$nested_amd" ]; then
        vendor="AMD"
        nested_status=$(cat "$nested_amd" 2>/dev/null || echo "0")
    else
        log_warn "Could not determine CPU vendor for nested virtualization check"
        log_warn "Continuing anyway - nested may still work if enabled at hypervisor level"
        return 0
    fi
    
    # Normalize the status
    if [[ "$nested_status" == "Y" || "$nested_status" == "1" ]]; then
        log_info "✓ Nested virtualization is ENABLED on ${vendor} CPU"
        return 0
    else
        log_warn "Nested virtualization appears to be DISABLED on ${vendor} CPU"
        echo ""
        echo "To enable nested virtualization (requires root on host):"
        if [ "$vendor" == "Intel" ]; then
            echo "  echo 'options kvm_intel nested=1' | sudo tee /etc/modprobe.d/kvm.conf"
            echo "  sudo modprobe -r kvm_intel && sudo modprobe kvm_intel"
        else
            echo "  echo 'options kvm_amd nested=1' | sudo tee /etc/modprobe.d/kvm.conf"
            echo "  sudo modprobe -r kvm_amd && sudo modprobe kvm_amd"
        fi
        echo ""
        log_warn "Continuing anyway - the VM will start but nested virt may not work inside Windows"
        return 0
    fi
}

# Check CPU features
check_cpu_features() {
    log_info "Checking CPU virtualization features..."
    
    local cpuinfo="/proc/cpuinfo"
    if [ ! -f "$cpuinfo" ]; then
        log_warn "Cannot read /proc/cpuinfo"
        return 0
    fi
    
    local flags
    flags=$(grep -m1 "^flags" "$cpuinfo" | cut -d: -f2)
    
    if echo "$flags" | grep -qw "vmx"; then
        log_info "✓ Intel VT-x (VMX) supported"
    elif echo "$flags" | grep -qw "svm"; then
        log_info "✓ AMD-V (SVM) supported"
    else
        log_warn "Neither VMX nor SVM found in CPU flags"
        log_warn "Hardware virtualization may not be available"
    fi
    
    return 0
}

# Check Docker/Podman availability
check_container_runtime() {
    log_info "Checking container runtime..."
    
    if command -v docker &>/dev/null; then
        CONTAINER_CMD="docker"
        COMPOSE_CMD="docker compose"
        if ! docker compose version &>/dev/null; then
            if command -v docker-compose &>/dev/null; then
                COMPOSE_CMD="docker-compose"
            fi
        fi
        log_info "✓ Docker is available"
    elif command -v podman &>/dev/null; then
        CONTAINER_CMD="podman"
        COMPOSE_CMD="podman-compose"
        log_info "✓ Podman is available"
    else
        log_error "No container runtime found!"
        echo "Please install Docker or Podman"
        return 1
    fi
    
    return 0
}

# Create storage directory
setup_storage() {
    log_info "Setting up storage directory: $STORAGE_PATH"
    
    mkdir -p "$STORAGE_PATH"
    
    if [ ! -w "$STORAGE_PATH" ]; then
        log_error "Storage directory is not writable: $STORAGE_PATH"
        return 1
    fi
    
    log_info "✓ Storage directory ready"
    return 0
}

# Generate compose file
generate_compose() {
    log_info "Generating docker-compose configuration..."
    
    cat > "${STORAGE_PATH}/docker-compose.nested.yml" << EOF
# Auto-generated Docker Compose file for Windows with Nested Virtualization
# Generated: $(date -Iseconds)
#
# This configuration enables nested virtualization (VMX/SVM passthrough)
# allowing Windows to run Android emulators and other nested VMs.

services:
  windows:
    image: dockurr/windows
    container_name: ${CONTAINER_NAME}
    environment:
      VERSION: "${WINDOWS_VERSION}"
      RAM_SIZE: "${RAM_SIZE}"
      CPU_CORES: "${CPU_CORES}"
      DISK_SIZE: "${DISK_SIZE}"
      PASSWORD: "${WIN_PASSWORD}"
      USERNAME: "Admin"
      # CRITICAL: Enable VMX passthrough for nested virtualization
      VMX: "Y"
      # Enable Hyper-V enlightenments for better performance
      HV: "Y"
      # Debug mode
      DEBUG: "${DEBUG}"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - "${VNC_PORT}:8006"
      - "${RDP_PORT}:3389/tcp"
      - "${RDP_PORT}:3389/udp"
    volumes:
      - ${STORAGE_PATH}:/storage
    restart: unless-stopped
    stop_grace_period: 2m
    # Ensure sufficient shared memory for QEMU
    shm_size: 1g
    # Security options for nested virtualization
    security_opt:
      - seccomp:unconfined
EOF

    log_info "✓ Compose file generated: ${STORAGE_PATH}/docker-compose.nested.yml"
    return 0
}

# Start the container
start_container() {
    log_info "Starting Windows container with nested virtualization..."
    
    cd "${STORAGE_PATH}"
    
    if [ "$CONTAINER_CMD" == "docker" ]; then
        $COMPOSE_CMD -f docker-compose.nested.yml up -d
    else
        $COMPOSE_CMD -f docker-compose.nested.yml up -d
    fi
    
    local rc=$?
    if [ $rc -ne 0 ]; then
        log_error "Failed to start container (exit code: $rc)"
        return 1
    fi
    
    log_info "✓ Container started successfully"
    return 0
}

# Print connection information
print_connection_info() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "                        CONNECTION INFORMATION"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "  noVNC Web Access:"
    echo "    http://localhost:${VNC_PORT}/vnc.html"
    echo ""
    echo "  RDP Connection:"
    echo "    Host: localhost"
    echo "    Port: ${RDP_PORT}"
    echo "    Username: Admin"
    echo "    Password: ${WIN_PASSWORD}"
    echo ""
    echo "  Container Logs:"
    echo "    ${CONTAINER_CMD} logs -f ${CONTAINER_NAME}"
    echo ""
    echo "  Stop Container:"
    echo "    ${CONTAINER_CMD} stop ${CONTAINER_NAME}"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""
    echo "IMPORTANT: After Windows boots, verify nested virtualization:"
    echo "  1. Open Task Manager → Performance → CPU"
    echo "     Look for 'Virtualization: Enabled'"
    echo ""
    echo "  2. Open PowerShell as Admin and run:"
    echo "     systeminfo | findstr /i \"Hyper-V\""
    echo ""
    echo "  3. To enable Hyper-V (if not auto-enabled):"
    echo "     Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
}

# Print usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -v, --version VERSION    Windows version (default: 11)"
    echo "                           Options: 11, 10, 2022, 2019, etc."
    echo "  -r, --ram SIZE           RAM size (default: 8G)"
    echo "  -c, --cores NUM          CPU cores (default: 4)"
    echo "  -d, --disk SIZE          Disk size (default: 64G)"
    echo "  -p, --password PASS      Windows password (default: Anonymous263)"
    echo "  -s, --storage PATH       Storage path (default: ./storage)"
    echo "  --vnc-port PORT          noVNC port (default: 8006)"
    echo "  --rdp-port PORT          RDP port (default: 3389)"
    echo "  --debug                  Enable debug mode"
    echo "  --check-only             Only check prerequisites, don't start"
    echo "  -h, --help               Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use defaults"
    echo "  $0 -v 10 -r 16G -c 8                 # Windows 10 with 16GB RAM"
    echo "  $0 --check-only                       # Just verify environment"
    echo ""
}

# Parse command line arguments
CHECK_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            WINDOWS_VERSION="$2"
            shift 2
            ;;
        -r|--ram)
            RAM_SIZE="$2"
            shift 2
            ;;
        -c|--cores)
            CPU_CORES="$2"
            shift 2
            ;;
        -d|--disk)
            DISK_SIZE="$2"
            shift 2
            ;;
        -p|--password)
            WIN_PASSWORD="$2"
            shift 2
            ;;
        -s|--storage)
            STORAGE_PATH="$2"
            shift 2
            ;;
        --vnc-port)
            VNC_PORT="$2"
            shift 2
            ;;
        --rdp-port)
            RDP_PORT="$2"
            shift 2
            ;;
        --debug)
            DEBUG="Y"
            shift
            ;;
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    banner
    
    log_info "Configuration:"
    log_info "  Windows Version: $WINDOWS_VERSION"
    log_info "  RAM: $RAM_SIZE"
    log_info "  CPU Cores: $CPU_CORES"
    log_info "  Disk: $DISK_SIZE"
    log_info "  Storage: $STORAGE_PATH"
    log_info "  VNC Port: $VNC_PORT"
    log_info "  RDP Port: $RDP_PORT"
    echo ""
    
    # Run checks
    local checks_passed=true
    
    if ! check_kvm; then
        checks_passed=false
    fi
    
    check_nested
    check_cpu_features
    
    if ! check_container_runtime; then
        checks_passed=false
    fi
    
    if [ "$CHECK_ONLY" = true ]; then
        echo ""
        if [ "$checks_passed" = true ]; then
            log_info "All critical checks passed! Ready to run."
        else
            log_error "Some checks failed. Please fix the issues above."
        fi
        exit 0
    fi
    
    if [ "$checks_passed" = false ]; then
        log_error "Critical checks failed. Cannot continue."
        exit 1
    fi
    
    # Setup and start
    if ! setup_storage; then
        exit 1
    fi
    
    if ! generate_compose; then
        exit 1
    fi
    
    if ! start_container; then
        exit 1
    fi
    
    print_connection_info
}

main "$@"
