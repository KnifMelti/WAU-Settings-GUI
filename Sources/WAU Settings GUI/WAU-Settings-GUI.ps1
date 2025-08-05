#Requires -Version 5.1

<#
.SYNOPSIS
Provides a user-friendly portable standalone interface to modify every aspect of Winget-AutoUpdate (**WAU**) settings

.DESCRIPTION
Configure **WAU** settings after installation:
- Update intervals and timing
- Notification levels
- Configuring list and mods paths
- Additional options like running at logon, user context, etc.
- Creating/deleting shortcuts
- Managing log files
- Starting **WAU** manually
- Screenshot with masking functionality for documentation (**F11**)
- **GPO** management integration
- Status information display showing version details, last run times, and current configuration state
- Dev Tools for advanced troubleshooting (**F12**):
  - `[gpo]` Open **WAU** policies path in registry (if **GPO Managed**)
  - `[tsk]` Task scheduler access (look in **WAU** folder)
  - `[reg]` Open **WAU** settings path in registry
  - `[uid]` **GUID** path exploration (**MSI** installation)
  - `[sys]` Open **WinGet** system wide installed application list (if previously saved by **WAU**)
  - `[lst]` Open the current local list
  - `[usr]` Change colors/update schedule for **WAU Settings GUI**
  - `[msi]` **MSI** transform creation (using current showing configuration)
  - `[cfg]` **Configuration** backup/import (i.e. for sharing settings)
  - `[wau]` Reinstall **WAU** (with current showing configuration)
    - Stores source in `[INSTALLDIR]\msi\[VERSION]` (enables **WAU** `Repair` in **Programs and Features**)
  - `[ver]` Manual check for **WAU Settings GUI** updates (checks automatically every week as standard)
    - If manual check and `ver\backup` exists a restore option is also presented
  - `[src]` Direct access to **WAU Settings GUI** `[INSTALLDIR]`

.NOTES
Must be run as Administrator
#>

param(
    [switch]$Portable
 )

# Set portable mode flag
$Script:PORTABLE_MODE = $Portable.IsPresent

# Set essential variables, used already in <# MAIN #>
$Script:WorkingDir = $PSScriptRoot
$Script:WAU_GUI_NAME = "WAU-Settings-GUI"  # Default name for WAU Settings GUI executable
$Script:WAU_GUI_REPO = "KnifMelti/WAU-Settings-GUI" # GitHub repository for WAU Settings GUI

<# FUNCTIONS #>
# 0. Initialization function
function Initialize-GUI {
    # Import required assemblies
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName PresentationFramework

    # Set modules path
    $modulesPath = Join-Path -Path $Script:WorkingDir -ChildPath "modules"
    $missingFiles = @()

    # Check for modules directory and required files
    if (-not (Test-Path -Path $modulesPath)) {
        $missingFiles += "modules"
    } else {
        # Check required modules
        $requiredModules = @("config.psm1")
        foreach ($module in $requiredModules) {
            $modulePath = Join-Path -Path $modulesPath -ChildPath $module
            if (-not (Test-Path -Path $modulePath)) {
                $missingFiles += "modules\$module"
            }
        }
    }
    
    # If files are missing, attempt repair
    if ($missingFiles.Count -gt 0) {
        Write-Host "Missing critical files detected. Attempting repair..." -ForegroundColor Yellow
        $repairResult = Repair-WAUSettingsFiles -MissingFiles $missingFiles
        
        if (-not $repairResult.Success) {
            throw "Critical files missing and repair failed: $($repairResult.Message)"
        }
        
        Write-Host $repairResult.Message -ForegroundColor Green
    }

    # Import the Config module
    Import-Module (Join-Path -Path $modulesPath -ChildPath "config.psm1") -Force

    $ModuleInfo = Get-Module "config"
    $ExportedVariables = $ModuleInfo.ExportedVariables.Keys

    foreach ($VarName in $ExportedVariables) {
        Set-Variable -Name $VarName -Value (Get-Variable -Name $VarName -Scope Global).Value -Scope Script
    }

    # Import config_user.psm1 only if it exists
    $configUserModulePath = Join-Path -Path $modulesPath -ChildPath "config_user.psm1"
    if (Test-Path $configUserModulePath) {
        Import-Module $configUserModulePath -Force
        $ModuleInfo = Get-Module "config_user"
        $ExportedVariables = $ModuleInfo.ExportedVariables.Keys

        foreach ($VarName in $ExportedVariables) {
            Set-Variable -Name $VarName -Value (Get-Variable -Name $VarName -Scope Global).Value -Scope Script
        }
    }

    # Then import other modules (yet to come... ...make a loop!)
    # Import-Module (Join-Path -Path $modulesPath -ChildPath "GUI.psm1") -Force
    # Import-Module (Join-Path -Path $modulesPath -ChildPath "Registry.psm1") -Force
    # Import-Module (Join-Path -Path $modulesPath -ChildPath "Logging.psm1") -Force
    # Import-Module (Join-Path -Path $modulesPath -ChildPath "Uninstaller.psm1") -Force

}

# 1. Utility functions (no dependencies)
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Repair-WAUSettingsFiles {
    param(
        [string[]]$MissingFiles,
        [switch]$Silent = $false
    )
    
    try {
        # Ensure ver directory exists
        $verDir = Join-Path $Script:WorkingDir "ver"
        if (-not (Test-Path $verDir)) {
            New-Item -ItemType Directory -Path $verDir -Force | Out-Null
        }
        
        # Find existing ZIP for current version
        $expectedZipName = "*$Script:WAU_GUI_VERSION*.zip"
        $existingZip = Get-ChildItem -Path $verDir -Filter $expectedZipName -File | Select-Object -First 1
        
        # If no ZIP exists for current version, try to download it
        if (-not $existingZip) {
            if (-not $Silent) {
                Write-Host "Downloading repair files for version $Script:WAU_GUI_VERSION..." -ForegroundColor Yellow
            }
            
            # Fetch release info from GitHub
            $apiUrl = "https://api.github.com/repos/$Script:WAU_GUI_REPO/releases"
            $releases = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
            $release = $releases | Where-Object { $_.tag_name.TrimStart('v') -eq $Script:WAU_GUI_VERSION } | Select-Object -First 1
            
            if (-not $release) {
                throw "No GitHub release found for version $Script:WAU_GUI_VERSION"
            }
            
            # Look for ZIP asset
            $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
            if (-not $asset) {
                # Fallback to source code ZIP
                $asset = [PSCustomObject]@{
                    name = "$($Script:WAU_GUI_NAME)-Source-$($release.tag_name).zip"
                    browser_download_url = "https://github.com/$Script:WAU_GUI_REPO/archive/refs/tags/$($release.tag_name).zip"
                }
            }
            
            $downloadPath = Join-Path $verDir $asset.name
            $headers = @{ 'User-Agent' = 'WAU-Settings-GUI-Repair/1.0' }
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -UseBasicParsing -Headers $headers
            
            # Validate ZIP
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::OpenRead($downloadPath).Dispose()
            $existingZip = Get-Item $downloadPath
        }
        
        if (-not $existingZip) {
            throw "Could not locate or download repair ZIP file"
        }
        
        # Extract and restore missing files
        $tempExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) "WAU-Settings-GUI-Repair-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        # Extract ZIP
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($existingZip.FullName, $tempExtractDir)
        
        # Find source directory with extensive search
        $sourceDir = $null
        $possiblePaths = @()
        
        # Search for key indicator files/directories
        $indicators = @("WAU-Settings-GUI.ps1", "modules", "config")
        
        # Check root level first
        foreach ($indicator in $indicators) {
            $testPath = Join-Path $tempExtractDir $indicator
            if (Test-Path $testPath) {
                $sourceDir = $tempExtractDir
                break
            }
        }
        
        # If not found in root, search subdirectories
        if (-not $sourceDir) {
            $allDirs = Get-ChildItem -Path $tempExtractDir -Directory -Recurse
            foreach ($dir in $allDirs) {
                foreach ($indicator in $indicators) {
                    $testPath = Join-Path $dir.FullName $indicator
                    if (Test-Path $testPath) {
                        $possiblePaths += $dir.FullName
                    }
                }
            }
            
            # Prioritize paths that contain "Sources\WAU Settings GUI" or similar
            $bestPath = $possiblePaths | Where-Object { $_ -like "*WAU*Settings*GUI*" } | Select-Object -First 1
            if (-not $bestPath) {
                $bestPath = $possiblePaths | Where-Object { $_ -like "*Sources*" } | Select-Object -First 1
            }
            if (-not $bestPath) {
                $bestPath = $possiblePaths | Select-Object -First 1
            }
            
            $sourceDir = $bestPath
        }
        
        if (-not $sourceDir) {
            # Last resort: look for any directory containing modules folder
            $modulesDirs = Get-ChildItem -Path $tempExtractDir -Directory -Recurse | Where-Object { 
                Test-Path (Join-Path $_.FullName "modules") 
            }
            if ($modulesDirs) {
                $sourceDir = $modulesDirs[0].FullName
            }
        }
        
        if (-not $sourceDir) {
            throw "Could not find source files in repair archive"
        }
        
        $repairedFiles = @()
        $failedFiles = @()
        
        # Restore each missing file
        foreach ($missingFile in $MissingFiles) {
            $sourcePath = Join-Path $sourceDir $missingFile
            $destPath = Join-Path $Script:WorkingDir $missingFile
            
            if (Test-Path $sourcePath) {
                # Ensure destination directory exists
                $destDir = Split-Path $destPath -Parent
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                
                # Copy file
                Copy-Item -Path $sourcePath -Destination $destPath -Force
                $repairedFiles += $missingFile
                
                if (-not $Silent) {
                    Write-Host "Restored: $missingFile" -ForegroundColor Green
                }
            } else {
                $failedFiles += $missingFile
            }
        }
        
        # Clean up temp directory
        Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        
        if ($failedFiles.Count -gt 0) {
            throw "Could not repair all files. Failed: $($failedFiles -join ', ')"
        }
        
        return @{
            Success = $true
            RepairedFiles = $repairedFiles
            Message = "Successfully repaired $($repairedFiles.Count) files"
        }
        
    } catch {
        # Clean up on failure
        if ($tempExtractDir -and (Test-Path $tempExtractDir)) {
            Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        return @{
            Success = $false
            RepairedFiles = @()
            Message = "Repair failed: $($_.Exception.Message)"
        }
    }
}
Function Start-PopUp ($Message) {

    if (!$PopUpWindow) {

        [xml]$XAML = ($Script:POPUP_XAML -replace "x:N", "N")

        #Read the form
        $Reader = (New-Object System.Xml.XmlNodeReader $XAML)
        $Script:PopUpWindow = [Windows.Markup.XamlReader]::Load($Reader)
        $PopUpWindow.Icon = $Script:GUI_ICON
        $PopUpWindow.Background = $Script:COLOR_BACKGROUND

        # Make sure window stays on top (redundant, but ensures behavior)
        $PopUpWindow.Topmost = $true

        #Store Form Objects In PowerShell
        $XAML.SelectNodes("//*[@Name]") | ForEach-Object {
            Set-Variable -Name "$($_.Name)" -Value $PopUpWindow.FindName($_.Name) -Scope Script
        }

        $PopUpWindow.Show()
    }
    #Message to display
    $PopUpLabel.Text = $Message
    #Update PopUp
    $PopUpWindow.Dispatcher.Invoke([action] {}, "Render")
}
Function Close-PopUp {
    if ($null -ne $Script:PopUpWindow) {
        $Script:PopUpWindow.Close()
        $Script:PopUpWindow = $null
    }
}
function Add-Shortcut {
    param(
        [string]$Shortcut,
        [string]$Target,
        [string]$StartIn,
        [string]$Arguments,
        [string]$Icon,
        [string]$Description,
        [string]$WindowStyle = "Normal",
        [bool]$RunAsAdmin = $false
    )

    $WScriptShell = New-Object -ComObject WScript.Shell
    $ShortcutObj = $WScriptShell.CreateShortcut($Shortcut)
    $ShortcutObj.TargetPath = $Target
    if (![string]::IsNullOrWhiteSpace($StartIn)) {
        $ShortcutObj.WorkingDirectory = $StartIn
    }
    $ShortcutObj.Arguments = $Arguments
    if (![string]::IsNullOrWhiteSpace($Icon)) {
        $ShortcutObj.IconLocation = $Icon
    }
    $ShortcutObj.Description = $Description
    switch ($WindowStyle.ToLower()) {
        "minimized" { $ShortcutObj.WindowStyle = 7 }
        "maximized" { $ShortcutObj.WindowStyle = 3 }
        default     { $ShortcutObj.WindowStyle = 1 }
    }
    $ShortcutObj.Save()

    # Set "Run as administrator" flag if requested
    if ($RunAsAdmin) {
        try {
            $bytes = [System.IO.File]::ReadAllBytes($Shortcut)
            # The "Run as administrator" flag is at byte offset 21 (0x15)
            # Set bit 5 (0x20) to enable "Run as administrator"
            $bytes[21] = $bytes[21] -bor 0x20
            [System.IO.File]::WriteAllBytes($Shortcut, $bytes)
        }
        catch {
            Write-Warning "Failed to set 'Run as administrator' flag for shortcut: $($_.Exception.Message)"
        }
    }

    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($ShortcutObj) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WScriptShell) | Out-Null
}
function Test-InstalledWAU {
    param (
        [Parameter(Mandatory=$true)]
        [string]$displayName
    )

    $uninstallKeys = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    $matchingApps = @()
    
    foreach ($key in $uninstallKeys) {
        try {
            $subKeys = Get-ChildItem -Path $key -ErrorAction Stop
            foreach ($subKey in $subKeys) {
                try {
                    $properties = Get-ItemProperty -Path $subKey.PSPath -ErrorAction Stop
                    if ($properties.DisplayName -like "$displayName") {
                        $matchingApps += $properties.DisplayVersion
                        $parentKeyName = Split-Path -Path $subKey.PSPath -Leaf
                        $matchingApps += $parentKeyName
                    }
                }
                catch {
                    continue
                }
            }
        }
        catch {
            continue
        }
    }

    return $matchingApps
}
function Test-WAUGUIUpdate {
    try {
        $ApiUrl = "https://api.github.com/repos/$Script:WAU_GUI_REPO/releases/latest"
        $Release = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
        $latestVersion = $Release.tag_name.TrimStart('v')
        
        # Compare versions
        $currentVer = [Version]$Script:WAU_GUI_VERSION
        $latestVer = [Version]$latestVersion
        
        # Check if we already have the latest version downloaded
        # If obsolete 'updates' folder exists, remove it
        if (Test-Path -Path (Join-Path $Script:WorkingDir "updates")) {
            Remove-Item -Path (Join-Path $Script:WorkingDir "updates") -Recurse -Force
        }
        $downloadDir = Join-Path $Script:WorkingDir "ver"
        $alreadyDownloaded = $false
        $existingFilePath = $null
        
        if (Test-Path $downloadDir) {
            # Look for files with the latest version in the name
            $existingFiles = Get-ChildItem -Path $downloadDir -Filter "*.zip" | Where-Object {
                $_.Name -like "*$latestVersion*" -or $_.Name -like "*$($Release.tag_name)*"
            }
            
            if ($existingFiles) {
                $alreadyDownloaded = $true
                $existingFilePath = $existingFiles[0].FullName
                Write-Host "Found existing download for version $latestVersion`: $($existingFiles[0].Name)"
            }
        }
        
        # Find download URL - GitHub automatically creates source code assets
        $downloadAsset = $null
        
        # First, try to find manually uploaded assets with specific patterns
        $patterns = @(
            "*WAU-Settings-GUI*.zip",
            "*WAU*Settings*GUI*.zip", 
            "*Settings*GUI*.zip",
            "*GUI*.zip",
            "*.zip"
        )
        
        foreach ($pattern in $patterns) {
            $downloadAsset = $Release.assets | Where-Object { $_.name -like $pattern } | Select-Object -First 1
            if ($downloadAsset) {
                Write-Host "Found manually uploaded asset using pattern '$pattern': $($downloadAsset.name)"
                break
            }
        }
        
        # If no manually uploaded ZIP found, use GitHub's automatic source code ZIP
        if (-not $downloadAsset) {
            # GitHub automatically provides source code downloads at predictable URLs
            $downloadUrl = "https://github.com/$Script:WAU_GUI_REPO/archive/refs/tags/$($Release.tag_name).zip"
            $downloadAsset = [PSCustomObject]@{
                name = "$($Script:WAU_GUI_NAME)-Source-$($Release.tag_name).zip"
                browser_download_url = $downloadUrl
            }
            Write-Host "Using GitHub automatic source code ZIP: $($downloadAsset.name)"
        }
        
        return @{
            UpdateAvailable = ($latestVer -gt $currentVer)
            CurrentVersion = $Script:WAU_GUI_VERSION
            LatestVersion = $latestVersion
            DownloadUrl = $downloadAsset.browser_download_url
            ReleaseNotes = $Release.body
            AssetName = $downloadAsset.name
            AlreadyDownloaded = $alreadyDownloaded
            ExistingFilePath = $existingFilePath
        }
    }
    catch {
        return @{
            UpdateAvailable = $false
            Error = $_.Exception.Message
        }
    }
}
function Get-CleanReleaseNotes {
    param([string]$RawNotes)
    
    if ([string]::IsNullOrWhiteSpace($RawNotes)) {
        return "Se GitHub för release notes"
    }
    
    # Extract bullet points from "What's Changed" section
    $lines = $RawNotes -split "`r?`n"  # Split on both \r\n and \n
    $inChangedSection = $false
    $bulletPoints = @()
    
    foreach ($line in $lines) {
        $trimmedLine = $line.Trim()
        
        if ($trimmedLine -match '^## What''s Changed') {
            $inChangedSection = $true
            continue
        }
        
        if ($inChangedSection) {
            # Stop at next section or download statistics
            if ($trimmedLine -match '^## ' -and $trimmedLine -notmatch '^## What''s Changed') {
                break
            }
            
            # Extract bullet points (handles *, -, and indented bullets)
            if ($line -match '^\s*([\*\-])\s+(.+)') {
                $bulletChar = $matches[1]
                $bulletText = $matches[2].Trim()  # Extra trim to remove any \r characters
                
                # Skip bullet if it contains "by @username"
                if ($bulletText -match 'by\s+@\w+') {
                    continue
                }
                # Remove markdown links
                $bulletText = $bulletText -replace '\[([^\]]+)\]\([^\)]+\)', '$1'
                # Remove markdown formatting
                $bulletText = $bulletText -replace '\*\*([^*]+)\*\*', '$1'
                
                if ($bulletText.Length -gt 5) {
                    $bulletPoints += "$bulletChar $bulletText"
                }
            }
        }
    }
    
    if ($bulletPoints.Count -gt 0) {
        # Show 6 bullet points
        $maxBullets = 6
        $selectedBullets = $bulletPoints | Select-Object -First $maxBullets
        
        # Add "..." if there are more bullet points
        if ($bulletPoints.Count -gt $maxBullets) {
            $selectedBullets += "..."
        }
        
        # Use Windows-style line breaks
        return $selectedBullets -join "`r`n"
    } else {
        return "Se GitHub för release notes"
    }
}
function Start-WAUGUIUpdate {
    param($updateInfo)
    
    try {
        if ([string]::IsNullOrEmpty($updateInfo.DownloadUrl)) {
            throw "No download URL found in release"
        }
        
        $downloadDir = Join-Path $Script:WorkingDir "ver"
        if (-not (Test-Path $downloadDir)) {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
        }
        
        $fileName = if ($updateInfo.AssetName) { $updateInfo.AssetName } else { Split-Path $updateInfo.DownloadUrl -Leaf }
        $downloadPath = Join-Path $downloadDir $fileName
        
        # Check if we already have the file downloaded
        if ($updateInfo.AlreadyDownloaded -and $updateInfo.ExistingFilePath -and (Test-Path $updateInfo.ExistingFilePath)) {
            $downloadPath = $updateInfo.ExistingFilePath
            $fileName = Split-Path $downloadPath -Leaf
            Write-Host "Using existing download: $fileName"
        } else {
            Start-PopUp "Downloading update: $fileName..."
            
            # Add User-Agent header for better GitHub API compatibility
            $headers = @{
                'User-Agent' = 'WAU-Settings-GUI-Updater/1.0'
            }
            
            Invoke-WebRequest -Uri $updateInfo.DownloadUrl -OutFile $downloadPath -UseBasicParsing -Headers $headers
            
            # Verify download was successful
            if (-not (Test-Path $downloadPath) -or (Get-Item $downloadPath).Length -eq 0) {
                throw "Downloaded file is missing or empty"
            }
        }
        
        Close-PopUp
        
        # Ask user if they want to install now
        $statusText = if ($updateInfo.AlreadyDownloaded) { "existing" } else { "downloaded successfully" }
        $result = [System.Windows.MessageBox]::Show(
            "Update $statusText!`n`nFile: $fileName`nLocation: $downloadPath`n`nDo you want to extract and install the update now?",
            "Update Ready",
            "OkCancel",
            "Question"
        )
        
        if ($result -eq 'Ok') {
            Start-PopUp "Installing update..."
            
            try {
                # Extract the ZIP file
                $extractPath = Join-Path $downloadDir "extract_temp"
                if (Test-Path $extractPath) {
                    Remove-Item -Path $extractPath -Recurse -Force
                }
                
                Add-Type -AssemblyName System.IO.Compression.FileSystem
                [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadPath, $extractPath)
                
                # Find the source directory (handle both manual uploads and GitHub source archives)
                $sourceDir = $null
                
                # Look for a subdirectory that contains the main files
                $subDirs = Get-ChildItem -Path $extractPath -Directory
                foreach ($dir in $subDirs) {
                    if ((Test-Path (Join-Path $dir.FullName "WAU-Settings-GUI.ps1")) -or 
                        (Test-Path (Join-Path $dir.FullName "Sources"))) {
                        $sourceDir = $dir.FullName
                        break
                    }
                }
                
                # If no subdirectory found, check if files are in root
                if (-not $sourceDir) {
                    if ((Test-Path (Join-Path $extractPath "WAU-Settings-GUI.ps1")) -or 
                        (Test-Path (Join-Path $extractPath "Sources"))) {
                        $sourceDir = $extractPath
                    }
                }

                if (-not $sourceDir) {
                    throw "Could not find source files in extracted archive"
                }
                
                # Find the actual files to copy
                $filesToCopy = $null
                
                # Check for Sources\WAU Settings GUI structure
                $wauSettingsPath = Join-Path $sourceDir "Sources\WAU Settings GUI"
                if (Test-Path $wauSettingsPath) {
                    $filesToCopy = $wauSettingsPath
                } elseif (Test-Path (Join-Path $sourceDir "WAU-Settings-GUI.ps1")) {
                    $filesToCopy = $sourceDir
                }
                
                if (-not $filesToCopy) {
                    throw "Could not find WAU Settings GUI files in the archive"
                }
                
                # Create backup of current version
                $backupDir = Join-Path $Script:WorkingDir "ver_$($Script:WAU_GUI_VERSION)_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
                if (-not (Test-Path $backupDir)) {
                    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                }
                
                # Backup current files (exclude created directories)
                Get-ChildItem -Path $Script:WorkingDir -Exclude "ver", "ver_*", "msi", "cfg" | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination $backupDir -Recurse -Force
                }
                
                # Delete UnInst.exe (to be recreated by the new version)
                $uninstPath = Join-Path $Script:WorkingDir "UnInst.exe"
                if (Test-Path $uninstPath) {
                    Remove-Item -Path $uninstPath -Force
                }

                # Create zip backup of the backup directory
                try {
                    $backupZipDir = Join-Path $downloadDir "backup"
                    if (-not (Test-Path $backupZipDir)) {
                        New-Item -ItemType Directory -Path $backupZipDir -Force | Out-Null
                    }
                    
                    $backupDirName = Split-Path $backupDir -Leaf
                    $zipFileName = "$backupDirName.zip"
                    $zipFilePath = Join-Path $backupZipDir $zipFileName
                    
                    # Create zip file from backup directory
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    [System.IO.Compression.ZipFile]::CreateFromDirectory($backupDir, $zipFilePath)
                    
                    # Verify zip was created successfully
                    if (Test-Path $zipFilePath) {
                        Write-Host "Backup zip created: $zipFilePath"
                        
                        # Remove the original backup directory to save space
                        Remove-Item -Path $backupDir -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Host "Original backup directory removed: $backupDir"
                    }
                }
                catch {
                    Write-Warning "Failed to create backup zip: $($_.Exception.Message)"
                    # Continue with installation even if zip creation fails
                }                
                
                # Icon cleanup before file copying
                if ($window -and $window.Icon) { $window.Icon = $null }
                if ($Script:PopUpWindow) { $Script:PopUpWindow.Close(); $Script:PopUpWindow = $null }

                # Force garbage collection to release file handles
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()

                # Close the current window BEFORE copying files to release file locks
                if ($Script:MainWindowStarted -and $window) { $window.Close() }

                # Add a small delay to ensure window is closed and files are released
                Start-Sleep -Milliseconds 1500

                # Copy new files, overwriting all existing files without exceptions
                Get-ChildItem -Path $filesToCopy | ForEach-Object {
                    $relativePath = $_.Name
                    $destinationPath = Join-Path $Script:WorkingDir $relativePath
                
                    if ($_.PSIsContainer) {
                        # For directories, we need special handling
                        if ($relativePath -eq "modules") {
                            if (-not (Test-Path $destinationPath)) {
                                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                            }
                            
                            # Copy all files from source modules
                            Get-ChildItem -Path $_.FullName -File | ForEach-Object {
                                $moduleFile = $_
                                $moduleDestPath = Join-Path $destinationPath $moduleFile.Name
                                Copy-Item -Path $moduleFile.FullName -Destination $moduleDestPath -Force
                            }
                            
                            # Copy subdirectories if any
                            Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
                                Copy-Item -Path $_.FullName -Destination $destinationPath -Recurse -Force
                            }
                        } elseif ($relativePath -eq "config") {
                            # Special handling for config directory to skip locked files
                            if (-not (Test-Path $destinationPath)) {
                                New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                            }
                            
                            # Copy files from source config except locked image files
                            Get-ChildItem -Path $_.FullName -File | ForEach-Object {
                                $configFile = $_
                                $configDestPath = Join-Path $destinationPath $configFile.Name
                                
                                # Skip locked image files in config directory
                                if ($configFile.Name -like "*.png" -or $configFile.Name -like "*.ico") {
                                    Write-Host "Preserving existing locked file: config\$($configFile.Name)"
                                } else {
                                    Copy-Item -Path $configFile.FullName -Destination $configDestPath -Force
                                }
                            }
                            
                            # Copy subdirectories if any
                            Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
                                Copy-Item -Path $_.FullName -Destination $destinationPath -Recurse -Force
                            }
                        } else {
                            # For other directories, remove existing and copy fresh
                            if (Test-Path $destinationPath) {
                                Remove-Item -Path $destinationPath -Recurse -Force
                            }
                            Copy-Item -Path $_.FullName -Destination $Script:WorkingDir -Recurse -Force
                        }
                    } else {
                        try {
                            Copy-Item -Path $_.FullName -Destination $destinationPath -Force -ErrorAction Stop
                        }
                        catch {
                            # If file is locked, skip it with warning
                            if ($_.Exception.Message -like "*being used by another process*") {
                                Write-Warning "Skipping locked file: $relativePath"
                                continue
                            }
                            throw
                        }
                    }
                }

                # Create/update the desktop shortcut AFTER copying files
                if (-not $Script:PORTABLE_MODE) {
                    $shortcutPath = $Script:DESKTOP_WAU_SETTINGS
                    $targetPath = Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'
                    $newIconPath = Join-Path $Script:WorkingDir "config\WAU Settings GUI.ico"
                    
                    if (Test-Path $targetPath) {
                        Add-Shortcut -Shortcut $shortcutPath `
                                -Target $Script:CONHOST_EXE `
                                -StartIn $Script:WorkingDir `
                                -Arguments "$Script:POWERSHELL_ARGS `"$targetPath`"" `
                                -Icon $newIconPath `
                                -Description "Configure Winget-AutoUpdate settings after installation" `
                                -WindowStyle "Normal" `
                                -RunAsAdmin $true
                    }
                }

                # Clean up extraction directory AFTER copying files
                Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
                
                # Close popup and show success message AFTER everything is completed successfully
                Close-PopUp
                
                [System.Windows.MessageBox]::Show(
                    "Update installed successfully!`n`nThe application will now restart with the new version.",
                    "Update Complete",
                    "OK",
                    "Information"
                )
                
                # Restart the application with the new version
                if (-not $Script:PORTABLE_MODE) {
                    Start-Process -FilePath $Script:DESKTOP_WAU_SETTINGS
                } else {
                    Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$(Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1')`" -Portable"
                }
                exit
            } catch {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Failed to install update: $($_.Exception.Message)", "Installation Error", "OK", "Error")
                
                # Fallback to manual installation
                Start-Process "explorer.exe" "$Script:WorkingDir"
                Start-Process "explorer.exe" "$downloadPath"
                
                # Only call Close-WindowGracefully if we still have a valid window
                if ($Script:MainWindowStarted -and $window -and -not $window.IsClosed) {
                    Close-WindowGracefully -controls $controls -window $window
                }
                exit
            }
        }
        return $true
    }
    catch {
        Close-PopUp
        [System.Windows.MessageBox]::Show("Failed to download update: $($_.Exception.Message)", "Update Error", "OK", "Error")
        return $false
    }
}
function Start-RestoreFromBackup {
    param(
        [string]$backupPath,
        $controls,
        $window
    )
    
    try {
        Start-PopUp "Restoring from backup..."
        
        # Extract backup to temp location
        $tempExtractDir = Join-Path ([System.IO.Path]::GetTempPath()) "WAU-Settings-GUI-Restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($backupPath, $tempExtractDir)
        
        # Icon cleanup before file copying (same as in Start-WAUGUIUpdate)
        if ($window -and $window.Icon) { $window.Icon = $null }
        if ($Script:PopUpWindow) { $Script:PopUpWindow.Close(); $Script:PopUpWindow = $null }

        # Force garbage collection to release file handles
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()

        # Close the current window BEFORE copying files to release file locks
        if ($Script:MainWindowStarted -and $window) { $window.Close() }

        # Add a small delay to ensure window is closed and files are released
        Start-Sleep -Milliseconds 1500

        # Copy restored files, overwriting current files (same logic as in Start-WAUGUIUpdate)
        Get-ChildItem -Path $tempExtractDir | ForEach-Object {
            $relativePath = $_.Name
            $destinationPath = Join-Path $Script:WorkingDir $relativePath
        
            if ($_.PSIsContainer) {
                # For directories, we need special handling
                if ($relativePath -eq "modules") {
                    if (-not (Test-Path $destinationPath)) {
                        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                    }
                    
                    # Copy all files from source modules
                    Get-ChildItem -Path $_.FullName -File | ForEach-Object {
                        $moduleFile = $_
                        $moduleDestPath = Join-Path $destinationPath $moduleFile.Name
                        Copy-Item -Path $moduleFile.FullName -Destination $moduleDestPath -Force
                    }
                    
                    # Copy subdirectories if any
                    Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
                        Copy-Item -Path $_.FullName -Destination $destinationPath -Recurse -Force
                    }
                } elseif ($relativePath -eq "config") {
                    # Special handling for config directory to skip locked files
                    if (-not (Test-Path $destinationPath)) {
                        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                    }
                    
                    # Copy files from source config except locked image files
                    Get-ChildItem -Path $_.FullName -File | ForEach-Object {
                        $configFile = $_
                        $configDestPath = Join-Path $destinationPath $configFile.Name
                        
                        # Skip locked image files in config directory
                        if ($configFile.Name -like "*.png" -or $configFile.Name -like "*.ico") {
                            Write-Host "Preserving existing locked file: config\$($configFile.Name)"
                        } else {
                            Copy-Item -Path $configFile.FullName -Destination $configDestPath -Force
                        }
                    }
                    
                    # Copy subdirectories if any
                    Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
                        Copy-Item -Path $_.FullName -Destination $destinationPath -Recurse -Force
                    }
                } else {
                    # For other directories, remove existing and copy fresh
                    if (Test-Path $destinationPath) {
                        Remove-Item -Path $destinationPath -Recurse -Force
                    }
                    Copy-Item -Path $_.FullName -Destination $Script:WorkingDir -Recurse -Force
                }
            } else {
                try {
                    Copy-Item -Path $_.FullName -Destination $destinationPath -Force -ErrorAction Stop
                }
                catch {
                    # If file is locked, skip it with warning
                    if ($_.Exception.Message -like "*being used by another process*") {
                        Write-Warning "Skipping locked file: $relativePath"
                        continue
                    }
                    throw
                }
            }
        }

        # Create/update the desktop shortcut AFTER copying files (same as in Start-WAUGUIUpdate)
        if (-not $Script:PORTABLE_MODE) {
            $shortcutPath = $Script:DESKTOP_WAU_SETTINGS
            $targetPath = Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'
            $newIconPath = Join-Path $Script:WorkingDir "config\WAU Settings GUI.ico"
            
            if (Test-Path $targetPath) {
                Add-Shortcut -Shortcut $shortcutPath `
                        -Target $Script:CONHOST_EXE `
                        -StartIn $Script:WorkingDir `
                        -Arguments "$Script:POWERSHELL_ARGS `"$targetPath`"" `
                        -Icon $newIconPath `
                        -Description "Configure Winget-AutoUpdate settings after installation" `
                        -WindowStyle "Normal" `
                        -RunAsAdmin $true
            }
        }

        # Clean up extraction directory AFTER copying files
        Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        
        # Close popup and show success message AFTER everything is completed successfully
        Close-PopUp
        
        [System.Windows.MessageBox]::Show(
            "Restore completed successfully!`n`nThe application will now restart with the restored version.",
            "Restore Complete",
            "OK",
            "Information"
        )
        
        # Restart the application with the restored version
        if (-not $Script:PORTABLE_MODE) {
            Start-Process -FilePath $Script:DESKTOP_WAU_SETTINGS
        } else {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$(Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1')`" -Portable"
        }
        exit
    }
    catch {
        Close-PopUp
        [System.Windows.MessageBox]::Show("Failed to restore from backup: $($_.Exception.Message)", "Restore Error", "OK", "Error")
        
        # Cleanup on failure
        if (Test-Path $tempExtractDir) {
            Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Fallback to manual restoration
        Start-Process "explorer.exe" "$Script:WorkingDir"
        Start-Process "explorer.exe" "$backupPath"
        
        # Only call Close-WindowGracefully if we still have a valid window
        if ($Script:MainWindowStarted -and $window -and -not $window.IsClosed) {
            Close-WindowGracefully -controls $controls -window $window
        }
        exit
    }
}

