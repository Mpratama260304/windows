# Windows in Docker with Nested Virtualization

<p align="center">
  <strong>Run Windows inside Docker with full nested virtualization support</strong><br/>
  <em>Enables Android Emulator, Hyper-V, Docker Desktop, and WSL2 inside the Windows VM</em>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#deployment-guides">Deployment Guides</a> •
  <a href="#android-emulator">Android Emulator</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

## Features

- ✅ **Nested Virtualization** - VMX/SVM passthrough to Windows guest
- ✅ **Hyper-V Support** - Run Hyper-V VMs inside the Windows guest
- ✅ **Android Emulator** - Full WHPX/Hyper-V backend support
- ✅ **noVNC Web Access** - Browser-based VNC on port 8006
- ✅ **RDP Access** - Native Remote Desktop on port 3389
- ✅ **Auto-Install** - Unattended Windows installation
- ✅ **KVM Acceleration** - Hardware-accelerated virtualization
- ✅ **Multiple Windows Versions** - Windows 10, 11, Server 2019/2022

## Requirements

| Component | Requirement |
|-----------|-------------|
| CPU | Intel VT-x or AMD-V with nested virtualization |
| KVM | `/dev/kvm` must be available |
| RAM | Minimum 8GB recommended |
| Storage | 64GB+ for Windows + applications |
| Docker/Podman | Container runtime with privileged support |

## Quick Start

### Using Docker Compose (Recommended)

```yaml
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "11"
      VMX: "Y"              # Enable nested virtualization
      HV: "Y"               # Enable Hyper-V enlightenments
      RAM_SIZE: "8G"
      CPU_CORES: "4"
      DISK_SIZE: "64G"
      PASSWORD: "Anonymous263"
    devices:
      - /dev/kvm
      - /dev/net/tun
    cap_add:
      - NET_ADMIN
    ports:
      - 8006:8006           # noVNC web access
      - 3389:3389/tcp       # RDP
      - 3389:3389/udp
    volumes:
      - ./windows:/storage
    restart: always
    stop_grace_period: 2m
    security_opt:
      - seccomp:unconfined
```

Start with:
```bash
docker compose up -d
```

### Using the Helper Script

```bash
# Clone the repository
git clone https://github.com/Mpratama260304/windows.git
cd windows

# Run with defaults
./run.sh

# Or customize
./run.sh --version 10 --ram 16G --cores 8 --password MyPassword123
```

### Using Docker CLI

```bash
docker run -d \
  --name windows \
  -e VERSION="11" \
  -e VMX="Y" \
  -e HV="Y" \
  -e RAM_SIZE="8G" \
  -e CPU_CORES="4" \
  -e PASSWORD="Anonymous263" \
  -p 8006:8006 \
  -p 3389:3389/tcp \
  -p 3389:3389/udp \
  --device=/dev/kvm \
  --device=/dev/net/tun \
  --cap-add NET_ADMIN \
  --security-opt seccomp=unconfined \
  -v "${PWD}/windows:/storage" \
  --stop-timeout 120 \
  dockurr/windows
```

## Connection Details

| Access Method | URL/Address | Credentials |
|---------------|-------------|-------------|
| noVNC Web | http://localhost:8006/vnc.html | No auth required |
| RDP | localhost:3389 | Admin / Anonymous263 |

## Deployment Guides

### GitHub Codespaces

GitHub Codespaces provides `/dev/kvm` with nested virtualization enabled by default.

1. Create a new Codespace from this repository
2. Start the container:
   ```bash
   docker compose up -d
   ```
3. Use the forwarded port 8006 for noVNC access
4. For RDP, forward port 3389 in VS Code ports panel

**Note**: Codespaces have KVM available but may have limited CPU/RAM. Use at least a 4-core machine type.

### Linux Host with Docker

#### 1. Verify KVM is available:
```bash
ls -la /dev/kvm
# Should show: crw-rw---- 1 root kvm ...
```

#### 2. Enable nested virtualization (if not already enabled):

