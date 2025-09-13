## Copilot instructions for WAU Settings GUI

Purpose: Make correct, minimal changes fast in this PowerShell 5.1 + WPF XAML app with an AutoHotkey v2 wrapper by following repo-specific patterns only.

### What this is
- Portable GUI to configure Winget-AutoUpdate (WAU). Core: `WAU-Settings-GUI.ps1` (logic/UI), `WAU-Settings-GUI.ahk` (wrapper → elevated EXE), `config/*.xaml` (views), `modules/config.psm1` (globals), `config_user.psm1` (overrides).

### Architecture & integration
- Registry layers: WAU at `HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate`, GPO at `HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate`. Always read effective values via `Get-DisplayValue` (GPO > local).
- Updater: `$Script:WAU_GUI_REPO = "KnifMelti/WAU-Settings-GUI"`; releases fetched via GitHub API; backups in `ver\backup\`.
- Modes: GPO-managed disables most controls (shortcuts stay editable). `-Portable` avoids registry/FS artifacts.
- UI binding: XAML interpolates `$Script:*` from `modules/config.psm1` (colors, titles, icons).

### Core patterns (use these)
- Config precedence & atomic writes:
  ```powershell
  $val = Get-DisplayValue -PropertyName "WAU_ListPath" -Config $updatedConfig -Policies $updatedPolicies
  Set-WAUConfig -Settings @{ WAU_StartMenuShortcut = 1 } # Only changed keys are written
  ```
- Validate paths (local/UNC/HTTP/HTTPS/special) before saving; keep UI responsive:
  ```powershell
  if (-not (Test-PathValue -path $controls.ListPathTextBox.Text)) { return }
  $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background,[Action]{ $controls.StatusBarText.Text = "Saving..." })
  Start-PopUp "Saving WAU Settings..."; Close-PopUp
  ```
- Mods path semantics: GUI → registry `WAU_ModsPath` → MSI property `MODSPATH`. Accepts URL, UNC, local path, or literal `AzureBlob` (use SAS URL field). Always validate with `Test-PathValue`.
- GPO mode bulk disable (except shortcuts):
  ```powershell
  Set-ControlsState -parentControl $window -enabled:$false -excludePattern "*Shortcut*"
  ```
- Self-update relaunch (avoid file locks/recursion):
  ```powershell
  Start-Process $newExePath -ArgumentList "/FROMPS" -Verb RunAs
  ```
- After path changes, regenerate shortcuts to match registry state.

### Build, run, debug
- Run as Administrator from `Sources/WAU Settings GUI/`:
  ```powershell
  .\WAU-Settings-GUI.ps1 -Verbose   # Debug
  .\WAU-Settings-GUI.ps1 -Portable  # No shortcuts/registry
  ```
- Build/sign: VS Code task "Compile and Sign WAU Settings GUI" or:
  ```powershell
  .\compile_and_sign.ps1 -InputFile .\WAU-Settings-GUI.ahk
  ```
  Requires Ahk2Exe (AutoHotkey v2 compiler) + Windows 10 SDK; signing via `sign_exe.ps1`. AHK embeds `ProductVersion`; PS reads it at runtime.

### UI & Dev Tools (F12 / click logo)
- Views: `config/settings-window.xaml` (main), `config/settings-popup.xaml` (modal). Assets in `config/` (runtime) and `Sources/assets/` (build-time).
 - Tool tags open system/WAU helpers, e.g. `[gpo]`, `[reg]`, `[tsk]`, `[msi]`, `[cfg]`, `[ver]`, `[wau]`, `[usr]`, `[src]`, `[lst]`, `[uid]`, `[sys]`, `[wsb]`, `[mod]`.
  - `[wsb]` launches Windows Sandbox test for WAU (creates `test.wsb`, copies `InstallWSB.cmd`/`UninstallWSB.cmd`, switches `/qn`→`/qb`, maps `C:\WAU-Test`, then runs install). Requires Windows Sandbox feature (Pro/Enterprise/Education); may prompt to enable + restart.
  - `[mod]` opens the WAU mods folder. Use with `WAU_ModsPath` to prepare pre/post-install scripts (e.g. `KnifMelti.WAU-Settings-GUI-preinstall.ps1`).

### Dependencies & updates
- Depends on Romanitho/Winget-AutoUpdate; prompts to install if missing.
- Built-in updater checks weekly; backups in `ver\backup\`. WAU can also update this app; consider a preinstall script or exclusion to avoid locks.

### Code standards
- Comments in English. Chat in Swedish. Clear naming, PowerShell error handling/validation.
- Key functions you’ll reuse: `Get-DisplayValue`, `Set-WAUConfig`, `Test-PathValue`, `Set-ControlsState`, popup helpers, dispatcher threading.
