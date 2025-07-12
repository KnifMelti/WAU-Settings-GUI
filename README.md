<img src="Sources/assets/WAU%20Settings%20GUI.png" alt="WAU Settings GUI" width="128" align="right"><br><br>

# WAU Settings GUI (for Winget-AutoUpdate)

Provides a user-friendly portable standalone interface to modify every aspect of Winget-AutoUpdate (**WAU**) settings

### Dependencies
This project depends on the following repository:
- [Winget-AutoUpdate](https://github.com/Romanitho/Winget-AutoUpdate): has all the settings this project can handle/modify/save/restore/share and document.

If **WAU** is not installed, the GUI prompts at startup to download and install it with standard settings.

---

### Description
Significantly enhance **WAU's** usability for home users while maintaining enterprise-grade functionality.<br>
Benefits from not having to manage the settings in several places when testing etc. (great for developers)...

...a perfect companion for those supporting the community (if the community actually uses it!) - being able to ask for a screenshot of the settings because it comes with all included (even a screenshot function masking potentially sensitive data)!

Configure **WAU** settings after installation, including:
- Update intervals and timing
- Notification levels
- Configuring list and mods paths
- Additional options like running at logon, user context, etc.
- Creating/deleting shortcuts
- Managing log files
- Starting WAU manually
- Screenshot with masking functionality for documentation
- GPO management integration
- Real-time status information display showing version details, last run times, and current configuration state
- Developer tools for advanced troubleshooting:
  - Task scheduler access
  - Registry editor access
  - GUID path exploration
  - WinGet system wide installed application list
  - List file management
  - MSI transform creation (using current showing configuration)
  - Configuration backup/import (i.e. for sharing settings)
  - Uninstall/install **WAU** (with current showing configuration)
  - Manual/automatic check for updates (checks automatically every week as standard, can be managed via `config_user.psm1`)
  - Direct access to the **WAU Settings GUI** install folder

NB: Must be run as **Administrator** (exe and shortcuts have the flag set)

### Automatic Installation
- Use **WinGet CLI** from **Command Prompt** to install the latest version:
  
  ```bash
  winget install KnifMelti.WAU-Settings-GUI
  ```

  Already have **WAU** installed? Then you can use the `--scope` parameter to install it for the current user only (because it has set `"scope":  "Machine"` in the preferences):
  
  ```bash
  winget install KnifMelti.WAU-Settings-GUI --scope user
  ```

  This will install to:
  
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
  - <img src="Sources/assets//WAU-Settings-GUI.png" alt="Installer/Portable">
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

### Uninstallation
- Use **WinGet CLI** from **Command Prompt** (Run as **Administrator**!) to uninstall:
  
  ```bash
  winget uninstall KnifMelti.WAU-Settings-GUI
  ```
Then manually delete the shortcuts from your **Desktop** and/or **Start Menu\Programs\Winget-AutoUpdate** folder.

### Screenshots
Managed by Registry (local):  
![image](Sources/assets/Screenshot_Local.png)

Dev Tools (F12):  
![image](Sources/assets/Screenshot_F12.png)

Managed by GPO (central/local):  
![image](Sources/assets/Screenshot_GPO.png)


