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
  - Manual/automatic check for **WAU Settings GUI** updates (checks every week as standard, can be managed via `config_user.psm1`)
  - Direct access to the **WAU Settings GUI** install folder

NB: Must be run as Administrator (shortcut creation sets the flag)

### Installation
- Extract `Sources\WAU Settings GUI`
- Standalone Installer/Portable (i.e. no need to install **WAU Settings GUI**)
- Detects if running from USB drive, etc.
- Run `WAU-Settings-GUI.exe`:
  - <img src="Sources/assets//WAU-Settings-GUI.png" alt="Installer/Portable">
  - Select a base directory for the installation (it must be writable for downloads, etc.) or run it directly in portable mode
  - The files will be extracted to the selected directory where you can run `WAU-Settings-GUI.exe` directly afterwards (now it knows it's installed)
  - If **WAU** is not installed, it will prompt to download and install it with standard settings (creating a **WAU Settings (Administrator)** shortcut on your own **Desktop**).
  - Toggle the **☐|☑ Start Menu shortcuts** option in the GUI and `Save Settings`
  - Retoggle **☑|☐** and `Save Settings` again (depending on your choice)
- The **WAU Settings (Administrator)** shortcut has now been created under **Start Menu\Programs\Winget-AutoUpdate** folder (along with the other **WAU** shortcuts) or on your own **Desktop**.
- In `config_user.psm1` you can set the `AUTOUPDATE_CHECK` variable to `$true/$false` to enable/disable version autoupdate check for **WAU Settings GUI** once every `AUTOUPDATE_DAYS` and other user-specific settings (i.e. colors).
- Move `config_user.psm1` to the `modules` folder to enable it.

### Screenshots
Managed by Registry (local):  
![image](Sources/assets/Screenshot_Local.png)

Dev Tools (F12):  
![image](Sources/assets/Screenshot_F12.png)

Managed by GPO (central/local):  
![image](Sources/assets/Screenshot_GPO.png)


