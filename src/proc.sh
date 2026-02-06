#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# proc.sh - CPU/Processor Configuration for Nested Virtualization
# ═══════════════════════════════════════════════════════════════════════════════
# This script configures QEMU CPU settings to enable nested virtualization
# inside the Windows guest, allowing:
# - Hyper-V to run nested VMs
# - Android Emulator with WHPX/Hyper-V backend
# - Docker Desktop with Hyper-V backend
# - WSL2 with virtualization features
#
# IMPORTANT: This script MUST override the base image's CPU configuration
# to enable VMX/SVM passthrough for nested virtualization!
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

# Environment variable defaults
: "${VMX:="Y"}"           # Enable VMX/SVM passthrough (nested virtualization)
: "${HV:="Y"}"            # Enable Hyper-V enlightenments
: "${FORCE_TCG:="N"}"     # Force TCG mode (disable KVM)
: "${HV_VENDOR_ID:=""}"   # Custom Hyper-V vendor ID
: "${CPU_CORES:="2"}"     # Number of CPU cores
: "${CPU_MODEL:=""}"      # Custom CPU model (empty = auto)
: "${SMP:=""}"            # Custom SMP configuration

# ═══════════════════════════════════════════════════════════════════════════════
# KVM Detection and Validation
# ═══════════════════════════════════════════════════════════════════════════════

check_kvm() {
    local kvm_available=false
    local kvm_writable=false
    
    # Check if /dev/kvm exists
    if [[ -e /dev/kvm ]]; then
        kvm_available=true
        
        # Check read/write permissions
        if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
            kvm_writable=true
        fi
    fi
    
    # Force TCG mode if requested
    if [[ "${FORCE_TCG}" == [Yy1]* ]]; then
        warn "FORCE_TCG=Y: Forcing TCG mode (software emulation)"
        warn "╔═══════════════════════════════════════════════════════════════════════╗"
        warn "║  WARNING: Nested virtualization will NOT work inside Windows!         ║"
        warn "║  Task Manager will show 'Virtualization: Not Enabled'                 ║"
        warn "║  Android Emulator/Hyper-V will NOT function properly.                 ║"
        warn "╚═══════════════════════════════════════════════════════════════════════╝"
        return 1
    fi
    
    # KVM not available
    if [[ "$kvm_available" != true ]]; then
        error "╔═══════════════════════════════════════════════════════════════════════╗"
        error "║  CRITICAL: /dev/kvm NOT FOUND!                                        ║"
        error "╠═══════════════════════════════════════════════════════════════════════╣"
        error "║  KVM is required for hardware acceleration and nested virtualization. ║"
        error "║  Without KVM, virtualization inside Windows will NOT work.            ║"
        error "╠═══════════════════════════════════════════════════════════════════════╣"
        error "║  Possible solutions:                                                  ║"
        error "║  1. Enable virtualization in BIOS/UEFI (VT-x/AMD-V)                   ║"
        error "║  2. Load KVM modules: modprobe kvm kvm_intel (or kvm_amd)             ║"
        error "║  3. Add --device=/dev/kvm to docker run                               ║"
        error "║  4. If running in a VM, enable nested virtualization on host          ║"
        error "╚═══════════════════════════════════════════════════════════════════════╝"
        warn "Falling back to TCG (software emulation)..."
        return 1
    fi
    
    # KVM available but not accessible
    if [[ "$kvm_writable" != true ]]; then
        error "╔═══════════════════════════════════════════════════════════════════════╗"
        error "║  WARNING: /dev/kvm exists but is not readable/writable!               ║"
        error "╠═══════════════════════════════════════════════════════════════════════╣"
        error "║  Current permissions: $(ls -l /dev/kvm 2>/dev/null | awk '{print $1, $3, $4}')"
        error "╠═══════════════════════════════════════════════════════════════════════╣"
        error "║  Fix options:                                                         ║"
        error "║  1. Run container with --privileged                                   ║"
        error "║  2. chmod 666 /dev/kvm on host                                        ║"
        error "║  3. Add user to 'kvm' group: usermod -aG kvm \$USER                   ║"
        error "╚═══════════════════════════════════════════════════════════════════════╝"
        warn "Falling back to TCG (software emulation)..."
        return 1
    fi
    
    # Log KVM info
    info "KVM available: /dev/kvm ($(ls -l /dev/kvm 2>/dev/null | awk '{print $1}'))"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# CPU Feature Detection
# ═══════════════════════════════════════════════════════════════════════════════

detect_cpu_vendor() {
    local vendor=""
    local flags=""
    
    if [[ -f /proc/cpuinfo ]]; then
        vendor=$(grep -m1 "vendor_id" /proc/cpuinfo | cut -d: -f2 | tr -d ' ' || echo "")
        flags=$(grep -m1 "^flags" /proc/cpuinfo | cut -d: -f2 || echo "")
    fi
    
    if echo "$flags" | grep -qw "vmx"; then
        echo "intel"
    elif echo "$flags" | grep -qw "svm"; then
        echo "amd"
    elif [[ "$vendor" == "GenuineIntel" ]]; then
        echo "intel"
    elif [[ "$vendor" == "AuthenticAMD" ]]; then
        echo "amd"
    else
        echo "unknown"
    fi
}

check_nested_support() {
    local vendor="$1"
    local nested_param=""
    local nested_status=""
    
    case "$vendor" in
        "intel")
            nested_param="/sys/module/kvm_intel/parameters/nested"
            ;;
        "amd")
            nested_param="/sys/module/kvm_amd/parameters/nested"
            ;;
        *)
            return 0
            ;;
    esac
    
    if [[ -f "$nested_param" ]]; then
        nested_status=$(cat "$nested_param" 2>/dev/null || echo "N")
        if [[ "$nested_status" == "Y" || "$nested_status" == "1" ]]; then
            info "Host nested virtualization: ENABLED"
            return 0
        else
            warn "Host nested virtualization appears DISABLED"
            warn "Windows may show 'Virtualization: Disabled' in Task Manager"
            return 0
        fi
    fi
    
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Build QEMU CPU Arguments (CRITICAL: This builds the FULL CPU string)
# ═══════════════════════════════════════════════════════════════════════════════