**Intel CPUs:**
```bash
# Check current status
cat /sys/module/kvm_intel/parameters/nested
# Y or 1 means enabled

# Enable if needed
echo 'options kvm_intel nested=1' | sudo tee /etc/modprobe.d/kvm.conf
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel
```

**AMD CPUs:**
```bash
# Check current status
cat /sys/module/kvm_amd/parameters/nested
# 1 means enabled

# Enable if needed
echo 'options kvm_amd nested=1' | sudo tee /etc/modprobe.d/kvm.conf
sudo modprobe -r kvm_amd
sudo modprobe kvm_amd
```

#### 3. Start the container:
```bash
docker compose up -d
```

### DigitalOcean GPU Droplet

DigitalOcean GPU droplets run on bare metal and support nested virtualization.

1. Create a GPU droplet with Ubuntu 22.04+
2. Install Docker:
   ```bash
   curl -fsSL https://get.docker.com | sh
   ```
3. Verify KVM:
   ```bash
   ls -la /dev/kvm
   ```
4. Clone and start:
   ```bash
   git clone https://github.com/Mpratama260304/windows.git
   cd windows
   docker compose up -d
   ```

### Kubernetes

```bash
kubectl apply -f kubernetes.yml
```

**Important**: The Kubernetes nodes must have:
- `/dev/kvm` available
- Nested virtualization enabled
- Privileged pods allowed

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `VERSION` | `11` | Windows version (11, 10, 2022, 2019, etc.) |
| `VMX` | `Y` | Enable VMX/SVM passthrough (nested virt) |
| `HV` | `Y` | Enable Hyper-V enlightenments |
| `RAM_SIZE` | `4G` | Guest RAM allocation |
| `CPU_CORES` | `2` | Guest CPU cores |
| `DISK_SIZE` | `64G` | Virtual disk size |
| `USERNAME` | `Docker` | Windows username |
| `PASSWORD` | (empty) | Windows password |
| `DEBUG` | `N` | Enable debug logging |

## Verifying Nested Virtualization

After Windows boots, verify that virtualization is enabled:

### Method 1: Task Manager
1. Open Task Manager (Ctrl+Shift+Esc)
2. Go to Performance → CPU
3. Look for **"Virtualization: Enabled"**

### Method 2: PowerShell
```powershell
# Check if Hyper-V is available
systeminfo | findstr /i "Hyper-V"

# Should show:
# Hyper-V Requirements:      A hypervisor has been detected...
```

### Method 3: Check CPU Features
```powershell
Get-ComputerInfo | Select-Object HyperVRequirementVMMonitorModeExtensions
# Should return: True
```

## Android Emulator Setup

Once nested virtualization is verified, you can run Android Emulator:

### Option 1: Android Studio Emulator

1. Download Android Studio from https://developer.android.com/studio
2. Install and launch Android Studio
3. Go to Tools → SDK Manager → SDK Tools
4. Install "Android Emulator" and "Intel x86 Emulator Accelerator (HAXM)"
5. Create AVD using AVD Manager
6. The emulator will automatically use WHPX/Hyper-V backend

### Option 2: Standalone Emulator (Command Line)

```powershell
# Download command-line tools
Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-9477386_latest.zip" -OutFile cmdline-tools.zip

# Extract and setup
Expand-Archive cmdline-tools.zip -DestinationPath C:\Android
cd C:\Android\cmdline-tools\bin

# Accept licenses and install components
.\sdkmanager.bat --licenses
.\sdkmanager.bat "platform-tools" "emulator" "system-images;android-33;google_apis;x86_64"

# Create and start emulator
.\avdmanager.bat create avd -n test -k "system-images;android-33;google_apis;x86_64"
C:\Android\emulator\emulator.exe -avd test
```

### Enable Hyper-V Features (if not auto-enabled)

If Hyper-V wasn't automatically enabled during installation:

```powershell
# Run as Administrator
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -NoRestart
Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart

# Reboot required
Restart-Computer
```

## QEMU Configuration Details

The container uses the following QEMU configuration for nested virtualization:

