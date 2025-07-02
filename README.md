# WAU Settings GUI (for Winget-AutoUpdate)
Provides a user-friendly standalone interface to modify every aspect of Winget-AutoUpdate (WAU) settings

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

NB: Must be run as Administrator (shortcut creation function sets the flag)

### Installation
- Extract `Install.cmd`, `WAU-Settings-GUI.ps1` and `config` to wherever you want to install **WAU Settings GUI**
- Don't place them in the **WAU** installation directory, as this will be overwritten on updates.
- Run `Install.cmd`
  - Toggle the 'Start Menu shortcuts' option in the GUI and save settings
  - Retoggle it and save settings again (depending on your choice)
- The 'WAU Settings GUI' shortcut is now created in Start Menu under 'Winget AutoUpdate' folder or on your own desktop.
- This first release uses the [2.5.2](https://github.com/Romanitho/Winget-AutoUpdate/releases/tag/v2.5.2) version of **WAU GUID path** for the icon

### Screenshots
Managed by Registry (local):  
![image](https://github.com/user-attachments/assets/fb4592b5-23cb-465f-bd7a-fc593f59164a)

Dev Tools (F12):  
![image](https://github.com/user-attachments/assets/4548193c-76aa-4c70-ab07-77bee285d570)

Managed by GPO (central/local):  
![image](https://github.com/user-attachments/assets/1cd6706b-b08f-45ce-8756-728c898317fc)


