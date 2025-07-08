# Manual installation
- Extract `Sources\WAU Settings GUI` to wherever you want to run **WAU Settings GUI** from (must be writable for downloads, etc.)
- Run `Install.cmd`
  - If **WAU** is not installed, it will prompt to download and install it with standard settings (creating a **WAU Settings (Administrator)** shortcut on your own **Desktop**).
  - Toggle the **☐|☑ Start Menu shortcuts** option in the GUI and `Save Settings`
  - Retoggle **☑|☐** and `Save Settings` again (depending on your choice)
- The **WAU Settings (Administrator)** shortcut has now been created under **Start Menu\Programs\Winget-AutoUpdate** folder (along with the other **WAU** shortcuts) or on your own **Desktop**.
- In `config_user.psm1` you can set the `AUTOUPDATE_CHECK` variable to `$true/$false` to enable/disable version autoupdate check for **WAU Settings GUI** once every `AUTOUPDATE_DAYS` and other user-specific settings (i.e. colors).
- Move `config_user.psm1` to the `modules` folder to enable it.