build_cpu_args() {
    local kvm_enabled="$1"
    local vendor="$2"
    local cpu_args=""
    
    if [[ "$kvm_enabled" == true ]]; then
        # ═══════════════════════════════════════════════════════════════════════
        # KVM Mode: Full hardware acceleration with nested virtualization
        # ═══════════════════════════════════════════════════════════════════════
        
        # Start with host CPU passthrough for maximum compatibility
        cpu_args="host"
        
        # Enable KVM acceleration
        cpu_args+=",kvm=on"
        
        # Add L3 cache for performance
        cpu_args+=",l3-cache=on"
        
        # ─────────────────────────────────────────────────────────────────────
        # VMX/SVM Passthrough - CRITICAL for nested virtualization
        # NOTE: We explicitly use + to ENABLE, never use - which disables
        # ─────────────────────────────────────────────────────────────────────
        if [[ "${VMX}" == [Yy1]* ]]; then
            case "$vendor" in
                "intel")
                    # ENABLE VMX for Intel (use + not -)
                    cpu_args+=",+vmx"
                    info "╔══════════════════════════════════════════════════════════════╗"
                    info "║  VMX (Intel VT-x) passthrough ENABLED                        ║"
                    info "║  Windows should detect 'Virtualization: Enabled'             ║"
                    info "╚══════════════════════════════════════════════════════════════╝"
                    ;;
                "amd")
                    # ENABLE SVM for AMD (use + not -)
                    cpu_args+=",+svm"
                    info "╔══════════════════════════════════════════════════════════════╗"
                    info "║  SVM (AMD-V) passthrough ENABLED                             ║"
                    info "║  Windows should detect 'Virtualization: Enabled'             ║"
                    info "╚══════════════════════════════════════════════════════════════╝"
                    ;;
                *)
                    # Try both for unknown vendors
                    warn "Unknown CPU vendor, detecting virtualization extension..."
                    if grep -qw "vmx" /proc/cpuinfo 2>/dev/null; then
                        cpu_args+=",+vmx"
                        info "Detected and enabled VMX"
                    elif grep -qw "svm" /proc/cpuinfo 2>/dev/null; then
                        cpu_args+=",+svm"
                        info "Detected and enabled SVM"
                    fi
                    ;;
            esac
        else
            warn "VMX=N: VMX/SVM passthrough DISABLED - nested virtualization won't work!"
        fi
        
        # ─────────────────────────────────────────────────────────────────────
        # Hyper-V Enlightenments - Improves Windows guest performance
        # ─────────────────────────────────────────────────────────────────────
        if [[ "${HV}" == [Yy1]* ]]; then
            # Core Hyper-V enlightenments
            cpu_args+=",hv_relaxed=on"      # Relaxed timing (reduces VM exits)
            cpu_args+=",hv_vapic=on"        # Virtual APIC
            cpu_args+=",hv_time=on"         # Reference time counter
            cpu_args+=",hv_spinlocks=0x1fff" # Spinlock optimizations
            
            # Additional enlightenments for better performance
            cpu_args+=",hv_vpindex=on"      # Virtual processor index
            cpu_args+=",hv_runtime=on"      # Runtime MSR
            cpu_args+=",hv_synic=on"        # Synthetic interrupt controller
            cpu_args+=",hv_stimer=on"       # Synthetic timers
            cpu_args+=",hv_reset=on"        # Reset MSR
            cpu_args+=",hv_frequencies=on"  # Frequency MSRs
            cpu_args+=",hv_reenlightenment=on" # Re-enlightenment notifications
            cpu_args+=",hv_tlbflush=on"     # TLB flush optimization
            cpu_args+=",hv_ipi=on"          # IPI optimization
            
            # hv_passthrough exposes all available Hyper-V features
            # This is key for Hyper-V nested virtualization
            cpu_args+=",hv_passthrough=on"
            
            info "Hyper-V enlightenments ENABLED"
        fi
        
        # ─────────────────────────────────────────────────────────────────────
        # Custom Hyper-V vendor ID (for compatibility with picky software)
        # ─────────────────────────────────────────────────────────────────────
        if [[ -n "${HV_VENDOR_ID}" ]]; then
            cpu_args+=",hv_vendor_id=${HV_VENDOR_ID}"
            info "Custom Hyper-V vendor ID: ${HV_VENDOR_ID}"
        fi
        
        # Disable migration for stability (nested virt doesn't migrate well)
        cpu_args+=",migratable=no"
        
        # Add TSC (timestamp counter) support
        cpu_args+=",+invtsc"
        
    else
        # ═══════════════════════════════════════════════════════════════════════
        # TCG Mode: Software emulation (no nested virtualization support)
        # ═══════════════════════════════════════════════════════════════════════
        
        if [[ -n "${CPU_MODEL}" ]]; then
            cpu_args="${CPU_MODEL}"
        else
            # Use max CPU model for best compatibility in TCG mode
            cpu_args="max"
        fi
        
        warn "Running in TCG mode - nested virtualization will NOT work!"
    fi
    
    echo "$cpu_args"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Build SMP (Symmetric Multi-Processing) Arguments
