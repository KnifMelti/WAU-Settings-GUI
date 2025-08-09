## Copilot instructions for WAU Settings GUI

Purpose: Help AI agents ship correct changes fast in this PowerShell + WPF + AutoHotkey repo by following our concrete patterns and workflows only.

### What this is
- Portable Windows app to configure Winget-AutoUpdate (WAU). Core is PowerShell 5.1 with WPF XAML; an AutoHotkey v2 wrapper compiles to an elevated EXE.
- Key files: `Sources/WAU Settings GUI/WAU-Settings-GUI.ps1` (main logic, ~5K lines), `.../WAU-Settings-GUI.ahk` (wrapper), `.../config/*.xaml` (UI), `.../modules/config.psm1` (globals), `.../config_user.psm1` (overrides).

### Architecture & Integration Points
- **Registry layers**: WAU settings at `HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate`, GPO policies at `HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate`. Always read with policy precedence via `Get-DisplayValue`.
- **Update system**: `$Script:WAU_GUI_REPO = "KnifMelti/WAU-Settings-GUI"`. GitHub API drives auto-updates with backups stored in `ver\backup\`.
- **Execution modes**: GPO-managed disables most controls except shortcuts; portable mode (`-Portable`) avoids registry/filesystem artifacts.
- **UI binding**: XAML uses `$Script:*` variable interpolation for colors, titles, icons from `modules/config.psm1`.

### Code Standards
- **All code comments must be in English** - Ensure consistency across the codebase
- **All chat messages must be in Swedish, but code snippets must be in English**
- Use descriptive variable names and clear function documentation
- Follow PowerShell best practices for error handling and parameter validation

### Core patterns to follow (with examples)
- **Config precedence & atomic writes**: Always respect GPO > local registry hierarchy
   ```powershell
   $val = Get-DisplayValue -PropertyName "WAU_ListPath" -Config $updatedConfig -Policies $updatedPolicies
   Set-WAUConfig -Settings @{ WAU_StartMenuShortcut = 1 }  # Only updates changed values
   ```
- **Path validation & UI responsiveness**: Validate before saving, keep UI responsive during operations
   ```powershell
   if (-not (Test-PathValue -path $controls.ListPathTextBox.Text)) { return }
   $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background,[Action]{ 
       $controls.StatusBarText.Text = "Saving..." 
   })
   Start-PopUp "Saving WAU Settings..."; Close-PopUp
   ```
- **GPO mode & bulk control management**: Disable controls in GPO mode except shortcuts
   ```powershell
   Set-ControlsState -parentControl $window -enabled:$false -excludePattern "*Shortcut*"
   ```

### Build, Run & Debug Workflows  
- **Direct development**: Run PowerShell script as admin from `Sources/WAU Settings GUI/`:
   ```powershell
   .\WAU-Settings-GUI.ps1 -Verbose    # Full debug mode
   .\WAU-Settings-GUI.ps1 -Portable   # Portable mode (no shortcuts/registry)
   ```
- **Production build**: Use VS Code task "Compile and Sign WAU Settings GUI" or run manually:
   ```powershell
   .\compile_and_sign.ps1 -InputFile .\WAU-Settings-GUI.ahk
   ```
   Requires AutoHotkey v2 compiler (`Ahk2Exe.exe`) and Windows 10 SDK for signing.
- **Version flow**: AHK wrapper sets `ProductVersion` in metadata; PowerShell reads from compiled EXE at runtime.

### UI Architecture & Dev Tools
- **XAML structure**: `config/settings-window.xaml` (main), `config/settings-popup.xaml` (modal). Variables like `$Script:GUI_TITLE` get interpolated.
- **Dev Tools** (F12/click logo): Each `[tag]` button in XAML opens specific tools:
   - `[gpo]` → GPO registry, `[reg]` → WAU registry, `[tsk]` → Task Scheduler  
   - `[msi]` → MSI transform, `[cfg]` → backup/restore, `[ver]` → update check
- **Asset management**: Icons/images in `config/` (runtime) and `../assets/` (build-time).

### Critical Gotchas
- **Self-update file locking**: When relaunching from PowerShell, pass `/FROMPS` to AHK wrapper to avoid recursion:
   ```powershell
   Start-Process $newExePath -ArgumentList "/FROMPS" -Verb RunAs
   ```
- **Path support matrix**: Support local paths, UNC (`\\server\share`), HTTP/HTTPS URLs, and special values like `AzureBlob`. Always validate with `Test-PathValue`.
- **Shortcut sync**: After changing install/list paths, shortcuts must be regenerated to match registry state.
- **GPO exceptions**: Properties `WAU_AppInstallerShortcut`, `WAU_DesktopShortcut`, `WAU_StartMenuShortcut` are always editable even in GPO mode.

### Dependencies & Updates
- **WAU integration**: Main dependency is [Romanitho/Winget-AutoUpdate](https://github.com/Romanitho/Winget-AutoUpdate). If not installed, GUI prompts for download.
- **Auto-update system**: Checks GitHub releases weekly (configurable). Creates backups in `ver\backup\` before updating.
- **Signing**: Uses KnifMelti certificate via `sign_exe.ps1`. Update signtool path if Windows SDK version differs.

### Function Reference
All core patterns implemented in `WAU-Settings-GUI.ps1`: `Get-DisplayValue` (L1121), `Set-WAUConfig` (L1542), `Test-PathValue` (L2522), `Set-ControlsState` (L2596), popup management, dispatcher threading.
