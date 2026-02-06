#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# selftest.sh - Self-Test Script for Windows Nested Virtualization Container
# ═══════════════════════════════════════════════════════════════════════════════
# This script performs automated validation tests to ensure the container is
# properly configured for nested virtualization.
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#
# Usage: ./scripts/selftest.sh
# ═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════${NC}"
}

test_pass() {
    echo -e "  ${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

test_fail() {
    echo -e "  ${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

test_warn() {
    echo -e "  ${YELLOW}⚠ WARN${NC}: $1"
    ((TESTS_WARNED++))
}

test_skip() {
    echo -e "  ${YELLOW}○ SKIP${NC}: $1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Test Suite
# ═══════════════════════════════════════════════════════════════════════════════

print_header "SELFTEST: Windows Nested Virtualization"

echo ""
echo "Running automated tests..."
echo ""

# ---------------------------------------------------------------------------
# Test 1: CPU Virtualization Support
# ---------------------------------------------------------------------------
echo "Test 1: CPU Virtualization Support"

virt_ext=$(egrep -m1 -o 'vmx|svm' /proc/cpuinfo 2>/dev/null || echo "")

if [[ "$virt_ext" == "vmx" ]]; then
    test_pass "Intel VT-x (VMX) detected"
    CPU_VENDOR="intel"
elif [[ "$virt_ext" == "svm" ]]; then
    test_pass "AMD-V (SVM) detected"
    CPU_VENDOR="amd"
else
    test_fail "No hardware virtualization (VMX/SVM) detected in /proc/cpuinfo"
    CPU_VENDOR=""
fi

# ---------------------------------------------------------------------------
# Test 2: KVM Device Availability
# ---------------------------------------------------------------------------
echo ""
echo "Test 2: KVM Availability"

if [[ -e /dev/kvm ]]; then
    test_pass "/dev/kvm exists"
    
    if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
        test_pass "/dev/kvm is readable and writable"
    else
        test_fail "/dev/kvm exists but is not accessible"
    fi
else
    test_fail "/dev/kvm does not exist - run container with --device=/dev/kvm"
fi

# ---------------------------------------------------------------------------
# Test 3: QEMU Process (if running)
# ---------------------------------------------------------------------------
echo ""
echo "Test 3: QEMU Configuration"

qemu_cmd=$(ps aux 2>/dev/null | grep -v grep | grep "qemu-system-x86_64" | head -1 || echo "")

if [[ -n "$qemu_cmd" ]]; then
    test_pass "QEMU process is running"
    
    # Test for -enable-kvm
    if echo "$qemu_cmd" | grep -q "\-enable-kvm"; then
        test_pass "QEMU using -enable-kvm"
    else
        test_fail "QEMU NOT using -enable-kvm (virtualization will be slow)"
    fi
    
    # Test for CPU host passthrough
    if echo "$qemu_cmd" | grep -qE "\-cpu\s*host"; then
        test_pass "QEMU using host CPU passthrough"
    else
        test_warn "QEMU not using -cpu host"
    fi
    
    # Test for VMX/SVM passthrough (critical for nested virt)
    if [[ "$CPU_VENDOR" == "intel" ]]; then
        if echo "$qemu_cmd" | grep -q "+vmx"; then
            test_pass "VMX passthrough enabled (+vmx)"
        else
            test_fail "VMX passthrough NOT enabled - nested virt won't work"
        fi
    elif [[ "$CPU_VENDOR" == "amd" ]]; then
        if echo "$qemu_cmd" | grep -q "+svm"; then
            test_pass "SVM passthrough enabled (+svm)"
        else
            test_fail "SVM passthrough NOT enabled - nested virt won't work"
        fi
    else
        test_skip "Cannot verify VMX/SVM - unknown CPU vendor"
    fi
    
    # Test for Hyper-V enlightenments
    if echo "$qemu_cmd" | grep -qE "hv_relaxed|hv_vapic|hv_time|hv_passthrough"; then
        test_pass "Hyper-V enlightenments enabled"
    else
        test_warn "Hyper-V enlightenments not detected (may affect performance)"
    fi
    
else
    test_skip "QEMU not running - configuration tests skipped"
fi

# ---------------------------------------------------------------------------
# Test 4: noVNC Availability
# ---------------------------------------------------------------------------
echo ""
echo "Test 4: noVNC Web Interface"

novnc_port="${NOVNC_PORT:-8006}"

if ss -lntp 2>/dev/null | grep -q ":${novnc_port}"; then
    test_pass "noVNC port ${novnc_port} is listening"
    
    # Try HTTP request
    http_response=$(curl -sI "http://127.0.0.1:${novnc_port}/vnc.html" 2>/dev/null | head -1 || echo "")
    
    if echo "$http_response" | grep -q "200"; then
        test_pass "noVNC HTTP endpoint returns 200 OK"
    else
        test_warn "noVNC HTTP endpoint not responding (may need time to start)"
    fi
else
    test_skip "noVNC port ${novnc_port} not listening (may need time to start)"
fi

# ---------------------------------------------------------------------------
# Test 5: VNC Server
# ---------------------------------------------------------------------------
echo ""
echo "Test 5: VNC Server"

vnc_port="${VNC_PORT:-5900}"

if ss -lntp 2>/dev/null | grep -q ":${vnc_port}"; then
    test_pass "VNC server port ${vnc_port} is listening"
else
    test_skip "VNC port ${vnc_port} not listening (may need QEMU to start)"
fi

# ---------------------------------------------------------------------------
# Test 6: Storage/Disk
# ---------------------------------------------------------------------------
echo ""
echo "Test 6: Storage Configuration"

storage_dir="${STORAGE:-/storage}"

if [[ -d "$storage_dir" ]]; then
    test_pass "Storage directory exists: $storage_dir"
    
    if [[ -w "$storage_dir" ]]; then
        test_pass "Storage directory is writable"
    else
        test_fail "Storage directory is not writable"
    fi
else
    test_warn "Storage directory does not exist: $storage_dir"
fi

# ---------------------------------------------------------------------------
# Test 7: OVMF/UEFI Files
# ---------------------------------------------------------------------------
echo ""
echo "Test 7: UEFI Firmware"

# Look for OVMF CODE
ovmf_code=""
for path in /usr/share/OVMF /usr/share/ovmf /usr/share/edk2/ovmf /usr/share/qemu; do
    if [[ -f "${path}/OVMF_CODE.fd" ]]; then
        ovmf_code="${path}/OVMF_CODE.fd"
        break
    fi
done

if [[ -n "$ovmf_code" ]]; then
    test_pass "OVMF_CODE found: $ovmf_code"
else
    test_warn "OVMF_CODE.fd not found in standard locations"
fi

# Look for OVMF VARS template
ovmf_vars=""
for path in /usr/share/OVMF /usr/share/ovmf /usr/share/edk2/ovmf /usr/share/qemu; do
    if [[ -f "${path}/OVMF_VARS.fd" ]]; then
        ovmf_vars="${path}/OVMF_VARS.fd"
        break
    fi
done

if [[ -n "$ovmf_vars" ]]; then
    test_pass "OVMF_VARS template found: $ovmf_vars"
else
    test_warn "OVMF_VARS.fd not found in standard locations"
fi

# ---------------------------------------------------------------------------
# Test 8: Environment Variables
# ---------------------------------------------------------------------------
echo ""
echo "Test 8: Environment Configuration"

# Check VMX setting
if [[ "${VMX:-Y}" == [Yy1]* ]]; then
    test_pass "VMX passthrough enabled (VMX=${VMX:-Y})"
else
    test_warn "VMX passthrough disabled (VMX=${VMX:-N})"
fi

# Check HV setting
if [[ "${HV:-Y}" == [Yy1]* ]]; then
    test_pass "Hyper-V enlightenments enabled (HV=${HV:-Y})"
else
    test_warn "Hyper-V enlightenments disabled (HV=${HV:-N})"
fi

# Check FORCE_TCG
if [[ "${FORCE_TCG:-N}" == [Yy1]* ]]; then
    test_fail "FORCE_TCG is enabled - nested virtualization will NOT work!"
else
    test_pass "FORCE_TCG is not set (KVM will be used if available)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Results Summary
# ═══════════════════════════════════════════════════════════════════════════════

print_header "TEST RESULTS"

echo ""
echo -e "  ${GREEN}Passed${NC}:  $TESTS_PASSED"
echo -e "  ${RED}Failed${NC}:  $TESTS_FAILED"
echo -e "  ${YELLOW}Warned${NC}:  $TESTS_WARNED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "  ${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${GREEN} ✓ ALL CRITICAL TESTS PASSED${NC}"
    echo -e "  ${GREEN}═══════════════════════════════════════════════════════════════════════${NC}"
    
    if [[ $TESTS_WARNED -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}Note: Some warnings were generated. Review them above.${NC}"
    fi
    
    echo ""
    echo "  Nested virtualization should work properly."
    echo "  Windows Task Manager should show 'Virtualization: Enabled'"
    echo ""
    
    exit 0
else
    echo -e "  ${RED}═══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${RED} ✗ SOME TESTS FAILED${NC}"
    echo -e "  ${RED}═══════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Please fix the failed tests above before expecting nested"
    echo "  virtualization to work inside Windows."
    echo ""
    
    exit 1
fi