# ═══════════════════════════════════════════════════════════════════════════════

build_smp_args() {
    local cores="${CPU_CORES:-2}"
    local smp_args=""
    
    if [[ -n "${SMP}" ]]; then
        # Use custom SMP configuration if provided
        smp_args="${SMP}"
    else
        # Default: cores with 1 thread per core, 1 socket
        smp_args="${cores},sockets=1,cores=${cores},threads=1"
    fi
    
    echo "$smp_args"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Configuration
# ═══════════════════════════════════════════════════════════════════════════════

# Detect CPU vendor
CPU_VENDOR=$(detect_cpu_vendor)
info "Detected CPU vendor: ${CPU_VENDOR:-unknown}"

# Check KVM availability
KVM_ENABLED=false
if check_kvm; then
    KVM_ENABLED=true
fi

# Check nested virtualization support on host
check_nested_support "$CPU_VENDOR"

# Build CPU arguments - this is the FULL CPU string
CPU_ARGS=$(build_cpu_args "$KVM_ENABLED" "$CPU_VENDOR")

# Build SMP arguments  
SMP_ARGS=$(build_smp_args)

# ═══════════════════════════════════════════════════════════════════════════════
# CRITICAL: Override or append to QEMU Arguments
# The base image may have already set some CPU args, we need to REPLACE them
# ═══════════════════════════════════════════════════════════════════════════════

# Remove any existing -cpu argument from ARGS (from base image)
ARGS=$(echo "$ARGS" | sed -E 's/-cpu [^-]+-cpu /-cpu /g' | sed -E 's/-cpu [^ ]+//g')

# Remove any existing -smp argument from ARGS
ARGS=$(echo "$ARGS" | sed -E 's/-smp [^ ]+//g')

# Remove any existing -enable-kvm or -machine arguments
ARGS=$(echo "$ARGS" | sed -E 's/-enable-kvm//g')
ARGS=$(echo "$ARGS" | sed -E 's/-machine [^ ]+//g')

if [[ "$KVM_ENABLED" == true ]]; then
    # KVM acceleration
    ARGS+=" -enable-kvm"
    ARGS+=" -machine q35,accel=kvm,kernel_irqchip=on"
else
    # TCG (software) emulation
    ARGS+=" -machine q35,accel=tcg"
fi

# CPU configuration (this is the critical part for nested virt)
ARGS+=" -cpu ${CPU_ARGS}"

# SMP configuration
ARGS+=" -smp ${SMP_ARGS}"

# Log final configuration
info "═══════════════════════════════════════════════════════════════════════"
info "QEMU CPU CONFIGURATION (NESTED VIRTUALIZATION)"
info "═══════════════════════════════════════════════════════════════════════"
info "CPU: ${CPU_ARGS}"
info "SMP: ${SMP_ARGS}"
if [[ "$KVM_ENABLED" == true ]]; then
    info "Acceleration: KVM (hardware)"
    if [[ "${VMX}" == [Yy1]* ]]; then
        if [[ "$CPU_VENDOR" == "intel" ]]; then
            info "VMX passthrough: ENABLED (+vmx)"
        elif [[ "$CPU_VENDOR" == "amd" ]]; then
            info "SVM passthrough: ENABLED (+svm)"
        fi
    fi
else
    warn "Acceleration: TCG (software) - SLOW, no nested virt!"
fi
info "═══════════════════════════════════════════════════════════════════════"

return 0
