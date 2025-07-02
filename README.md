# WAU Settings GUI (for Winget-AutoUpdate)
Provides a user-friendly interface to modify every aspect of **Winget-AutoUpdate** (**WAU**) settings.

### Dependencies
This project depends on the following repository:
- [Winget-AutoUpdate](https://github.com/Romanitho/Winget-AutoUpdate): Has all the settings handled by this project.

### Description
Significantly enhance **WAU's** usability for home users while maintaining enterprise-grade functionality.<br>
Benefits from not having to manage the settings in several places when testing etc. (perfect for developers)...

...a perfect companion for those supporting the community being able to ask for a screenshot of the settings because it now has everything in it (even a screenshot function)!

Configure **WAU** settings after installation, including:
- Update intervals and timing
- Notification levels
- Configuring list and mods paths
- Additional options like running at logon, user context, etc.
- Creating/removing shortcuts
- Managing log files
- Starting WAU manually
- Screenshot functionality for documentation
- GPO management integration
- Real-time status information display showing version details, last run times, and current configuration state
- Developer tools for advanced troubleshooting:
  - Task scheduler access
  - Registry editor access
  - GUID path exploration
  - List file management
  - MSI transform creation
  - Configuration backup/import (i.e. for sharing settings)

NB: Must be run as Administrator (initial `.lnk` in project and shortcut creation function sets the flag)!

### Installation
[README.md](https://github.com/KnifMelti/WAU-Settings-GUI/blob/main/Sources/WAU%20Settings%20GUI/README.md)

### Screenshots
Managed by Registry (local):  
![image](https://github.com/user-attachments/assets/4017c461-da41-4b5f-8960-73d7db64224a)


Dev Tools (F12):  
![image](https://github.com/user-attachments/assets/4548193c-76aa-4c70-ab07-77bee285d570)


Managed by GPO (central/local):  
![image](https://github.com/user-attachments/assets/1cd6706b-b08f-45ce-8756-728c898317fc)


