<img src="Sources/assets/WAU%20Settings%20GUI.png" alt="WAU Settings GUI" width="128" align="right">

# WAU Settings GUI (for Winget-AutoUpdate)

Provides a user-friendly standalone interface to modify every aspect of Winget-AutoUpdate (**WAU**) settings

### Dependencies
This project depends on the following repository:
- [Winget-AutoUpdate](https://github.com/Romanitho/Winget-AutoUpdate): has all the settings this project can handle/modify/save/restore/share and document.

### Description
Significantly enhance **WAU's** usability for home users while maintaining enterprise-grade functionality.<br>
Benefits from not having to manage the settings in several places when testing etc. (great for developers)...

...a perfect companion for those supporting the community (if the community actually uses it!) - being able to ask for a screenshot of the settings because it comes with everything included (even a screenshot function with masking of potentially sensitive data)!

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
  - MSI transform creation
  - Configuration backup/import (i.e. for sharing settings)

NB: Must be run as Administrator (shortcut creation sets the flag)

### Installation
- Extract `Sources\WAU Settings GUI` (`Install.cmd`, `WAU-Settings-GUI.ps1` and `config`) to wherever you want to run **WAU Settings GUI** from
- Don't place them in the **WAU** installation directory, as this will be overwritten on updates.
- Run `Install.cmd`
  - Toggle the **☐|☑ Start Menu shortcuts** option in the GUI and save settings
  - Retoggle **☑|☐** and save settings again (depending on your choice)
- The **WAU Settings (Administrator)** shortcut has now been created under **Start Menu\Programs\Winget-AutoUpdate** folder (along with the other **WAU** shortcuts) or on your own **Desktop**.

### Screenshots
Managed by Registry (local):  
![image](Sources/assets/Screenshot_Local.png)

Dev Tools (F12):  
![image](Sources/assets/Screenshot_F12.png)

Managed by GPO (central/local):  
![image](Sources/assets/Screenshot_GPO.png)


