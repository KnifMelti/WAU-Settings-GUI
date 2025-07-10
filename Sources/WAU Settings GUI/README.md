## Installation
- Extract `Sources\WAU Settings GUI`
- Standalone Installer/Portable (i.e. no need to install **WAU Settings GUI**)
- Detects if running from USB drive, etc.
- Run `WAU-Settings-GUI.exe`:
  - <img src="../assets/WAU-Settings-GUI.png" alt="Installer/Portable">
  - Select a base directory for the installation (it must be writable for downloads, etc.) or run it directly in portable mode
  - The files will be extracted to the selected directory where you can run `WAU-Settings-GUI.exe` directly afterwards (now it knows it's installed)
  - If **WAU** is not installed, it will prompt to download and install it with standard settings (creating a **WAU Settings (Administrator)** shortcut on your own **Desktop**).
  - Toggle the **☐|☑ Start Menu shortcuts** option in the GUI and `Save Settings`
  - Retoggle **☑|☐** and `Save Settings` again (depending on your choice)
- The **WAU Settings (Administrator)** shortcut has now been created under **Start Menu\Programs\Winget-AutoUpdate** folder (along with the other **WAU** shortcuts) or on your own **Desktop**.
- In `config_user.psm1` you can set the `AUTOUPDATE_CHECK` variable to `$true/$false` to enable/disable version autoupdate check for **WAU Settings GUI** once every `AUTOUPDATE_DAYS` and other user-specific settings (i.e. colors).
- Move `config_user.psm1` to the `modules` folder to enable it.

## Update
- Download the latest released version
- Extract the files to the same directory as before (overwrite existing files)
- It looks for updates automatically every week (can be managed via `config_user.psm1`)
