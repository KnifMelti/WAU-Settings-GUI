# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WAU Settings GUI is a portable standalone Windows application that provides a user-friendly interface to configure Winget-AutoUpdate (WAU). The project combines PowerShell 5.1, WPF XAML, and AutoHotkey v2 to create an elevated administrator tool.

**Key dependency**: [Romanitho/Winget-AutoUpdate](https://github.com/Romanitho/Winget-AutoUpdate) - The GUI prompts to install WAU if not present.

## Architecture

### Directory Structure

```
Sources/WAU Settings GUI/
├── WAU-Settings-GUI.ahk         # AHK v2 wrapper (creates elevated EXE)
├── WAU-Settings-GUI.ps1         # Main PowerShell script (~6,365 lines)
├── WAU-Settings-GUI.exe         # Compiled executable (signed)
├── SandboxTest.ps1              # Standalone Windows Sandbox testing
├── config_user.psm1             # User-configurable overrides
├── compile_and_sign.ps1         # Build script (excludes from release)
├── sign_exe.ps1                 # Code signing script (excludes from release)
├── config/
│   ├── settings-window.xaml    # Main WPF window definition
│   └── settings-popup.xaml     # Modal progress popup
└── modules/
    └── config.psm1              # Global config (colors, paths, registry keys)
```

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

### Pending WAU ProgramData Migration

**Status**: Planned by upstream (not yet implemented)

WAU maintainer (Romanitho) plans to migrate data files from Program Files to ProgramData following Windows best practices:

**Files being moved:**
- `logs/` folder
- `mods/` folder
- `config/` folder (except WAU-MSI_Actions.ps1)
- `excluded_apps.txt`
- `included_apps.txt`
- `icons/` folder (customization)

**Expected structure:**
- **Program Files**: WAU binaries (read-only) - `C:\Program Files\Winget-AutoUpdate\`
- **ProgramData**: Data files - `C:\ProgramData\Winget-AutoUpdate\`

**Current GUI implementation:**

All paths dynamically constructed using `InstallLocation` from registry:
```powershell
$logsPath = Join-Path $currentConfig.InstallLocation "logs"
$modsPath = Join-Path $currentConfig.InstallLocation "mods"
$configPath = Join-Path $currentConfig.InstallLocation "config"
$excludedFile = Join-Path $currentConfig.InstallLocation "excluded_apps.txt"
```

**Migration approach when WAU implements this:**

1. Add `WAU_DATA_PATH = "C:\ProgramData\Winget-AutoUpdate"` to [modules/config.psm1](Sources/WAU Settings GUI/modules/config.psm1)
2. Create helper function `Get-WAUDataPath` that returns data path with fallback to `InstallLocation` for backward compatibility
3. Replace approximately 35 path references from `Join-Path $InstallLocation` to `Join-Path (Get-WAUDataPath)`
4. Update shortcuts to point to new log locations

**Affected code locations in WAU-Settings-GUI.ps1:**
- Shortcut creation (logs shortcuts): lines 2412-2430
- Dev Tools buttons `[mod]`, `[lst]`, `[sys]`: lines 5227+
- Open Logs button: lines 5985+
- List file management: lines 4245+
- Status display: lines 4053+
- Config file access: lines 4069, 4247, 5195, 5378

**Documentation updates needed:**
- [WAU-Settings-GUI.ahk](Sources/WAU Settings GUI/WAU-Settings-GUI.ahk) line 34: Update comment path from `C:\Program Files\` to `C:\ProgramData\`

**Reference**: https://github.com/Romanitho/Winget-AutoUpdate/issues/1060

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

**IMPORTANT**: WAU-Settings-GUI.ps1 should NOT be run directly from PowerShell (except for `-SandboxTest`). The application must be launched via:
- The compiled `.exe` file
- Desktop/Start Menu shortcuts created during installation

**For development/testing only**:

From `Sources/WAU Settings GUI/`:

```powershell
.\WAU-Settings-GUI.ps1 -SandboxTest # Windows Sandbox test mode (standalone)
```

**Parameters**:
- `-SandboxTest` - Launches the Windows Sandbox testing interface directly (does not require the main GUI)

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

### Script Mapping System

Four predefined scripts are saved to `wsb/` folder on first use:
- **InstallWSB.ps1** - Recognizes files created from `[msi]` button
- **WinGetManifest.ps1** - Recognizes WinGet manifest files (`.yaml` manifests)
- **Installer.ps1** - Recognizes folders containing `install.*` files
- **Explorer.ps1** - General script to open mapped folder

Script selection is controlled by `wsb\script-mappings.txt` configuration file using pattern matching. Users can create custom scripts and mappings for specialized testing scenarios.

## Screenshot Functionality (F11)

Press **F11** to capture a window screenshot with automatic sensitive data masking:
- Masks notification email addresses
- Masks ModsPath URLs (except AzureBlob literal)
- Masks SAS URLs and tokens
- Copies to clipboard automatically
- Ideal for sharing configuration without exposing credentials
- Function: `New-WindowScreenshot` with `Hide-SensitiveText` helper

## Key Functions

### Configuration Management
- `Get-DisplayValue` - Read effective config value (respects GPO precedence)
- `Set-WAUConfig` - Write settings to registry atomically (only changed keys)
- `Get-WAUCurrentConfig` - Retrieve current WAU configuration from registry
- `Import-WAUSettingsFromFile` - Import configuration from backup files

### Validation and Testing
- `Test-PathValue` - Validate local/UNC/HTTP paths
- `Test-Administrator` - Verify running with admin privileges
- `Test-InstalledWAU` - Check if WAU is installed
- `Test-LocalMSIVersion` - Verify local MSI version matches expected

### WAU Operations
- `Install-WAU` - Install WAU with specified configuration
- `Uninstall-WAU` - Uninstall WAU and restore settings
- `Start-WAUManually` - Trigger WAU task execution
- `Update-WAUScheduledTask` - Update task scheduler configuration

### UI and Controls
- `Set-ControlsState` - Bulk enable/disable controls (with exclusion patterns)
- `Start-PopUp` / `Close-PopUp` - Modal progress indicators
- `New-WindowScreenshot` - Capture window with sensitive data masking (F11)
- `Hide-SensitiveText` - Mask sensitive information in screenshots

### Development Tools
- `New-MSITransformFromControls` - Generate MSI transform from current config
- `Start-WSBTesting` - Launch Windows Sandbox test environment
- `Get-WAUMsi` - Download WAU MSI installer
- `Repair-WAUSettingsFiles` - Auto-repair corrupted/missing files

## GPO Mode Behavior

When WAU is GPO-managed, disable most controls except shortcuts:

```powershell
Set-ControlsState -parentControl $window -enabled:$false -excludePattern "*Shortcut*"
```

After path changes in GPO mode, regenerate shortcuts to match registry state.

## Keyboard Shortcuts

- **F5** - Refresh status display (shows version details, last run times, configuration state)
- **F11** - Take screenshot with automatic masking of sensitive data
- **F12** - Toggle Dev Tools panel (also available by clicking logo)
- **Double-click logo** - Open WAU Settings GUI repository on GitHub

## Release Workflow

The project uses GitHub Actions for automated releases:

### Workflows
- **Release.yml** - Creates release ZIP from `Sources/WAU Settings GUI/` (excludes build scripts)
- **WinGet Releaser.yml** - Submits new versions to WinGet community repository
- **update-release-stats.yml** - Updates release download statistics

### Release Process
1. Create and publish a GitHub release with tag (e.g., `v1.2.3.4`)
2. Release workflow packages the source directory into a ZIP
3. WinGet Releaser automatically creates/updates the WinGet manifest
4. Users receive updates via built-in updater (weekly check) or WinGet

## Coding Conventions

### PowerShell Best Practices
- **Compatibility**: PowerShell 5.1 only (no PowerShell 7+ features like null coalescing)
- **Comments**: Always write comments in English
- **Error Handling**: Use try-catch blocks for external operations (file I/O, registry, network)
- **Scope**: Use `$Script:` prefix for module-level variables
- **Functions**: Use verb-noun naming convention (e.g., `Get-WAUConfig`, `Set-ControlsState`)

### UI Responsiveness
Always use dispatcher for UI updates during long operations:
```powershell
$window.Dispatcher.Invoke([Action]{ $controls.StatusBarText.Text = "Processing..." })
```

### Registry Operations
- Always check GPO precedence using `Get-DisplayValue`
- Write only changed values with `Set-WAUConfig`
- Use atomic operations to prevent partial updates

### Path Handling
- Validate all paths with `Test-PathValue` before saving
- Support local paths, UNC paths, and HTTP(S) URLs
- Use `Join-Path` for all path construction (prepare for ProgramData migration)

## Important Notes

- Must always run as Administrator (exe and shortcut has UAC flag set)
- `SandboxTest` standalone shortcut doesn't require Administrator privileges
- Executable is code-signed with KnifMelti Certificate
- XAML files use string interpolation from `modules/config.psm1` variables
- Comments should be in English
- PowerShell 5.1 compatible code required (no PowerShell 7 features)
- Main script is ~6,365 lines (as of latest version)
- Auto-repair functionality runs on startup if files are corrupted/missing

## Troubleshooting

### Common Issues
- **File locks during update**: Use WAU preinstall mod to close GUI before updating
- **Missing shortcuts**: Toggle shortcut options and save to regenerate
- **GPO mode limitations**: Most controls disabled except shortcuts (by design)
- **Sandbox requirements**: Requires Windows Pro/Enterprise/Education with virtualization enabled

### Development Tips
- Use `-Verbose` parameter to enable detailed logging
- Test GPO scenarios using registry policies path
- Use `[cfg]` Dev Tool to backup/restore configurations during testing
- Leverage `Repair-WAUSettingsFiles` for automatic file recovery