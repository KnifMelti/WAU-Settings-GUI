# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WAU Settings GUI is a portable standalone Windows application that provides a user-friendly interface to configure Winget-AutoUpdate (WAU). The project combines PowerShell 5.1, WPF XAML, and AutoHotkey v2 to create an elevated administrator tool.

**Key dependency**: [Romanitho/Winget-AutoUpdate](https://github.com/Romanitho/Winget-AutoUpdate) - The GUI prompts to install WAU if not present.

## Architecture

### Core Components

- **WAU-Settings-GUI.ahk** - AutoHotkey v2 wrapper that creates the elevated executable
- **WAU-Settings-GUI.ps1** - Main PowerShell script containing all UI logic and WAU integration
- **config/settings-window.xaml** - Primary WPF window definition
- **config/settings-popup.xaml** - Modal popup window
- **modules/config.psm1** - Global configuration variables (colors, paths, registry keys)
- **config_user.psm1** - User-configurable overrides for colors and update schedules
- **SandboxTest.ps1** - Windows Sandbox testing functionality

### Registry Architecture

WAU uses a two-layer registry system with precedence:

1. **Local settings**: `HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate`
2. **GPO policies**: `HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate` (takes precedence)

Always read effective values using `Get-DisplayValue` which respects GPO > local precedence. When GPO-managed, most controls are disabled except shortcuts.

### Configuration Patterns

```powershell
# Read effective value (respects GPO precedence)
$val = Get-DisplayValue -PropertyName "WAU_ListPath" -Config $updatedConfig -Policies $updatedPolicies

# Write settings atomically (only changed keys)
Set-WAUConfig -Settings @{ WAU_StartMenuShortcut = 1 }

# Validate paths before saving
if (-not (Test-PathValue -path $controls.ListPathTextBox.Text)) { return }
```

### Mods Path Semantics

The GUI writes `WAU_ModsPath` to registry, which maps to MSI property `MODSPATH`. Accepts:
- Local paths
- UNC paths
- HTTP/HTTPS URLs
- Literal `AzureBlob` (requires SAS URL field)

Always validate with `Test-PathValue`.

### UI Threading

Keep UI responsive during long operations:

```powershell
$window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background,[Action]{
    $controls.StatusBarText.Text = "Saving..."
})
Start-PopUp "Saving WAU Settings..."
# ... long operation ...
Close-PopUp
```

## Build and Run

### Prerequisites

- PowerShell 5.1+
- AutoHotkey v2 with Ahk2Exe compiler
- Windows 10 SDK (for code signing)
- Administrator privileges (required for all operations)

### Running for Development

From `Sources/WAU Settings GUI/`:

```powershell
.\WAU-Settings-GUI.ps1              # Normal mode
.\WAU-Settings-GUI.ps1 -Verbose     # Debug mode
.\WAU-Settings-GUI.ps1 -Portable    # No shortcuts/registry artifacts
.\WAU-Settings-GUI.ps1 -SandboxTest # Windows Sandbox test mode
```

### Building the EXE

Use VS Code task "Compile and Sign WAU Settings GUI" (Ctrl+Shift+B) or:

```powershell
.\compile_and_sign.ps1 -InputFile .\WAU-Settings-GUI.ahk
```

The build process:
1. Compiles `.ahk` to `.exe` using Ahk2Exe
2. Signs the executable via `sign_exe.ps1`
3. The AHK file contains embedded version info via directives

## Dev Tools (F12 / Click Logo)

The Dev Tools panel provides quick access to system resources:

- `[manifests/issues/errors]` - WinGet package repository links
- `[gpo]` - Open WAU policies in registry (if GPO managed)
- `[tsk]` - Task Scheduler (WAU subfolder)
- `[reg]` - Open WAU settings path in registry
- `[uid]` - GUID path exploration (MSI installation)
- `[sys]` - WinGet system-wide app list
- `[mod]` - WAU mods folder (for pre/post-install scripts)
- `[lst]` - Current list
- `[usr]` - Change colors/update schedule
- `[msi]` - MSI transform creation with current config
- `[wsb]` - Windows Sandbox test (requires Pro/Enterprise/Education)
- `[cfg]` - Configuration backup/import (share settings)
- `[wau]` - Reinstall WAU with current config
- `[ver]` - Manual update check (auto-checks weekly)
- `[src]` - Direct access to install directory

## Installation Modes

### Portable WinGet Package
```bash
winget install KnifMelti.WAU-Settings-GUI
```
Installs to: `%USERPROFILE%\AppData\Local\Microsoft\WinGet\Packages\KnifMelti.WAU-Settings-GUI_Microsoft.Winget.Source_8wekyb3d8bbwe`

Command alias: `WAU-Settings-GUI`

### Manual Installation
Download and run [WAU-Settings-GUI.exe](https://github.com/KnifMelti/WAU-Settings-GUI/releases/latest)
- Auto-detects USB drive (runs as portable)
- Prompts for install directory selection

## Updates

Built-in updater: Checks weekly (configurable via `[usr]` button in Dev Tools)
- Creates backup in `ver\backup\` before updating
- Handles file locks gracefully
- Self-relaunch mechanism avoids recursion: `Start-Process $newExePath -ArgumentList "/FROMPS" -Verb RunAs`

WAU can also update the GUI. To avoid file locks, create a preinstall script in WAU mods folder:
```powershell
# [ModsPath]\KnifMelti.WAU-Settings-GUI-preinstall.ps1
Get-Process powershell | Where-Object {$_.MainWindowTitle -like "WAU Settings*"} | Stop-Process -Force
```

Or exclude from WAU updates via `excluded_apps.txt`:
```
KnifMelti.WAU-Settings-GUI
```

## Windows Sandbox Testing

The `[wsb]` Dev Tool creates a clean Windows Sandbox environment for testing WAU installations:
- Generates `test.wsb` configuration
- Copies install/uninstall scripts
- Maps current **WAU** version folder to `WAU-install` on sandbox desktop folder
- Switches MSI from silent (`/qn`) to basic UI (`/qb`)
- First run creates a **SandboxTest** shortcut in User Start Menu for advanced testing when Windows Sandbox is installed

Three predefined scripts are saved to `wsb/` folder on first use when Windows Sandbox is installed:
- **InstallWSB.ps1** - Recognizes files created from `[msi]` button
- **WinGetManifest.ps1** - Recognizes WinGet manifest files
- **Explorer.ps1** - General script to open mapped folder

## Key Functions

- `Get-DisplayValue` - Read effective config value (respects GPO precedence)
- `Set-WAUConfig` - Write settings to registry atomically
- `Test-PathValue` - Validate local/UNC/HTTP paths
- `Set-ControlsState` - Bulk enable/disable controls (with exclusion patterns)
- `Start-PopUp` / `Close-PopUp` - Modal progress indicators
- `SandboxTest` - Launch Windows Sandbox with WinGet configured

## GPO Mode Behavior

When WAU is GPO-managed, disable most controls except shortcuts:

```powershell
Set-ControlsState -parentControl $window -enabled:$false -excludePattern "*Shortcut*"
```

After path changes in GPO mode, regenerate shortcuts to match registry state.

## Important Notes

- Must always run as Administrator (exe and shortcut has UAC flag set)
- `SandboxTest` standalone shortcut doesn't require Administrator privilegies 
- Executable is code-signed with KnifMelti Certificate
- XAML files use string interpolation from `modules/config.psm1` variables
- Comments should be in English
- PowerShell 5.1 compatible code required (no PowerShell 7 features)