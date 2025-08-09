## Copilot instructions for WAU Settings GUI

Purpose: Help AI agents ship correct changes fast in this PowerShell + WPF + AutoHotkey repo by following our concrete patterns and workflows only.

What this is
- Portable Windows app to configure Winget-AutoUpdate (WAU). Core is PowerShell 5.1 with WPF XAML; an AutoHotkey v2 wrapper compiles to an elevated EXE.
- Key files: `Sources/WAU Settings GUI/WAU-Settings-GUI.ps1` (main), `.../WAU-Settings-GUI.ahk` (wrapper), `.../config/*.xaml` (UI), `.../modules/config.psm1` (globals), `.../config_user.psm1` (overrides).

Must-know integration points
- Registry: settings `HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate`, policies `HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate` (see `modules/config.psm1`). Always read with policy precedence via `Get-DisplayValue`.
- WAU repo and updates: `$Script:WAU_GUI_REPO = "KnifMelti/WAU-Settings-GUI"`. GitHub API calls drive update/repair and backups in `ver\...`.
- Modes: GPO-managed disables all but shortcut settings; portable mode via `-Portable` avoids desktop/start menu artifacts.

Code Standards
- **All code comments must be in English** - Ensure consistency across the codebase
- **All chat messages must be in Swedish, but code snippets must be in English**
- Use descriptive variable names and clear function documentation
- Follow PowerShell best practices for error handling and parameter validation

Core patterns to follow (with examples)
- Read config with precedence and write atomically:
   ```powershell
   $val = Get-DisplayValue -PropertyName "WAU_ListPath" -Config $updatedConfig -Policies $updatedPolicies
   Set-WAUConfig -Settings @{ WAU_StartMenuShortcut = 1 }
   ```
- Validate inputs and keep UI responsive:
   ```powershell
   if (-not (Test-PathValue -path $controls.ListPathTextBox.Text)) { return }
   $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background,[Action]{ $controls.StatusBarText.Text = "Saving..." })
   Start-PopUp "Saving WAU Settings..."; Close-PopUp
   ```
- Respect GPO mode and bulk toggle controls:
   ```powershell
   Set-ControlsState -parentControl $window -enabled:$false -excludePattern "*Shortcut*"
   ```

Build, run, sign
- Editing/debug: run the script directly as admin from `Sources/WAU Settings GUI`:
   ```powershell
   .\WAU-Settings-GUI.ps1 -Verbose
   .\WAU-Settings-GUI.ps1 -Portable
   ```
- Compile EXE: open `WAU-Settings-GUI.ahk` and run the VS Code task “Compile and Sign WAU Settings GUI” (uses `compile_and_sign.ps1`). Requires AutoHotkey v2 compiler and signtool (Windows 10 SDK). The AHK sets ProductVersion; PowerShell reads version from the compiled EXE at runtime.
- Signing: `sign_exe.ps1` signs with the KnifMelti certificate thumbprint; update signtool path if SDK version differs.

UI and assets
- XAML files in `config/` define layout; attributes reference `$Script:*` variables (colors, title, icon). Keep colors in `modules/config.psm1` or `config_user.psm1`.
- Dev Tools (F12/click logo) are wired to open registry paths, Task Scheduler, MSI transform, lists, logs, and self-update; replicate the `[tag]` button pattern from `settings-window.xaml` if adding tools.

Gotchas that break things
- File locking during self-update: when relaunching EXE from PowerShell, pass "/FROMPS" to the AHK wrapper to avoid recursion/locks (see `Start-Process ... -ArgumentList "/FROMPS"`).
- Shortcut/registry drift: after changing install/list paths, sync Start Menu/Desktop/App Installer shortcuts to match registry flags.
- Paths: support local, UNC, HTTP/HTTPS, and special values like `AzureBlob`; always `Test-PathValue` before saving.

References in repo
- Examples of all patterns live in `WAU-Settings-GUI.ps1`: `Get-DisplayValue`, `Set-WAUConfig`, `Start-PopUp`/`Close-PopUp`, `Set-ControlsState`, `Dispatcher.BeginInvoke`.

Questions or gaps? Tell us which step is unclear (build task, signing, GPO handling, or update flow) and we’ll clarify or add a snippet.
