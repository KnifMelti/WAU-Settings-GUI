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

$Global:ConfigUser = $ConfigUserVariables

# Create individual global variables from hashtable for backward compatibility
$ConfigUserVariables.GetEnumerator() | ForEach-Object {
    Set-Variable -Name $_.Key -Value $_.Value -Scope Global
}

# Export hashtable AND individual variables
$variablesToExport = @('ConfigUser') + $ConfigUserVariables.Keys
Export-ModuleMember -Variable $variablesToExport