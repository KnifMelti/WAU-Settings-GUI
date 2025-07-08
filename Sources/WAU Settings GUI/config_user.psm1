# Global Configuration to avoid hardcoded values in the scripts

# Basic variables
$ConfigUserVariables = @{
	'AUTOUPDATE_CHECK' = $true # Enable version autoupdate check for WAU Settings GUI
	'AUTOUPDATE_DAYS' = 7 # 7 for a week, 1 for a day, 30 for a month, 0 for every time the GUI is opened
	'COLOR_ENABLED' = "#228B22"  # Forest green
	'COLOR_DISABLED' = "#FF6666" # Light red
	'COLOR_ACTIVE' = "Orange"
	'COLOR_INACTIVE' = "Gray" # Grey
	'COLOR_BACKGROUND' = "#F5F5F5"  # Set background color to light gray
}

# Set basic variables
$ConfigUserVariables.GetEnumerator() | ForEach-Object {
    Set-Variable -Name $_.Key -Value $_.Value -Scope Global
}

# Export all
$AllVariables = $ConfigUserVariables.Keys
Export-ModuleMember -Variable $AllVariables