# WAU Settings GUI (for Winget-AutoUpdate)
Provides a user-friendly interface to modify every aspect of **Winget-AutoUpdate** (**WAU**) settings.

### Dependencies
This project depends on the following repository:
- [Winget-AutoUpdate](https://github.com/Romanitho/Winget-AutoUpdate): Has all the settings handled by this project.

### Description
Significantly enhance **WAU's** usability for home users while maintaining enterprise-grade functionality.<br>
Benefits from not having to manage the settings in several places when testing etc. (great for developers)...

...a perfect companion for those supporting the community being able to ask for a screenshot of the settings because it now has everything in it (even a screenshot function with masking of potentially sensitive data)!

Configure **WAU** settings after installation, including:
- Update intervals and timing
- Notification levels
- Configuring list and mods paths
- Additional options like running at logon, user context, etc.
- Creating/removing shortcuts
- Managing log files
- Starting WAU manually
- Screenshot with masking functionality for documentation
- GPO management integration
- Real-time status information display showing version details, last run times, and current configuration state
- Developer tools for advanced troubleshooting:
  - Task scheduler access
  - Registry editor access
  - GUID path exploration
  - List file management
  - MSI transform creation
  - Configuration backup/import (i.e. for sharing settings)

NB: Must be run as Administrator (initial `.lnk` in project and shortcut creation function has/sets the flag)!

### Installation
- Extract `WAU-Settings-GUI.ps1` and `config` to **WAU** installation directory (usually "%ProgramFiles%\Winget-AutoUpdate")
- The shortcut can be placed anywhere, for example in the Start Menu of **WAU**:
  -  "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate"
- Change the shortcut properties if **WAU** installation directory differs from standard location
- This first release uses the [2.5.2](https://github.com/Romanitho/Winget-AutoUpdate/releases/tag/v2.5.2) version of **WAU GUID path** for the icon

You can manage shortcuts afterwards in **WAU Settings (Administrator)** itself.

The icon for the shortcut when managed afterwards is fetched from the **GUID path** of the current installed version of **WAU** (%SystemRoot%\Installer\GUID).

The files/shortcut will survive an upgrade of **WAU**. 


### Screenshots
Managed by Registry (local):  
![image](https://github.com/user-attachments/assets/fb4592b5-23cb-465f-bd7a-fc593f59164a)

Dev Tools (F12):  
![image](https://github.com/user-attachments/assets/4548193c-76aa-4c70-ab07-77bee285d570)

Managed by GPO (central/local):  
![image](https://github.com/user-attachments/assets/1cd6706b-b08f-45ce-8756-728c898317fc)


