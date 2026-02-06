#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# boot.sh - UEFI/BIOS Boot Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# Handles OVMF UEFI firmware setup for QEMU, including:
# - OVMF_CODE (read-only firmware)
# - OVMF_VARS (writable variable store, copied per-VM)
# ═══════════════════════════════════════════════════════════════════════════════
set -Eeuo pipefail

# Environment variable defaults
: "${BOOT_MODE:="windows"}"     # Boot mode: windows, windows_legacy, uefi, bios
: "${SECURE_BOOT:="N"}"         # Enable Secure Boot (requires OVMF_CODE.secboot.fd)
: "${STORAGE:="/storage"}"      # Storage directory for VM data

# OVMF paths - common locations
OVMF_PATHS=(
    "/usr/share/OVMF"
    "/usr/share/ovmf"
    "/usr/share/edk2/ovmf"
    "/usr/share/qemu"
    "/usr/share/edk2-ovmf"
    "/run/ovmf"
)

# ═══════════════════════════════════════════════════════════════════════════════
# Find OVMF Files
# ═══════════════════════════════════════════════════════════════════════════════

find_ovmf_code() {
    local secure="${1:-N}"
    local code_names=()
    
    if [[ "${secure}" == [Yy1]* ]]; then
        # Secure boot enabled - look for secure boot variant
        code_names=(
            "OVMF_CODE.secboot.fd"
            "OVMF_CODE_4M.secboot.fd"
            "OVMF_CODE.ms.fd"
            "edk2-x86_64-secure-code.fd"
        )
    else
        # Standard UEFI
        code_names=(
            "OVMF_CODE.fd"
            "OVMF_CODE_4M.fd"
            "OVMF_CODE.pure-efi.fd"
            "edk2-x86_64-code.fd"
            "OVMF-pure-efi.fd"
        )
    fi
    
    for path in "${OVMF_PATHS[@]}"; do
        for name in "${code_names[@]}"; do
            if [[ -f "${path}/${name}" ]]; then
                echo "${path}/${name}"
                return 0
            fi
        done
    done
    
    # Fallback: search the system
    local found
    found=$(find /usr/share -name "OVMF_CODE*.fd" -type f 2>/dev/null | head -n1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    
    return 1
}

find_ovmf_vars_template() {
    local secure="${1:-N}"
    local vars_names=()
    
    if [[ "${secure}" == [Yy1]* ]]; then
        vars_names=(
            "OVMF_VARS.secboot.fd"
            "OVMF_VARS_4M.ms.fd"
            "OVMF_VARS.ms.fd"
            "edk2-x86_64-secure-vars.fd"
        )
    else
        vars_names=(
            "OVMF_VARS.fd"
            "OVMF_VARS_4M.fd"
            "OVMF_VARS.pure-efi.fd"
            "edk2-x86_64-vars.fd"
        )
    fi
    
    for path in "${OVMF_PATHS[@]}"; do
        for name in "${vars_names[@]}"; do
            if [[ -f "${path}/${name}" ]]; then
                echo "${path}/${name}"
                return 0
            fi
        done
    done
    
    # Fallback: search the system
    local found
    found=$(find /usr/share -name "OVMF_VARS*.fd" -type f 2>/dev/null | head -n1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    
    return 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# Initialize OVMF VARS (Copy Template to Writable Location)
# ═══════════════════════════════════════════════════════════════════════════════

init_ovmf_vars() {
    local template="$1"
    local vars_path="${STORAGE}/OVMF_VARS.fd"
    
    # Create storage directory if needed
    mkdir -p "${STORAGE}" 2>/dev/null || true
    
    # Check if vars file already exists
    if [[ -f "${vars_path}" ]]; then
        # Verify it's not corrupted (should be non-zero size)
        local size
        size=$(stat -c%s "${vars_path}" 2>/dev/null || echo "0")
        if [[ "$size" -gt 0 ]]; then
            info "Using existing OVMF_VARS: ${vars_path}"
            echo "${vars_path}"
            return 0
        fi
        # Remove corrupted file
        rm -f "${vars_path}"
    fi
    
    # Copy template to writable location
    info "Copying OVMF_VARS template to ${vars_path}..."
    if ! cp "${template}" "${vars_path}"; then
        error "Failed to copy OVMF_VARS template!"
        return 1
    fi
    
    # Make it writable
    chmod 644 "${vars_path}" 2>/dev/null || true
    
    echo "${vars_path}"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Build UEFI Boot Arguments
# ═══════════════════════════════════════════════════════════════════════════════

build_uefi_args() {
    local code_path=""
    local vars_template=""
    local vars_path=""
    local boot_args=""
    
    # Find OVMF_CODE
    code_path=$(find_ovmf_code "${SECURE_BOOT}")
    if [[ -z "$code_path" ]] || [[ ! -f "$code_path" ]]; then
        error "OVMF_CODE not found! Please install OVMF package."
        error "  Ubuntu/Debian: apt install ovmf"
        error "  Fedora: dnf install edk2-ovmf"
        return 1
    fi
    info "OVMF_CODE: ${code_path}"
    
    # Find OVMF_VARS template
    vars_template=$(find_ovmf_vars_template "${SECURE_BOOT}")
    if [[ -z "$vars_template" ]] || [[ ! -f "$vars_template" ]]; then
        error "OVMF_VARS template not found! Please install OVMF package."
        return 1
    fi
    info "OVMF_VARS template: ${vars_template}"
    
    # Initialize OVMF_VARS (copy to writable location)
    vars_path=$(init_ovmf_vars "${vars_template}")
    if [[ -z "$vars_path" ]] || [[ ! -f "$vars_path" ]]; then
        error "Failed to initialize OVMF_VARS!"
        return 1
    fi
    
    # Build pflash arguments
    # CODE is read-only
    boot_args+="-drive if=pflash,format=raw,readonly=on,file=${code_path}"
    boot_args+=" -drive if=pflash,format=raw,file=${vars_path}"
    
    # Add global settings for UEFI
    boot_args+=" -global driver=cfi.pflash01,property=secure,value=on"
    
    echo "${boot_args}"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Build Legacy BIOS Boot Arguments
# ═══════════════════════════════════════════════════════════════════════════════

build_bios_args() {
    # For legacy BIOS boot, we just use SeaBIOS (default in QEMU)
    echo ""
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Configuration
# ═══════════════════════════════════════════════════════════════════════════════

BOOT_ARGS=""
BOOT_DESC=""

case "${BOOT_MODE,,}" in
    "windows" | "uefi" | "windows_secure")
        # Modern Windows - UEFI boot
        BOOT_ARGS=$(build_uefi_args)
        if [[ $? -ne 0 ]]; then
            error "Failed to configure UEFI boot!"
        else
            BOOT_DESC=" (UEFI)"
            info "Boot mode: UEFI"
        fi
        ;;
    "windows_legacy" | "bios" | "legacy")
        # Legacy boot - SeaBIOS
        BOOT_ARGS=$(build_bios_args)
        BOOT_DESC=" (Legacy BIOS)"
        info "Boot mode: Legacy BIOS"
        ;;
    *)
        # Default to UEFI for Windows
        BOOT_ARGS=$(build_uefi_args)
        if [[ $? -ne 0 ]]; then
            warn "Failed to configure UEFI boot, falling back to BIOS..."
            BOOT_ARGS=$(build_bios_args)
            BOOT_DESC=" (Legacy BIOS - fallback)"
        else
            BOOT_DESC=" (UEFI)"
        fi
        ;;
esac

# Add boot arguments to QEMU args
if [[ -n "${BOOT_ARGS}" ]]; then
    ARGS+=" ${BOOT_ARGS}"
fi

return 0
