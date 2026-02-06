#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# diagnose.sh - Diagnostic Script for Windows Nested Virtualization Container
# ═══════════════════════════════════════════════════════════════════════════════
# This script outputs diagnostic information to help troubleshoot issues with
# nested virtualization in the Windows container.
#
# Usage: ./scripts/diagnose.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
}

print_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# System Information
# ═══════════════════════════════════════════════════════════════════════════════

print_header "SYSTEM INFORMATION"

echo -e "  Hostname:        $(hostname)"
echo -e "  Kernel:          $(uname -r)"
echo -e "  OS:              $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || echo 'Unknown')"
echo -e "  Date:            $(date -Iseconds)"

# ═══════════════════════════════════════════════════════════════════════════════
# CPU Virtualization Features
# ═══════════════════════════════════════════════════════════════════════════════

print_header "CPU VIRTUALIZATION FEATURES"

# Check VMX/SVM support
virt_ext=$(egrep -m1 -o 'vmx|svm' /proc/cpuinfo 2>/dev/null || echo "none")
if [[ "$virt_ext" == "vmx" ]]; then
    print_ok "Intel VT-x (VMX) supported"
    cpu_vendor="intel"
elif [[ "$virt_ext" == "svm" ]]; then
    print_ok "AMD-V (SVM) supported"
    cpu_vendor="amd"
else
    print_error "No hardware virtualization support detected (vmx/svm)"
    cpu_vendor="unknown"
fi

# Check nested virtualization parameter
if [[ "$cpu_vendor" == "intel" ]]; then
    nested_param="/sys/module/kvm_intel/parameters/nested"
elif [[ "$cpu_vendor" == "amd" ]]; then
    nested_param="/sys/module/kvm_amd/parameters/nested"
else
    nested_param=""
fi

if [[ -n "$nested_param" ]] && [[ -f "$nested_param" ]]; then
    nested_val=$(cat "$nested_param" 2>/dev/null || echo "N")
    if [[ "$nested_val" == "Y" || "$nested_val" == "1" ]]; then
        print_ok "Nested virtualization ENABLED on host"
    else
        print_warn "Nested virtualization DISABLED on host (value: $nested_val)"
    fi
else
    print_info "Could not determine nested virtualization status"
fi

# Show CPU model and flags
echo ""
echo "  CPU Model:"
grep -m1 "model name" /proc/cpuinfo 2>/dev/null | sed 's/.*: /    /' || echo "    Unknown"

echo ""
echo "  Relevant CPU flags:"
cpu_flags=$(grep -m1 "^flags" /proc/cpuinfo 2>/dev/null | tr ' ' '\n' | grep -E 'vmx|svm|ept|npt|vpid|avx|hypervisor' | sort -u | tr '\n' ' ')
echo "    $cpu_flags"

# ═══════════════════════════════════════════════════════════════════════════════
# KVM Status
# ═══════════════════════════════════════════════════════════════════════════════

print_header "KVM STATUS"

# Check /dev/kvm
if [[ -e /dev/kvm ]]; then
    print_ok "/dev/kvm exists"
    ls -l /dev/kvm 2>/dev/null | sed 's/^/    /'
    
    if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
        print_ok "/dev/kvm is readable and writable"
    else
        print_error "/dev/kvm is not accessible"
    fi
else
    print_error "/dev/kvm does NOT exist"
    print_info "Make sure to run container with: --device=/dev/kvm"
fi

# Check KVM modules
echo ""
echo "  KVM modules loaded:"
lsmod 2>/dev/null | grep -E '^kvm' | sed 's/^/    /' || echo "    None found"

# ═══════════════════════════════════════════════════════════════════════════════
# QEMU Process Status
# ═══════════════════════════════════════════════════════════════════════════════

print_header "QEMU PROCESS STATUS"

qemu_procs=$(ps aux 2>/dev/null | grep -v grep | grep "qemu-system-x86_64" || echo "")

if [[ -n "$qemu_procs" ]]; then
    print_ok "QEMU process is running"
    echo ""
    echo "  Full command line:"
    ps aux | grep -v grep | grep "qemu-system-x86_64" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | tr ' ' '\n' | grep -v '^$' | head -50 | sed 's/^/    /'
    
    echo ""
    echo "  Key parameters check:"
    
    # Check for KVM acceleration
    if echo "$qemu_procs" | grep -q "\-enable-kvm"; then
        print_ok "Using KVM acceleration (-enable-kvm)"
    else
        print_error "NOT using KVM acceleration"
    fi
    
    # Check for CPU host passthrough
    if echo "$qemu_procs" | grep -qE "\-cpu\s+host"; then
        print_ok "Using host CPU passthrough (-cpu host)"
    else
        print_warn "Not using host CPU passthrough"
    fi
    
    # Check for VMX/SVM
    if echo "$qemu_procs" | grep -qE "\+vmx|\+svm"; then
        print_ok "VMX/SVM passthrough enabled (+vmx or +svm)"
    else
        print_error "VMX/SVM passthrough NOT enabled"
    fi
    
    # Check Hyper-V enlightenments
    if echo "$qemu_procs" | grep -q "hv_"; then
        print_ok "Hyper-V enlightenments enabled"
    else
        print_warn "Hyper-V enlightenments not detected"
    fi
    
