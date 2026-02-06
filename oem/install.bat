@echo off
REM ═══════════════════════════════════════════════════════════════════════════════
REM install.bat - Auto-executed during first Windows boot
REM ═══════════════════════════════════════════════════════════════════════════════
REM This script runs automatically during Windows OOBE to:
REM 1. Copy verification scripts to an accessible location
REM 2. Create desktop shortcuts for common tasks
REM 3. Display setup status
REM ═══════════════════════════════════════════════════════════════════════════════

echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo  Windows Nested Virtualization Setup
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

REM Create tools directory
if not exist "C:\Tools" mkdir "C:\Tools"

REM Copy verification script
if exist "C:\OEM\verify-virtualization.ps1" (
    copy "C:\OEM\verify-virtualization.ps1" "C:\Tools\" >nul
    echo [OK] Copied verification script to C:\Tools\
)

REM Create desktop shortcut for verification script
echo Set oWS = WScript.CreateObject("WScript.Shell") > "%TEMP%\shortcut.vbs"
echo sLinkFile = "%USERPROFILE%\Desktop\Verify Virtualization.lnk" >> "%TEMP%\shortcut.vbs"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%TEMP%\shortcut.vbs"
echo oLink.TargetPath = "powershell.exe" >> "%TEMP%\shortcut.vbs"
echo oLink.Arguments = "-ExecutionPolicy Bypass -File C:\Tools\verify-virtualization.ps1 -Verbose" >> "%TEMP%\shortcut.vbs"
echo oLink.Description = "Verify nested virtualization is enabled" >> "%TEMP%\shortcut.vbs"
echo oLink.Save >> "%TEMP%\shortcut.vbs"
cscript //nologo "%TEMP%\shortcut.vbs"
del "%TEMP%\shortcut.vbs"
echo [OK] Created desktop shortcut: Verify Virtualization

echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo  Setup Complete!
echo ═══════════════════════════════════════════════════════════════════════════════
echo.
echo  After Windows finishes setting up:
echo.
echo  1. REBOOT is required to activate Hyper-V features
echo     (Features are being installed during first boot)
echo.  
echo  2. After reboot, double-click "Verify Virtualization" on Desktop
echo     to confirm everything is working
echo.
echo  3. You can then install:
echo     - Android Studio with emulator
echo     - Docker Desktop
echo     - WSL2
echo.
echo ═══════════════════════════════════════════════════════════════════════════════
echo.

REM Keep window open briefly so user can read
timeout /t 10 /nobreak >nul

exit /b 0
