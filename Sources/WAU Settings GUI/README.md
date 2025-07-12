NB: Must be run as **Administrator** (exe and shortcuts have the flag set)

### Automatic Installation
- Use **WinGet CLI** from **Command Prompt** to install the latest version:
  
  ```bash
  winget install KnifMelti.WAU-Settings-GUI
  ```

- Already have **WAU** installed?<br>Then you can use the `--scope` parameter to install it for the current user only (because **WAU** has set `"scope":  "Machine"` in the preferences):
  
  ```bash
  winget install KnifMelti.WAU-Settings-GUI --scope user
  ```

  Both of these commands will install to:
  
   `%USERPROFILE%\AppData\Local\Microsoft\WinGet\Packages\KnifMelti.WAU-Settings-GUI_Microsoft.Winget.Source_8wekyb3d8bbwe`.

- Alternatively, you can install for **All Users (64-Bit)** from **Command Prompt** (Run as **administrator**):
  
  ```bash
  winget install KnifMelti.WAU-Settings-GUI --scope machine
  ```
  This will install to:
  
  `%ProgramFiles%\WinGet\Packages\KnifMelti.WAU-Settings-GUI_Microsoft.Winget.Source_8wekyb3d8bbwe`.

### Manual Installation
- Download and extract `Sources\WAU Settings GUI`
- Standalone Installer/Portable (i.e. no need to install)
- Detects if running from USB drive, etc.
- Run `WAU-Settings-GUI.exe`:
  - <img src="../assets//WAU-Settings-GUI.png" alt="Installer/Portable">
  - Select a base directory for the installation or run directly in portable mode

### Running
- After installation, you can start **WAU Settings GUI** by running `WAU-Settings-GUI.exe` from the installation directory (or via an ordinary **Command Prompt** using the `PortableCommandAlias` from `WinGet`: **WAU-Settings-GUI**)
- If **WAU** is not installed, it will prompt to download and install with standard settings (creating a **WAU Settings (Administrator)** shortcut on your own **Desktop**)
- Toggle the **☐|☑ Start Menu shortcuts** option in the GUI and `Save Settings`
- Retoggle **☑|☐** and `Save Settings` again (depending on your choice)
- The **WAU Settings (Administrator)** shortcut has now been created under **Start Menu\Programs\Winget-AutoUpdate** folder (along with the other **WAU** shortcuts) or on your own **Desktop** (pin to taskbar when running maybe?)
- In `config_user.psm1` you can set the `AUTOUPDATE_CHECK` variable to `$true/$false` to enable/disable version autoupdate check once every `AUTOUPDATE_DAYS` and other user-specific settings (i.e. colors)
- Move `config_user.psm1` to the `modules` folder to enable it

### Updating
- Dev Tools (F12): Click the button `[ver]`
- Checks automatically every week as standard (can be managed via `config_user.psm1`)
- If an update exists, **WAU Settings GUI** will ask if you want to download and manage the update manually; opening the downloaded ***.zip** and the installation folder for you to copy/owerwrite the old files

### Uninstallation
- Use **WinGet CLI** from **Command Prompt** to uninstall:
  
  ```bash
  winget uninstall KnifMelti.WAU-Settings-GUI
  ```
- Manually delete the shortcuts from your **Desktop** and/or **Start Menu\Programs\Winget-AutoUpdate** folder.