else
    print_info "QEMU process is not running"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Network Ports
# ═══════════════════════════════════════════════════════════════════════════════

print_header "NETWORK PORTS"

echo "  Listening ports (relevant):"
ss -lntp 2>/dev/null | egrep ':8006|:3389|:5900|:13389' | sed 's/^/    /' || echo "    None found"

echo ""

# Check noVNC
if ss -lntp 2>/dev/null | grep -q ':8006'; then
    print_ok "noVNC port 8006 is listening"
else
    print_warn "noVNC port 8006 is not listening"
fi

# Check RDP
if ss -lntp 2>/dev/null | grep -q ':3389'; then
    print_ok "RDP port 3389 is listening"
else
    print_info "RDP port 3389 is not listening (may be forwarded by QEMU)"
fi

# Check VNC
if ss -lntp 2>/dev/null | grep -q ':5900'; then
    print_ok "VNC port 5900 is listening"
else
    print_info "VNC port 5900 is not listening"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# noVNC Health Check
# ═══════════════════════════════════════════════════════════════════════════════

print_header "NOVNC HEALTH CHECK"

novnc_response=$(curl -sI "http://127.0.0.1:8006/vnc.html" 2>/dev/null | head -1 || echo "")

if echo "$novnc_response" | grep -q "200"; then
    print_ok "noVNC HTTP endpoint responding (HTTP 200)"
else
    print_warn "noVNC HTTP endpoint not responding"
    print_info "Response: $novnc_response"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Storage/Disk Check
# ═══════════════════════════════════════════════════════════════════════════════

print_header "STORAGE CHECK"

storage_dir="${STORAGE:-/storage}"

if [[ -d "$storage_dir" ]]; then
    print_ok "Storage directory exists: $storage_dir"
    
    echo ""
    echo "  Storage contents:"
    ls -lah "$storage_dir" 2>/dev/null | head -20 | sed 's/^/    /'
    
    echo ""
    echo "  Disk usage:"
    df -h "$storage_dir" 2>/dev/null | sed 's/^/    /'
else
    print_error "Storage directory does not exist: $storage_dir"
fi

# Check OVMF vars
ovmf_vars="${storage_dir}/OVMF_VARS.fd"
if [[ -f "$ovmf_vars" ]]; then
    print_ok "OVMF_VARS file exists"
else
    print_info "OVMF_VARS file not found (will be created on first boot)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Environment Variables
# ═══════════════════════════════════════════════════════════════════════════════

print_header "RELEVANT ENVIRONMENT VARIABLES"

env_vars="VMX HV FORCE_TCG CPU_CORES RAM_SIZE DISK_SIZE DISPLAY_MODE VNC_PORT NOVNC_PORT RDP_PORT VERSION DEBUG"

for var in $env_vars; do
    val="${!var:-<not set>}"
    echo "  $var = $val"
done

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

print_header "DIAGNOSTIC SUMMARY"

errors=0
warnings=0

# Count issues
[[ "$virt_ext" == "none" ]] && ((errors++))
[[ ! -e /dev/kvm ]] && ((errors++))
[[ -e /dev/kvm ]] && { [[ ! -r /dev/kvm ]] || [[ ! -w /dev/kvm ]]; } && ((errors++))

if [[ -n "$qemu_procs" ]]; then
    echo "$qemu_procs" | grep -q "\-enable-kvm" || ((errors++))
    echo "$qemu_procs" | grep -qE "\+vmx|\+svm" || ((errors++))
fi

if [[ $errors -eq 0 ]]; then
    echo -e "  ${GREEN}✓ No critical issues detected${NC}"
else
    echo -e "  ${RED}✗ $errors critical issue(s) detected${NC}"
fi

echo ""
echo "  For nested virtualization to work inside Windows:"
echo "    1. Host must support VMX/SVM (checked above)"
echo "    2. KVM must be available and accessible"
echo "    3. QEMU must run with -enable-kvm and +vmx/+svm"
echo "    4. Windows must have Hyper-V features enabled"
echo ""

exit 0
