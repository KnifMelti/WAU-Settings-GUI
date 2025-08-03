# Copilot Instructions for WAU Settings GUI

## Project Overview
**WAU Settings GUI** is a portable Windows application that provides a user-friendly interface for configuring [Winget-AutoUpdate (WAU)](https://github.com/Romanitho/Winget-AutoUpdate). It's built using **PowerShell 5.1** with **WPF (XAML)** UI and **AutoHotkey v2** for the executable wrapper.

## Architecture Components

### Core Structure
- **`WAU-Settings-GUI.ps1`** (4800+ lines) - Main PowerShell script with all business logic
- **`WAU-Settings-GUI.ahk`** - AutoHotkey v2 wrapper that compiles to `.exe` and launches PowerShell
- **`config/settings-window.xaml`** - WPF window definition with all UI controls
- **`config/settings-popup.xaml`** - WPF popup window for status messages and operations
- **`modules/config.psm1`** - Global configuration constants (registry paths, colors, etc.)
- **`config_user.psm1`** - User-customizable settings (colors, update schedule)

### Key Integration Points

#### Registry Management
- **WAU Settings:** `HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate`
- **GPO Policies:** `HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate`
- Configuration changes are written directly to registry and trigger WAU scheduled task updates

#### Dual-Mode Operation
1. **Normal Mode:** Full configuration access
2. **GPO Mode:** Only shortcut settings modifiable when Group Policy is active
   - Detected via `$Script:WAU_POLICIES_PATH` registry existence
   - UI automatically disables non-shortcut controls

#### Portable vs Installed Modes
- **Portable:** `-Portable` parameter, no desktop shortcuts created
- **Installed:** Creates desktop shortcut, manages Start Menu shortcuts
- Detection: USB/CD drive type or WinGet package path patterns

## Critical Development Patterns

### Code Standards
- **All code comments must be in English** - Ensure consistency across the codebase
- **All chat messages must be in Swedish, but code snippets must be in English**
- Use descriptive variable names and clear function documentation
- Follow PowerShell best practices for error handling and parameter validation

### Configuration Management
```powershell
# Always use Get-DisplayValue for configuration reads - handles GPO precedence
$value = Get-DisplayValue -PropertyName "WAU_ListPath" -Config $config -Policies $policies

# Configuration saves use Set-WAUConfig function
$settings = @{ WAU_StartMenuShortcut = 1 }
Set-WAUConfig -Settings $settings
```

### UI State Management
- **Status Updates:** Use `$controls.StatusBarText` for user feedback
- **Popup Management:** `Start-PopUp "message"` / `Close-PopUp` for operations
- **Control States:** `Set-ControlsState` for bulk enable/disable
- **Color Coding:** `$Script:COLOR_ENABLED`, `COLOR_DISABLED`, `COLOR_ACTIVE`, `COLOR_INACTIVE`

### Dev Tools Integration (F12)
Buttons format: `[xxx]` for registry/tool access
- `[gpo]` - GPO registry path
- `[reg]` - WAU settings registry
- `[uid]` - GUID-based paths (MSI installs)
- `[msi]` - MSI transform creation
- `[cfg]` - Configuration backup/import

## Build & Deployment

### AutoHotkey Compilation
```ahk2
;@Ahk2Exe-Set FileVersion, 1.8.2.6
;@Ahk2Exe-SetMainIcon ..\assets\WAU Settings GUI.ico
;@Ahk2Exe-UpdateManifest 1  ; Enables "Run as Administrator"
```

### Version Management
- Version defined in AHK header AND PowerShell script
- Auto-update checks GitHub releases weekly via `$Script:WAU_GUI_REPO`
- Backup mechanism: `ver\backup` folder for rollbacks

### Deployment Patterns
- **GitHub Releases:** ZIP with portable files
- **WinGet Package:** Installs to user scope with `PortableCommandAlias`
- **MSI Transforms:** Generated for enterprise deployment via Dev Tools

## Testing & Debugging

### Key Test Scenarios
1. **WAU Installation States:** Not installed, installed via MSI, portable
2. **GPO vs Local Config:** Registry precedence handling
3. **Shortcut Management:** Start Menu, Desktop, App Installer combinations
4. **Path Validation:** ListPath, ModsPath - local/UNC/special values (GPO, AzureBlob)

### Debug Commands
```powershell
# Run with verbose output
.\WAU-Settings-GUI.ps1 -Verbose

# Portable mode testing
.\WAU-Settings-GUI.ps1 -Portable

# Check registry state
Get-ItemProperty -Path "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
```

## Common Gotchas

### File Locking
- AHK wrapper may lock PowerShell script during updates
- Use `Get-Process` checks before file operations
- `FromPS` parameter prevents infinite loops during updates

### Registry Synchronization
- Always sync actual shortcut existence with registry values
- GPO policies override local settings except shortcuts
- Schedule task updates required when interval settings change

### Path Handling
- Support local paths (`C:\folder`), UNC (`\\server\share`), HTTP/HTTPS URLs (`https://example.com`), and special values (`GPO`, `AzureBlob`)
- Validate paths before saving using `Test-PathValue`
- Install location changes require shortcut recreation

### UI Threading
- Use `Dispatcher.BeginInvoke` for async status updates
- `$Script:WAIT_TIME` (1000ms) for consistent UI timing
- Popup management prevents UI blocking during operations

When making changes, always test both GPO and non-GPO modes, verify shortcut creation/deletion, and ensure registry changes trigger appropriate WAU task updates.
