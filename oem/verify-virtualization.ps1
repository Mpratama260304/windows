# ═══════════════════════════════════════════════════════════════════════════════
# verify-virtualization.ps1
# ═══════════════════════════════════════════════════════════════════════════════
# This script verifies and enables nested virtualization features in Windows.
# Run as Administrator.
#
# Usage:
#   .\verify-virtualization.ps1              # Check status only
#   .\verify-virtualization.ps1 -EnableAll   # Enable all features
#   .\verify-virtualization.ps1 -Verbose     # Detailed output
# ═══════════════════════════════════════════════════════════════════════════════

param(
    [switch]$EnableAll,
    [switch]$Verbose
)

$ErrorActionPreference = "SilentlyContinue"

function Write-Header {
    param([string]$Text)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan  
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Write-Status {
    param(
        [string]$Name,
        [bool]$Enabled,
        [string]$Details = ""
    )
    
    $status = if ($Enabled) { "✓ ENABLED" } else { "✗ DISABLED" }
    $color = if ($Enabled) { "Green" } else { "Red" }
    
    Write-Host "  $Name : " -NoNewline
    Write-Host $status -ForegroundColor $color
    
    if ($Details -and $Verbose) {
        Write-Host "    $Details" -ForegroundColor Gray
    }
}

Write-Header "NESTED VIRTUALIZATION STATUS CHECK"

# ═══════════════════════════════════════════════════════════════════════════════
# Check 1: CPU Virtualization Support
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "CPU Information:" -ForegroundColor Yellow

$cpu = Get-WmiObject -Class Win32_Processor
Write-Host "  Name: $($cpu.Name)"
Write-Host "  Cores: $($cpu.NumberOfCores) | Threads: $($cpu.NumberOfLogicalProcessors)"

$computerInfo = Get-ComputerInfo -Property "HyperVRequirement*"

$vmSupported = $computerInfo.HyperVRequirementVMMonitorModeExtensions
Write-Status -Name "VM Monitor Extensions (VT-x/AMD-V)" -Enabled $vmSupported

$slat = $computerInfo.HyperVRequirementSecondLevelAddressTranslation
Write-Status -Name "Second Level Address Translation" -Enabled $slat

$virtualizationInFirmware = $computerInfo.HyperVRequirementVirtualizationFirmwareEnabled
Write-Status -Name "Virtualization Enabled in Firmware" -Enabled $virtualizationInFirmware

# ═══════════════════════════════════════════════════════════════════════════════
# Check 2: Windows Features
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "Windows Features:" -ForegroundColor Yellow

$features = @(
    @{Name = "Microsoft-Hyper-V-All"; Display = "Hyper-V (All Components)"},
    @{Name = "Microsoft-Hyper-V"; Display = "Hyper-V Platform"},
    @{Name = "Microsoft-Hyper-V-Tools-All"; Display = "Hyper-V Management Tools"},
    @{Name = "HypervisorPlatform"; Display = "Windows Hypervisor Platform"},
    @{Name = "VirtualMachinePlatform"; Display = "Virtual Machine Platform"},
    @{Name = "Containers"; Display = "Windows Containers"}
)

$needsReboot = $false

foreach ($feature in $features) {
    $state = Get-WindowsOptionalFeature -Online -FeatureName $feature.Name
    $enabled = $state.State -eq "Enabled"
    $pending = $state.RestartRequired
    
    if ($pending) {
        $needsReboot = $true
        Write-Status -Name $feature.Display -Enabled $false -Details "(Pending Reboot)"
    } else {
        Write-Status -Name $feature.Display -Enabled $enabled
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Check 3: Hypervisor Status
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "Hypervisor Status:" -ForegroundColor Yellow

$hypervisorPresent = $computerInfo.HyperVisorPresent
Write-Status -Name "Hypervisor Present" -Enabled $hypervisorPresent

$bcdedit = bcdedit /enum | Select-String "hypervisorlaunchtype"
$hypervisorLaunchType = if ($bcdedit) { $bcdedit.ToString().Split()[-1] } else { "Not Set" }
$hvEnabled = $hypervisorLaunchType -eq "auto" -or $hypervisorLaunchType -eq "Auto"
Write-Status -Name "Hypervisor Launch Type" -Enabled $hvEnabled -Details $hypervisorLaunchType

# ═══════════════════════════════════════════════════════════════════════════════
# Check 4: Services
# ═══════════════════════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "Virtualization Services:" -ForegroundColor Yellow

$services = @(
    @{Name = "vmms"; Display = "Hyper-V Virtual Machine Management"},
    @{Name = "vmcompute"; Display = "Hyper-V Host Compute Service"},
    @{Name = "hvhost"; Display = "HV Host Service"}
)

foreach ($svc in $services) {
    $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
    $running = $service -and $service.Status -eq "Running"
    $exists = $service -ne $null
    
    if (!$exists) {
        Write-Host "  $($svc.Display) : " -NoNewline
        Write-Host "NOT INSTALLED" -ForegroundColor Gray
    } else {
        Write-Status -Name $svc.Display -Enabled $running -Details $service.Status
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════

Write-Header "SUMMARY"

$readyForAndroid = $vmSupported -and $virtualizationInFirmware -and $hypervisorPresent

if ($readyForAndroid) {
    Write-Host ""
    Write-Host "  ✓ System is ready for Android Emulator!" -ForegroundColor Green
    Write-Host "    You can use WHPX/Hyper-V backend for acceleration." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  ✗ System is NOT ready for Android Emulator" -ForegroundColor Red
    
    if (!$vmSupported) {
        Write-Host "    - CPU virtualization extensions not detected" -ForegroundColor Red
    }
    if (!$virtualizationInFirmware) {
        Write-Host "    - Virtualization not enabled in BIOS/UEFI" -ForegroundColor Red
    }
    if (!$hypervisorPresent) {
        Write-Host "    - Hypervisor not running (enable Hyper-V and reboot)" -ForegroundColor Red
    }
}

if ($needsReboot) {
    Write-Host ""
    Write-Host "  ⚠ A REBOOT IS REQUIRED to complete feature installation!" -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# Enable Features (if requested)
# ═══════════════════════════════════════════════════════════════════════════════

if ($EnableAll) {
    Write-Header "ENABLING VIRTUALIZATION FEATURES"
    
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (!$isAdmin) {
        Write-Host "  ERROR: This script must be run as Administrator to enable features." -ForegroundColor Red
        exit 1
    }
    
    $featuresToEnable = @(
        "Microsoft-Hyper-V-All",
        "HypervisorPlatform", 
        "VirtualMachinePlatform",
        "Containers"
    )
    
    foreach ($featureName in $featuresToEnable) {
        Write-Host "  Enabling $featureName..." -NoNewline
        try {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart -ErrorAction Stop
            if ($result.RestartNeeded) {
                Write-Host " Done (Reboot Required)" -ForegroundColor Yellow
                $needsReboot = $true
            } else {
                Write-Host " Done" -ForegroundColor Green
            }
        } catch {
            Write-Host " Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Set hypervisor launch type
    Write-Host "  Setting hypervisor launch type to AUTO..." -NoNewline
    bcdedit /set hypervisorlaunchtype auto | Out-Null
    Write-Host " Done" -ForegroundColor Green
    
    # Set scheduler type for better nested virt
    Write-Host "  Setting hypervisor scheduler type..." -NoNewline
    bcdedit /set hypervisorschedulertype classic | Out-Null
    Write-Host " Done" -ForegroundColor Green
    
    if ($needsReboot) {
        Write-Host ""
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
        Write-Host "  REBOOT REQUIRED to complete installation!" -ForegroundColor Yellow
        Write-Host "  Run 'Restart-Computer' or restart from Start menu." -ForegroundColor Yellow
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    }
}

Write-Host ""