# 2. Configuration functions
function Get-DisplayValue {
    param (
        [string]$PropertyName,
        $Config,
        $Policies
    )
    
    # Check if GPO management is active
    $isGPOManaged = ($null -ne $Policies)
    
    # These properties are always editable and taken from local config, even in GPO mode
    $alwaysFromConfig = @('WAU_AppInstallerShortcut', 'WAU_DesktopShortcut', 'WAU_StartMenuShortcut')
    
    # If GPO managed and this property exists in policies and it's not in the exceptions list
    if ($isGPOManaged -and 
        $Policies.PSObject.Properties.Name -contains $PropertyName -and
        $PropertyName -notin $alwaysFromConfig) {
        return $Policies.$PropertyName
    }
    
    # Otherwise use the local config value
    return $Config.$PropertyName
}
function Get-WAUCurrentConfig {
    try {
        # Check if UnInst.exe exists or installed/first run file exists
        $installedFile = Join-Path $Script:WorkingDir "installed.txt"
        $firstRunFile = Join-Path $Script:WorkingDir "firstrun.txt"
        $uninstPath = Join-Path $Script:WorkingDir "UnInst.exe"
        $wauGuiPath = Join-Path $Script:WorkingDir "$Script:WAU_GUI_NAME.exe"
        if (-not $Script:PORTABLE_MODE -and -not $Script:MainWindowStarted) {
            if (-not (Test-Path $firstRunFile) -or -not (Test-Path $installedFile) -or -not (Test-Path $uninstPath) -and (Test-Path $wauGuiPath)) {
                $currentProcess = Get-Process -Id $PID
                $isRunningAsPowerShell = $currentProcess.ProcessName -eq "powershell" -or $currentProcess.ProcessName -eq "pwsh"
                if ($isRunningAsPowerShell) {
                Add-Shortcut $Script:DESKTOP_WAU_SETTINGS $Script:CONHOST_EXE "$($Script:WorkingDir)" "$Script:POWERSHELL_ARGS `"$((Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'))`"" "$Script:GUI_ICON" "Configure Winget-AutoUpdate settings after installation" "Normal" $true
                Set-Content -Path $firstRunFile -Value "WAU Settings GUI first run completed" -Force
                Set-Content -Path $installedFile -Value "WAU Settings GUI installed" -Force
                # Set file attributes to Hidden and System
                try {
                    $fileInfo = Get-Item -Path $firstRunFile
                    $fileInfo.Attributes = 'Hidden,System'
                    $fileInfo = Get-Item -Path $installedFile
                    $fileInfo.Attributes = 'Hidden,System'
                } catch {
                    # Ignore attribute setting errors
                }
                # Remove incorrect subdirectories if present
                $badModulesDir = Join-Path $Script:WorkingDir "modules\modules"
                if (Test-Path $badModulesDir) {
                    Remove-Item -Path $badModulesDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                $badConfigDir = Join-Path $Script:WorkingDir "config\config"
                if (Test-Path $badConfigDir) {
                    Remove-Item -Path $badConfigDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                Start-Process -FilePath $wauGuiPath -ArgumentList "/FROMPS"
                exit
                }
            }
        }
        $config = Get-ItemProperty -Path $Script:WAU_REGISTRY_PATH -ErrorAction SilentlyContinue
        if (!$config -or [string]::IsNullOrEmpty($config.ProductVersion)) {
            throw "WAU not found in registry or ProductVersion missing"
        }

        return $config
    }
    catch {
        if (!$Script:MainWindowStarted) {
            Close-PopUp
        }
        
        # Show initial prompt
        $userWantsToInstall = [System.Windows.MessageBox]::Show(
            "WAU configuration not found. Please ensure WAU is properly installed.`n`nDo you want to download and install WAU now?", 
            "WAU Not Found", 
            "OkCancel", 
            "Question"
        ) -eq 'Ok'
        
            if ($userWantsToInstall) {
                $result = Get-WAUMsi  # Download latest stable WAU
                
                if ($result) {
                    $msiFilePath = $result.MsiFilePath
                }
                
                if ($msiFilePath) {
                    # Install WAU using the downloaded MSI file
                    $installResult = Install-WAU -msiFilePath $msiFilePath
                
                # Handle post-installation logic
                if ($Script:MainWindowStarted) {
                    return $null  # Return to main window regardless of install result
                }
                        
                # Create desktop shortcut for settings
                if (-not $Script:PORTABLE_MODE) {
                    Add-Shortcut $Script:DESKTOP_WAU_SETTINGS $Script:CONHOST_EXE $Script:WorkingDir "$Script:POWERSHELL_ARGS `"$((Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'))`"" $Script:GUI_ICON "Configure Winget-AutoUpdate settings after installation" "Normal" $true
                    if ($installResult) {
                        Start-Process -FilePath $Script:DESKTOP_WAU_SETTINGS
                        exit
                    }
                    exit 1
                }
                
                if ($installResult) {
                    # Installation succeeded, try to get config again
                    try {
                        return Get-ItemProperty -Path $Script:WAU_REGISTRY_PATH -ErrorAction Stop
                    }
                    catch {
                        [System.Windows.MessageBox]::Show("Installation succeeded but cannot read WAU configuration.", "Configuration Error", "OK", "Error")
                        exit 1
                    }
                } else {
                    exit 1  # Installation failed
                }
                exit 0
            } else {
                # MSI download failed
                if ($Script:MainWindowStarted) {
                    return $null  # Return to main window
                } else {
                    if (-not $Script:PORTABLE_MODE) {
                        Add-Shortcut $Script:DESKTOP_WAU_SETTINGS $Script:CONHOST_EXE "$($Script:WorkingDir)" "$Script:POWERSHELL_ARGS `"$((Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'))`"" "$Script:GUI_ICON" "Configure Winget-AutoUpdate settings after installation" "Normal" $true
                    }
                    exit 1
                }
            }
        } else {
            # User declined to install
            if ($Script:MainWindowStarted) {
                return $null  # Return to main window
            } else {
                if (-not $Script:PORTABLE_MODE) {
                    Add-Shortcut $Script:DESKTOP_WAU_SETTINGS $Script:CONHOST_EXE "$($Script:WorkingDir)" "$Script:POWERSHELL_ARGS `"$((Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'))`"" "$Script:GUI_ICON" "Configure Winget-AutoUpdate settings after installation" "Normal" $true
                }
                exit 1
            }
        }
    }
}
function Import-WAUSettingsFromFile {
    param(
        [string]$FilePath,
        $Controls
    )
    
    try {
        $content = Get-Content -Path $FilePath -Encoding UTF8
        
        # Parse .reg.txt content and extract registry values
        foreach ($line in $content) {
            if ($line -match '"(.+?)"=(.+)') {
                $valueName = $matches[1]
                $valueData = $matches[2]
                
                # Convert value based on type and update corresponding GUI control
                switch ($valueName) {
                    'WAU_NotificationLevel' { 
                        # Extract string value and set notification level
                        if ($valueData -match '"(.+?)"') {
                            $level = $matches[1]
                            $Controls.NotificationLevelComboBox.SelectedIndex = switch ($level) {
                                "Full" { 0 }
                                "SuccessOnly" { 1 }
                                "ErrorsOnly" { 2 }
                                "None" { 3 }
                                default { 0 }
                            }
                        }
                    }
                    'WAU_UpdatesInterval' {
                        # Extract string value
                        if ($valueData -match '"(.+?)"') {
                            $interval = $matches[1]
                            $Controls.UpdateIntervalComboBox.SelectedIndex = switch ($interval) {
                                "Daily" { 0 }
                                "BiDaily" { 1 }
                                "Weekly" { 2 }
                                "BiWeekly" { 3 }
                                "Monthly" { 4 }
                                "Never" { 5 }
                                default { 5 }
                            }
                        }
                    }
                    'WAU_UpdatesAtTime' {
                        if ($valueData -match '"(.+?)"') {
                            $time = $matches[1]
                            $hourIndex = [int]$time.Substring(0,2) - 1
                            $minuteIndex = [int]$time.Substring(3,2)
                            if ($hourIndex -ge 0 -and $hourIndex -lt $Controls.UpdateTimeHourComboBox.Items.Count) {
                                $Controls.UpdateTimeHourComboBox.SelectedIndex = $hourIndex
                            }
                            if ($minuteIndex -ge 0 -and $minuteIndex -lt $Controls.UpdateTimeMinuteComboBox.Items.Count) {
                                $Controls.UpdateTimeMinuteComboBox.SelectedIndex = $minuteIndex
                            }
                        }
                    }
                    'WAU_UpdatesTimeDelay' {
                        if ($valueData -match '"(.+?)"') {
                            $delay = $matches[1]
                            $hourIndex = [int]$delay.Substring(0,2)
                            $minuteIndex = [int]$delay.Substring(3,2)
                            if ($hourIndex -ge 0 -and $hourIndex -lt $Controls.RandomDelayHourComboBox.Items.Count) {
                                $Controls.RandomDelayHourComboBox.SelectedIndex = $hourIndex
                            }
                            if ($minuteIndex -ge 0 -and $minuteIndex -lt $Controls.RandomDelayMinuteComboBox.Items.Count) {
                                $Controls.RandomDelayMinuteComboBox.SelectedIndex = $minuteIndex
                            }
                        }
                    }
                    'WAU_UpdatePrerelease' { 
                        $Controls.UpdatePreReleaseCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_UseWhiteList' {
                        $Controls.UseWhiteListCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_DisableAutoUpdate' {
                        $Controls.DisableWAUAutoUpdateCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_DoNotRunOnMetered' {
                        $Controls.DoNotRunOnMeteredCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_UpdatesAtLogon' {
                        $Controls.UpdatesAtLogonCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_UserContext' {
                        $Controls.UserContextCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_BypassListForUsers' {
                        $Controls.BypassListForUsersCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_StartMenuShortcut' {
                        $Controls.StartMenuShortcutCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_DesktopShortcut' {
                        $Controls.DesktopShortcutCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_AppInstallerShortcut' {
                        $Controls.AppInstallerShortcutCheckBox.IsChecked = ($valueData -eq 'dword:00000001')
                    }
                    'WAU_ListPath' {
                        if ($valueData -match '"(.+?)"') {
                            $Controls.ListPathTextBox.Text = $matches[1]
                        } elseif ($valueData -match '""') {
                            $Controls.ListPathTextBox.Text = ""
                        }
                    }
                    'WAU_ModsPath' {
                        if ($valueData -match '"(.+?)"') {
                            $Controls.ModsPathTextBox.Text = $matches[1]
                        } elseif ($valueData -match '""') {
                            $Controls.ModsPathTextBox.Text = ""
                        }
                    }
                    'WAU_AzureBlobSASURL' {
                        if ($valueData -match '"(.+?)"') {
                            $Controls.AzureBlobSASURLTextBox.Text = $matches[1]
                        } elseif ($valueData -match '""') {
                            $Controls.AzureBlobSASURLTextBox.Text = ""
                        }
                    }
                    'WAU_MaxLogFiles' {
                        if ($valueData -match 'dword:(\w+)') {
                            $logFiles = [int]"0x$($matches[1])"
                            if ($logFiles -ge 0 -and $logFiles -le 99) {
                                $Controls.MaxLogFilesComboBox.SelectedIndex = $logFiles
                            }
                        }
                    }
                    'WAU_MaxLogSize' {
                        if ($valueData -match 'dword:(\w+)') {
                            $logSize = [int]"0x$($matches[1])"
                            # Find matching item in ComboBox
                            $logSizeIndex = -1
                            for ($i = 0; $i -lt $Controls.MaxLogSizeComboBox.Items.Count; $i++) {
                                if ($Controls.MaxLogSizeComboBox.Items[$i].Tag -eq $logSize.ToString()) {
                                    $logSizeIndex = $i
                                    break
                                }
                            }
                            if ($logSizeIndex -ge 0) {
                                $Controls.MaxLogSizeComboBox.SelectedIndex = $logSizeIndex
                            } else {
                                $Controls.MaxLogSizeComboBox.Text = $logSize.ToString()
                            }
                        }
                    }
                }
            }
        }
        
        # Update dependent states after importing all values
        Update-StatusDisplay -Controls $Controls
        Update-MaxLogSizeState -Controls $Controls
        Update-PreReleaseCheckBoxState -Controls $Controls
    }
    catch {
        throw "Could not parse file: $($_.Exception.Message)"
    }
}
function Update-WAUScheduledTask {
    param([hashtable]$Settings)
    
    try {
        $task = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue
        if (!$task) { 
            [System.Windows.MessageBox]::Show("No scheduled task found: $($_.Exception.Message)", "Error", "OK", "Error")
            return 
        }
        
        # Get current triggers
        $currentTriggers = $task.Triggers
        $configChanged = $false

        # Check if LogOn trigger setting has changed (same logic as WAU-Policies)
        $hasLogonTrigger = $currentTriggers | Where-Object { $_.CimClass.CimClassName -eq "MSFT_TaskLogonTrigger" }
        if (($Settings.WAU_UpdatesAtLogon -eq 1 -and -not $hasLogonTrigger) -or 
            ($Settings.WAU_UpdatesAtLogon -ne 1 -and $hasLogonTrigger)) {
            $configChanged = $true
        }

        # Check if schedule type has changed (same logic as WAU-Policies)
        $currentIntervalType = "None"
        foreach ($trigger in $currentTriggers) {
            if ($trigger.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger" -and $trigger.DaysInterval -eq 1) {
                $currentIntervalType = "Daily"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskDailyTrigger" -and $trigger.DaysInterval -eq 2) {
                $currentIntervalType = "BiDaily"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 1) {
                $currentIntervalType = "Weekly"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 2) {
                $currentIntervalType = "BiWeekly"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskWeeklyTrigger" -and $trigger.WeeksInterval -eq 4) {
                $currentIntervalType = "Monthly"
                break
            }
            elseif ($trigger.CimClass.CimClassName -eq "MSFT_TaskTimeTrigger" -and [DateTime]::Parse($trigger.StartBoundary) -lt (Get-Date)) {
                $currentIntervalType = "Never"
                break
            }
        }

        if ($currentIntervalType -ne $Settings.WAU_UpdatesInterval) {
            $configChanged = $true
        }

        # Check if delay has changed (same logic as WAU-Policies)
        $randomDelay = [TimeSpan]::ParseExact($Settings.WAU_UpdatesTimeDelay, "hh\:mm", $null)
        $timeTrigger = $currentTriggers | Where-Object { $_.CimClass.CimClassName -ne "MSFT_TaskLogonTrigger" } | Select-Object -First 1
        if ($null -ne $timeTrigger -and $timeTrigger.RandomDelay -match '^PT(?:(\d+)H)?(?:(\d+)M)?$') {
            $hours = if ($matches[1]) { [int]$matches[1] } else { 0 }
            $minutes = if ($matches[2]) { [int]$matches[2] } else { 0 }
            $existingRandomDelay = New-TimeSpan -Hours $hours -Minutes $minutes
        }
        if ($existingRandomDelay -ne $randomDelay) {
            $configChanged = $true
        }

        # Check if schedule time has changed (same logic as WAU-Policies)
        if ($currentIntervalType -ne "None" -and $currentIntervalType -ne "Never") {
            if ($null -ne $timeTrigger -and $timeTrigger.StartBoundary) {
                $currentTime = [DateTime]::Parse($timeTrigger.StartBoundary).ToString("HH:mm:ss")
                if ($currentTime -ne $Settings.WAU_UpdatesAtTime) {
                    $configChanged = $true
                }
            }
        }

        # Only update triggers if configuration has changed (same logic as WAU-Policies)
        if ($configChanged) {
            
            # Build new triggers array (same logic as WAU-Policies)
            $taskTriggers = @()
            if ($Settings.WAU_UpdatesAtLogon -eq 1) {
                $taskTriggers += New-ScheduledTaskTrigger -AtLogOn
            }
            if ($Settings.WAU_UpdatesInterval -eq "Daily") {
                $taskTriggers += New-ScheduledTaskTrigger -Daily -At $Settings.WAU_UpdatesAtTime -RandomDelay $randomDelay
            }
            elseif ($Settings.WAU_UpdatesInterval -eq "BiDaily") {
                $taskTriggers += New-ScheduledTaskTrigger -Daily -At $Settings.WAU_UpdatesAtTime -DaysInterval 2 -RandomDelay $randomDelay
            }
            elseif ($Settings.WAU_UpdatesInterval -eq "Weekly") {
                $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $Settings.WAU_UpdatesAtTime -DaysOfWeek 2 -RandomDelay $randomDelay
            }
            elseif ($Settings.WAU_UpdatesInterval -eq "BiWeekly") {
                $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $Settings.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 2 -RandomDelay $randomDelay
            }
            elseif ($Settings.WAU_UpdatesInterval -eq "Monthly") {
                $taskTriggers += New-ScheduledTaskTrigger -Weekly -At $Settings.WAU_UpdatesAtTime -DaysOfWeek 2 -WeeksInterval 4 -RandomDelay $randomDelay
            }
            
            # If trigger(s) set
            if ($taskTriggers) {
                Set-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -Trigger $taskTriggers | Out-Null
            }
            # If not, remove trigger(s) by setting past due date
            else {
                $taskTriggers = New-ScheduledTaskTrigger -Once -At "01/01/1970"
                Set-ScheduledTask -TaskPath $task.TaskPath -TaskName $task.TaskName -Trigger $taskTriggers | Out-Null
            }
            
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to update scheduled task: $($_.Exception.Message)", "Error", "OK", "Error")
    }
}
function Set-WAUConfig {
    param(
        [hashtable]$Settings
    )
    
    try {
        # Get current configuration to compare
        $currentConfig = Get-WAUCurrentConfig
        
        # Only update registry values that have actually changed
        foreach ($key in $Settings.Keys) {
            # Skip shortcut-related settings for now - handle them separately
            if ($key -in @('WAU_StartMenuShortcut', 'WAU_AppInstallerShortcut', 'WAU_DesktopShortcut')) {
                continue
            }
            
            $currentValue = $currentConfig.$key
            $newValue = $Settings[$key]
            
            # Compare current value with new value
            if ($currentValue -ne $newValue) {
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name $key -Value $newValue -Force | Out-Null
            }
        }
        
        # Update scheduled task only if relevant settings changed
        $scheduleSettings = @('WAU_UpdatesInterval', 'WAU_UpdatesAtTime', 'WAU_UpdatesAtLogon', 'WAU_UpdatesTimeDelay')
        $scheduleChanged = $false
        foreach ($setting in $scheduleSettings) {
            if ($Settings.ContainsKey($setting) -and $currentConfig.$setting -ne $Settings[$setting]) {
                $scheduleChanged = $true
                break
            }
        }
        
        if ($scheduleChanged) {
            Update-WAUScheduledTask -Settings $Settings
        }

        # Handle Start Menu shortcuts
        if ($Settings.ContainsKey('WAU_StartMenuShortcut')) {
            $currentStartMenuSetting = $currentConfig.WAU_StartMenuShortcut
            $newStartMenuSetting = $Settings['WAU_StartMenuShortcut']
            
            if ($currentStartMenuSetting -ne $newStartMenuSetting) {
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_StartMenuShortcut' -Value $newStartMenuSetting -Force
                
                if ($newStartMenuSetting -eq 1) {
                    if (-not (Test-Path $Script:STARTMENU_WAU_DIR)) {
                        New-Item -Path $Script:STARTMENU_WAU_DIR -ItemType Directory | Out-Null
                    }
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\Run WAU.lnk" $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" "$Script:WAU_ICON" "Run Winget AutoUpdate" "Normal"
                    # Ensure logs directory and updates.log exist before creating shortcut
                    $logsDir = Join-Path $currentConfig.InstallLocation "logs"
                    $updatesLogPath = Join-Path $logsDir "updates.log"
                    if (-not (Test-Path $logsDir)) {
                        New-Item -Path $logsDir -ItemType Directory -Force | Out-Null
                    }
                    if (-not (Test-Path $updatesLogPath)) {
                        New-Item -Path $updatesLogPath -ItemType File -Force | Out-Null
                    }
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\Open log.lnk" $updatesLogPath "" "" "" "Open WAU log" "Normal"
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\Open Logs.lnk" $logsDir "" "" "" "Open WAU Logs Directory" "Normal"
                    Add-Shortcut "$Script:STARTMENU_WAU_DIR\WAU App Installer.lnk" $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Installer-GUI.ps1`"" "$Script:WAU_ICON" "Search for and Install WinGet Apps, etc..." "Normal"
                    if (-not $Script:PORTABLE_MODE) {
                        Add-Shortcut "$Script:STARTMENU_WAU_DIR\$Script:GUI_TITLE.lnk" $Script:CONHOST_EXE "$($Script:WorkingDir)" "$Script:POWERSHELL_ARGS `"$((Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'))`"" "$Script:GUI_ICON" "Configure Winget-AutoUpdate settings after installation" "Normal" $true
                    }
                }
                else {
                    if (Test-Path $Script:STARTMENU_WAU_DIR) {
                        Remove-Item -Path $Script:STARTMENU_WAU_DIR -Recurse -Force
                    }
                    
                    # Create desktop shortcut for WAU Settings if Start Menu shortcuts are removed
                    if (-not $Script:PORTABLE_MODE -and -not (Test-Path $Script:DESKTOP_WAU_SETTINGS)) {
                        Add-Shortcut $Script:DESKTOP_WAU_SETTINGS $Script:CONHOST_EXE "$($Script:WorkingDir)" "$Script:POWERSHELL_ARGS `"$((Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'))`"" "$Script:GUI_ICON" "Configure Winget-AutoUpdate settings after installation" "Normal" $true
                    }
                }
            }
        }

        # Handle App Installer shortcut
        if ($Settings.ContainsKey('WAU_AppInstallerShortcut')) {
            $currentAppInstallerSetting = $currentConfig.WAU_AppInstallerShortcut
            $newAppInstallerSetting = $Settings['WAU_AppInstallerShortcut']
            
            if ($currentAppInstallerSetting -ne $newAppInstallerSetting) {
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_AppInstallerShortcut' -Value $newAppInstallerSetting -Force
                
                if ($newAppInstallerSetting -eq 1) {
                    Add-Shortcut $Script:DESKTOP_WAU_APPINSTALLER $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)WAU-Installer-GUI.ps1`"" "$Script:WAU_ICON" "Search for and Install WinGet Apps, etc..." "Normal"
                }
                else {
                    if (Test-Path $Script:DESKTOP_WAU_APPINSTALLER) {
                        Remove-Item -Path $Script:DESKTOP_WAU_APPINSTALLER -Force
                    }
                }
            }
        }

        # Handle Desktop shortcut
        if ($Settings.ContainsKey('WAU_DesktopShortcut')) {
            $currentDesktopSetting = $currentConfig.WAU_DesktopShortcut
            $newDesktopSetting = $Settings['WAU_DesktopShortcut']
            
            if ($currentDesktopSetting -ne $newDesktopSetting) {
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_DesktopShortcut' -Value $newDesktopSetting -Force
                
                if ($newDesktopSetting -eq 1) {
                    Add-Shortcut $Script:DESKTOP_RUN_WAU $Script:CONHOST_EXE "$($currentConfig.InstallLocation)" "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" "$Script:WAU_ICON" "Winget AutoUpdate" "Normal"
                }
                else {
                    if (Test-Path $Script:DESKTOP_RUN_WAU) {
                        Remove-Item -Path $Script:DESKTOP_RUN_WAU -Force
                    }
                }
            }
        }

        # Remove WAU Settings desktop shortcut if Start Menu is created (only if WAU Settings Start menu shortcut exists)
        if ($Settings.ContainsKey('WAU_StartMenuShortcut') -and $Settings['WAU_StartMenuShortcut'] -eq 1) {
            $startMenuShortcutPath = "$Script:STARTMENU_WAU_DIR\$Script:GUI_TITLE.lnk"
            if (Test-Path $startMenuShortcutPath) {
                if (Test-Path $Script:DESKTOP_WAU_SETTINGS) {
                    Remove-Item -Path $Script:DESKTOP_WAU_SETTINGS -Force
                }
            }
            
            # Also remove Run WAU desktop shortcut if Start Menu is created and Desktop shortcuts are disabled
            if ($Settings.ContainsKey('WAU_DesktopShortcut') -and $Settings['WAU_DesktopShortcut'] -eq 0) {
                if (Test-Path $Script:DESKTOP_RUN_WAU) {
                    Remove-Item -Path $Script:DESKTOP_RUN_WAU -Force
                }
            }
        }

        # Mirror actual desktop shortcut status to registry
        $actualShortcutExists = Test-Path $Script:DESKTOP_RUN_WAU
        $currentDesktopSetting = $currentConfig.WAU_DesktopShortcut
        $correctRegistryValue = if ($actualShortcutExists) { 1 } else { 0 }
        
        if ($currentDesktopSetting -ne $correctRegistryValue) {
            Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name 'WAU_DesktopShortcut' -Value $correctRegistryValue -Force
        }
        
        return $true
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to save configuration: $($_.Exception.Message)", "Error", "OK", "Error")
        return $false
    }
}

# 3. WAU operation functions (depends on config functions)
function New-MSITransformFromControls {
    param(
        [string]$msiFilePath,
        $controls,
        [bool]$createFiles = $false
    )
    
    try {
        # Create a Windows Installer object
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($msiFilePath, 0))
        
        # Extract Properties from MSI
        $properties = @('ProductName', 'ProductVersion', 'ProductCode')
        $views = @{}
        $values = @{}
        
        # Create and execute views
        foreach ($prop in $properties) {
            $views[$prop] = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, "SELECT Value FROM Property WHERE Property = '$prop'")
            $views[$prop].GetType().InvokeMember("Execute", "InvokeMethod", $null, $views[$prop], $null)
            
            # Fetch and extract value
            $record = $views[$prop].GetType().InvokeMember("Fetch", "InvokeMethod", $null, $views[$prop], $null)
            $values[$prop] = if ($record) {
                $value = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($record) | Out-Null
                $value
            } else { $null }
            
            # Close and release view
            $views[$prop].GetType().InvokeMember("Close", "InvokeMethod", $null, $views[$prop], $null)
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($views[$prop]) | Out-Null
        }
        
        # Assign variables
        $name = $values['ProductName']
        $version = $values['ProductVersion'] 
        $guid = $values['ProductCode']
        
        if (-not $guid) {
            throw "Could not extract Product Code from the MSI file"
        }
        
        # Create transform file name
        $transformName = if ($createFiles) {
            if ($Script:GUI_TITLE -match '^(.+?)\s*\(') {
                $matches[1].Trim() + '.mst'
            } else {
                $Script:GUI_TITLE.Trim() + '.mst'
            }
        } else {
            [System.IO.Path]::GetTempFileName() + ".mst"
        }
        
        # Get directory for transform
        $msiDirectory = if ($createFiles) {
            [System.IO.Path]::GetDirectoryName($msiFilePath)
        } else {
            [System.IO.Path]::GetTempPath()
        }
        $transformPath = [System.IO.Path]::Combine($msiDirectory, $transformName)
        
        # Create a copy of the MSI to modify
        $tempFile = [System.IO.Path]::GetTempFileName()
        Copy-Item $msiFilePath $tempFile -Force
        $modifiedDb = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($tempFile, 1))
        
        # Collect all properties from form controls
        $properties = @{
            'REBOOT' = 'R'  # Always set REBOOT=R
        }
        
        # Map control values to MSI properties (ALL PROPERTIES IN UPPERCASE)
        
        # ComboBox selections
        $properties['UPDATESINTERVAL'] = if ($controls.UpdateIntervalComboBox.SelectedItem) { 
            $controls.UpdateIntervalComboBox.SelectedItem.Tag 
        } else { 
            'Never'  # Default value
        }
        
        $properties['NOTIFICATIONLEVEL'] = if ($controls.NotificationLevelComboBox.SelectedItem) { 
            $controls.NotificationLevelComboBox.SelectedItem.Tag 
        } else { 
            'Full'  # Default value
        }
        
        # Time settings
        $hour = "{0:D2}" -f ($controls.UpdateTimeHourComboBox.SelectedIndex + 1)
        $minute = "{0:D2}" -f ($controls.UpdateTimeMinuteComboBox.SelectedIndex)
        $properties['UPDATESATTIME'] = "$hour`:$minute`:00"

        $hour = "{0:D2}" -f ($controls.RandomDelayHourComboBox.SelectedIndex)
        $minute = "{0:D2}" -f ($controls.RandomDelayMinuteComboBox.SelectedIndex)
        $properties['UPDATESATTIMEDELAY'] = "$hour`:$minute"

        # Path settings
        $properties['LISTPATH'] = if (![string]::IsNullOrWhiteSpace($controls.ListPathTextBox.Text)) {
            $controls.ListPathTextBox.Text
        } else {
            ""
        }

        $properties['MODSPATH'] = if (![string]::IsNullOrWhiteSpace($controls.ModsPathTextBox.Text)) {
            $controls.ModsPathTextBox.Text
        } else {
            ""
        }

        $properties['AZUREBLOBSASURL'] = if (![string]::IsNullOrWhiteSpace($controls.AzureBlobSASURLTextBox.Text)) {
            $controls.AzureBlobSASURLTextBox.Text
        } else {
            ""
        }
        
        # Checkbox properties
        $properties['DISABLEWAUAUTOUPDATE'] = if ($controls.DisableWAUAutoUpdateCheckBox.IsChecked) { '1' } else { '0' }
        $properties['UPDATEPRERELEASE'] = if ($controls.UpdatePreReleaseCheckBox.IsChecked) { '1' } else { '0' }
        $properties['DONOTRUNONMETERED'] = if ($controls.DoNotRunOnMeteredCheckBox.IsChecked) { '1' } else { '0' }
        $properties['STARTMENUSHORTCUT'] = if ($controls.StartMenuShortcutCheckBox.IsChecked) { '1' } else { '0' }
        $properties['DESKTOPSHORTCUT'] = if ($controls.DesktopShortcutCheckBox.IsChecked) { '1' } else { '0' }
        $properties['APPINSTALLERSHORTCUT'] = if ($controls.AppInstallerShortcutCheckBox.IsChecked) { '1' } else { '0' }
        $properties['UPDATESATLOGON'] = if ($controls.UpdatesAtLogonCheckBox.IsChecked) { '1' } else { '0' }
        $properties['USERCONTEXT'] = if ($controls.UserContextCheckBox.IsChecked) { '1' } else { '0' }
        $properties['BYPASSLISTFORUSERS'] = if ($controls.BypassListForUsersCheckBox.IsChecked) { '1' } else { '0' }
        $properties['USEWHITELIST'] = if ($controls.UseWhiteListCheckBox.IsChecked) { '1' } else { '0' }
        
        # Log settings
        $properties['MAXLOGFILES'] = if ($controls.MaxLogFilesComboBox.SelectedItem) {
            $controls.MaxLogFilesComboBox.SelectedItem.Content
        } else {
            '3'
        }
        
        $properties['MAXLOGSIZE'] = if ($controls.MaxLogSizeComboBox.SelectedItem -and $controls.MaxLogSizeComboBox.SelectedItem.Tag) {
            $controls.MaxLogSizeComboBox.SelectedItem.Tag
        } elseif (![string]::IsNullOrWhiteSpace($controls.MaxLogSizeComboBox.Text)) {
            $controls.MaxLogSizeComboBox.Text
        } else {
            '1048576'
        }
        
        # Add/Update all properties in the modified database
        foreach ($propName in $properties.Keys) {
            $propValue = $properties[$propName]
            
            if ([string]::IsNullOrEmpty($propValue)) {
                $propValue = ""
            }
            
            try {
                # Try INSERT first, then UPDATE if it fails
                $insertView = $modifiedDb.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $modifiedDb, "INSERT INTO Property (Property, Value) VALUES ('$propName', '$propValue')")
                try {
                    $insertView.GetType().InvokeMember("Execute", "InvokeMethod", $null, $insertView, $null)
                }
                catch {
                    # Property might already exist, try UPDATE instead
                    $insertView.GetType().InvokeMember("Close", "InvokeMethod", $null, $insertView, $null)
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($insertView) | Out-Null
                    
                    $updateView = $modifiedDb.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $modifiedDb, "UPDATE Property SET Value = '$propValue' WHERE Property = '$propName'")
                    $updateView.GetType().InvokeMember("Execute", "InvokeMethod", $null, $updateView, $null)
                    $updateView.GetType().InvokeMember("Close", "InvokeMethod", $null, $updateView, $null)
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($updateView) | Out-Null
                    continue
                }
                $insertView.GetType().InvokeMember("Close", "InvokeMethod", $null, $insertView, $null)
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($insertView) | Out-Null
            }
            catch {
                Write-Warning "Failed to set property $propName = $propValue"
            }
        }
        
        # Commit changes to modified database
        $modifiedDb.GetType().InvokeMember("Commit", "InvokeMethod", $null, $modifiedDb, $null)
        
        # Generate transform between original and modified databases
        $modifiedDb.GetType().InvokeMember("GenerateTransform", "InvokeMethod", $null, $modifiedDb, @($database, $transformPath))
        
        # Create transform summary info to make it valid
        $modifiedDb.GetType().InvokeMember("CreateTransformSummaryInfo", "InvokeMethod", $null, $modifiedDb, @($database, $transformPath, 0, 0))
        
        # Create additional files if requested
        if ($createFiles) {
            # Copy GUID to clipboard
            Set-Clipboard -Value $guid
            
            # Sort properties for display
            $propertyOrder = @(
                'UPDATESINTERVAL', 'NOTIFICATIONLEVEL', 'UPDATESATTIME', 'UPDATESATTIMEDELAY',
                'LISTPATH', 'MODSPATH', 'AZUREBLOBSASURL',
                'DISABLEWAUAUTOUPDATE', 'UPDATEPRERELEASE', 'DONOTRUNONMETERED',
                'STARTMENUSHORTCUT', 'DESKTOPSHORTCUT', 'APPINSTALLERSHORTCUT',
                'UPDATESATLOGON', 'USERCONTEXT', 'BYPASSLISTFORUSERS', 'USEWHITELIST',
                'MAXLOGFILES', 'MAXLOGSIZE', 'REBOOT'
            )
            
            $propertiesSummary = ($propertyOrder | ForEach-Object {
                if ($properties.ContainsKey($_)) {
                    if ($properties[$_] -eq "") {
                        "$_=(empty)"
                    } else {
                        "$_=$($properties[$_])"
                    }
                }
            }) -join "`n"

            # Create Install.cmd
            $cmdFileName = "Install.cmd"
            $cmdFilePath = [System.IO.Path]::Combine($msiDirectory, $cmdFileName)
            $msiFileName = [System.IO.Path]::GetFileName($msiFilePath)
            $logFileName = [System.IO.Path]::GetFileNameWithoutExtension($transformName) + ".log"
            $cmdContent = @"
::MSI detection for $($version): $($guid)
::Detection for ANY version: $($Script:WAU_REGISTRY_PATH),  Value Name: ProductVersion, Detection Method: Value exists

msiexec /i "%~dp0$msiFileName" TRANSFORMS="%~dp0$transformName" /qn /l*v "%~dp0Inst-$logFileName"
"@
            Set-Content -Path $cmdFilePath -Value $cmdContent -Encoding ASCII

            # Create Uninstall.cmd
            $cmdFileName = "Uninstall.cmd"
            $cmdFilePath = [System.IO.Path]::Combine($msiDirectory, $cmdFileName)
            $cmdContent = @"
::Uninstall for $($version):
msiexec /x"$($guid)" REBOOT=R /qn /l*v "%~dp0Uninst-$logFileName"

::Uninstall for ANY version:
::powershell.exe -Command "Get-Package -Name "*Winget-AutoUpdate*" | Uninstall-Package -Force"
"@
            Set-Content -Path $cmdFilePath -Value $cmdContent -Encoding ASCII
            
            $message = "Transform file created successfully!`n`nTransform File: $transformName`nLocation: $transformPath`n`nInstall/Uninstall scripts created.`n`nProperties Set:`n$propertiesSummary`n`nProduct Name: $name`nProduct Version: $version`nProduct Code: $guid`n`nThe Product Code has been copied to your clipboard."
        } else {
            $message = "Transform created successfully for installation"
        }
        
        return @{
            Success = $true
            TransformPath = $transformPath
            Directory = $msiDirectory
            Message = $message
            GUID = $guid
            ProductName = $name
            ProductVersion = $version
        }
    }
    catch {
        return @{
            Success = $false
            Message = "Failed to create transform: $($_.Exception.Message)"
        }
    }
    finally {
        # Clean up temp file
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        
        # Clean up COM objects
        if ($modifiedDb) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($modifiedDb) | Out-Null }
        if ($database) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null }
        if ($installer) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer) | Out-Null }
    }
}
function Test-LocalMSIVersion {
    param(
        [string]$msiDirectory = (Join-Path $Script:WorkingDir "msi"),
        [string]$targetVersion = $null
    )
    
    try {
        # If no target version specified, try to get installed version
        if (-not $targetVersion) {
            try {
                if ($Script:WAU_GUID) {
                    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Script:WAU_GUID)"
                    $wauRegistry = Get-ItemProperty -Path $registryPath -ErrorAction Stop
                    
                    $comments = $wauRegistry.Comments
                    $displayVersion = $wauRegistry.DisplayVersion
                    
                    if ($comments -and $comments -ne "STABLE") {
                        if ($comments -match "WAU\s+([0-9]+\.[0-9]+\.[0-9]+(?:-\d+)?)(?:\s|\[)") {
                            $targetVersion = "v$($matches[1])"
                        }
                    } else {
                        $targetVersion = "v$($displayVersion -replace '\.\d+$', '')"
                    }
                }
            } catch {
                # Continue without target version
            }
        }
        
        # Look for MSI in version-specific folder
        $versionDir = if ($targetVersion) {
            Join-Path $msiDirectory $targetVersion.TrimStart('v')
        } else {
            $msiDirectory
        }
        
        if (-not (Test-Path $versionDir)) {
            return @{
                UpdateNeeded = $true
                Reason = "Version folder not found: $versionDir"
                LocalVersion = $null
                LatestVersion = $null
            }
        }
        
        # Find local MSI file
        $localMSI = Get-ChildItem -Path $versionDir -Filter "*.msi" -File | Select-Object -First 1
        if (-not $localMSI) {
            return @{
                UpdateNeeded = $true
                Reason = "No local MSI found in: $versionDir"
                LocalVersion = $null
                LatestVersion = $null
            }
        }
        
        # Extract version from local MSI
        $installer = New-Object -ComObject WindowsInstaller.Installer
        $database = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($localMSI.FullName, 0))
        
        $view = $database.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $database, "SELECT Value FROM Property WHERE Property = 'ProductVersion'")
        $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null)
        
        $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
        $localVersion = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
        
        # Clean up COM objects
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($record) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($view) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($database) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer) | Out-Null
        
        return @{
            UpdateNeeded = $false
            Reason = "Local MSI found and current"
            LocalVersion = $localVersion
            LatestVersion = $localVersion
            LocalMSIPath = $localMSI.FullName
        }
    }
    catch {
        return @{
            UpdateNeeded = $true
            Reason = "Error checking version: $($_.Exception.Message)"
            LocalVersion = $null
            LatestVersion = $null
        }
    }
}
function Get-WAUMsi {
    param(
        [switch]$ForceDownload,
        [string]$SpecificVersion  # Parameter for specific version
    )
    
    $msiDir = Join-Path $Script:WorkingDir "msi"
    if (!(Test-Path $msiDir)) {
        New-Item -ItemType Directory -Path $msiDir -Force | Out-Null
    }
    
    # Determine which version to download
    $targetVersion = $null
    $isPreRelease = $false
    
    if ($SpecificVersion) {
        $targetVersion = $SpecificVersion
    } else {
        # Try to get installed version from registry
        try {
            if ($Script:WAU_GUID) {
                $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Script:WAU_GUID)"
                $wauRegistry = Get-ItemProperty -Path $registryPath -ErrorAction Stop
                
                $comments = $wauRegistry.Comments
                $displayVersion = $wauRegistry.DisplayVersion
                
                # Determine version string like AHK code
                if ($comments -and $comments -ne "STABLE") {
                    $isPreRelease = $true
                    # Extract version number from Comments if not "STABLE"
                    # Example: "WAU 2.7.0-0 [Nightly Build]" -> "v2.7.0-0"
                    if ($comments -match "WAU\s+([0-9]+\.[0-9]+\.[0-9]+(?:-\d+)?)(?:\s|\[)") {
                        $targetVersion = "v$($matches[1])"
                    } else {
                        $targetVersion = "v$displayVersion"
                    }
                } else {
                    # Remove last dot and numbers for STABLE version
                    $targetVersion = "v$($displayVersion -replace '\.\d+$', '')"
                }
                
                Write-Host "Using installed version: $targetVersion $(if($isPreRelease){'(Pre-release)'}else{'(Stable)'})"
            }
        } catch {
            Write-Host "Could not determine installed version, using latest stable"
            # Fallback to latest stable
        }
    }
    
    # Create version folder
    $versionDir = if ($targetVersion) {
        Join-Path $msiDir $targetVersion.TrimStart('v')
    } else {
        Join-Path $msiDir "latest"
    }
    
    if (!(Test-Path $versionDir)) {
        New-Item -ItemType Directory -Path $versionDir -Force | Out-Null
    }
    
    try {
        if ($targetVersion) {
            # Handle specific version
            $expectedMsiName = "WAU-$targetVersion.msi"
            $localMsiPath = Join-Path $versionDir $expectedMsiName
            
            # Check cache for specific version
            if ((Test-Path $localMsiPath) -and -not $ForceDownload) {
                return @{
                    MsiAsset = @{ name = $expectedMsiName }
                    MsiFilePath = $localMsiPath
                    VersionInfo = "Using cached MSI: $targetVersion"
                    IsPreRelease = $isPreRelease
                }
            }
            
            # Download specific version
            $downloadUrl = "https://github.com/$Script:WAU_REPO/releases/download/$targetVersion/WAU.msi"
            Start-PopUp "Downloading WAU $targetVersion..."
            
        } else {
            # Handle latest version - check online first to get correct filename
            $ApiUrl = "https://api.github.com/repos/$Script:WAU_REPO/releases/latest"
            $Release = Invoke-RestMethod -Uri $ApiUrl -UseBasicParsing
            $MsiAsset = $Release.assets | Where-Object { $_.name -like "*.msi" }
            if (!$MsiAsset) {
                throw "MSI file not found in latest release"
            }
            
            $expectedMsiName = $MsiAsset.name
            $localMsiPath = Join-Path $versionDir $expectedMsiName
            $downloadUrl = $MsiAsset.browser_download_url
            
            # Check cache with correct filename
            if ((Test-Path $localMsiPath) -and -not $ForceDownload) {
                return @{
                    MsiAsset = @{ name = $expectedMsiName }
                    MsiFilePath = $localMsiPath
                    VersionInfo = "Using cached MSI: latest ($expectedMsiName)"
                    IsPreRelease = $false
                }
            }
            
            Start-PopUp "Downloading latest WAU: $($MsiAsset.name)..."
        }
        
        Invoke-WebRequest -Uri $downloadUrl -OutFile $localMsiPath -UseBasicParsing
        Close-PopUp
        
        return @{
            MsiAsset = @{ name = $expectedMsiName }
            MsiFilePath = $localMsiPath
            VersionInfo = "Downloaded: $(if ($targetVersion) { $targetVersion } else { "latest ($expectedMsiName)" })"
            IsPreRelease = $isPreRelease
        }
    }
    catch {
        Close-PopUp
        [System.Windows.MessageBox]::Show("Failed to download WAU: $($_.Exception.Message)", "Error", "OK", "Error")
        return $null
    }
}
function Install-WAU {
    param(
        [string]$msiFilePath,
        $controls
    )
    
    try {
        if (-not (Test-Path $msiFilePath)) {
            throw "MSI file not found: $msiFilePath"
        }
        
        # Check if we're in main application context
        if ($Script:MainWindowStarted -and $controls) {
            # If in main window context; create transform from current settings and start installation
            $transformResult = New-MSITransformFromControls -msiFilePath $msiFilePath -controls $controls -createFiles $false
            
            if ($transformResult.Success) {
                # Start installation process with transform
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiFilePath`" TRANSFORMS=`"$($transformResult.TransformPath)`" /qb" -Wait
            } else {
                throw "Failed to create transform: $($transformResult.Message)"
            }
        } else {
            # If not in main window context; Start installation process with default settings
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiFilePath`" /qb" -Wait
        }                    
        
        # Check if installation was successful
        $Script:WAU_INSTALL_INFO = Test-InstalledWAU -DisplayName "Winget-AutoUpdate"
        if ($Script:WAU_INSTALL_INFO.Count -ge 1) {
            [System.Windows.MessageBox]::Show("WAU installed successfully! Please configure the new installation.", "Installation Complete", "OK", "Information")

            # Get WAU installation info and store as constants
            $Script:WAU_VERSION = if ($Script:WAU_INSTALL_INFO.Count -ge 1) { $Script:WAU_INSTALL_INFO[0] } else { "Unknown" }
            $Script:WAU_GUID = if ($Script:WAU_INSTALL_INFO.Count -ge 2) { $Script:WAU_INSTALL_INFO[1] } else { $null }
            $wauIconPath = "${env:SystemRoot}\Installer\${Script:WAU_GUID}\icon.ico"
            if (Test-Path $wauIconPath) {
                $Script:WAU_ICON = $wauIconPath
            }

            # Reload configuration after successful installation
            if ($Script:MainWindowStarted -and $controls) {
                Update-WAUGUIFromConfig -Controls $controls 
            }

            return $true
        } else {
            [System.Windows.MessageBox]::Show("Installation may have failed. Please check the installation manually.", "Installation Status Unknown", "OK", "Warning")
            return $false
        }
    } 
    catch {
        Close-PopUp
        [System.Windows.MessageBox]::Show("Failed to install WAU: $($_.Exception.Message)", "Installation Failed", "OK", "Error")
        return $false
    }
}
function Uninstall-WAU {
    try {
        # Check if WAU is installed
        $installedWAU = Test-InstalledWAU -DisplayName "Winget-AutoUpdate"
        if ($installedWAU.Count -eq 0) {
            [System.Windows.MessageBox]::Show("WAU is not installed.", "Uninstall WAU", "OK", "Information")
            return $false
        }
        
        Start-PopUp "Uninstalling WAU..."
        
        # Start uninstallation process
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/x `"$($installedWAU[1])`" /qb" -Wait
        # After uninstall, verify WAU is no longer installed
        $remainingWAU = Test-InstalledWAU -DisplayName "Winget-AutoUpdate"
        if ($remainingWAU.Count -ne 0) {
            throw "WAU is still detected as installed after uninstallation."
        }
        # Remove WAU Start Menu
        if (Test-Path $Script:STARTMENU_WAU_DIR) {
            Remove-Item -Path $Script:STARTMENU_WAU_DIR -Recurse -Force
        }
        # Create desktop shortcut for WAU Settings GUI if not already present
        if (-not $Script:PORTABLE_MODE -and -not (Test-Path $Script:DESKTOP_WAU_SETTINGS)) {
            Add-Shortcut $Script:DESKTOP_WAU_SETTINGS $Script:CONHOST_EXE "$($Script:WorkingDir)" "$Script:POWERSHELL_ARGS `"$((Join-Path $Script:WorkingDir 'WAU-Settings-GUI.ps1'))`"" "$Script:GUI_ICON" "Configure Winget-AutoUpdate settings after installation" "Normal" $true
        }
        Close-PopUp
        
        return $true
    } 
    catch {
        Close-PopUp
        [System.Windows.MessageBox]::Show("Failed to uninstall WAU: $($_.Exception.Message)", "Uninstall Failed", "OK", "Error")
        return $false
    }
}
function New-WAUTransformFile {
    param($controls)
    try {
        # Get installed WAU version from registry (same as Dev [uid] button)
        $targetVersion = $null
        $isPreRelease = $false
        
        try {
            if ($Script:WAU_GUID) {
                $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Script:WAU_GUID)"
                $wauRegistry = Get-ItemProperty -Path $registryPath -ErrorAction Stop
                
                $comments = $wauRegistry.Comments
                $displayVersion = $wauRegistry.DisplayVersion
                
                # Determine version string like AHK code
                if ($comments -and $comments -ne "STABLE") {
                    $isPreRelease = $true
                    if ($comments -match "WAU\s+([0-9]+\.[0-9]+\.[0-9]+(?:-\d+)?)(?:\s|\[)") {
                        $targetVersion = "v$($matches[1])"
                    } else {
                        $targetVersion = "v$displayVersion"
                    }
                } else {
                    $targetVersion = "v$($displayVersion -replace '\.\d+$', '')"
                }
                
                Start-PopUp "Creating transform for installed WAU version: $targetVersion..."
            }
        } catch {
            Start-PopUp "Could not determine installed version, using latest..."
        }
        
        # Download/use correct MSI version
        $result = Get-WAUMsi -SpecificVersion $targetVersion
        if ($result) {
            $msiFilePath = $result.MsiFilePath
        }
        
        if (-not $msiFilePath -or -not (Test-Path $msiFilePath)) {
            throw "Failed to get MSI file for version: $targetVersion"
        }
        
        Close-PopUp
        Start-PopUp "Creating transform file..."
        
        # Use existing transform generation
        $transformResult = New-MSITransformFromControls -msiFilePath $msiFilePath -controls $controls -createFiles $true
        Close-PopUp
        
        if ($transformResult.Success) {
            $versionInfo = "Using WAU $targetVersion $(if($isPreRelease){'(Pre-release)'}else{'(Stable)'})"
            $fullMessage = "$($transformResult.Message)`n`n$versionInfo"
            [System.Windows.MessageBox]::Show($fullMessage, "Transform Created", "OK", "Information")
            Start-Process "explorer.exe" -ArgumentList $transformResult.Directory
        } else {
            [System.Windows.MessageBox]::Show($transformResult.Message, "Error", "OK", "Error")
        }
        
        return $true
    }
    catch {
        Close-PopUp
        [System.Windows.MessageBox]::Show("Failed to create transform: $($_.Exception.Message)", "Error", "OK", "Error")
        return $false
    }
}
function Start-WAUManually {
    try {
        $currentConfig = Get-WAUCurrentConfig
        $task = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction SilentlyContinue
        if ($task) {
            Start-Process -FilePath $Script:CONHOST_EXE `
                -ArgumentList "$Script:POWERSHELL_ARGS `"$($currentConfig.InstallLocation)$Script:USER_RUN_SCRIPT`"" `
                -ErrorAction Stop
        } else {
            Close-PopUp
            [System.Windows.MessageBox]::Show("WAU scheduled task not found!", "Error", "OK", "Error")
        }
    }
    catch {
        Close-PopUp
        [System.Windows.MessageBox]::Show("Failed to start WAU: $($_.Exception.Message)", "Error", "OK", "Error")
    }
}

# 4. GUI helper functions (depends on config functions)
function Hide-SensitiveText {
    param(
        [string]$originalText,
        [int]$visibleChars = 5
    )
    
    if ([string]::IsNullOrWhiteSpace($originalText) -or $originalText.Length -le ($visibleChars * 2)) {
        return $originalText
    }
    
    $start = $originalText.Substring(0, $visibleChars)
    $end = $originalText.Substring($originalText.Length - $visibleChars)
    $masked = "*" * [Math]::Max(1, $originalText.Length - ($visibleChars * 2))
    
    return "$start$masked$end"
}
function Get-ColoredStatusText {
    param(
        [string]$label, 
        [bool]$enabled, 
        [string]$enabledText = "Enabled", 
        [string]$disabledText = "Disabled"
    )
    
    $color = if ($enabled) { $Script:COLOR_ENABLED } else { $Script:COLOR_DISABLED }
    $status = if ($enabled) { $enabledText } else { $disabledText }
    return "{0}: <Run Foreground='{1}'>{2}</Run>" -f $label, $color, $status
}
function Test-ValidPathCharacter {
    param([string]$text, [string]$currentTextBoxValue = "")
    
    # Allow characters for paths and URLs: letters, digits, :, \, /, -, _, ., space, $, 'GPO', 'AzureBlob', and SAS URL characters (?, &, =, %)
    $isValidChar = $text -match '^[a-zA-Z0-9:\\/_.\s\-\$?&=%]*$'
    
    if (-not $isValidChar) {
        return $false
    }
    
    # Get WAU installation path to block
    try {
        $currentConfig = Get-WAUCurrentConfig
        $installLocation = $currentConfig.InstallLocation.TrimEnd('\')
        
        # Check if the proposed new text would contain the install location
        $proposedText = $currentTextBoxValue + $text
        if ($proposedText -like "*$installLocation*") {
            return $false
        }
    }
    catch {
        # If we can't get config, just allow the character
    }
    
    # For PreviewTextInput, we only check basic character validity and install location
    # We don't check for trailing slashes or filenames here since the user is still typing
    
    return $true
}
function Test-PathTextBox_PreviewTextInput {
    param($source, $e)
    
    # Get current text in the TextBox
    $currentText = $source.Text
    
    # Check if the input character is valid and doesn't create forbidden path
    if (-not (Test-ValidPathCharacter -text $e.Text -currentTextBoxValue $currentText)) {
        $e.Handled = $true  # Block the character
    }
}
function Test-PathTextBox_TextChanged {
    param($source, $e)
    
    try {
        $currentConfig = Get-WAUCurrentConfig
        $installLocation = $currentConfig.InstallLocation.TrimEnd('\')
        
        $hasError = $false
        $errorMessage = ""
        
        # Store original tooltip if not already stored
        if (-not $source.Tag) {
            $source.Tag = $source.ToolTip
        }
        
        # Empty is OK
        if ([string]::IsNullOrWhiteSpace($source.Text)) {
            $source.ClearValue([System.Windows.Controls.TextBox]::BorderBrushProperty)
            # Restore original tooltip
            $source.ToolTip = $source.Tag
            return
        }

        # Only allow "GPO" or "AzureBlob" as special values
        if ($source.Text -eq "GPO" -or $source.Text -eq "AzureBlob") {
            $source.ClearValue([System.Windows.Controls.TextBox]::BorderBrushProperty)
            $source.ToolTip = $source.Tag
            return
        }

        # Allow local paths (e.g. D:\Folder), UNC paths (\\server\share), or URLs (http/https)
        if (
            -not (
                $source.Text -match '^[a-zA-Z]:\\' -or
                $source.Text -match '^\\\\' -or
                $source.Text -match '^https?://'
            )
        ) {
            $source.BorderBrush = [System.Windows.Media.Brushes]::Red
            $source.ToolTip = "Only local paths, UNC paths, URLs, or the special values 'GPO' and 'AzureBlob' are allowed."
            return
        }

        # Check if current text contains the install location
        if ($source.Text -like "*$installLocation*") {
            $hasError = $true
            $errorMessage = "Cannot use WAU installation directory: $installLocation"
        }
        # For URLs, apply the same restrictions as local paths
        elseif ($source.Text -match '^https?://') {
            if ($source.Text.EndsWith('\') -or $source.Text.EndsWith('/')) {
                $hasError = $true
                $errorMessage = "URL cannot end with '\' or '/'"
            }
            else {
                $lastSegment = Split-Path -Leaf $source.Text
                if ($lastSegment -and $lastSegment.Contains('.')) {
                    $hasError = $true
                    $errorMessage = "URL cannot end with a filename (no dots allowed in final segment)"
                }
            }
        }
        # For non-URLs, apply local path restrictions
        elseif ($source.Text.EndsWith('\') -or $source.Text.EndsWith('/')) {
            $hasError = $true
            $errorMessage = "Path cannot end with '\' or '/'"
        }
        # Check if path ends with a filename (contains dot in last segment)
        else {
            $lastSegment = Split-Path -Leaf $source.Text
            if ($lastSegment -and $lastSegment.Contains('.')) {
                $hasError = $true
                $errorMessage = "Path cannot end with a filename (no dots allowed in final segment)"
            }
        }
        
        if ($hasError) {
            $source.BorderBrush = [System.Windows.Media.Brushes]::Red
            $source.ToolTip = $errorMessage
        } else {
            $source.ClearValue([System.Windows.Controls.TextBox]::BorderBrushProperty)
            # Restore original tooltip
            $source.ToolTip = $source.Tag
        }
    }
    catch {
        # If we can't get config, clear any error styling
        $source.ClearValue([System.Windows.Controls.TextBox]::BorderBrushProperty)
        # Restore original tooltip if available
        if ($source.Tag) {
            $source.ToolTip = $source.Tag
        } else {
            $source.ClearValue([System.Windows.Controls.TextBox]::ToolTipProperty)
        }
    }
}
function Test-PathValue {
    param([string]$path)

    if ([string]::IsNullOrWhiteSpace($path)) {
        return $true  # Empty paths are allowed
    }

    # Allow special values "GPO" and "AzureBlob"
    if ($path -eq "GPO" -or $path -eq "AzureBlob") {
        return $true
    }

    try {
        $currentConfig = Get-WAUCurrentConfig
        $installLocation = $currentConfig.InstallLocation.TrimEnd('\')

        # Check if path contains WAU install location
        if ($path -like "*$installLocation*") {
            return $false
        }
    }
    catch {
        # If we can't get config, allow the path
    }

    # URL validation (must not end with / or \, and last segment must not contain dot)
    if ($path -match '^https?://') {
        if ($path.EndsWith('\') -or $path.EndsWith('/')) {
            return $false
        }
        $lastSegment = Split-Path -Leaf $path
        if ($lastSegment -and $lastSegment.Contains('.')) {
            return $false
        }
        return $true
    }

    # UNC and local path validation (must not end with / or \, and last segment must not contain dot)
    if ($path -match '^[a-zA-Z]:\\' -or $path -match '^\\\\') {
        if ($path.EndsWith('\') -or $path.EndsWith('/')) {
            return $false
        }
        $lastSegment = Split-Path -Leaf $path
        if ($lastSegment -and $lastSegment.Contains('.')) {
            return $false
        }
        return $true
    }

    # Otherwise, not valid
    return $false
}
function Update-StatusDisplay {
    param($controls)

    $interval = $controls.UpdateIntervalComboBox.SelectedItem.Tag
    if ($interval -eq "Never") {
        $controls.StatusText.Text = "Disabled"
        $controls.StatusText.Foreground = "Red"
        $controls.StatusDescription.Text = "WAU will not check for updates"
        $controls.UpdateTimeHourComboBox.IsEnabled = $false
        $controls.UpdateTimeMinuteComboBox.IsEnabled = $false
        $controls.RandomDelayHourComboBox.IsEnabled = $false
        $controls.RandomDelayMinuteComboBox.IsEnabled = $false
    } else {
        $controls.StatusText.Text = "Enabled"
        $controls.StatusText.Foreground = "Green"
        $controls.StatusDescription.Text = "WAU will check for updates"
        $controls.UpdateTimeHourComboBox.IsEnabled = $true
        $controls.UpdateTimeMinuteComboBox.IsEnabled = $true
        $controls.RandomDelayHourComboBox.IsEnabled = $true
        $controls.RandomDelayMinuteComboBox.IsEnabled = $true
    }
}
function Set-ControlsState {
    param(
        $parentControl,
        [bool]$enabled = $true,
        [string]$excludePattern = $null
    )

    $alwaysEnabledControls = @(
        'ScreenshotButton', 'SaveButton', 'CancelButton', 'RunNowButton', 'OpenLogsButton', 'GUIPng',
        'DevGPOButton', 'DevTaskButton', 'DevRegButton', 'DevGUIDButton', 'DevSysButton', 'DevListButton',
        'DevUsrButton', 'DevMSIButton', 'DevVerButton', 'DevSrcButton', 'VersionLinksTextBlock'
    )

    function Get-Children($control) {
        if ($null -eq $control) { return @() }
        $children = @()
        if ($control -is [System.Windows.Controls.Panel]) {
            $children = $control.Children
        } elseif ($control -is [System.Windows.Controls.ContentControl]) {
            if ($control.Content -and $control.Content -isnot [string]) {
                $children = @($control.Content)
            }
        } elseif ($control -is [System.Windows.Controls.ItemsControl]) {
            $children = $control.Items
        }
        return $children
    }

    function Test-ExceptionChild($control) {
        $children = Get-Children $control
        foreach ($child in $children) {
            $childName = $null
            try { $childName = $child.GetValue([System.Windows.FrameworkElement]::NameProperty) } catch {}
            if (
                ($childName -and $childName -in $alwaysEnabledControls) -or
                ($excludePattern -and $childName -and $childName -like "*$excludePattern*")
            ) {
                return $true
            }
            if (Test-ExceptionChild $child) { return $true }
        }
        return $false
    }

    $hasException = Test-ExceptionChild $parentControl

    # Only set IsEnabled=$false if there are NO exceptions in the child tree
    if ($parentControl -is [System.Windows.Controls.Control] -and $parentControl.GetType().Name -ne 'Window') {
        if ($hasException) {
            $parentControl.IsEnabled = $true
        } else {
            $parentControl.IsEnabled = $enabled
        }
    }

    $children = Get-Children $parentControl
    foreach ($control in $children) {
        $controlName = $null
        try { $controlName = $control.GetValue([System.Windows.FrameworkElement]::NameProperty) } catch {}

        $isAlwaysEnabled = $controlName -and $controlName -in $alwaysEnabledControls
        $isExcluded = $excludePattern -and $controlName -and $controlName -like "*$excludePattern*"

        if ($isAlwaysEnabled -or $isExcluded) {
            if ($control -is [System.Windows.Controls.Control]) {
                $control.IsEnabled = $true
            }
            Set-ControlsState -parentControl $control -enabled $true -excludePattern $excludePattern
        } else {
            Set-ControlsState -parentControl $control -enabled $enabled -excludePattern $excludePattern
        }
    }
}
function Update-MaxLogSizeState {
    param($controls)

    $selectedValue = $controls.MaxLogFilesComboBox.SelectedItem.Content
    if ($selectedValue -eq "1") {
        $controls.MaxLogSizeComboBox.IsEnabled = $false
        $controls.MaxLogSizeComboBox.SelectedIndex = 0  # Reset to 1 MB default
    } else {
        $controls.MaxLogSizeComboBox.IsEnabled = $true
    }
}
function Update-PreReleaseCheckBoxState {
    param($controls)

    if ($controls.DisableWAUAutoUpdateCheckBox.IsChecked) {
        $controls.UpdatePreReleaseCheckBox.IsChecked = $false
        $controls.UpdatePreReleaseCheckBox.IsEnabled = $false
    } else {
        $controls.UpdatePreReleaseCheckBox.IsEnabled = $true
    }
}
function Update-GPOManagementState {
    param($controls, $skipPopup = $false)
    
    # Get updated policies
    $updatedPolicies = $null
    try {
        $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
    }
    catch {
        # GPO registry key doesn't exist or can't be read
    }

    #  Check if GPO management is active
    $gpoControlsActive = ($null -ne $updatedPolicies)
    
    if ($gpoControlsActive) {
         # Show popup only if not skipped (i.e., when window first opens)
        if (-not $skipPopup) {
            # Update status bar to show GPO is controlling settings
            $controls.StatusBarText.Text = "Managed by GPO"
            $controls.StatusBarText.Foreground = $Script:COLOR_ACTIVE
            
            # Show popup when GPO is controlling settings with delay to ensure main window is visible first
            $controls.StatusBarText.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds ($Script:WAIT_TIME / 2)  # Small delay to ensure main window is rendered
                Start-PopUp "Only Shortcut Settings can be modified when GPO Management is active..."
                
                # Close the popup after showing it for 2 standard wait times
                Start-Sleep -Milliseconds ($Script:WAIT_TIME * 2)
                Close-PopUp
            }) | Out-Null
        }

        # Disable all except Shortcut controls
        Set-ControlsState -parentControl $window -enabled $false -excludePattern "*Shortcut*"

        # Enable DevGPOButton when GPO is active
        $controls.DevGPOButton.IsEnabled = $true

    } else {
        # Enable all controls
        Set-ControlsState -parentControl $window -enabled $true

        # Disable DevGPOButton when GPO is not active
        $controls.DevGPOButton.IsEnabled = $false

        # Reset status bar if it was showing GPO message
        if ($controls.StatusBarText.Text -eq "Managed by GPO") {
            $controls.StatusBarText.Text = $Script:STATUS_READY_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_INACTIVE
        }

        # Make sure any popup is closed when GPO is not active
        try {
            if ($null -ne $Script:PopUpWindow) {
                Close-PopUp
            }
        }
        catch {
            # Popup might already be closed
        }
        
        # Re-apply other state updates
        Update-StatusDisplay -Controls $controls
        Update-MaxLogSizeState -Controls $controls
        Update-PreReleaseCheckBoxState -Controls $controls
    }
    
    return $gpoControlsActive
}
function Update-WAUGUIFromConfig {
    param($controls)
    
    # Get updated config and policies
    $updatedConfig = Get-WAUCurrentConfig
    $updatedPolicies = $null
    try {
        $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
    }
    catch {
        # GPO registry key doesn't exist or can't be read
    }

    $wauGPOListPathEnabled = ($updatedPolicies.WAU_ListPath -eq "GPO")
    $gpoControlsActive = ($null -ne $updatedPolicies)

    # Update Notification Level
    $notifLevel = Get-DisplayValue -PropertyName "WAU_NotificationLevel" -Config $updatedConfig -Policies $updatedPolicies
    $Controls.NotificationLevelComboBox.SelectedIndex = switch ($notifLevel) {
        "Full" { 0 }
        "SuccessOnly" { 1 }
        "ErrorsOnly" { 2 }
        "None" { 3 }
        default { 0 }
    }
    
    # Update Update Interval
    $updateInterval = Get-DisplayValue -PropertyName "WAU_UpdatesInterval" -Config $updatedConfig -Policies $updatedPolicies
    $Controls.UpdateIntervalComboBox.SelectedIndex = switch ($updateInterval) {
        "Daily" { 0 }
        "BiDaily" { 1 }
        "Weekly" { 2 }
        "BiWeekly" { 3 }
        "Monthly" { 4 }
        "Never" { 5 }
        default { 5 }
    }
    
    # Update time and delay
    $updateTime = (Get-DisplayValue -PropertyName "WAU_UpdatesAtTime" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    # Get the first 2 characters (hours), convert to int, subtract 1, and set as SelectedIndex
    $hourIndex = [int]$updateTime.Substring(0,2) - 1
    if ($hourIndex -ge 0 -and $hourIndex -lt $controls.UpdateTimeHourComboBox.Items.Count) {
        $controls.UpdateTimeHourComboBox.SelectedIndex = $hourIndex
    } else {
        $controls.UpdateTimeHourComboBox.SelectedIndex = 5  # fallback to 06
    }
    # Get the 4-5 characters (minutes), convert to int, and set as SelectedIndex
    $minuteIndex = [int]$updateTime.Substring(3,2)
    if ($minuteIndex -ge 0 -and $minuteIndex -lt $controls.UpdateTimeMinuteComboBox.Items.Count) {
        $controls.UpdateTimeMinuteComboBox.SelectedIndex = $minuteIndex
    } else {
        $controls.UpdateTimeMinuteComboBox.SelectedIndex = 0  # fallback to 00
    }

    # Special case: 'WAU_UpdatesTimeDelay' isn't in the wild yet, so we handle it separately
    $randomDelayValue = Get-DisplayValue -PropertyName "WAU_UpdatesTimeDelay" -Config $updatedConfig -Policies $updatedPolicies
    $randomDelay = if ($null -ne $randomDelayValue) { $randomDelayValue.ToString() } else { "" }
    if ($null -eq $randomDelay -or $randomDelay -eq "" -or $randomDelay.Length -lt 5) {
        $randomDelay = "00:00"
    }
    # Get the first 2 characters (hours), convert to int and set as SelectedIndex
    $hourIndex = [int]$randomDelay.Substring(0,2)
    if ($hourIndex -ge 0 -and $hourIndex -lt $controls.RandomDelayHourComboBox.Items.Count) {
        $controls.RandomDelayHourComboBox.SelectedIndex = $hourIndex
    } else {
        $controls.RandomDelayHourComboBox.SelectedIndex = 0  # fallback to 00
    }
    # Get the 4-5 characters (minutes), convert to int, and set as SelectedIndex
    $minuteIndex = [int]$randomDelay.Substring(3,2)
    if ($minuteIndex -ge 0 -and $minuteIndex -lt $controls.RandomDelayMinuteComboBox.Items.Count) {
        $controls.RandomDelayMinuteComboBox.SelectedIndex = $minuteIndex
    } else {
        $controls.RandomDelayMinuteComboBox.SelectedIndex = 0  # fallback to 00
    }

    # Update paths
    $Controls.ListPathTextBox.Text = (Get-DisplayValue -PropertyName "WAU_ListPath" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    $Controls.ModsPathTextBox.Text = (Get-DisplayValue -PropertyName "WAU_ModsPath" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    $Controls.AzureBlobSASURLTextBox.Text = (Get-DisplayValue -PropertyName "WAU_AzureBlobSASURL" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    
    # Update checkboxes
    $Controls.UpdatesAtLogonCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_UpdatesAtLogon" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.DoNotRunOnMeteredCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_DoNotRunOnMetered" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.UserContextCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_UserContext" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.BypassListForUsersCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_BypassListForUsers" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.DisableWAUAutoUpdateCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_DisableAutoUpdate" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.UpdatePreReleaseCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_UpdatePrerelease" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.UseWhiteListCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_UseWhiteList" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.AppInstallerShortcutCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_AppInstallerShortcut" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.DesktopShortcutCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_DesktopShortcut" -Config $updatedConfig -Policies $updatedPolicies)
    $Controls.StartMenuShortcutCheckBox.IsChecked = [bool](Get-DisplayValue -PropertyName "WAU_StartMenuShortcut" -Config $updatedConfig -Policies $updatedPolicies)
    
    # Update log settings
    $maxLogFiles = (Get-DisplayValue -PropertyName "WAU_MaxLogFiles" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    try {
        $maxLogFilesInt = [int]$maxLogFiles
        if ($maxLogFilesInt -ge 0 -and $maxLogFilesInt -le 99) {
            $Controls.MaxLogFilesComboBox.SelectedIndex = $maxLogFilesInt
        } else {
            $Controls.MaxLogFilesComboBox.SelectedIndex = 3  # Default fallback
        }
    } catch {
        $Controls.MaxLogFilesComboBox.SelectedIndex = 3  # Default fallback
    }

    # Update log size
    $maxLogSize = (Get-DisplayValue -PropertyName "WAU_MaxLogSize" -Config $updatedConfig -Policies $updatedPolicies).ToString()
    $logSizeIndex = -1
    try {
        for ($i = 0; $i -lt $Controls.MaxLogSizeComboBox.Items.Count; $i++) {
            if ($Controls.MaxLogSizeComboBox.Items[$i].Tag -eq $maxLogSize) {
                $logSizeIndex = $i
                break
            }
        }
    }
    catch {
        $logSizeIndex = 0  # Fallback to first item
    }

    if ($logSizeIndex -ge 0) {
        $Controls.MaxLogSizeComboBox.SelectedIndex = $logSizeIndex
    } else {
        $Controls.MaxLogSizeComboBox.Text = $maxLogSize
    }

    # Update information section
    $Controls.WAUSettingsVersionText.Text = $Script:WAU_GUI_VERSION
    $Controls.WAUVersionText.Text = $Script:WAU_VERSION  
    $Controls.WinGetVersionText.Text = $Script:WINGET_VERSION

    # Set links for version information
    $Controls.WAUSettingsVersionLink.NavigateUri = "https://github.com/$($Script:WAU_GUI_REPO)/releases"
    $Controls.WAUVersionLink.NavigateUri = "https://github.com/$($Script:WAU_REPO)/releases"
    $Controls.WinGetVersionLink.NavigateUri = "https://github.com/microsoft/winget-cli/releases"

    # Get last run time for the scheduled task 'Winget-AutoUpdate'
    try {
        $task = Get-ScheduledTask -TaskName 'Winget-AutoUpdate' -ErrorAction Stop
        $lastRunTime = $task | Get-ScheduledTaskInfo | Select-Object -ExpandProperty LastRunTime
        if ($lastRunTime -and $lastRunTime -ne [datetime]::MinValue) {
            $Controls.RunDate.Text = " WAU Last Run: $($lastRunTime.ToString('yyyy-MM-dd HH:mm'))"
        } else {
            $Controls.RunDate.Text = " WAU Last Run: Never"
        }
    } catch {
        $Controls.RunDate.Text = " WAU Last Run: Unknown!"
    }

    # Update install location hyperlink
    $Controls.InstallLocationText.Text = $updatedConfig.InstallLocation
    $Controls.InstallLocationLink.NavigateUri = $updatedConfig.InstallLocation
    
    if ($wauGPOListPathEnabled -and ($null -ne $updatedPolicies)) {
        $Controls.LocalListText.Inlines.Clear()
        $Controls.LocalListText.Inlines.Add("Current Local List: ")
        if ($updatedPolicies.WAU_UseWhiteList -eq 1) {
            $run = New-Object System.Windows.Documents.Run("'GPO (Included Apps)'")
        } else {
            $run = New-Object System.Windows.Documents.Run("'GPO (Excluded Apps)'")
        }   
        $run.Foreground = $Script:COLOR_ENABLED
        $Controls.LocalListText.Inlines.Add($run)
    }    
    else {
        try {
            $installdir = $updatedConfig.InstallLocation
            if ($updatedConfig.WAU_UseWhiteList -eq 1 -or ($updatedPolicies.WAU_UseWhiteList -eq 1 -and ($null -ne $updatedPolicies))) {
                $whiteListFile = Join-Path $installdir 'included_apps.txt'
                if (Test-Path $whiteListFile) {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Current Local List: ")
                    $run = New-Object System.Windows.Documents.Run("'included_apps.txt'")
                    $run.Foreground = $Script:COLOR_ENABLED
                    $Controls.LocalListText.Inlines.Add($run)
                } else {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Missing Current Local List: ")
                    $run = New-Object System.Windows.Documents.Run("'included_apps.txt'")
                    $run.Foreground = $Script:COLOR_DISABLED
                    $Controls.LocalListText.Inlines.Add($run)
                }
            } else {
                $excludedFile = Join-Path $installdir 'excluded_apps.txt'
                $defaultExcludedFile = Join-Path $installdir 'config\default_excluded_apps.txt'
                if (Test-Path $excludedFile) {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Current Local List: ")
                    $run = New-Object System.Windows.Documents.Run("'excluded_apps.txt'")
                    $run.Foreground = $Script:COLOR_ENABLED
                    $Controls.LocalListText.Inlines.Add($run)
                } elseif (Test-Path $defaultExcludedFile) {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Current Local List: ")
                    $run = New-Object System.Windows.Documents.Run("'config\default_excluded_apps.txt'")
                    $run.Foreground = $Script:COLOR_ACTIVE
                    $Controls.LocalListText.Inlines.Add($run)
                } else {
                    $Controls.LocalListText.Inlines.Clear()
                    $Controls.LocalListText.Inlines.Add("Missing Local Lists: ")
                    $run = New-Object System.Windows.Documents.Run("'excluded_apps.txt' and 'config\default_excluded_apps.txt'")
                    $run.Foreground = $Script:COLOR_DISABLED
                    $Controls.LocalListText.Inlines.Add($run)
                }
            }
        }
        catch {
            $Controls.LocalListText.Inlines.Clear()
            $Controls.LocalListText.Inlines.Add("Current Local List: ")
            $run = New-Object System.Windows.Documents.Run("'Unknown'")
            $run.Foreground = $Script:COLOR_INACTIVE
            $Controls.LocalListText.Inlines.Add($run)
        }
    }

    # Update WAU AutoUpdate status
    $wauAutoUpdateDisabled = [bool](Get-DisplayValue -PropertyName "WAU_DisableAutoUpdate" -Config $updatedConfig -Policies $updatedPolicies)
    $wauPreReleaseEnabled = [bool](Get-DisplayValue -PropertyName "WAU_UpdatePrerelease" -Config $updatedConfig -Policies $updatedPolicies)
    $gpoManagementEnabled = ($null -ne $updatedPolicies)

    # Compose colored status text using Inlines (for TextBlock with Inlines)
    $statusText = @(
    Get-ColoredStatusText "WAU AutoUpdate" (-not $wauAutoUpdateDisabled)
    Get-ColoredStatusText "WAU PreRelease" $wauPreReleaseEnabled
    Get-ColoredStatusText "GPO Management" $gpoManagementEnabled
    ) -join " | "

    # Set the Inlines property for colorized text
    $Controls.WAUAutoUpdateText.Inlines.Clear()
    [void]$Controls.WAUAutoUpdateText.Inlines.Add([Windows.Markup.XamlReader]::Parse("<Span xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'>$statusText</Span>"))

    # Trigger status update
    Update-StatusDisplay -Controls $controls
    Update-MaxLogSizeState -Controls $controls
    Update-PreReleaseCheckBoxState -Controls $controls

    # Check if we're being called from a save operation by checking if we're in GPO mode
    $gpoControlsActive = ($null -ne $updatedPolicies)

    # Only show popup when window first opens, not when updating after save
    $skipPopupForInitialLoad = $false
    
    # Update GPO management state
    Update-GPOManagementState -Controls $controls -skipPopup $skipPopupForInitialLoad

    # Close the initial "Gathering Data..." popup if it's still open
    # ONLY do this if we're not in GPO mode (to avoid interfering with GPO popup)
    if (-not $gpoControlsActive) {
        try {
            if ($null -ne $Script:PopUpWindow) {
                Close-PopUp
            }
        }
        catch {
            # Popup might already be closed
        }
    }

    # Optional: Check for updates on startup (async) - configurable interval (can be disabled in config_user.psm1)
    $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
        try {
            # Only check for updates if auto-update check is enabled
            if (-not $Script:AUTOUPDATE_CHECK) {
                return
            }

            # Ensure config directory exists first
            $configDir = Join-Path $Script:WorkingDir "config"
            if (-not (Test-Path $configDir)) {
                New-Item -ItemType Directory -Path $configDir -Force | Out-Null
            }

            $timestampFile = Join-Path $configDir "last_update_check.txt"
            
            # Grace period check
            $firstRunFile = Join-Path $Script:WorkingDir "firstrun.txt"
            $gracePeriodHours = 1
            $inGracePeriod = $false

            # Use Get-ChildItem with -Force to handle Hidden/System files
            try {
                $firstRunFiles = Get-ChildItem -Path $Script:WorkingDir -Name "firstrun.txt" -Force -ErrorAction SilentlyContinue
                if ($firstRunFiles) {
                    $firstRunInfo = Get-Item -Path $firstRunFile -Force
                    $creationTime = $firstRunInfo.CreationTime
                    $currentTime = Get-Date
                    $timeSinceFirstRun = $currentTime - $creationTime
                    
                    if ($timeSinceFirstRun.TotalHours -lt $gracePeriodHours) {
                        $inGracePeriod = $true
                    }
                }
            }
            catch {
                # If we can't read first run time, proceed with normal check
            }

            # Only do actual update check if not in grace period and interval allows
            if (-not $inGracePeriod) {
                $shouldCheck = $true
                
                # Check if we should skip based on last check date
                if (Test-Path $timestampFile) {
                    try {
                        $lastCheckDate = Get-Content $timestampFile -ErrorAction Stop
                        $lastCheck = [DateTime]::ParseExact($lastCheckDate, "yyyy-MM-dd", $null)
                        $today = Get-Date
                        
                        $daysSinceLastCheck = ($today - $lastCheck).Days
                        
                        # Special case: 0 means check every time GUI opens
                        if ($Script:AUTOUPDATE_DAYS -eq 0) {
                            $shouldCheck = $true
                        } elseif ($daysSinceLastCheck -lt $Script:AUTOUPDATE_DAYS) {
                            $shouldCheck = $false
                        }
                    }
                    catch {
                        # If file is corrupted or invalid, proceed with check
                        $shouldCheck = $true
                    }
                }
                
                if ($shouldCheck) {
                    $updateInfo = Test-WAUGUIUpdate
                    
                    # Update timestamp file ONLY after performing the actual check
                    try {
                        $today = Get-Date -Format "yyyy-MM-dd"
                        Set-Content -Path $timestampFile -Value $today -Force
                    }
                    catch {
                        # Silent fail if we can't write timestamp file
                    }
                    
                    if ($updateInfo.UpdateAvailable -and -not $updateInfo.Error) {
                        $notesText = Get-CleanReleaseNotes -RawNotes $updateInfo.ReleaseNotes
                        $message = "Update available!`n`nCurrent version: $($updateInfo.CurrentVersion)`nLatest version: $($updateInfo.LatestVersion)`nRelease notes:`n$notesText`n`nDo you want to download the update?"
                        $result = [System.Windows.MessageBox]::Show($message, "Update Available", "OkCancel", "Question")
                        if ($result -eq 'Ok') {
                            Start-WAUGUIUpdate -updateInfo $updateInfo
                        }
                    }
                }
            }
        }
        catch {
            # Silent fail for background check
        }
    }) | Out-Null
}
function Test-WAULists {
    param($controls, $updatedConfig)

    # Only run if main window is started and not in GPO mode
    $updatedPolicies = $null
    try {
        $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
    } catch {}

    $gpoControlsActive = ($null -ne $updatedPolicies)

    if (-not $gpoControlsActive -and $Script:MainWindowStarted) {
        $currentListPath = (Get-DisplayValue -PropertyName "WAU_ListPath" -Config $updatedConfig)
        $installLocation = $updatedConfig.InstallLocation
        $excludedFile = Join-Path $installLocation "excluded_apps.txt"
        $includedFile = Join-Path $installLocation "included_apps.txt"
        $defaultExcluded = Join-Path $installLocation "config\default_excluded_apps.txt"

        $hasListPath = -not [string]::IsNullOrWhiteSpace($currentListPath)
        $hasAnyListFile = (Test-Path $excludedFile) -or (Test-Path $includedFile)

        # Only prompt if ListPath is empty AND no list file exists in WAU installation folder And not in portable mode
        if (-not $hasListPath -and -not $hasAnyListFile -and -not $Script:PORTABLE_MODE) {
            $msg = "No 'External List Path' is set and no list file exists under $installLocation.`n`nDo you want to create a local 'lists' folder with an editable 'excluded_apps.txt' to use?`n`n'default_excluded_apps.txt' will always be overwritten when 'WAU' updates itself!"
            $result = [System.Windows.MessageBox]::Show($msg, "Create lists folder?", "OKCancel", "Question")
            if ($result -eq 'OK') {
                # Ask user for location of 'lists' folder
                $userProfile = [Environment]::GetFolderPath('UserProfile')
                $workingDir = $Script:WorkingDir

                $folderMsg = "Please select a folder where the 'lists' folder should be created (must be outside your user profile and WAU installation directory):"
                [System.Windows.MessageBox]::Show($folderMsg, "Select Location", "OK", "Information")

                $folderDialog = New-Object System.Windows.Forms.FolderBrowserDialog
                $folderDialog.Description = "Select folder where 'lists' folder will be created (must be outside user profile and WAU installation directory)"
                $folderDialog.ShowNewFolderButton = $true
                $folderDialog.SelectedPath = "C:\"

                do {
                    $dialogResult = $folderDialog.ShowDialog()
                    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
                        $selectedPath = $folderDialog.SelectedPath

                        # Check if selected folder is under UserProfile or WorkingDir
                        $fullSelectedPath = [System.IO.Path]::GetFullPath($selectedPath)
                        $fullUserProfile = [System.IO.Path]::GetFullPath($userProfile)
                        $fullWorkingDir = [System.IO.Path]::GetFullPath($workingDir)

                        # Is selected path inside user profile?
                        $isUnderUserProfile = $fullSelectedPath.StartsWith($fullUserProfile, [StringComparison]::OrdinalIgnoreCase)
                        # Is selected path inside WAU installation directory?
                        $isUnderWorkingDir = $fullSelectedPath.StartsWith($fullWorkingDir, [StringComparison]::OrdinalIgnoreCase)

                        if ($isUnderUserProfile -or $isUnderWorkingDir) {
                            [System.Windows.MessageBox]::Show("Selected folder is under your user profile or WAU installation directory. Please choose a different location.", "Invalid Location", "OK", "Warning")
                            continue
                        }

                        # Test write access to selected folder
                        try {
                            $testFile = Join-Path $selectedPath "test_write_access.tmp"
                            Set-Content -Path $testFile -Value "test" -ErrorAction Stop
                            Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue

                            # Valid location found
                            $listsDir = Join-Path $selectedPath "lists"
                            break
                        }
                        catch {
                            [System.Windows.MessageBox]::Show("No write access to selected folder. Please choose a different location.", "Access Denied", "OK", "Warning")
                            continue
                        }
                    }
                    else {
                        # User cancelled folder selection
                        return
                    }
                } while ($true)

                if (-not (Test-Path $listsDir)) {
                    New-Item -Path $listsDir -ItemType Directory | Out-Null
                }
                # Create excluded_apps.txt in the new lists folder
                $appsExcluded = Join-Path $listsDir "excluded_apps.txt"
                if (-not (Test-Path $appsExcluded)) {
                    if (Test-Path $defaultExcluded) {
                        Copy-Item $defaultExcluded $appsExcluded -Force
                    } else {
                        Set-Content $appsExcluded "# Add apps to exclude, one per line."
                    }
                }

                # Set WAU_ListPath to the new lists folder
                Set-ItemProperty -Path $Script:WAU_REGISTRY_PATH -Name "WAU_ListPath" -Value $listsDir -Force
                # Update the controls to reflect the new path
                Invoke-SettingsLoad -controls $controls
                # Open excluded_apps.txt for editing
                Start-Process "explorer.exe" $appsExcluded
            }
        }
    }
}

# 5. GUI action functions (depends on config + GUI helper functions)
function New-WindowScreenshot {
    param($window, $controls)

    try {
        # Store original values for sensitive fields
        $originalListPath = $controls.ListPathTextBox.Text
        $originalModsPath = $controls.ModsPathTextBox.Text
        $originalAzureBlob = $controls.AzureBlobSASURLTextBox.Text

        # Temporarily mask sensitive text
        if (-not [string]::IsNullOrWhiteSpace($originalListPath)) {
            $controls.ListPathTextBox.Text = Hide-SensitiveText $originalListPath
        }
        if (-not [string]::IsNullOrWhiteSpace($originalModsPath)) {
            $controls.ModsPathTextBox.Text = Hide-SensitiveText $originalModsPath
        }
        if (-not [string]::IsNullOrWhiteSpace($originalAzureBlob)) {
            $controls.AzureBlobSASURLTextBox.Text = Hide-SensitiveText $originalAzureBlob
        }

        # Force UI update to show masked values
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100

        # Ensure window is active/focused
        $window.Activate()
        $window.Focus()
        Start-Sleep -Milliseconds 50

        # Send Alt+Print Screen to capture active window
        [System.Windows.Forms.SendKeys]::SendWait("%{PRTSC}")

        # Show confirmation
        $controls.StatusBarText.Text = "Screenshot copied"
        $controls.StatusBarText.Foreground = $Script:COLOR_ACTIVE

        # Timer to reset status
        $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Start-Sleep -Milliseconds $Script:WAIT_TIME
            $controls.StatusBarText.Text = $Script:STATUS_READY_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_INACTIVE
        }) | Out-Null

    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to capture screenshot: $($_.Exception.Message)", "Error", "OK", "Error")
    }
    finally {
        # Always restore original values
        $controls.ListPathTextBox.Text = $originalListPath
        $controls.ModsPathTextBox.Text = $originalModsPath
        $controls.AzureBlobSASURLTextBox.Text = $originalAzureBlob
    }
}
function Test-SettingsChanged {
    param($controls)
    
    try {
        # Get current saved configuration and policies
        $currentConfig = Get-WAUCurrentConfig
        $policies = $null
        try {
            $policies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
        } catch { }
        
        # Check if GPO management is active
        $isGPOManaged = ($null -ne $policies)
        
        $changes = @()
        
        if ($isGPOManaged) {
            # In GPO mode, only check shortcut settings (these are always from local config)
            
            # Desktop shortcut
            $savedDesktop = [bool]($currentConfig.WAU_DesktopShortcut -eq 1)
            $guiDesktop = [bool]$controls.DesktopShortcutCheckBox.IsChecked
            if ($savedDesktop -ne $guiDesktop) { $changes += "Desktop Shortcut" }
            
            # Start Menu shortcut
            $savedStartMenu = [bool]($currentConfig.WAU_StartMenuShortcut -eq 1)
            $guiStartMenu = [bool]$controls.StartMenuShortcutCheckBox.IsChecked
            if ($savedStartMenu -ne $guiStartMenu) { $changes += "Start Menu Shortcut" }
            
            # App Installer shortcut
            $savedAppInstaller = [bool]($currentConfig.WAU_AppInstallerShortcut -eq 1)
            $guiAppInstaller = [bool]$controls.AppInstallerShortcutCheckBox.IsChecked
            if ($savedAppInstaller -ne $guiAppInstaller) { $changes += "App Installer Shortcut" }
            
        } else {
            # In normal mode, check all settings
            
            # Update interval
            $savedInterval = Get-DisplayValue "WAU_UpdatesInterval" $currentConfig $policies
            $guiInterval = $controls.UpdateIntervalComboBox.SelectedItem.Tag
            if ($savedInterval -ne $guiInterval) { $changes += "Update Interval" }
            
            # Notification level
            $savedNotification = Get-DisplayValue "WAU_NotificationLevel" $currentConfig $policies
            $guiNotification = $controls.NotificationLevelComboBox.SelectedItem.Tag
            if ($savedNotification -ne $guiNotification) { $changes += "Notification Level" }
            
            # Update time
            $savedTime = Get-DisplayValue "WAU_UpdatesAtTime" $currentConfig $policies
            $guiTime = "{0:D2}:{1:D2}:00" -f ($controls.UpdateTimeHourComboBox.SelectedIndex + 1), $controls.UpdateTimeMinuteComboBox.SelectedIndex
            if ($savedTime -ne $guiTime) { $changes += "Update Time" }
            
            # Random delay
            $savedDelay = Get-DisplayValue "WAU_UpdatesTimeDelay" $currentConfig $policies
            $guiDelay = "{0:D2}:{1:D2}" -f ($controls.RandomDelayHourComboBox.SelectedIndex), $controls.RandomDelayMinuteComboBox.SelectedIndex
            if ($savedDelay -ne $guiDelay) { $changes += "Random Delay" }
            
            # List path
            $savedListPath = Get-DisplayValue "WAU_ListPath" $currentConfig $policies
            $guiListPath = $controls.ListPathTextBox.Text
            if ($savedListPath -ne $guiListPath) { $changes += "External List Path" }
            
            # Mods path
            $savedModsPath = Get-DisplayValue "WAU_ModsPath" $currentConfig $policies
            $guiModsPath = $controls.ModsPathTextBox.Text
            if ($savedModsPath -ne $guiModsPath) { $changes += "External Mods Path" }
            
            # Azure Blob SAS URL
            $savedAzureBlob = Get-DisplayValue "WAU_AzureBlobSASURL" $currentConfig $policies
            $guiAzureBlob = $controls.AzureBlobSASURLTextBox.Text
            if ($savedAzureBlob -ne $guiAzureBlob) { $changes += "Azure Blob SAS URL" }
            
            # All checkboxes
            $savedDisableAutoUpdate = [bool](Get-DisplayValue "WAU_DisableAutoUpdate" $currentConfig $policies)
            $guiDisableAutoUpdate = [bool]$controls.DisableWAUAutoUpdateCheckBox.IsChecked
            if ($savedDisableAutoUpdate -ne $guiDisableAutoUpdate) { $changes += "Disable WAU AutoUpdate" }
            
            $savedUpdatePrerelease = [bool](Get-DisplayValue "WAU_UpdatePrerelease" $currentConfig $policies)
            $guiUpdatePrerelease = [bool]$controls.UpdatePreReleaseCheckBox.IsChecked
            if ($savedUpdatePrerelease -ne $guiUpdatePrerelease) { $changes += "Update PreRelease" }
            
            $savedDoNotRunOnMetered = [bool](Get-DisplayValue "WAU_DoNotRunOnMetered" $currentConfig $policies)
            $guiDoNotRunOnMetered = [bool]$controls.DoNotRunOnMeteredCheckBox.IsChecked
            if ($savedDoNotRunOnMetered -ne $guiDoNotRunOnMetered) { $changes += "Don't run on data plan" }
            
            $savedUpdatesAtLogon = [bool](Get-DisplayValue "WAU_UpdatesAtLogon" $currentConfig $policies)
            $guiUpdatesAtLogon = [bool]$controls.UpdatesAtLogonCheckBox.IsChecked
            if ($savedUpdatesAtLogon -ne $guiUpdatesAtLogon) { $changes += "Run at user logon" }
            
            $savedUserContext = [bool](Get-DisplayValue "WAU_UserContext" $currentConfig $policies)
            $guiUserContext = [bool]$controls.UserContextCheckBox.IsChecked
            if ($savedUserContext -ne $guiUserContext) { $changes += "Run in user context" }
            
            $savedBypassListForUsers = [bool](Get-DisplayValue "WAU_BypassListForUsers" $currentConfig $policies)
            $guiBypassListForUsers = [bool]$controls.BypassListForUsersCheckBox.IsChecked
            if ($savedBypassListForUsers -ne $guiBypassListForUsers) { $changes += "Bypass list in user context" }
            
            $savedUseWhiteList = [bool](Get-DisplayValue "WAU_UseWhiteList" $currentConfig $policies)
            $guiUseWhiteList = [bool]$controls.UseWhiteListCheckBox.IsChecked
            if ($savedUseWhiteList -ne $guiUseWhiteList) { $changes += "Use whitelist" }
            
            # Shortcut checkboxes
            $savedDesktop = [bool]($currentConfig.WAU_DesktopShortcut -eq 1)
            $guiDesktop = [bool]$controls.DesktopShortcutCheckBox.IsChecked
            if ($savedDesktop -ne $guiDesktop) { $changes += "Desktop Shortcut" }
            
            $savedStartMenu = [bool]($currentConfig.WAU_StartMenuShortcut -eq 1)
            $guiStartMenu = [bool]$controls.StartMenuShortcutCheckBox.IsChecked
            if ($savedStartMenu -ne $guiStartMenu) { $changes += "Start Menu Shortcut" }
            
            $savedAppInstaller = [bool]($currentConfig.WAU_AppInstallerShortcut -eq 1)
            $guiAppInstaller = [bool]$controls.AppInstallerShortcutCheckBox.IsChecked
            if ($savedAppInstaller -ne $guiAppInstaller) { $changes += "App Installer Shortcut" }
            
            # Log settings
            $savedMaxLogFiles = Get-DisplayValue "WAU_MaxLogFiles" $currentConfig $policies
            $guiMaxLogFiles = $controls.MaxLogFilesComboBox.SelectedItem.Content
            if ($savedMaxLogFiles -ne $guiMaxLogFiles) { $changes += "Max Log Files" }
            
            $savedMaxLogSize = Get-DisplayValue "WAU_MaxLogSize" $currentConfig $policies
            $guiMaxLogSize = if ($controls.MaxLogSizeComboBox.SelectedItem -and $controls.MaxLogSizeComboBox.SelectedItem.Tag) { 
                $controls.MaxLogSizeComboBox.SelectedItem.Tag 
            } else { 
                $controls.MaxLogSizeComboBox.Text 
            }
            if ($savedMaxLogSize -ne $guiMaxLogSize) { $changes += "Max Log Size" }
        }
        
        return @{
            HasChanges = ($changes.Count -gt 0)
            Changes = $changes
            IsGPOManaged = $isGPOManaged
        }
    }
    catch {
        # On error, assume no changes to be safe
        return @{ 
            HasChanges = $false
            Changes = @()
            IsGPOManaged = $false
        }
    }
}
function Save-WAUSettings {
    param($controls)

        # Validate path inputs before saving
        $pathErrors = @()
        
        if (-not (Test-PathValue -path $controls.ListPathTextBox.Text)) {
            $pathErrors += "External List Path contains invalid value"
        }
        
        if (-not (Test-PathValue -path $controls.ModsPathTextBox.Text)) {
            $pathErrors += "External Mods Path contains invalid value"
        }
        
        if (-not (Test-PathValue -path $controls.AzureBlobSASURLTextBox.Text)) {
            $pathErrors += "Azure Blob SAS URL contains invalid value"
        }
        
        if ($pathErrors.Count -gt 0) {
            $errorMessage = "Cannot save settings. Please fix the following errors:`n`n" + ($pathErrors -join "`n")
            [System.Windows.MessageBox]::Show($errorMessage, "Validation Error", "OK", "Warning")
            return
        }

        # Check if settings are controlled by GPO
        $updatedPolicies = $null
        try {
            $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
        }
        catch {
            # GPO registry key doesn't exist or can't be read
        }

        if ($null -ne $updatedPolicies) {
            # For GPO mode - show popup immediately without delay
            Start-PopUp "Saving WAU Settings..."
            # Update status to "Saving..."
            $controls.StatusBarText.Text = "Saving..."
            $controls.StatusBarText.Foreground = $Script:COLOR_ACTIVE

            # Only allow saving shortcut settings
            $newSettings = @{
                WAU_AppInstallerShortcut = if ($controls.AppInstallerShortcutCheckBox.IsChecked) { 1 } else { 0 }
                WAU_DesktopShortcut = if ($controls.DesktopShortcutCheckBox.IsChecked) { 1 } else { 0 }
                WAU_StartMenuShortcut = if ($controls.StartMenuShortcutCheckBox.IsChecked) { 1 } else { 0 }
            }
            
            # Save settings and close popup after a short delay
            if (Set-WAUConfig -Settings $newSettings) {
                # Close popup after default wait time and update GUI
                $controls.StatusBarText.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                    Start-Sleep -Milliseconds $Script:WAIT_TIME
                    # Update status to "Done"
                    $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
                    $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
                    Close-PopUp
                    
                    # Update GUI settings
                    $updatedConfigAfterSave = Get-WAUCurrentConfig

                    # Update only the shortcut checkboxes since that's all we saved
                    $controls.AppInstallerShortcutCheckBox.IsChecked = ($updatedConfigAfterSave.WAU_AppInstallerShortcut -eq 1)
                    $controls.DesktopShortcutCheckBox.IsChecked = ($updatedConfigAfterSave.WAU_DesktopShortcut -eq 1)
                    $controls.StartMenuShortcutCheckBox.IsChecked = ($updatedConfigAfterSave.WAU_StartMenuShortcut -eq 1)
                    
                    # Update GPO management state but SKIP the popup since we're updating after save
                    Update-GPOManagementState -Controls $controls -skipPopup $true
                }) | Out-Null
            } else {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Failed to save settings.", "Error", "OK", "Error")
            }
        } else {
            Start-PopUp "Saving WAU Settings..."
            # Update status to "Saving..."
            $controls.StatusBarText.Text = "Saving..."
            $controls.StatusBarText.Foreground = $Script:COLOR_ACTIVE
            
            # Force UI update
            [System.Windows.Forms.Application]::DoEvents()
            
            # Prepare settings hashtable
            $newSettings = @{
                WAU_UpdatesInterval = $controls.UpdateIntervalComboBox.SelectedItem.Tag
                WAU_NotificationLevel = $controls.NotificationLevelComboBox.SelectedItem.Tag
                WAU_UpdatesAtTime = "{0:D2}:{1:D2}:00" -f ($controls.UpdateTimeHourComboBox.SelectedIndex + 1), $controls.UpdateTimeMinuteComboBox.SelectedIndex
                WAU_UpdatesTimeDelay = "{0:D2}:{1:D2}" -f ($controls.RandomDelayHourComboBox.SelectedIndex), $controls.RandomDelayMinuteComboBox.SelectedIndex
                WAU_ListPath = $controls.ListPathTextBox.Text
                WAU_ModsPath = $controls.ModsPathTextBox.Text
                WAU_AzureBlobSASURL = $controls.AzureBlobSASURLTextBox.Text
                WAU_DisableAutoUpdate = if ($controls.DisableWAUAutoUpdateCheckBox.IsChecked) { 1 } else { 0 }
                WAU_UpdatePreRelease = if ($controls.DisableWAUAutoUpdateCheckBox.IsChecked) { 0 } elseif ($controls.UpdatePreReleaseCheckBox.IsChecked) { 1 } else { 0 }
                WAU_DoNotRunOnMetered = if ($controls.DoNotRunOnMeteredCheckBox.IsChecked) { 1 } else { 0 }
                WAU_StartMenuShortcut = if ($controls.StartMenuShortcutCheckBox.IsChecked) { 1 } else { 0 }
                WAU_DesktopShortcut = if ($controls.DesktopShortcutCheckBox.IsChecked) { 1 } else { 0 }
                WAU_AppInstallerShortcut = if ($controls.AppInstallerShortcutCheckBox.IsChecked) { 1 } else { 0 }
                WAU_UpdatesAtLogon = if ($controls.UpdatesAtLogonCheckBox.IsChecked) { 1 } else { 0 }
                WAU_UserContext = if ($controls.UserContextCheckBox.IsChecked) { 1 } else { 0 }
                WAU_BypassListForUsers = if ($controls.BypassListForUsersCheckBox.IsChecked) { 1 } else { 0 }
                WAU_UseWhiteList = if ($controls.UseWhiteListCheckBox.IsChecked) { 1 } else { 0 }
                WAU_MaxLogFiles = $controls.MaxLogFilesComboBox.SelectedItem.Content
                WAU_MaxLogSize = if ($controls.MaxLogSizeComboBox.SelectedItem -and $controls.MaxLogSizeComboBox.SelectedItem.Tag) { $controls.MaxLogSizeComboBox.SelectedItem.Tag } else { $controls.MaxLogSizeComboBox.Text }
            }
            
            # Save settings
            if (Set-WAUConfig -Settings $newSettings) {
                # Update status to "Done"
                $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
                $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
                
                # Update GUI settings without popup (skip popup for normal mode too when updating after save)
                Update-WAUGUIFromConfig -Controls $controls
            } else {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Failed to save settings.", "Error", "OK", "Error")
            }
        }
        # Create timer to reset status back to ready after half standard wait time
        $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Start-Sleep -Milliseconds ($Script:WAIT_TIME / 2)
            $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
            $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
        }) | Out-Null
}
function Test-WindowKeyPress {
    param($controls, $window, $keyEventArgs)
    
    switch ($keyEventArgs.Key) {
        'F5' { 
            Invoke-SettingsLoad -controls $controls
            $keyEventArgs.Handled = $true
        }
        'F12' { 
            Set-DevToolsVisibility -controls $controls -window $window
            $keyEventArgs.Handled = $true
        }
        'F11' {
            New-WindowScreenshot -window $window -controls $controls
            $keyEventArgs.Handled = $true
        }
        'Enter' { 
            if ($keyEventArgs.KeyboardDevice.Modifiers -eq [System.Windows.Input.ModifierKeys]::None) {
                Save-WAUSettings -controls $controls
                $keyEventArgs.Handled = $true
            }
        }
        'Escape' { 
            Close-WindowGracefully -controls $controls -window $window
            $keyEventArgs.Handled = $true
        }
    }
}
function Invoke-SettingsLoad {
    param($controls)

    # Update status to "Loading"
    $controls.StatusBarText.Text = "Loading..."
    $controls.StatusBarText.Foreground = $Script:COLOR_ACTIVE
    Start-PopUp "Loading WAU Data..."
    try {
        # Update WAU version info before refreshing GUI
        $Script:WAU_INSTALL_INFO = Test-InstalledWAU -DisplayName "Winget-AutoUpdate"
        $Script:WAU_VERSION = if ($Script:WAU_INSTALL_INFO.Count -ge 1) { $Script:WAU_INSTALL_INFO[0] } else { "Unknown" }
        $Script:WAU_GUID = if ($Script:WAU_INSTALL_INFO.Count -ge 2) { $Script:WAU_INSTALL_INFO[1] } else { $null }
        
        # Update WinGet version
        try {
            $wingetVersionOutput = winget -v 2>$null
            $Script:WINGET_VERSION = $wingetVersionOutput.Trim().TrimStart("v")
        } catch {
            $Script:WINGET_VERSION = "Unknown"
        }
        
        # Refresh all settings from config and policies
        Update-WAUGUIFromConfig -Controls $controls
        Update-GPOManagementState -controls $controls -skipPopup $true

        # Reset status to "Done"
        $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
        $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
    }
    catch {
        $controls.StatusBarText.Text = "Load failed"
        $controls.StatusBarText.Foreground = $Script:COLOR_DISABLED
    }

    # Create timer to reset status back to ready after half standard wait time
    $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
        Start-Sleep -Milliseconds ($Script:WAIT_TIME / 2)
        $controls.StatusBarText.Text = $Script:STATUS_READY_TEXT
        $controls.StatusBarText.Foreground = $Script:COLOR_INACTIVE
        Close-PopUp
    }) | Out-Null
}
function Set-DevToolsVisibility {
    param($controls, $window)
    if ($controls.DevGPOButton.Visibility -eq 'Collapsed') {
        $controls.DevGPOButton.Visibility = 'Visible'
        $controls.DevTaskButton.Visibility = 'Visible'
        $controls.DevRegButton.Visibility = 'Visible'
        $controls.DevGUIDButton.Visibility = 'Visible'
        $controls.DevSysButton.Visibility = 'Visible'
        $controls.DevListButton.Visibility = 'Visible'
        $controls.DevUsrButton.Visibility = 'Visible'
        $controls.DevMSIButton.Visibility = 'Visible'
        $controls.DevCfgButton.Visibility = 'Visible'
        $controls.DevWAUButton.Visibility = 'Visible'
        $controls.DevVerButton.Visibility = 'Visible'
        $controls.DevSrcButton.Visibility = 'Visible'
        $controls.LinksStackPanel.Visibility = 'Visible'
        if ($Script:PORTABLE_MODE) {
            $window.Title = "$Script:GUI_TITLE - Dev Tools - Portable Mode"
        } else {
            $window.Title = "$Script:GUI_TITLE - Dev Tools"
        }
    } else {
        $controls.DevGPOButton.Visibility = 'Collapsed'
        $controls.DevTaskButton.Visibility = 'Collapsed'
        $controls.DevRegButton.Visibility = 'Collapsed'
        $controls.DevGUIDButton.Visibility = 'Collapsed'
        $controls.DevSysButton.Visibility = 'Collapsed'
        $controls.DevListButton.Visibility = 'Collapsed'
        $controls.DevUsrButton.Visibility = 'Collapsed'
        $controls.DevMSIButton.Visibility = 'Collapsed'
        $controls.DevCfgButton.Visibility = 'Collapsed'
        $controls.DevWAUButton.Visibility = 'Collapsed'
        $controls.DevVerButton.Visibility = 'Collapsed'
        $controls.DevSrcButton.Visibility = 'Collapsed'
        $controls.LinksStackPanel.Visibility = 'Collapsed'
        if ($Script:PORTABLE_MODE) {
            $window.Title = "$Script:GUI_TITLE - Portable Mode"
        } else {
            $window.Title = "$Script:GUI_TITLE"
        }
    }

    # Reset status to "Done"
    $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
    $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED

    # Create timer to reset status back to ready after half standard wait time
    $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
        Start-Sleep -Milliseconds ($Script:WAIT_TIME / 2)
        $controls.StatusBarText.Text = $Script:STATUS_READY_TEXT
        $controls.StatusBarText.Foreground = $Script:COLOR_INACTIVE
    }) | Out-Null
}
function Close-WindowGracefully {
    param($controls, $window)
    
    try {
        # Check if settings have changed
        $changeResult = Test-SettingsChanged -controls $controls
        
        if ($changeResult.HasChanges) {
            $message = if ($changeResult.IsGPOManaged) {
                "You have unsaved shortcut changes. Do you want to save them before closing?"
            } else {
                "You have unsaved changes. Do you want to save them before closing?"
            }
            
            $result = [System.Windows.MessageBox]::Show(
                $message,
                "Unsaved Changes",
                "YesNoCancel",
                "Question",
                "Yes"
            )
            
            switch ($result) {
                'Yes' {
                    # Save and then close
                    Save-WAUSettings -controls $controls
                    # Close window after a short delay to let save operation complete
                    $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                        Start-Sleep -Milliseconds 500  # Short delay for save to complete
                        $window.Close()
                    }) | Out-Null
                }
                'No' {
                    # Close without saving
                    $window.Close()
                }
                'Cancel' {
                    # Don't close, return to window
                    return
                }
            }
        } else {
            # No changes, close directly
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status and close window after half standard wait time
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds($Script:WAIT_TIME / 2)
            $timer.Add_Tick({
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                if ($null -ne $timer) {
                    $timer.Stop()
                }
                $window.Close()
            })
            $timer.Start()
        }
    }
    catch {
        # Fallback force close
        $window.DialogResult = $false
    }
}

