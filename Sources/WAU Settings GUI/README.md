# Manual installation
- Extract `WAU-Settings-GUI.ps1` and `config` to **WAU** installation directory (usually "%ProgramFiles%\Winget-AutoUpdate")
- The shortcut can be placed anywhere, for example in the Start Menu of **WAU**:
  -  "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate"
- Change the shortcut properties if **WAU** installation directory differs from standard location
- This first release uses the [2.5.2](https://github.com/Romanitho/Winget-AutoUpdate/releases/tag/v2.5.2) version of **WAU GUID path** for the icon

You can manage shortcuts afterwards in **WAU Settings (Administrator)** itself.

The icon for the shortcut when managed afterwards is fetched from the **GUID path** of the current installed version of **WAU** (%SystemRoot%\Installer\GUID).

The files/shortcut will survive an upgrade of **WAU** (except the **XAML** files under **config** - will release this as completely stand-alone soon).
