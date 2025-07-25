<img src="Sources/assets/WAU%20Settings%20GUI.png" alt="WAU Settings GUI" width="128" align="right"><br><br>

# WAU Settings GUI (for Winget-AutoUpdate)

Provides a user-friendly portable standalone interface to modify every aspect of Winget-AutoUpdate (**WAU**) settings

### Dependencies
This project depends on the following repository:
- [Winget-AutoUpdate](https://github.com/Romanitho/Winget-AutoUpdate): has all the settings this project can handle/modify/save/restore/share and document.

If **WAU** is not installed, the **GUI** prompts at startup to download and install it with standard settings.

---

### Description
Significantly enhance **WAU's** usability for home admin users while maintaining enterprise-grade functionality.<br>
Benefits from not having to manage the settings in several places when testing etc. (great for developers)...

...a perfect companion for those supporting the community (if the community actually uses it!) - being able to ask for a screenshot of the settings because it comes with all included (even a screenshot function masking potentially sensitive data)!

Configure **WAU** settings after installation, including:
- Update intervals and timing
- Notification levels
- Configuring list and mods paths
- Additional options like running at logon, user context, etc.
- Creating/deleting shortcuts
- Managing log files
- Starting **WAU** manually
- Screenshot with masking functionality for documentation (**F11**)
- **GPO** management integration
- Status information display showing version details, last run times, and current configuration state
- Dev Tools for advanced troubleshooting (**F12**):
  - Open **WAU** policies path in registry (if **GPO Managed**)
  - Task scheduler access
  - Registry editor access
  - **GUID** path exploration
  - Open **WinGet** system wide installed application list (if saved by **WAU**)
  - List file management
  - Change colors/update schedule for **WAU Settings GUI**
  - **MSI** transform creation (using current showing configuration)
  - Configuration backup/import (i.e. for sharing settings)
  - Uninstall/install **WAU** (with current showing configuration)
  - Manual/automatic check for updates (checks automatically every week as standard)
  - Direct access to the **WAU Settings GUI** install folder

NB: Must be run as **Administrator** (exe and shortcuts have the flag set)

### Automatic Installation
- Use **WinGet CLI** from **Command Prompt** to install the latest released **WinGet** version:
  
  ```bash
  winget install KnifMelti.WAU-Settings-GUI --scope user
  ```

This will install a **Portable WinGet Package** (with `PortableCommandAlias`: **WAU-Settings-GUI**) to:
  
   `%USERPROFILE%\AppData\Local\Microsoft\WinGet\Packages\KnifMelti.WAU-Settings-GUI_Microsoft.Winget.Source_8wekyb3d8bbwe`.

### Manual Installation
- Download and extract the latest release: [WAU-Settings-GUI-vX.X.X.X.zip](https://github.com/KnifMelti/WAU-Settings-GUI/releases/latest)
- **Standalone** Portable/Installer (i.e. no need to install)
- Detects if running from **USB** drive, etc.
- Run `WAU-Settings-GUI.exe`:
  - <img src="Sources/assets//WAU-Settings-GUI.png" alt="Portable/Installer">
  - Select a base directory for the installation or run directly in portable mode

### Running
- After installation, **WAU Settings GUI** starts (if installed by **WinGet** you must start it via an ordinary **Command Prompt** using the `PortableCommandAlias`: **WAU-Settings-GUI**)
- If **WAU** is not installed, it will prompt to download and install with standard settings
- If a local list is not found, it will prompt to create a new one
- In the **GUI** you now have **☐|☑ Start Menu shortcuts** / **☐|☑ WAU Desktop shortcut** / **☐|☑ App Installer shortcut** options showing the current installed **WAU** configuration
- Configure every setting to your preferences and `Save Settings`
- The **WAU Settings (Administrator)** shortcut has now been created under **Start Menu\Programs\Winget-AutoUpdate** folder (along with the other **WAU** shortcuts) or on your own **Desktop** (pin to taskbar when running maybe?) depending on your choice
- If **WAU** is updated and some shortcut goes missing their icons you'll have to toggle the **☐|☑ Start Menu shortcuts** / **☐|☑ WAU Desktop shortcut** / **☐|☑ App Installer shortcut** options again to create new shortcuts so that they are updated to the new **WAU** version icon

### Updating
- Dev Tools (**F12**): Click the button `[ver]`
- Checks automatically every week as standard (click the button `[usr]` under Dev Tools to change the update schedule)
- If an update exists, **WAU Settings GUI** will ask if you want to download and install the new version
- Before installing a backup of the current version will be created in `ver\backup` folder

- **WAU** will also rudimentary update **WAU Settings GUI** in user scope with every new released **WinGet** version 
  - To avoid failed updates you can create a **KnifMelti.WAU-Settings-GUI-preinstall.ps1** script in the **WAU** `mods` folder to shut down **WAU Settings GUI** before updating (open files) or not run it when updating:
  ```powershell
  Get-Process powershell | Where-Object {$_.MainWindowTitle -like "WAU Settings*"} | Stop-Process -Force
  ```
  - Disable the **WAU** updating alltogether via your `excluded_apps.txt`:<br>`KnifMelti.WAU-Settings-GUI`
- Alternatively, you can use **WinGet CLI** from **Command Prompt** to rudimentary update to every new released **WinGet** version of **WAU Settings GUI**:
  
  ```bash
  winget upgrade KnifMelti.WAU-Settings-GUI --scope user
  ```
 - The built-in updater is absolutely the best, making a backup of your current installed version first and taking care of locked files


### Uninstallation
- Use **Programs and Features** in **Control Panel** to uninstall **KnifMelti WAU Settings GUI**
- Uninstall can be done from `CMD` too (`/UNINSTALL` or silent `/UNINSTALL /S` parameter) using `UnInst.exe` in the **WAU Settings GUI** install folder, e.g.:
  
  ```bash
  "C:\WAU Settings GUI\UnInst.exe" /UNINSTALL /S
  ```
- This will remove everything, including the **Portable WinGet Package** from the source (it will not show up in the **WinGet** installed list anymore)
- **WAU** will be automatically reinstalled afterward restoring the current showing shortcuts and settings

### Screenshots
Managed by Registry (local):  
![image](Sources/assets/Screenshot_Local.png)

Dev Tools (F12):  
![image](Sources/assets/Screenshot_F12.png)

Managed by GPO (central/local):  
![image](Sources/assets/Screenshot_GPO.png)

Uninstall:  
![image](Sources/assets/Screenshot_Uninstall.png)

---

### GitHub Stats
![GitHub all releases](https://img.shields.io/github/downloads/KnifMelti/WAU-Settings-GUI/total)
![GitHub release (latest by date)](https://img.shields.io/github/downloads/KnifMelti/WAU-Settings-GUI/latest/total)