# 6. Main GUI function (depends on all above)
function Show-WAUSettingsGUI {
    
    # Get current configuration
    $currentConfig = Get-WAUCurrentConfig
    
    # If config is null (WAU not found and user chose not to install), return gracefully
    if ($null -eq $currentConfig) {
        return
    }
    
    # Set flag to indicate main window is starting/started (AFTER successful config retrieval)
    $Script:MainWindowStarted = $true

    # Load XAML
    [xml]$xamlXML = $Script:WINDOW_XAML -replace 'x:N', 'N'
    $reader = (New-Object System.Xml.XmlNodeReader $xamlXML)
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $window.Icon = $Script:GUI_ICON
    $window.Background = $Script:COLOR_BACKGROUND
    
    # Get controls
    $controls = @{}
    $xamlXML.SelectNodes("//*[@Name]") | ForEach-Object {
        $controls[$_.Name] = $window.FindName($_.Name)
    }

    # Update window title if in portable mode
    if ($Script:PORTABLE_MODE) {
        $window.Title = "$Script:GUI_TITLE - Portable Mode"
    }
    
    # Set initial values for Update Time Hour ComboBox programmatically
    1..24 | ForEach-Object { 
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = "{0:D2}" -f $_  # Formats to 01, 02, 03, etc.
        $item.Tag = "{0:D2}" -f $_
        $controls.UpdateTimeHourComboBox.Items.Add($item) | Out-Null
    }

    # Set initial values for Update Time Minute ComboBox programmatically
    0..59 | ForEach-Object { 
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = "{0:D2}" -f $_  # Formats to 00, 01, 02, etc.
        $item.Tag = "{0:D2}" -f $_
        $controls.UpdateTimeMinuteComboBox.Items.Add($item) | Out-Null
    }

    # Set initial values for Random Delay Hour ComboBox programmatically
    0..23 | ForEach-Object { 
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = "{0:D2}" -f $_  # Formats to 00, 01, 02, etc.
        $item.Tag = "{0:D2}" -f $_
        $controls.RandomDelayHourComboBox.Items.Add($item) | Out-Null
    }

    # Set initial values for Random Delay Minute ComboBox programmatically
    0..59 | ForEach-Object { 
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = "{0:D2}" -f $_  # Formats to 00, 01, 02, etc.
        $item.Tag = "{0:D2}" -f $_
        $controls.RandomDelayMinuteComboBox.Items.Add($item) | Out-Null
    }

    # Set default values
    $controls.UpdateTimeHourComboBox.SelectedIndex = 5  # For hour 06
    $controls.UpdateTimeMinuteComboBox.SelectedIndex = 0  # For minute 00

    # Set initial values for MaxLogFiles ComboBox programmatically
    0..99 | ForEach-Object { 
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = [string]$_
        $controls.MaxLogFilesComboBox.Items.Add($item) | Out-Null
    }

    # Event handler for interval change
    $controls.UpdateIntervalComboBox.Add_SelectionChanged({
        Update-StatusDisplay -Controls $controls
    })
    
    # Event handler for DisableWAUAutoUpdate checkbox
    $controls.DisableWAUAutoUpdateCheckBox.Add_Checked({
        Update-PreReleaseCheckBoxState -Controls $controls
    })
    
    $controls.DisableWAUAutoUpdateCheckBox.Add_Unchecked({
        Update-PreReleaseCheckBoxState -Controls $controls
    })

    # Event handler for MaxLogFiles change
    $controls.MaxLogFilesComboBox.Add_SelectionChanged({
        Update-MaxLogSizeState -Controls $controls
    })

    # Event handlers for path TextBox input validation
    $controls.ListPathTextBox.Add_PreviewTextInput({
        Test-PathTextBox_PreviewTextInput -source $args[0] -e $args[1]
    })
    
    $controls.ModsPathTextBox.Add_PreviewTextInput({
        Test-PathTextBox_PreviewTextInput -source $args[0] -e $args[1]
    })
    
    $controls.AzureBlobSASURLTextBox.Add_PreviewTextInput({
        Test-PathTextBox_PreviewTextInput -source $args[0] -e $args[1]
    })

    # Event handlers for path TextBox text validation
    $controls.ListPathTextBox.Add_TextChanged({
        Test-PathTextBox_TextChanged -source $args[0] -e $args[1]
    })
    
    $controls.ModsPathTextBox.Add_TextChanged({
        Test-PathTextBox_TextChanged -source $args[0] -e $args[1]
    })
    
    $controls.AzureBlobSASURLTextBox.Add_TextChanged({
        Test-PathTextBox_TextChanged -source $args[0] -e $args[1]
    })

    # Screenshot button handler
    $controls.ScreenshotButton.Add_Click({
        New-WindowScreenshot -window $window -controls $controls
    })

    # Populate current settings
    Update-WAUGUIFromConfig -Controls $controls    

    # Hyperlink event handlers
    $controls.ManifestsLink.Add_RequestNavigate({
        param($linkSource, $navEventArgs)
        try {
            Start-Process $navEventArgs.Uri.AbsoluteUri
            $navEventArgs.Handled = $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open link: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.IssuesLink.Add_RequestNavigate({
        param($linkSource, $navEventArgs)
        try {
            Start-Process $navEventArgs.Uri.AbsoluteUri
            $navEventArgs.Handled = $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open link: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    # Install location hyperlink event handler
    $controls.InstallLocationLink.Add_RequestNavigate({
        param($linkSource, $navEventArgs)
        try {
            $installPath = $navEventArgs.Uri.ToString()
            # Handle file:// URIs by converting to local path
            if ($installPath.StartsWith("file:///")) {
                $installPath = $installPath.Replace("file:///", "").Replace("/", "\")
            } elseif ($installPath.StartsWith("file://")) {
                $installPath = $installPath.Replace("file://", "").Replace("/", "\")
            }
            Start-Process "explorer.exe" -ArgumentList "`"$installPath`""
            $navEventArgs.Handled = $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open install location: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    # Variable to hold click timer and double-click flag
    $Script:ClickTimer = $null
    $Script:DoubleClickInProgress = $false
    
    # Single-click event with delay (to toggle Dev Tools)
    $controls.GUIPng.Add_Click({
        # If double-click is in progress, ignore single-click
        if ($Script:DoubleClickInProgress) {
            return
        }
        
        # Cancel existing timer if it exists
        if ($Script:ClickTimer) {
            $Script:ClickTimer.Stop()
            $Script:ClickTimer = $null
        }
        
        # Create timer for delayed single-click with longer delay
        $Script:ClickTimer = New-Object System.Windows.Threading.DispatcherTimer
        $Script:ClickTimer.Interval = [TimeSpan]::FromMilliseconds(300)  # Increased from 200ms
        $Script:ClickTimer.Add_Tick({
            # Double-check that double-click hasn't started
            if (-not $Script:DoubleClickInProgress) {
                Set-DevToolsVisibility -controls $controls -window $window
            }
            $Script:ClickTimer.Stop()
            $Script:ClickTimer = $null
        })
        $Script:ClickTimer.Start()
    })
    
    # Double-click event (open GitHub repo)
    $controls.GUIPng.Add_MouseDoubleClick({
        # Set flag to indicate double-click is in progress
        $Script:DoubleClickInProgress = $true
        
        # Stop single-click timer immediately
        if ($Script:ClickTimer) {
            $Script:ClickTimer.Stop()
            $Script:ClickTimer = $null
        }
        
        try {
            $repoUrl = "https://github.com/$($Script:WAU_GUI_REPO)"
            Start-Process $repoUrl
        } catch {
            [System.Windows.MessageBox]::Show("Failed to open GitHub repo: $($_.Exception.Message)", "Error", "OK", "Error")
        }
        
        # Reset double-click flag after a short delay
        $resetTimer = New-Object System.Windows.Threading.DispatcherTimer
        $resetTimer.Interval = [TimeSpan]::FromMilliseconds(500)
        $resetTimer.Add_Tick({
            $Script:DoubleClickInProgress = $false
            $resetTimer.Stop()
        })
        $resetTimer.Start()
    })

    $controls.DevGPOButton.Add_Click({
        try {
            Start-PopUp "WAU Policies registry opening..."
            # Open Registry Editor and navigate to WAU Policies registry key
            $regPath = $Script:WAU_POLICIES_PATH.Replace('HKLM:', 'HKEY_LOCAL_MACHINE')
            
            # Set the LastKey registry value to navigate to the desired location
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit" -Name "LastKey" -Value $regPath -Force
            
            # Open Registry Editor (it will open at the last key location)
            Start-Process "regedit.exe"

            # Update status to "Done"
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open Task Scheduler: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevTaskButton.Add_Click({
        try {
            Start-PopUp "Task scheduler opening, look in WAU folder..."
            # Open Task Scheduler
            $taskschdPath = "$env:SystemRoot\system32\taskschd.msc"
            Start-Process $taskschdPath

            # Update status to "Done"
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open Task Scheduler: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevRegButton.Add_Click({
        try {
            Start-PopUp "WAU registry opening..."
            # Open Registry Editor and navigate to WAU registry key
            $regPath = $Script:WAU_REGISTRY_PATH.Replace('HKLM:', 'HKEY_LOCAL_MACHINE')
            
            # Set the LastKey registry value to navigate to the desired location
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit" -Name "LastKey" -Value $regPath -Force
            
            # Open Registry Editor (it will open at the last key location)
            Start-Process "regedit.exe"
            
            # Update status to "Done"
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open Registry Editor: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevGUIDButton.Add_Click({
        try {
            Start-PopUp "WAU GUID paths opening..."
            # Open Registry Editor and navigate to WAU Installation GUID registry key
            $GUIDPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\${Script:WAU_GUID}"
	    
            # Set the LastKey registry value to navigate to the desired location
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit" -Name "LastKey" -Value $GUIDPath -Force
            
            # Open Registry Editor (it will open at the last key location)
            Start-Process "regedit.exe"

            # Open installer folder
            Start-Process "explorer.exe" -ArgumentList "${env:SystemRoot}\Installer\${Script:WAU_GUID}"

            # Check for install source and open only if MSI exists there
            try {
                $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Script:WAU_GUID)"
                $installSource = (Get-ItemProperty -Path $registryPath -Name "InstallSource" -ErrorAction SilentlyContinue).InstallSource
                
                if ($installSource -and (Test-Path $installSource)) {
                    $installSource = $installSource.TrimEnd('\')
                    
                    # Look for WAU MSI files (prioritize WAU.msi, then WAU-*.msi, then any *.msi)
                    $msiFile = $null
                    
                    # First try standard WAU.msi
                    $standardMsi = Join-Path $installSource "WAU.msi"
                    if (Test-Path $standardMsi) {
                        $msiFile = $standardMsi
                    } else {
                        # Then try WAU-*.msi pattern
                        $wauMsiFiles = Get-ChildItem -Path $installSource -Filter "WAU-*.msi" -File | Select-Object -First 1
                        if ($wauMsiFiles) {
                            $msiFile = $wauMsiFiles.FullName
                        } else {
                            # Finally try any *.msi file
                            $anyMsiFiles = Get-ChildItem -Path $installSource -Filter "*.msi" -File | Select-Object -First 1
                            if ($anyMsiFiles) {
                                $msiFile = $anyMsiFiles.FullName
                            }
                        }
                    }
                    
                    # Only open install source if MSI file was found
                    if ($msiFile) {
                        Start-Process "explorer.exe" -ArgumentList "/select,`"$msiFile`""
                    }
                }
            }
            catch {
                # Silent fail if we can't access install source
            }

            # Update status to "Done"
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open GUID Paths: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })
    
    $controls.DevSysButton.Add_Click({
        try {
            # Get updated config
            $updatedConfig = Get-WAUCurrentConfig
            $installdir = $updatedConfig.InstallLocation

            $systemFile = Join-Path $installdir 'config\winget_system_apps.txt'
            if (Test-Path $systemFile) {
                Start-PopUp "WinGet current list of system wide installed apps opening..."
                Start-Process "explorer.exe" -ArgumentList $systemFile
            } else {
                [System.Windows.MessageBox]::Show("No current list of WinGet system wide installed apps found", "File Not Found", "OK", "Warning")
                return
            }

            # Update status to "Done"
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open List: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevListButton.Add_Click({
        try {
            # Get updated config and policies
            $updatedConfig = Get-WAUCurrentConfig
            $updatedPolicies = $null
            try {
                $updatedPolicies = Get-ItemProperty -Path $Script:WAU_POLICIES_PATH -ErrorAction SilentlyContinue
            }
            catch {
                # GPO registry key doesn't exist or can't be read
            }
            $installdir = $updatedConfig.InstallLocation
            
            # Get the ListPath from config or policies
            $listPath = Get-DisplayValue -PropertyName "WAU_ListPath" -Config $updatedConfig -Policies $updatedPolicies
            
            if ($updatedConfig.WAU_UseWhiteList -eq 1 -or $updatedPolicies.WAU_UseWhiteList -eq 1) {
                # Check if ListPath is set to a local or UNC path for whitelist
                if (-not [string]::IsNullOrWhiteSpace($listPath) -and 
                    $listPath -ne "GPO" -and 
                    $listPath -ne "AzureBlob" -and
                    ($listPath -match '^[a-zA-Z]:\\' -or $listPath -match '^\\\\')) {
                    
                    # Use the external ListPath for whitelist
                    $whiteListFile = Join-Path $listPath 'included_apps.txt'
                    if (Test-Path $whiteListFile) {
                        Start-PopUp "WAU included apps list opening..."
                        Start-Process "explorer.exe" -ArgumentList $whiteListFile
                    } else {
                        [System.Windows.MessageBox]::Show("No included apps list found in external path ('$listPath\included_apps.txt')", "File Not Found", "OK", "Warning")
                        return
                    }
                } else {
                    # Use the default WAU installation directory for whitelist
                    $whiteListFile = Join-Path $installdir 'included_apps.txt'
                    if (Test-Path $whiteListFile) {
                        Start-PopUp "WAU included apps list opening..."
                        Start-Process "explorer.exe" -ArgumentList $whiteListFile
                    } else {
                        [System.Windows.MessageBox]::Show("No included apps list found ('included_apps.txt')", "File Not Found", "OK", "Warning")
                        return
                    }
                }
            } else {
                # Check if ListPath is set to a local or UNC path for excluded list
                if (-not [string]::IsNullOrWhiteSpace($listPath) -and 
                    $listPath -ne "GPO" -and 
                    $listPath -ne "AzureBlob" -and
                    ($listPath -match '^[a-zA-Z]:\\' -or $listPath -match '^\\\\')) {
                    
                    # Use the external ListPath for excluded list
                    $excludedFile = Join-Path $listPath 'excluded_apps.txt'
                    if (Test-Path $excludedFile) {
                        Start-PopUp "WAU excluded apps list opening..."
                        Start-Process "explorer.exe" -ArgumentList $excludedFile
                    } else {
                        [System.Windows.MessageBox]::Show("No excluded apps list found in external path ('$listPath\excluded_apps.txt')", "File Not Found", "OK", "Warning")
                        return
                    }
                } else {
                    # Use the default WAU installation directory for excluded list
                    $excludedFile = Join-Path $installdir 'excluded_apps.txt'
                    $defaultExcludedFile = Join-Path $installdir 'config\default_excluded_apps.txt'
                    if (Test-Path $excludedFile) {
                        Start-PopUp "WAU excluded apps list opening..."
                        Start-Process "explorer.exe" -ArgumentList $excludedFile
                    } elseif (Test-Path $defaultExcludedFile) {
                        Start-PopUp "WAU default excluded apps List opening..."
                        Start-Process "explorer.exe" -ArgumentList $defaultExcludedFile
                    } else {
                        [System.Windows.MessageBox]::Show("No excluded apps list found (neither 'excluded_apps.txt' nor 'config\default_excluded_apps.txt').", "File Not Found", "OK", "Warning")
                        return
                    }
                }
            }

            # Update status to "Done"
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open List: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevUsrButton.Add_Click({
        try {
            $modulesPath = Join-Path $Script:WorkingDir "modules"
            $configUserModulePath = Join-Path $modulesPath "config_user.psm1"
            $workingDirConfigUserPath = Join-Path $Script:WorkingDir "config_user.psm1"
            
            # Check if config_user.psm1 exists in modules folder
            if (Test-Path $configUserModulePath) {
                Start-PopUp "'config_user.psm1' opening from modules folder..."
                Start-Process "explorer.exe" -ArgumentList $configUserModulePath
            }
            # If not in modules, check if it exists in working directory
            elseif (Test-Path $workingDirConfigUserPath) {
                Start-PopUp "Copying 'config_user.psm1' to modules folder and opening..."
                
                # Ensure modules directory exists
                if (-not (Test-Path $modulesPath)) {
                    New-Item -ItemType Directory -Path $modulesPath -Force | Out-Null
                }
                
                # Copy from working directory to modules
                Copy-Item -Path $workingDirConfigUserPath -Destination $configUserModulePath -Force
                
                # Open the copied file
                Start-Process "explorer.exe" -ArgumentList $configUserModulePath
            }
            else {
                Close-PopUp
                [System.Windows.MessageBox]::Show("'config_user.psm1' not found in either working directory or modules folder.", "File Not Found", "OK", "Warning")
                return
            }
    
            # Update status to "Done"
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                Close-PopUp
            }) | Out-Null
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to handle 'config_user.psm1': $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevMSIButton.Add_Click({
        if (New-WAUTransformFile -controls $controls) {
            # Update status to "Done"
            $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
            $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
            
            # Create timer to reset status back to ready after standard wait time
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
            }) | Out-Null
        }
    })

    $controls.DevCfgButton.Add_Click({
        try {
            # Create backup directory for current settings
            $cfgDir = Join-Path $Script:WorkingDir "cfg"
            if (-not (Test-Path $cfgDir)) {
                New-Item -Path $cfgDir -ItemType Directory -Force | Out-Null
            }
            
            $computerName = $env:COMPUTERNAME
            $dateTime = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
            $backupFile = "$cfgDir\WAU Settings-$computerName-$dateTime.reg.txt"
            $tempBackupFile = "$cfgDir\WAU Settings-$computerName-$dateTime-temp.reg.txt"
            
            # Export current registry settings to temporary backup file
            $regKeyPath = $Script:WAU_REGISTRY_PATH.Replace('HKLM:', 'HKEY_LOCAL_MACHINE')
            $null = reg export $regKeyPath $tempBackupFile /y
            
            # Verify the export was successful
            if (-not (Test-Path $tempBackupFile) -or (Get-Item $tempBackupFile).Length -eq 0) {
                throw "Registry export failed or created empty file"
            }
            
            # Filter out unwanted registry values
            $content = Get-Content -Path $tempBackupFile -Encoding UTF8
            $filteredContent = $content | Where-Object {
                $_ -notmatch '"ProductVersion"=' -and
                $_ -notmatch '"InstallLocation"=' -and
                $_ -notmatch '"WAU_RunGPOManagement"='
            }
            
            # Save filtered content to final backup file
            Set-Content -Path $backupFile -Value $filteredContent -Encoding UTF8
            
            # Remove temporary file
            Remove-Item -Path $tempBackupFile -Force -ErrorAction SilentlyContinue
            
            # Verify the filtered backup was created successfully
            if (-not (Test-Path $backupFile) -or (Get-Item $backupFile).Length -eq 0) {
                throw "Filtered backup file creation failed"
            }
            
            # Show messagebox about backup and ask if user wants to import another file
            $importMsg = "A backup of your current settings has been saved to:`n$backupFile`n`nDo you want to continue and import a WAU Settings file?"
            $result = [System.Windows.MessageBox]::Show($importMsg, "Backup Created", "OKCancel", "Question", "Ok")
            if ($result -eq 'Cancel') {
                # Open the folder containing the backup file
                Start-Process "explorer.exe" -ArgumentList "/select,`"$backupFile`""
                return
            }

            Start-PopUp "Locate WAU Settings file..."

            # Open file dialog for importing settings
            $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
            $openFileDialog.Filter = "Registry Text Files (*.reg.txt)|*.reg.txt|Registry Files (*.reg)|*.reg"
            $openFileDialog.Title = "Select WAU Settings file to import"
            
            # Try Desktop, then Documents
           if (Test-Path ([Environment]::GetFolderPath('Desktop'))) {
                $openFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
            } else {
                $openFileDialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
            }
            
            $openFileDialog.RestoreDirectory = $true

            if ($openFileDialog.ShowDialog() -eq 'OK') {
                # Read and parse selected file
                Import-WAUSettingsFromFile -FilePath $openFileDialog.FileName -Controls $controls
                
                Close-PopUp

                # Update GUI with imported settings (without saving to registry)
                [System.Windows.MessageBox]::Show(
                    "Settings loaded from file.`nNote: Settings are not saved yet - 'Save Settings' if you want to keep them.", 
                    "Configuration Imported", 
                    "OK", 
                    "Information"
                )
            }
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to import configuration: $($_.Exception.Message)", "Error", "OK", "Error")
        }
        Close-PopUp
    })

    $controls.DevWAUButton.Add_Click({
        try {
            # Check if WAU is installed
            $installedWAU = Test-InstalledWAU -DisplayName "Winget-AutoUpdate"

            if ($installedWAU.Count -gt 0) {
                # WAU is installed - get version info from registry
                $savedVersion = $null
                try {
                    if ($Script:WAU_GUID) {
                        $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($Script:WAU_GUID)"
                        $wauRegistry = Get-ItemProperty -Path $registryPath -ErrorAction Stop
                        $comments = $wauRegistry.Comments
                        $displayVersion = $wauRegistry.DisplayVersion
                        if ($comments -and $comments -ne "STABLE") {
                            if ($comments -match "WAU\s+([0-9]+\.[0-9]+\.[0-9]+(?:-\d+)?)(?:\s|\[)") {
                                $savedVersion = "v$($matches[1])"
                            } else {
                                $savedVersion = "v$displayVersion"
                            }
                        } else {
                            $savedVersion = "v$($displayVersion -replace '\.\d+$', '')"
                        }
                    }
                } catch {}

                # Always do reinstall if WAU is installed
                $result = [System.Windows.MessageBox]::Show(
                    "WAU is installed ($savedVersion).`n`nDo you want to reinstall WAU with the current showing configuration?",
                    "Reinstall WAU",
                    "OkCancel",
                    "Question"
                )
                if ($result -eq 'Ok') {
                    $msiResult = Get-WAUMsi -SpecificVersion $savedVersion
                    if ($msiResult -and $msiResult.MsiFilePath) {
                        $uninstallResult = Uninstall-WAU
                        if ($uninstallResult) {
                            $installResult = Install-WAU -msiFilePath $msiResult.MsiFilePath -controls $controls
                            if ($installResult) {
                                Update-WAUGUIFromConfig -Controls $controls
                            }
                        }
                    }
                }
            } else {
                # WAU is not installed
                $result = [System.Windows.MessageBox]::Show(
                    "WAU is not installed.`n`nDo you want to download and install WAU with the current settings?",
                    "Install WAU",
                    "OkCancel",
                    "Question"
                )
                if ($result -eq 'Ok') {
                    $msiResult = Get-WAUMsi
                    if ($msiResult -and $msiResult.MsiFilePath) {
                        $installResult = Install-WAU -msiFilePath $msiResult.MsiFilePath -controls $controls
                        if ($installResult) {
                            Update-WAUGUIFromConfig -Controls $controls
                        }
                    }
                }
            }

            # Timer to reset status bar
            $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                Start-Sleep -Milliseconds $Script:WAIT_TIME
                $controls.StatusBarText.Text = $Script:STATUS_READY_TEXT
                $controls.StatusBarText.Foreground = $Script:COLOR_INACTIVE
            }) | Out-Null
        }
        catch {
            [System.Windows.MessageBox]::Show("Error during WAU reinstall: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevVerButton.Add_Click({
        try {
            # Check for existing backups first
            $backupDir = Join-Path $Script:WorkingDir "ver\backup"
            $hasBackups = $false
            $backupFiles = @()
            
            if (Test-Path $backupDir) {
                $backupFiles = Get-ChildItem -Path $backupDir -Filter "*.zip" | Sort-Object CreationTime -Descending
                $hasBackups = $backupFiles.Count -gt 0
            }
            
            if ($hasBackups) {
                # Show dialog with update/restore options
                $backupList = ($backupFiles | Select-Object -First 5 | ForEach-Object { 
                    "- $($_.Name) ($(Get-Date $_.CreationTime -Format 'yyyy-MM-dd HH:mm'))"
                }) -join "`n"
                
                $message = "Available backup versions:`n$backupList`n`nWhat would you like to do?`n`nChoose Yes to update, No to restore, or Cancel to exit."
                $result = [System.Windows.MessageBox]::Show(
                    $message,
                    "Update or Restore?",
                    "YesNoCancel",
                    "Question",
                    "Yes"
                )
                                
                switch ($result) {
                    'Yes' {
                        # Continue with update check
                        Start-PopUp "Checking for updates..."
                        $updateInfo = Test-WAUGUIUpdate
                        Close-PopUp
                        
                        if ($updateInfo.Error) {
                            [System.Windows.MessageBox]::Show("Failed to check for updates: $($updateInfo.Error)", "Update Check Failed", "OK", "Warning")
                            return
                        }
                        
                        if ($updateInfo.UpdateAvailable) {
                            $notesText = Get-CleanReleaseNotes -RawNotes $updateInfo.ReleaseNotes
                            $updateMessage = "Update available!`r`n`r`nCurrent version: $($updateInfo.CurrentVersion)`r`nLatest version: $($updateInfo.LatestVersion)`r`nRelease notes:`r`n$notesText`r`n`r`nDo you want to download the update?"
                            $updateResult = [System.Windows.MessageBox]::Show($updateMessage, "Update Available", "OkCancel", "Question")
                            
                            if ($updateResult -eq 'Ok') {
                                Start-WAUGUIUpdate -updateInfo $updateInfo
                            }
                        } else {
                            [System.Windows.MessageBox]::Show("You are running the latest version ($($updateInfo.CurrentVersion))", "No Updates Available", "OK", "Information")
                        }
                    }
                    'No' {
                        # Show restore dialog
                        Start-PopUp "Select backup to restore..."
                        
                        # Create custom selection dialog
                        $restoreDialog = New-Object System.Windows.Forms.Form
                        $restoreDialog.Text = "Select Backup to Restore"
                        $restoreDialog.Size = New-Object System.Drawing.Size(500, 300)
                        $restoreDialog.StartPosition = "CenterParent"
                        $restoreDialog.FormBorderStyle = "FixedDialog"
                        $restoreDialog.MaximizeBox = $false
                        $restoreDialog.MinimizeBox = $false
                        
                        $listBox = New-Object System.Windows.Forms.ListBox
                        $listBox.Location = New-Object System.Drawing.Point(10, 10)
                        $listBox.Size = New-Object System.Drawing.Size(460, 200)
                        
                        foreach ($backup in $backupFiles) {
                            $displayText = "$($backup.Name) - $(Get-Date $backup.CreationTime -Format 'yyyy-MM-dd HH:mm:ss')"
                            $listBox.Items.Add($displayText) | Out-Null
                        }
                        
                        $restoreButton = New-Object System.Windows.Forms.Button
                        $restoreButton.Location = New-Object System.Drawing.Point(310, 220)
                        $restoreButton.Size = New-Object System.Drawing.Size(75, 23)
                        $restoreButton.Text = "Restore"
                        $restoreButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
                        
                        $cancelButton = New-Object System.Windows.Forms.Button
                        $cancelButton.Location = New-Object System.Drawing.Point(395, 220)
                        $cancelButton.Size = New-Object System.Drawing.Size(75, 23)
                        $cancelButton.Text = "Cancel"
                        $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
                        
                        $restoreDialog.Controls.Add($listBox)
                        $restoreDialog.Controls.Add($restoreButton)
                        $restoreDialog.Controls.Add($cancelButton)
                        $restoreDialog.AcceptButton = $restoreButton
                        $restoreDialog.CancelButton = $cancelButton
                        
                        Close-PopUp
                        
                        if ($restoreDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and $listBox.SelectedIndex -ge 0) {
                            $selectedBackup = $backupFiles[$listBox.SelectedIndex]
                            
                            $confirmRestore = [System.Windows.MessageBox]::Show(
                                "Are you sure you want to restore from:`n$($selectedBackup.Name)`n`nThis will replace all current files and restart the application.",
                                "Confirm Restore",
                                "YesNo",
                                "Warning",
                                "No"
                            )
                            
                            if ($confirmRestore -eq 'Yes') {
                                Start-RestoreFromBackup -backupPath $selectedBackup.FullName -controls $controls -window $window
                            }
                        }
                        
                        $restoreDialog.Dispose()
                    }
                    'Cancel' {
                        # Do nothing
                        return
                    }
                }
            } else {
                # No backups available, proceed with normal update check
                Start-PopUp "Checking for updates..."
                $updateInfo = Test-WAUGUIUpdate
                Close-PopUp
                
                if ($updateInfo.Error) {
                    [System.Windows.MessageBox]::Show("Failed to check for updates: $($updateInfo.Error)", "Update Check Failed", "OK", "Warning")
                    return
                }
                
                if ($updateInfo.UpdateAvailable) {
                    $notesText = Get-CleanReleaseNotes -RawNotes $updateInfo.ReleaseNotes
                    $message = "Update available!`r`n`r`nCurrent version: $($updateInfo.CurrentVersion)`r`nLatest version: $($updateInfo.LatestVersion)`r`nRelease notes:`r`n$notesText`r`n`r`nDo you want to download the update?"
                    $result = [System.Windows.MessageBox]::Show($message, "Update Available", "OkCancel", "Question")
                    
                    if ($result -eq 'Ok') {
                        Start-WAUGUIUpdate -updateInfo $updateInfo
                    }
                } else {
                    [System.Windows.MessageBox]::Show("You are running the latest version ($($updateInfo.CurrentVersion))", "No Updates Available", "OK", "Information")
                }
            }
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to check for updates: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.DevSrcButton.Add_Click({
        Start-PopUp "WAU Settings GUI install folder opening..."
        Start-Process "explorer.exe" -ArgumentList $Script:WorkingDir
        # Update status to "Done"
        $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
        $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
        
        # Create timer to reset status back to "$Script:STATUS_READY_TEXT" after standard wait time
        # Use Invoke-Async to avoid blocking
        $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Start-Sleep -Milliseconds $Script:WAIT_TIME
            $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
            $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
            Close-PopUp
        }) | Out-Null
    })

    # Save button handler to save settings
    $controls.SaveButton.Add_Click({
        Save-WAUSettings -controls $controls
    })

    # Cancel button handler to close window
    $controls.CancelButton.Add_Click({
        Close-WindowGracefully -controls $controls -window $window
    })
    
    $controls.RunNowButton.Add_Click({
        Start-PopUp "WAU Update task starting..."
        Start-WAUManually
        # Update status to "Done"
        $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
        $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
        
        # Create timer to reset status back to "$Script:STATUS_READY_TEXT" after standard wait time
        # Use Invoke-Async to avoid blocking
        $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
            Start-Sleep -Milliseconds $Script:WAIT_TIME
            $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
            $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
            Close-PopUp
        }) | Out-Null
    })

    # Key Handlers
    $window.Add_PreviewKeyDown({
        Test-WindowKeyPress -controls $controls -window $window -keyEventArgs $_
    })
    
    $controls.OpenLogsButton.Add_Click({
        try {
            Start-PopUp "WAU Log directory opening..."
            $logPath = Join-Path $currentConfig.InstallLocation "logs"
            if (Test-Path $logPath) {
                Start-Process "explorer.exe" -ArgumentList $logPath
                # Update status to "Done"
                $controls.StatusBarText.Text = $Script:STATUS_DONE_TEXT
                $controls.StatusBarText.Foreground = $Script:COLOR_ENABLED
                
                # Create timer to reset status back to "$Script:STATUS_READY_TEXT" after standard wait time
                # Use Invoke-Async to avoid blocking
                $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
                    Start-Sleep -Milliseconds $Script:WAIT_TIME
                    $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
                    $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"
                    Close-PopUp
                }) | Out-Null
            } else {
                Close-PopUp
                [System.Windows.MessageBox]::Show("Log directory not found: $logPath", "Error", "OK", "Error")
            }
        }
        catch {
            Close-PopUp
            [System.Windows.MessageBox]::Show("Failed to open logs: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    # Event handlers for information links
    $controls.WAUSettingsVersionLink.Add_RequestNavigate({
        param($linkSource, $e)
        try {
            Start-Process $e.Uri.ToString()
            $e.Handled = $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open link: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.WAUVersionLink.Add_RequestNavigate({
        param($linkSource, $e)
        try {
            Start-Process $e.Uri.ToString()
            $e.Handled = $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open link: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    $controls.WinGetVersionLink.Add_RequestNavigate({
        param($linkSource, $e)
        try {
            Start-Process $e.Uri.ToString()
            $e.Handled = $true
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to open link: $($_.Exception.Message)", "Error", "OK", "Error")
        }
    })

    Close-PopUp

    # Create timer to reset status back to "$Script:STATUS_READY_TEXT" after STANDARD wait time
    # Use Invoke-Async to avoid blocking
    $window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{
        Start-Sleep -Milliseconds $Script:WAIT_TIME
        $controls.StatusBarText.Text = "$Script:STATUS_READY_TEXT"
        $controls.StatusBarText.Foreground = "$Script:COLOR_INACTIVE"

   }) | Out-Null
    
    Test-WAULists -controls $controls -updatedConfig $currentConfig

   # Show window
    $window.ShowDialog() | Out-Null
}

<# MAIN #>
# Set console encoding
$null = cmd /c ''
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'SilentlyContinue'

# Check if running as administrator
if (-not (Test-Administrator)) {
    # Import required assemblies
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("This application must be run as Administrator to modify WAU settings.", "Administrator Required", "OK", "Warning")
    exit 1
}

# Version information, takes care of if upgraded from external (WinGet/WAU)
$exePath = Join-Path $Script:WorkingDir "$Script:WAU_GUI_NAME.exe"
$uninstPath = Join-Path $Script:WorkingDir "UnInst.exe"

# Set default version before attempting to read
$Script:WAU_GUI_VERSION = "0.0.0.0"

if (Test-Path $exePath) {
    try {
        $fileVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($exePath)
        $Script:WAU_GUI_VERSION = $fileVersionInfo.ProductVersion
        
        # Check if UnInst.exe exists and if versions differ
        if (Test-Path $uninstPath) {
            try {
                $uninstVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($uninstPath)
                $uninstVersion = $uninstVersionInfo.ProductVersion
                
                # If versions differ, delete UnInst.exe
                if ($Script:WAU_GUI_VERSION -ne $uninstVersion) {
                    Remove-Item -Path $uninstPath -Force -ErrorAction SilentlyContinue
                }
            }
            catch {
                # If we can't read UnInst.exe version, delete it to be safe
                Remove-Item -Path $uninstPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        # If we can't read main exe version, keep default "0.0.0.0"
        # Don't remove UnInst.exe here to avoid creating a loop
    }
} else {
    # If main exe doesn't exist but UnInst.exe does, get version from UnInst.exe and copy it
    if (Test-Path $uninstPath) {
        try {
            $uninstVersionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($uninstPath)
            $Script:WAU_GUI_VERSION = $uninstVersionInfo.ProductVersion
        }
        catch {
            # Keep default "0.0.0.0" if we can't read UnInst.exe version
        }
        Copy-Item -Path $uninstPath -Destination $exePath -Force -ErrorAction SilentlyContinue
    }
    # If neither file exists, keep default "0.0.0.0"
}

# Ensure the original version ZIP exists in \ver
$verDir = Join-Path $Script:WorkingDir "ver"
if (-not (Test-Path $verDir)) {
    New-Item -ItemType Directory -Path $verDir -Force | Out-Null
}

$expectedZipName = "*$Script:WAU_GUI_VERSION*.zip"
$existingZip = Get-ChildItem -Path $verDir -Filter $expectedZipName -File | Select-Object -First 1

if (-not $existingZip) {
    try {
        # Fetch latest release info from GitHub
        $apiUrl = "https://api.github.com/repos/$Script:WAU_GUI_REPO/releases"
        $releases = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $release = $releases | Where-Object { $_.tag_name.TrimStart('v') -eq $Script:WAU_GUI_VERSION } | Select-Object -First 1
        if (-not $release) {
            throw "No GitHub release found for version $Script:WAU_GUI_VERSION"
        }

        # Look for the correct asset
        $asset = $release.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
        if (-not $asset) {
            throw "No ZIP file found in the GitHub release for version $Script:WAU_GUI_VERSION"
        }

        $downloadPath = Join-Path $verDir $asset.name
        # Download the ZIP file
        $headers = @{ 'User-Agent' = 'WAU-Settings-GUI-Repair/1.0' }
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -UseBasicParsing -Headers $headers

        # Validate that it is a valid ZIP
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        try {
            [System.IO.Compression.ZipFile]::OpenRead($downloadPath).Dispose()
        } catch {
            Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue
            throw "The downloaded file is not a valid ZIP archive."
        }
    } catch {
        # Import required assemblies
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Could not download the original version ZIP for repair:`n$($_.Exception.Message)", "Download Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

# Initialize
try {
    Initialize-GUI
} catch {
    [System.Windows.Forms.MessageBox]::Show("Error: $($_.Exception.Message)", "Application Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}

# Set WAU Settings GUI icon
$guiIconPath = Join-Path $Script:WorkingDir "config\WAU Settings GUI.ico"
if (Test-Path $guiIconPath) {
    $Script:GUI_ICON = $guiIconPath
} else {
    Write-Host "GUI icon missing. Attempting repair..." -ForegroundColor Yellow
    $repairResult = Repair-WAUSettingsFiles -MissingFiles @("config\WAU Settings GUI.ico") -Silent
    
    if ($repairResult.Success -and (Test-Path $guiIconPath)) {
        $Script:GUI_ICON = $guiIconPath
        Write-Host "GUI icon repaired successfully." -ForegroundColor Green
    } else {
        # Fallback to PowerShell icon
        $iconSource = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $systemTemp = [System.Environment]::GetEnvironmentVariable("TEMP", [System.EnvironmentVariableTarget]::Machine)
        if (-not $systemTemp) { $systemTemp = "$env:SystemRoot\Temp" }
        $iconDest = Join-Path $systemTemp "icon.ico"
        
        if (-not (Test-Path $iconDest)) {
            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconSource)
            $fs = [System.IO.File]::Open($iconDest, [System.IO.FileMode]::Create)
            $icon.Save($fs)
            $fs.Close()
        }
        $Script:GUI_ICON = $iconDest
        Write-Host "Using fallback icon." -ForegroundColor Yellow
    }
}

# Load PopUp XAML from config file and store as constant
$xamlConfigPath = Join-Path $Script:WorkingDir "config\settings-popup.xaml"
if (Test-Path $xamlConfigPath) {
    $inputXML = Get-Content $xamlConfigPath -Raw
    $inputXML = $inputXML -replace '\$Script:GUI_TITLE', $Script:GUI_TITLE
    $Script:POPUP_XAML = $inputXML.Trim()
} else {
    Write-Host "PopUp XAML missing. Attempting repair..." -ForegroundColor Yellow
    $repairResult = Repair-WAUSettingsFiles -MissingFiles @("config\settings-popup.xaml") -Silent
    
    if ($repairResult.Success -and (Test-Path $xamlConfigPath)) {
        $inputXML = Get-Content $xamlConfigPath -Raw
        $inputXML = $inputXML -replace '\$Script:GUI_TITLE', $Script:GUI_TITLE
        $Script:POPUP_XAML = $inputXML.Trim()
        Write-Host "PopUp XAML repaired successfully." -ForegroundColor Green
    } else {
        [System.Windows.MessageBox]::Show("Critical file missing and repair failed: config\settings-popup.xaml`n`n$($repairResult.Message)", "$Script:GUI_TITLE", "OK", "Error")
        exit 1
    }
}

#Pop "Starting..."
Start-PopUp "Gathering WAU Data..."

# Remove old config\version.txt if it exists
$oldVersionFile = Join-Path $Script:WorkingDir "config\version.txt"
if (Test-Path $oldVersionFile) {
    Remove-Item $oldVersionFile -Force -ErrorAction SilentlyContinue
}

# Load Window XAML from config file and store as constant
$xamlConfigPath = Join-Path $Script:WorkingDir "config\settings-window.xaml"
$guiPngPath = Join-Path $Script:WorkingDir "config\WAU Settings GUI.png"

# Check for missing config files
$missingConfigFiles = @()
if (-not (Test-Path $xamlConfigPath)) { $missingConfigFiles += "config\settings-window.xaml" }
if (-not (Test-Path $guiPngPath)) { $missingConfigFiles += "config\WAU Settings GUI.png" }

if ($missingConfigFiles.Count -gt 0) {
    Write-Host "Config files missing. Attempting repair..." -ForegroundColor Yellow
    $repairResult = Repair-WAUSettingsFiles -MissingFiles $missingConfigFiles -Silent
    
    if (-not $repairResult.Success) {
        [System.Windows.MessageBox]::Show("Critical files missing and repair failed:`n$($missingConfigFiles -join ', ')`n`n$($repairResult.Message)", "$Script:GUI_TITLE", "OK", "Error")
        exit 1
    }
    Write-Host "Config files repaired successfully." -ForegroundColor Green
}

# Set PNG path
if (Test-Path $guiPngPath) {
    $Script:WAU_GUI_PNG = $guiPngPath
}

# Load and process XAML
if (Test-Path $xamlConfigPath) {
    $inputXML = Get-Content $xamlConfigPath -Raw
    $inputXML = $inputXML -replace '\$Script:GUI_TITLE', $Script:GUI_TITLE
    $inputXML = $inputXML -replace '\$Script:WAU_GUI_PNG', $Script:WAU_GUI_PNG
    $inputXML = $inputXML -replace '\$Script:COLOR_ENABLED', $Script:COLOR_ENABLED
    $inputXML = $inputXML -replace '\$Script:COLOR_DISABLED', $Script:COLOR_DISABLED
    $inputXML = $inputXML -replace '\$Script:COLOR_ACTIVE', $Script:COLOR_ACTIVE
    $inputXML = $inputXML -replace '\$Script:COLOR_INACTIVE', $Script:COLOR_INACTIVE
    $inputXML = $inputXML -replace '\$Script:STATUS_READY_TEXT', $Script:STATUS_READY_TEXT
    $Script:WINDOW_XAML = $inputXML.Trim()
} else {
    [System.Windows.MessageBox]::Show("Critical error: Window XAML still missing after repair attempt", "$Script:GUI_TITLE", "OK", "Error")
    exit 1
}

# Get WAU installation info and store as constants
$Script:WAU_INSTALL_INFO = Test-InstalledWAU -DisplayName "Winget-AutoUpdate"
$Script:WAU_VERSION = if ($Script:WAU_INSTALL_INFO.Count -ge 1) { $Script:WAU_INSTALL_INFO[0] } else { "Unknown" }
$Script:WAU_GUID = if ($Script:WAU_INSTALL_INFO.Count -ge 2) { $Script:WAU_INSTALL_INFO[1] } else { $null }
$wauIconPath = "${env:SystemRoot}\Installer\${Script:WAU_GUID}\icon.ico"
if (Test-Path $wauIconPath) {
    $Script:WAU_ICON = $wauIconPath
} else {
    # If missing, fallback and extract icon from PowerShell.exe and save as icon.ico in SYSTEM TEMP
    $iconSource = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $systemTemp = [System.Environment]::GetEnvironmentVariable("TEMP", [System.EnvironmentVariableTarget]::Machine)
    if (-not $systemTemp) { $systemTemp = "$env:SystemRoot\Temp" }
    $iconDest = Join-Path $systemTemp "icon.ico"
    # Only extract if the icon doesn't already exist
    if (-not (Test-Path $iconDest)) {
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($iconSource)
        $fs = [System.IO.File]::Open($iconDest, [System.IO.FileMode]::Create)
        $icon.Save($fs)
        $fs.Close()
    }
    $Script:WAU_ICON = $iconDest
}

# Get WinGet version by running 'winget -v'
try {
    $wingetVersionOutput = winget -v 2>$null
    $Script:WINGET_VERSION = $wingetVersionOutput.Trim().TrimStart("v")
} catch {
    $Script:WINGET_VERSION = "Unknown"
}

# Show the GUI
Show-WAUSettingsGUI



