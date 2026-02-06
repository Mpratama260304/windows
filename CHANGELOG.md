# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added - Nested Virtualization Support

This release adds comprehensive nested virtualization support, allowing Windows to detect virtualization as enabled and run nested VMs (Hyper-V, Android Emulator, Docker Desktop with Hyper-V backend).

#### Core QEMU Configuration (`src/proc.sh`)
- **KVM Detection**: `check_kvm()` function validates `/dev/kvm` availability and permissions
- **CPU Vendor Detection**: Automatic detection of Intel (VMX) or AMD (SVM) CPUs
- **VMX/SVM Passthrough**: Enables `+vmx` or `+svm` based on host CPU for nested virtualization
- **Hyper-V Enlightenments**: Full set of Hyper-V optimizations for better performance:
  - `hv_relaxed`, `hv_vapic`, `hv_time`, `hv_spinlocks`
  - `hv_vpindex`, `hv_runtime`, `hv_synic`, `hv_stimer`
  - `hv_reset`, `hv_frequencies`, `hv_reenlightenment`
  - `hv_tlbflush`, `hv_ipi`, `hv_passthrough`
- **Fallback to TCG**: Graceful degradation with clear warnings when KVM unavailable
- **Environment Variables**:
  - `VMX=Y|N` - Enable/disable VMX/SVM passthrough (default: Y)
  - `HV=Y|N` - Enable/disable Hyper-V enlightenments (default: Y)
  - `FORCE_TCG=Y|N` - Force software emulation (default: N)
  - `HV_VENDOR_ID` - Custom Hyper-V vendor ID for compatibility

#### UEFI/Boot Configuration (`src/boot.sh`)
- **OVMF Auto-discovery**: Searches multiple paths for OVMF_CODE.fd and OVMF_VARS.fd
- **VARS Template Copy**: Automatically copies OVMF_VARS to writable storage location
- **Idempotent**: Reuses existing OVMF_VARS if available
- **Secure Boot Support**: Optional secure boot configuration via `SECURE_BOOT=Y`

#### Display Configuration (`src/display.sh`)
- **Multiple VGA Modes**: `std`, `qxl`, `virtio-vga`, `cirrus` via `DISPLAY_MODE`
- **Robust noVNC**: PID file management for idempotent restarts
- **Port Conflict Resolution**: Automatic cleanup of stale websockify processes
- **Health Check**: Endpoint verification for noVNC availability

#### Network Configuration (`src/network.sh`)
- **RDP Port Forwarding**: Primary (3389) and alternate (13389) ports
- **User Mode Networking**: Default SLIRP with full port forwarding
- **SMB/Samba Integration**: File sharing ports forwarded
- **Custom Port Forwarding**: `HOST_PORTS=8080:80,9090:443` format
- **Bridge Mode**: Optional bridge networking for advanced setups

#### Memory Configuration (`src/memory.sh`)
- **Flexible Sizing**: Support for G, M, K suffixes
- **Memory Validation**: Warnings when requesting >80% of available RAM
- **Balloon Device**: Optional memory ballooning for dynamic allocation

#### Disk Configuration (`src/disk.sh`)
- **Auto-creation**: Creates qcow2 disk on first boot
- **Existing Disk Detection**: Reuses existing disk images
- **Configurable**: Format, cache, discard options

#### Windows Auto-Configuration (Autounattend.xml)
- **RDP Pre-enabled**: TerminalServices enabled with NLA disabled for testing
- **Firewall Rules**: Remote Desktop firewall group enabled
- **Hyper-V Features**: Automatic installation on first login:
  - Microsoft-Hyper-V-All
  - HypervisorPlatform (WHPX for Android)
  - VirtualMachinePlatform
  - Containers
- **Hypervisor Scheduler**: Configured for nested virt compatibility

#### Diagnostic Tools
- **`scripts/diagnose.sh`**: Comprehensive diagnostic output:
  - CPU virtualization features (VMX/SVM)
  - KVM status and permissions
  - QEMU process analysis
  - Network port status
  - noVNC health check
  - Storage verification
  - Environment dump

- **`scripts/selftest.sh`**: Automated validation with exit codes:
  - Pass/Fail test suite
  - KVM availability tests
  - QEMU configuration validation
  - Service availability checks

#### Windows Verification Tools
- **`oem/verify-virtualization.ps1`**: PowerShell script for Windows guest:
  - CPU capability detection
  - Windows features status
  - Hypervisor verification
  - `--EnableAll` flag to enable all features
  
- **`oem/install.bat`**: First-boot setup script:
  - Copies verification tools
  - Creates desktop shortcuts
  - Displays setup instructions

#### Documentation
- Updated `README-NESTED.md` with:
  - Quick start guide
  - Environment variable reference
  - Deployment guides (Codespaces, Linux, DigitalOcean, Kubernetes)
  - Troubleshooting section
  - Android Emulator setup guide

#### Docker/Container Changes
- **Dockerfile**: Added default `VMX=Y` and `HV=Y` environment variables
- **compose.yml**: Updated with nested virtualization configuration
- **run.sh**: Enhanced launcher script with KVM checks and compose generation

### Technical Details

#### Critical QEMU Arguments for Nested Virtualization

```
# Machine configuration
-enable-kvm
-machine q35,accel=kvm,kernel_irqchip=on

# CPU configuration (Intel example)
-cpu host,kvm=on,+vmx,hv_relaxed=on,hv_vapic=on,hv_time=on,hv_spinlocks=0x1fff,hv_vpindex=on,hv_runtime=on,hv_synic=on,hv_stimer=on,hv_reset=on,hv_frequencies=on,hv_reenlightenment=on,hv_tlbflush=on,hv_ipi=on,hv_passthrough=on,migratable=no

# For AMD, replace +vmx with +svm
```

#### Verification Commands

From Linux host:
```bash
# Check QEMU is using KVM with VMX/SVM
ps aux | grep qemu-system-x86_64 | grep -E '\-enable-kvm.*\+(vmx|svm)'

# Run diagnostic
./scripts/diagnose.sh

# Run selftest
./scripts/selftest.sh
```

From Windows guest:
```powershell
# Check Task Manager → Performance → CPU → "Virtualization: Enabled"

# PowerShell check
Get-ComputerInfo | Select HyperVRequirement*

# Run verification script
C:\Tools\verify-virtualization.ps1, -Verbose
```

### Requirements

| Requirement | Details |
|-------------|---------|
| Host CPU | Intel VT-x (VMX) or AMD-V (SVM) |
| Host Nested Virt | `kvm_intel nested=1` or `kvm_amd nested=1` |
| Container Access | `--device=/dev/kvm --security-opt seccomp=unconfined` |
| Minimum RAM | 8GB recommended for Windows + Hyper-V |

### Known Limitations

1. **Intel Mac**: Not supported (no nested VMX in Hypervisor.framework)
2. **ARM64 Hosts**: Windows ARM64 needed, nested virt varies by platform
3. **Some VPS**: Nested virtualization may be disabled by provider
4. **TCG Fallback**: If KVM unavailable, virtualization inside Windows won't work

### Migration Notes

If upgrading from previous versions:
1. No changes needed to existing storage/disk images
2. New environment variables default to enabling nested virt
3. Run `./scripts/selftest.sh` to verify configuration
