# Global Configuration to avoid hardcoded values in the scripts

# Basic variables first
$ConfigVariables = @{
	'WAU_GUI_NAME' = "WAU-Settings-GUI"
	'WAU_GUI_PNG' = "WAU-Settings-GUI"
	'WAU_GUI_REPO' = "KnifMelti/WAU-Settings-GUI"
	'WAU_REPO' = "Romanitho/Winget-AutoUpdate"
	'WAU_REGISTRY_PATH' = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
	'WAU_POLICIES_PATH' = "HKLM:\SOFTWARE\Policies\Romanitho\Winget-AutoUpdate"
	'CONHOST_EXE' = "${env:SystemRoot}\System32\conhost.exe"
	'POWERSHELL_ARGS' = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File"
	'DESKTOP_RUN_WAU' = "${env:Public}\Desktop\Run WAU.lnk"
	'USER_RUN_SCRIPT' = "User-Run.ps1"
	'GUI_TITLE' = "WAU Settings (Administrator)"
	'AUTOUPDATE_CHECK' = $true # Enable version autoupdate check for WAU Settings GUI
	'AUTOUPDATE_DAYS' = 7 # 7 for a week, 1 for a day, 30 for a month, 0 for every time the GUI is opened
	'DESKTOP_WAU_APPINSTALLER' = "${env:Public}\Desktop\WAU App Installer.lnk"
	'STARTMENU_WAU_DIR' = "${env:PROGRAMDATA}\Microsoft\Windows\Start Menu\Programs\Winget-AutoUpdate"
	'COLOR_ENABLED' = "#228B22"  # Forest green
	'COLOR_DISABLED' = "#FF6666" # Light red
	'COLOR_ACTIVE' = "Orange"
	'COLOR_INACTIVE' = "Gray" # Grey
	'COLOR_BACKGROUND' = "#F5F5F5"  # Set background color to light gray
	'STATUS_READY_TEXT' = "Ready (F5 Load/F12 Dev)"
	'STATUS_DONE_TEXT' = "Done"
	'WAIT_TIME' = 1000 # 1 second wait time for UI updates
}

$Global:Config = $ConfigVariables

# Create combined variables after basic ones exist
$Global:DESKTOP_WAU_SETTINGS = [System.IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), "$($Config.GUI_TITLE).lnk")

# Create individual global variables from hashtable for backward compatibility
$ConfigVariables.GetEnumerator() | ForEach-Object {
    Set-Variable -Name $_.Key -Value $_.Value -Scope Global
}

# Export hashtable, combined variables AND individual variables
$variablesToExport = @('Config', 'DESKTOP_WAU_SETTINGS') + $ConfigVariables.Keys
Export-ModuleMember -Variable $variablesToExport