```
QEMU CPU Configuration:
  -cpu host,kvm=on,+hypervisor,migratable=no,hv_passthrough

Key CPU Flags:
  • host           - Pass through host CPU features
  • kvm=on         - Enable KVM acceleration
  • +hypervisor    - Expose hypervisor to guest
  • hv_passthrough - Enable all Hyper-V enlightenments

Hyper-V Enlightenments (via hv_passthrough):
  • hv_relaxed     - Relaxed timing
  • hv_vapic       - Virtual APIC
  • hv_spinlocks   - Paravirtualized spinlocks
  • hv_time        - Reference time counter
  • hv_vpindex     - Virtual processor index
  • hv_synic       - Synthetic interrupt controller
  • hv_stimer      - Synthetic timers
  • hv_tlbflush    - TLB flush hypercalls
  • hv_ipi         - IPI hypercalls

Machine Type: q35 (modern PCIe chipset)
Boot: UEFI (OVMF)
```

## Troubleshooting

### "Virtualization: Disabled" in Task Manager

1. **Check host nested virtualization:**
   ```bash
   # Intel
   cat /sys/module/kvm_intel/parameters/nested
   # AMD
   cat /sys/module/kvm_amd/parameters/nested
   ```
   Must show `Y` or `1`.

2. **Verify VMX=Y is set:**
   ```bash
   docker inspect windows | grep VMX
   ```

3. **Check QEMU logs:**
   ```bash
   docker logs windows 2>&1 | grep -i "cpu\|vmx\|kvm"
   ```

### Container starts but Windows doesn't boot

1. **Check KVM access:**
   ```bash
   ls -la /dev/kvm
   # If permission denied, run: sudo chmod 666 /dev/kvm
   ```

2. **View QEMU output:**
   ```bash
   docker logs -f windows
   ```

3. **Check for sufficient resources:**
   - Ensure host has enough free RAM
   - Check disk space for virtual disk

### RDP connection refused

1. **Wait for Windows to fully boot** (can take 5-10 minutes on first install)
2. **Check firewall isn't blocking:**
   ```bash
   docker exec windows netstat -tlnp | grep 3389
   ```
3. **Try noVNC first** at http://localhost:8006/vnc.html

### Slow performance

1. **Verify KVM is being used:**
   ```bash
   docker logs windows 2>&1 | grep -i "kvm\|tcg"
   # Should mention KVM, not TCG
   ```

2. **Increase resources:**
   ```yaml
   environment:
     RAM_SIZE: "16G"
     CPU_CORES: "8"
   ```

### Android Emulator crashes

1. **Verify nested virt in Windows:**
   ```powershell
   systeminfo | findstr /i "Hyper-V"
   ```

2. **Use x86_64 system images** (not ARM)

3. **Allocate sufficient RAM** to both the Windows VM and Android emulator

## Logs and Debugging

### Container logs:
```bash
docker logs -f windows
```

### QEMU logs (inside container):
```bash
docker exec windows cat /run/shm/qemu.log
```

### Enable debug mode:
```yaml
environment:
  DEBUG: "Y"
```

## Acceptance Tests

### Test A: Nested Virtualization on KVM Host

- [ ] Windows boots successfully
- [ ] noVNC accessible at http://localhost:8006/vnc.html
- [ ] RDP connects to localhost:3389
- [ ] Task Manager shows "Virtualization: Enabled"
- [ ] `systeminfo` shows Hyper-V requirements met

### Test B: Fallback to TCG (no KVM)

- [ ] Container starts with warning about TCG
- [ ] Windows boots (slowly)
- [ ] noVNC and RDP work
- [ ] Nested virtualization NOT available (expected)

### Test C: Android Emulator

- [ ] After reboot, Hyper-V features active
- [ ] Android Studio emulator starts
- [ ] Emulator uses WHPX/Hyper-V backend
- [ ] Android system boots in emulator

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test changes with both KVM and TCG modes
4. Submit a pull request

## License

See [license.md](license.md) for details.

## Acknowledgments

- Based on [dockur/windows](https://github.com/dockur/windows)
- Uses [qemux/qemu](https://github.com/qemus/qemu) base image
