function SandboxTest {
    [CmdletBinding()]
    param(
        [ScriptBlock] $Script,
        [string] $MapFolder,
        [string] $SandboxFolderName,
        [string] $WinGetVersion,
        [switch] $Prerelease,
        [switch] $Clean,
        [switch] $Async
    )
    <#
    .SYNOPSIS
    Starts a Windows Sandbox environment with WinGet installed for testing purposes.
    
    .DESCRIPTION
    This function creates and launches a Windows Sandbox with WinGet CLI installed and configured.
    It can execute custom scripts, map folders, and configure various WinGet options.
    
    .PARAMETER Script
    The script block to run in the Sandbox.
    
    .PARAMETER MapFolder
    The folder to map in the Sandbox.
    
    .PARAMETER SandboxFolderName
    Optional: The folder name to use inside the Sandbox Desktop for the mapped folder. If omitted, the leaf name of
    the host path is used.
    
    .PARAMETER WinGetVersion
    The version of WinGet to use.

    .PARAMETER Prerelease
    Include prerelease versions of WinGet.

    .PARAMETER Clean
    Clean existing cached dependencies before starting.
    
    .EXAMPLE
    SandboxTest -Script { Start-Process cmd.exe -ArgumentList "/c del /Q ""$env:USERPROFILE\Desktop\WAU-install\*.log"" & ""$env:USERPROFILE\Desktop\WAU-install\InstallWSB.cmd"" && explorer ""$env:USERPROFILE\Desktop\WAU-install""" } -Verbose

    .EXAMPLE
    SandboxTest -MapFolder "D:\WAU Settings GUI\msi\2.8.0"
    #>
    

    # Exit Codes:
    # -1 = Sandbox is not enabled
    #  0 = Success
    #  1 = Error fetching GitHub release
    #  2 = Unable to kill a running process

    # Helper functions
    function Test-FileChecksum {
        param (
            [Parameter(Mandatory = $true)]
            [String] $ExpectedChecksum,
            [Parameter(Mandatory = $true)]
            [String] $Path,
            [Parameter()]
            [String] $Algorithm = 'SHA256'
        )
        $currentHash = Get-FileHash -Path $Path -Algorithm $Algorithm -ErrorAction SilentlyContinue
        return ($currentHash -and $currentHash.Hash -eq $ExpectedChecksum)
    }

    enum DependencySources {
        InRelease
        Legacy
    }

    # Script Behaviors
    $ProgressPreference = 'SilentlyContinue'
    $ErrorActionPreference = 'Stop'
    if ($PSBoundParameters.Keys -notcontains 'InformationAction') { $InformationPreference = 'Continue' }
    $script:UseNuGetForMicrosoftUIXaml = $false
    $script:ScriptName = 'SandboxTest'
    $script:AppInstallerPFN = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe'
    $script:DependenciesBaseName = 'DesktopAppInstaller_Dependencies'
    $script:ReleasesApiUrl = 'https://api.github.com/repos/microsoft/winget-cli/releases?per_page=100'
    $script:DependencySource = [DependencySources]::InRelease
    $script:UsePowerShellModuleForInstall = $false

    # Bind function parameters to script-scoped variables used later
    $script:Prerelease     = [bool]$Prerelease
    $script:WinGetVersion  = $WinGetVersion

    # File Names
    $script:AppInstallerMsixFileName = "$script:AppInstallerPFN.msixbundle"
    $script:DependenciesZipFileName = "$script:DependenciesBaseName.zip"

    # Download Urls
    $script:VcLibsDownloadUrl = 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx'
    $script:UiLibsDownloadUrl_v2_7 = 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.7.3/Microsoft.UI.Xaml.2.7.x64.appx'
    $script:UiLibsDownloadUrl_v2_8 = 'https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx'
    $script:UiLibsDownloadUrl_NuGet = 'https://globalcdn.nuget.org/packages/microsoft.ui.xaml.2.8.6.nupkg?packageVersion=2.8.6'

    # Expected Hashes
    $script:VcLibsHash = 'B56A9101F706F9D95F815F5B7FA6EFBAC972E86573D378B96A07CFF5540C5961'
    $script:UiLibsHash_v2_7 = '8CE30D92ABEC6522BEB2544E7B716983F5CBA50751B580D89A36048BF4D90316'
    $script:UiLibsHash_v2_8 = '249D2AFB41CC009494841372BD6DD2DF46F87386D535DDF8D9F32C97226D2E46'
    $script:UiLibsHash_NuGet = '6B62BD3C277F55518C3738121B77585AC5E171C154936EC58D87268BBAE91736'

    # File Paths
    $script:AppInstallerDataFolder = Join-Path -Path (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Packages') -ChildPath $script:AppInstallerPFN
    $script:DependenciesCacheFolder = Join-Path -Path $script:AppInstallerDataFolder -ChildPath "$script:ScriptName.Dependencies"
    $script:TestDataFolder = Join-Path -Path $script:AppInstallerDataFolder -ChildPath $script:ScriptName
    $script:PrimaryMappedFolder = if ($MapFolder) { (Resolve-Path -Path $MapFolder).Path } else { $null }
    # Validate optional SandboxFolderName
    if ($SandboxFolderName) {
        $SandboxFolderName = $SandboxFolderName.Trim()
        $invalidNameChars = [System.IO.Path]::GetInvalidFileNameChars()
        if ($SandboxFolderName.IndexOfAny($invalidNameChars) -ge 0) {
            throw "SandboxFolderName contains invalid characters."
        }
    }

    # Starting
    Write-Information '--> Starting SandboxTest'

    $script:ConfigurationFile = Join-Path -Path $script:TestDataFolder -ChildPath "$script:ScriptName.wsb"
    Write-Verbose "PrimaryMappedFolder: $script:PrimaryMappedFolder"

    # Sandbox Settings
    $script:SandboxDesktopFolder = 'C:\Users\WDAGUtilityAccount\Desktop'
    $sandboxLeaf = if ($SandboxFolderName) {
        $SandboxFolderName
    } elseif ($script:PrimaryMappedFolder) {
        $leaf = $script:PrimaryMappedFolder | Split-Path -Leaf
        # Check if it's a root drive (contains : or is a path like D:\)
        if (![string]::IsNullOrWhiteSpace($leaf) -and $leaf -notmatch ':' -and $leaf -ne '\') {
            $leaf
        } else {
            # Root drive selected (e.g., D:\) - extract drive letter
            $driveLetter = $script:PrimaryMappedFolder.TrimEnd('\').Replace(':', '')
            if (![string]::IsNullOrWhiteSpace($driveLetter)) {
                "Drive_$driveLetter"
            } else {
                'MappedFolder'
            }
        }
    } else {
        ''
    }
    $script:SandboxWorkingDirectory = if ($script:PrimaryMappedFolder) { Join-Path -Path $script:SandboxDesktopFolder -ChildPath $sandboxLeaf } else { $script:SandboxDesktopFolder }
    $script:SandboxTestDataFolder = Join-Path -Path $script:SandboxDesktopFolder -ChildPath $($script:TestDataFolder | Split-Path -Leaf)
    $script:SandboxBootstrapFile = Join-Path -Path $script:SandboxTestDataFolder -ChildPath "$script:ScriptName.ps1"
    $script:HostGeoID = (Get-WinHomeLocation).GeoID

    # Detect host dark mode settings to replicate in sandbox
    $script:HostAppsUseLightTheme = try {
        (Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue).AppsUseLightTheme
    } catch { 0 }  # Default to dark if unable to detect

    $script:HostSystemUsesLightTheme = try {
        (Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -ErrorAction SilentlyContinue).SystemUsesLightTheme
    } catch { 0 }  # Default to dark if unable to detect

    # Misc
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Ensure the System.Net.Http assembly is loaded
    Add-Type -AssemblyName System.Net.Http
    $script:HttpClient = New-Object System.Net.Http.HttpClient
    $script:CleanupPaths = @()

    $script:SandboxWinGetSettings = @{
        '$schema' = 'https://aka.ms/winget-settings.schema.json'
        logging   = @{
            level = 'verbose'
        }
    }

    # Helper Functions
    function Invoke-CleanExit {
        <#
        .SYNOPSIS
        Cleans up resources used by the script and then exits
        .PARAMETER ExitCode
        Exit code to return
        #>
        param (
            [Parameter(Mandatory = $true)]
            [int] $ExitCode
        )
        Invoke-FileCleanup -FilePaths $script:CleanupPaths
        $script:HttpClient.Dispose()
        Write-Debug "Exiting ($ExitCode)"
        return $ExitCode
    }

    function Initialize-Folder {
        <#
        .SYNOPSIS
        Ensures that a folder is present. Creates it if it does not exist
        .PARAMETER FolderPath
        Path to folder
        .OUTPUTS
        Boolean. True if path exists or was created; False if otherwise
        #>
        param (
            [Parameter(Mandatory = $true)]
            [String] $FolderPath
        )
        $FolderPath = [System.Io.Path]::GetFullPath($FolderPath)
        if (Test-Path -Path $FolderPath -PathType Container) { return $true }
        if (Test-Path -Path $FolderPath) { return $false }
        Write-Debug "Initializing folder at $FolderPath"
        $directorySeparator = [System.IO.Path]::DirectorySeparatorChar

        foreach ($pathPart in $FolderPath.Split($directorySeparator)) {
            $builtPath += $pathPart + $directorySeparator
            if (!(Test-Path -Path $builtPath)) { New-Item -Path $builtPath -ItemType Directory | Out-Null }
        }

        return Test-Path -Path $FolderPath
    }

    function Get-Release {
        <#
        .SYNOPSIS
        Gets the details for a specific WinGet CLI release
        .OUTPUTS
        Nullable Object containing GitHub release details
        #>
        $releasesAPIResponse = Invoke-RestMethod -Uri $script:ReleasesApiUrl -UseBasicParsing
        if (!$script:Prerelease) {
            $releasesAPIResponse = $releasesAPIResponse.Where({ !$_.prerelease })
        }
        if (![String]::IsNullOrWhiteSpace($script:WinGetVersion)) {
            $releasesAPIResponse = @($releasesAPIResponse.Where({ $_.tag_name -match $('^v?' + [regex]::escape($script:WinGetVersion)) }))
        }
        if ($releasesAPIResponse.Count -lt 1) { return $null }
        return $releasesAPIResponse | Sort-Object -Property published_at -Descending | Select-Object -First 1
    }

    function Get-RemoteContent {
        <#
        .SYNOPSIS
        Gets the content of a file from a URI
        .PARAMETER URL
        Remote URI
        .PARAMETER OutputPath
        Local output path
        .PARAMETER Raw
        Return raw content
        .OUTPUTS
        File Contents
        #>
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [String] $URL,
            [String] $OutputPath = '',
            [switch] $Raw
        )
        Write-Debug "Attempting to fetch content from $URL"
        if ([String]::IsNullOrWhiteSpace($URL)) {
            $response = @{ StatusCode = 400 }
        } else {
            $response = Invoke-WebRequest -Uri $URL -Method Head -UseBasicParsing -ErrorAction SilentlyContinue
        }
        if ($response.StatusCode -ne 200) {
            Write-Debug "Fetching remote content from $URL returned status code $($response.StatusCode)"
            return $null
        }
        if ($OutputPath) {
            $localFile = [System.IO.FileInfo]::new($OutputPath)
        } else {
            $localFile = New-TemporaryFile
        }
        Write-Debug "Remote content will be stored at $($localFile.FullName)"
        if ($Raw) {
            $script:CleanupPaths += @($localFile.FullName)
        }
        try {
            $downloadTask = $script:HttpClient.GetByteArrayAsync($URL)
            [System.IO.File]::WriteAllBytes($localfile.FullName, $downloadTask.Result)
        }
        catch {
            $null | Out-File $localFile.FullName
        }
        if ($Raw) {
            return Get-Content -Path $localFile.FullName
        } else {
            return $localFile
        }
    }

    function Invoke-FileCleanup {
        <#
        .SYNOPSIS
        Removes files and folders from the file system
        .PARAMETER FilePaths
        List of paths to remove
        #>
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [AllowEmptyCollection()]
            [String[]] $FilePaths
        )
        if (!$FilePaths) { return }
        foreach ($path in $FilePaths) {
            Write-Debug "Removing $path"
            if (Test-Path $path) { Remove-Item -Path $path -Recurse }
            else { Write-Warning "Could not remove $path as it does not exist" }
        }
    }

    function Stop-NamedProcess {
        <#
        .SYNOPSIS
        Stops a process and waits for it to terminate
        .PARAMETER ProcessName
        Name of process to stop
        .PARAMETER TimeoutMilliseconds
        Timeout in milliseconds
        #>
        [CmdletBinding(SupportsShouldProcess)]
        param (
            [Parameter(Mandatory = $true)]
            [String] $ProcessName,
            [int] $TimeoutMilliseconds = 30000
        )
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if (!$process) { return }

        Write-Information "--> Stopping $ProcessName"
        if ($PSCmdlet.ShouldProcess($process)) { $process | Stop-Process -Force -WhatIf:$WhatIfPreference }

        $elapsedTime = 0
        $waitMilliseconds = 500
        $processStillRunning = $true
        do {
            $processStillRunning = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if ($processStillRunning) {
                Write-Debug "$ProcessName is still running after $($elapsedTime/1000) seconds"
                Start-Sleep -Milliseconds $waitMilliseconds
                $elapsedTime += $waitMilliseconds
            }
        } while ($processStillRunning -and $elapsedTime -lt $TimeoutMilliseconds)

        if ($processStillRunning) {
            Write-Error -Category OperationTimeout "Unable to terminate running process: $ProcessName" -ErrorAction Continue
            return (Invoke-CleanExit -ExitCode 2)
        }
    }

    # Main Function Logic
    try {
        # Check if Windows Sandbox is enabled
        if (-Not (Get-Command 'WindowsSandbox' -ErrorAction SilentlyContinue)) {
            Write-Error -ErrorAction Continue -Category NotInstalled -Message @'
Windows Sandbox does not seem to be available. Check the following URL for prerequisites and further details:
https://docs.microsoft.com/windows/security/threat-protection/windows-sandbox/windows-sandbox-overview

You can run the following command in an elevated PowerShell for enabling Windows Sandbox:
$ Enable-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM'
'@
            return (Invoke-CleanExit -ExitCode -1)
        }

        # Get the details for the version of WinGet that was requested
        Write-Verbose "Fetching release details from $script:ReleasesApiUrl; Filters: {Prerelease=$script:Prerelease; Version~=$script:WinGetVersion}"
        $script:WinGetReleaseDetails = Get-Release
        if (!$script:WinGetReleaseDetails) {
            Write-Error -Category ObjectNotFound 'No WinGet releases found matching criteria' -ErrorAction Continue
            return (Invoke-CleanExit -ExitCode 1)
        }
        if (!$script:WinGetReleaseDetails.assets) {
            Write-Error -Category ResourceUnavailable 'Could not fetch WinGet CLI release assets' -ErrorAction Continue
            return (Invoke-CleanExit -ExitCode 1)
        }

        Write-Verbose 'Parsing Release Information'
        $script:AppInstallerMsixShaDownloadUrl = $script:WinGetReleaseDetails.assets.Where({ $_.name -eq "$script:AppInstallerPFN.txt" }).browser_download_url
        $script:AppInstallerMsixDownloadUrl = $script:WinGetReleaseDetails.assets.Where({ $_.name -eq $script:AppInstallerMsixFileName }).browser_download_url
        $script:DependenciesShaDownloadUrl = $script:WinGetReleaseDetails.assets.Where({ $_.name -eq "$script:DependenciesBaseName.txt" }).browser_download_url
        $script:DependenciesZipDownloadUrl = $script:WinGetReleaseDetails.assets.Where({ $_.name -eq $script:DependenciesZipFileName }).browser_download_url

        $script:AppInstallerReleaseTag = $script:WinGetReleaseDetails.tag_name
        $script:AppInstallerParsedVersion = [System.Version]($script:AppInstallerReleaseTag -replace '(^v)|(-preview$)')
        Write-Debug "Using Release version $script:AppinstallerReleaseTag ($script:AppInstallerParsedVersion)"

        Write-Verbose 'Fetching file hash information'
        $script:AppInstallerMsixHash = Get-RemoteContent -URL $script:AppInstallerMsixShaDownloadUrl -Raw
        $script:DependenciesZipHash = Get-RemoteContent -URL $script:DependenciesShaDownloadUrl -Raw

    $script:AppInstallerReleaseAssetsFolder = Join-Path -Path (Join-Path -Path $script:AppInstallerDataFolder -ChildPath 'bin') -ChildPath $script:AppInstallerReleaseTag
    Write-Verbose "Using dependency source: $script:DependencySource"

        Write-Verbose 'Building Dependency List'
        $script:AppInstallerDependencies = @()
        if ($script:AppInstallerParsedVersion -ge [System.Version]'1.9.25180') {
            Write-Debug "Adding $script:DependenciesZipFileName to dependency list"
            $script:AppInstallerDependencies += @{
                DownloadUrl = $script:DependenciesZipDownloadUrl
                Checksum    = $script:DependenciesZipHash
                Algorithm   = 'SHA256'
                SaveTo      = (Join-Path -Path $script:AppInstallerReleaseAssetsFolder -ChildPath $script:DependenciesZipFileName)
            }
        }
        else {
            $script:DependencySource = [DependencySources]::Legacy
            Write-Debug 'Adding VCLibs UWP to dependency list'
            $script:AppInstallerDependencies += @{
                DownloadUrl = $script:VcLibsDownloadUrl
                Checksum    = $script:VcLibsHash
                Algorithm   = 'SHA256'
                SaveTo      = (Join-Path -Path $script:DependenciesCacheFolder -ChildPath 'Microsoft.VCLibs.Desktop.x64.appx')
            }
            if ($script:UseNuGetForMicrosoftUIXaml) {
                Write-Debug 'Adding Microsoft.UI.Xaml (NuGet) to dependency list'
                $script:AppInstallerDependencies += @{
                    DownloadUrl = $script:UiLibsDownloadUrl_NuGet
                    Checksum    = $script:UiLibsHash_NuGet
                    Algorithm   = 'SHA256'
                    SaveTo      = (Join-Path -Path $script:DependenciesCacheFolder -ChildPath 'Microsoft.UI.Xaml.zip')
                }
            }
            elseif ($script:AppInstallerParsedVersion -lt [System.Version]'1.7.10514') {
                Write-Debug 'Adding Microsoft.UI.Xaml (v2.7) to dependency list'
                $script:AppInstallerDependencies += @{
                    DownloadUrl = $script:UiLibsDownloadUrl_v2_7
                    Checksum    = $script:UiLibsHash_v2_7
                    Algorithm   = 'SHA256'
                    SaveTo      = (Join-Path -Path $script:DependenciesCacheFolder -ChildPath 'Microsoft.UI.Xaml.2.7.x64.appx')
                }
            }
            else {
                Write-Debug 'Adding Microsoft.UI.Xaml (v2.8) to dependency list'
                $script:AppInstallerDependencies += @{
                    DownloadUrl = $script:UiLibsDownloadUrl_v2_8
                    Checksum    = $script:UiLibsHash_v2_8
                    Algorithm   = 'SHA256'
                    SaveTo      = (Join-Path -Path $script:DependenciesCacheFolder -ChildPath 'Microsoft.UI.Xaml.2.8.x64.appx')
                }
            }
        }

        Write-Debug "Adding $script:AppInstallerMsixFileName ($script:AppInstallerReleaseTag) to dependency list"
        $script:AppInstallerDependencies += @{
            DownloadUrl = $script:AppInstallerMsixDownloadUrl
            Checksum    = $script:AppInstallerMsixHash
            Algorithm   = 'SHA256'
            SaveTo      = (Join-Path -Path $script:AppInstallerReleaseAssetsFolder -ChildPath $script:AppInstallerMsixFileName)
        }

        if ($script:UsePowerShellModuleForInstall) {
            $script:AppInstallerDependencies = @()
            Write-Verbose 'Falling back to PowerShell module for WinGet installation; skipping cached assets.'
        }

        Write-Information '--> Checking Dependencies'
        foreach ($dependency in $script:AppInstallerDependencies) {
            if ($Clean) { Invoke-FileCleanup -FilePaths $dependency.SaveTo }

            Write-Verbose "Checking the hash of $($dependency.SaveTo)"
            if (!(Test-FileChecksum $dependency.Checksum $dependency.SaveTo $dependency.Algorithm)) {
                if (!(Initialize-Folder $($dependency.SaveTo | Split-Path))) { throw "Could not create folder for caching $($dependency.DownloadUrl)" }
                Write-Information "  - Downloading $($dependency.DownloadUrl)"
                Get-RemoteContent -URL $dependency.DownloadUrl -OutputPath $dependency.SaveTo -ErrorAction SilentlyContinue | Out-Null
            }

            if (!(Test-FileChecksum $dependency.Checksum $dependency.SaveTo $dependency.Algorithm)) {
                $script:UsePowerShellModuleForInstall = $true
                Write-Debug "Hashes did not match; Expected $($dependency.Checksum), Received $((Get-FileHash -Path $dependency.SaveTo -Algorithm $dependency.Algorithm -ErrorAction Continue).Hash)"
                Write-Verbose 'Switching to PowerShell module install due to hash mismatch.'
                Remove-Item -Path $dependency.SaveTo -Force | Out-Null
                Write-Error -Category SecurityError 'Dependency hash does not match the downloaded file' -ErrorAction Continue
                Write-Error -Category SecurityError 'Please open an issue referencing this error at https://bit.ly/WinGet-SandboxTest-Needs-Update' -ErrorAction Continue
                break
            }
        }

        Stop-NamedProcess -ProcessName 'WindowsSandboxClient'
        Stop-NamedProcess -ProcessName 'WindowsSandboxRemoteSession'
        Stop-NamedProcess -ProcessName 'WindowsSandbox'
        Start-Sleep -Milliseconds 5000

        Write-Verbose 'Cleaning up previous test data'
        # Invoke-FileCleanup -FilePaths $script:TestDataFolder  # Temporarily disabled due to file locking

        # Wait longer for processes to fully terminate and release file handles
        Start-Sleep -Milliseconds 3000

        if (!(Initialize-Folder $script:TestDataFolder)) { throw 'Could not create folder for mapping files into the sandbox' }
        if (!(Initialize-Folder $script:DependenciesCacheFolder)) { throw 'Could not create folder for caching dependencies' }

        Write-Verbose "Copying assets into $script:TestDataFolder"
        $script:SandboxWinGetSettings | ConvertTo-Json | Out-File -FilePath (Join-Path -Path $script:TestDataFolder -ChildPath 'settings.json') -Encoding ascii
        foreach ($dependency in $script:AppInstallerDependencies) { 
            if (Test-Path -Path $dependency.SaveTo) {
                Copy-Item -Path $dependency.SaveTo -Destination $script:TestDataFolder -ErrorAction SilentlyContinue 
            }
        }

        # Define sandbox initialization code - split into pre-install and post-install
        $sandboxPreInstallScript = @'
#Function to create shortcuts
function Add-Shortcut ($Target, $Shortcut, $Arguments, $Icon, $Description, $WindowStyle) {
    $WScriptShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WScriptShell.CreateShortcut($Shortcut)
    $Shortcut.TargetPath = $Target
    if ($Arguments) { $Shortcut.Arguments = $Arguments }
    if ($Icon) { $Shortcut.IconLocation = $Icon }
    if ($Description) { $Shortcut.Description = $Description }
    if ($WindowStyle) {
        # Convert string values to integers that WScript.Shell expects
        $windowStyleValue = switch ($WindowStyle) {
            { $_ -is [int] } { $_ }
            'Normal' { 1 }
            'Maximized' { 3 }
            'Minimized' { 7 }
            default { 1 }  # Default to Normal if unrecognized
        }
        $Shortcut.WindowStyle = $windowStyleValue
    }
    $Shortcut.Save()
}

# Create NirSoft shortcut folder on desktop with custom icon
$nirSoftFolder = "${env:Public}\Desktop\NirSoft Utilities"
if (!(Test-Path $nirSoftFolder)) {
    New-Item -Path $nirSoftFolder -ItemType Directory -Force | Out-Null
    
    # Set custom folder icon using desktop.ini
    $desktopIniPath = Join-Path $nirSoftFolder "desktop.ini"
    "[.ShellClassInfo]`r`nIconResource=${env:SystemRoot}\System32\SHELL32.dll,14`r`nInfoTip=Download and run NirSoft Utilities" | Out-File -FilePath $desktopIniPath -Encoding ASCII -Force
    
    # Use attrib.exe to set attributes (more reliable in Sandbox)
    & attrib.exe +H +S "$desktopIniPath" 2>$null
    & attrib.exe +R "$nirSoftFolder" 2>$null
}

# Enable Dark Mode adaptively based on host system
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value PLACEHOLDER_APPS_LIGHT_THEME

# Enable Dark Mode for System adaptively
Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value PLACEHOLDER_SYSTEM_LIGHT_THEME

# Set the wallpaper based on theme (dark = img19.jpg, light = img0.jpg)
if (PLACEHOLDER_SYSTEM_LIGHT_THEME -eq 0) {
    $wallpaperPath = "C:\Windows\Web\Wallpaper\Windows\img19.jpg"  # Dark wallpaper
} else {
    $wallpaperPath = "C:\Windows\Web\Wallpaper\Windows\img0.jpg"   # Light wallpaper (Hero on Win10, Bloom on Win11)
}

$code = @"
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

Add-Type $code
$SPI_SETDESKWALLPAPER = 0x0014
$UPDATE_INI_FILE = 0x01
$SEND_CHANGE = 0x02

[Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $wallpaperPath, ($UPDATE_INI_FILE -bor $SEND_CHANGE))

# Enable Clipboard History
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1 -Type DWord -Force

# Create non-WAU shortcuts
Add-Shortcut "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" "${env:Public}\Desktop\Sysinternals Live.lnk" "https://live.sysinternals.com/" "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe,5" "Download and run from Sysinternals Live" "Normal"
Add-Shortcut "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" "$nirSoftFolder\NirSoft.lnk" "https://www.nirsoft.net/" "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe,5" "Download from NirSoft Utilities" "Normal"
Add-Shortcut "${env:SystemRoot}\System32\WindowsPowerShell\v1.0\powershell.exe" "${env:Public}\Desktop\CTT Windows Utility.lnk" "-ExecutionPolicy Bypass -Command `"Start-Process powershell.exe -verb runas -ArgumentList 'irm https://christitus.com/win | iex'`"" "${env:SystemRoot}\System32\SHELL32.dll,43" "Run Chris Titus Tech's Windows Utility"
Add-Shortcut "${env:SystemRoot}\System32\WindowsPowerShell\v1.0\powershell.exe" "$nirSoftFolder\UninstallView.lnk" "-ExecutionPolicy Bypass -WindowStyle Hidden -Command `"if(!(Test-Path '${env:TEMP}\UninstallView\UninstallView.exe')){Invoke-WebRequest -Uri 'https://www.nirsoft.net/utils/uninstallview-x64.zip' -OutFile '${env:TEMP}\uninstallview-x64.zip' -UseBasicParsing;Expand-Archive -Path '${env:TEMP}\uninstallview-x64.zip' -DestinationPath '${env:TEMP}\UninstallView' -Force};[System.Windows.Forms.SendKeys]::SendWait('{F5}');Start-Process '${env:TEMP}\UninstallView\UninstallView.exe' -Verb RunAs`"" "${env:TEMP}\UninstallView\UninstallView.exe,0" "Download and run UninstallView" "Minimized"
Add-Shortcut "${env:SystemRoot}\System32\WindowsPowerShell\v1.0\powershell.exe" "$nirSoftFolder\AdvancedRun.lnk" "-ExecutionPolicy Bypass -WindowStyle Hidden -Command `"if(!(Test-Path '${env:TEMP}\AdvancedRun\AdvancedRun.exe')){Invoke-WebRequest -Uri 'https://www.nirsoft.net/utils/advancedrun-x64.zip' -OutFile '${env:TEMP}\advancedrun-x64.zip' -UseBasicParsing;Expand-Archive -Path '${env:TEMP}\advancedrun-x64.zip' -DestinationPath '${env:TEMP}\AdvancedRun' -Force};[System.Windows.Forms.SendKeys]::SendWait('{F5}');Start-Process '${env:TEMP}\AdvancedRun\AdvancedRun.exe' -Verb RunAs`"" "${env:TEMP}\AdvancedRun\AdvancedRun.exe,0" "Download and run AdvancedRun" "Minimized"
Add-Shortcut "${env:windir}\regedit.exe" "${env:Public}\Desktop\Registry Editor.lnk" "" "" "Open Registry Editor" "Normal"

# Configure Regedit settings (Favorites)
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit\Favorites" /v "Uninstall Machine" /t REG_SZ /d Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall /f | Out-Null
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit\Favorites" /v "Uninstall User" /t REG_SZ /d Computer\HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall /f | Out-Null

# Configure Explorer settings
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v HideFileExt /t REG_DWORD /d 0 /f | Out-Null
reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Hidden /t REG_DWORD /d 1 /f | Out-Null

# Set execution policy for LocalMachine scope (wrap in Invoke-Command to suppress all output)
Invoke-Command -ScriptBlock {
    Set-ExecutionPolicy -Scope 'LocalMachine' -ExecutionPolicy 'Bypass' -Force
} -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 2>$null | Out-Null

# Refresh Explorer windows and desktop icons
Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
ie4uinit.exe -Show

# Create UninstallView configuration folder and config file
$uninstallViewFolder = "${env:TEMP}\UninstallView"
if (!(Test-Path $uninstallViewFolder)) {
    New-Item -Path $uninstallViewFolder -ItemType Directory -Force | Out-Null
}

# Create UninstallView.cfg with configuration
$uninstallViewConfig = "[General]`r`nMarkOddEvenRows=1`r`nShowGridLines=1`r`nShowInfoTip=1`r`nUseQuickFilter=1`r`nQuickFilterColumnsMode=1`r`nQuickFilterFindMode=1`r`nQuickFilterShowHide=1`r`nLoadFrom=1`r`nLoadingSpeed=1`r`nShowSystemComponents=1`r`nRegEditOpenMode=1`r`nAddExportHeaderLine=1`r`nSort=4099"
$uninstallViewConfig | Out-File -FilePath (Join-Path $uninstallViewFolder "UninstallView.cfg") -Encoding ASCII -Force

'@

        # Replace placeholders with actual host theme values
        $sandboxPreInstallScript = $sandboxPreInstallScript -replace 'PLACEHOLDER_APPS_LIGHT_THEME', $script:HostAppsUseLightTheme
        $sandboxPreInstallScript = $sandboxPreInstallScript -replace 'PLACEHOLDER_SYSTEM_LIGHT_THEME', $script:HostSystemUsesLightTheme

        if ($Script) {
            Write-Verbose "Creating script file from 'Script' argument with initialization code"

            # Detect if script contains InstallWSB.cmd
            $scriptText = $Script.ToString()
            $containsWAUInstall = $scriptText -match 'InstallWSB\.cmd'

            if ($containsWAUInstall) {
                Write-Verbose "Detected WAU installation - post-install initialization will run after user script"

                # Modify user script to wait for WAU installation to complete
                $modifiedUserScript = @'
# User Script (modified to wait for WAU installation)

'@ + $scriptText + "`r`n" + @'

# Wait for WAU installation to complete by polling registry and installation directory
Write-Host ""
Write-Host "Waiting for WAU installation to complete..." -ForegroundColor Yellow

$timeout = 300  # 5 minutes max
$elapsed = 0
$checkInterval = 2
$wauRegPath = "HKLM:\SOFTWARE\Romanitho\Winget-AutoUpdate"
$installLocation = $null

# First wait for registry key with InstallLocation
while ($elapsed -lt $timeout) {
    try {
        $installLocation = (Get-ItemProperty -Path $wauRegPath -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
        if ($installLocation) {
            Write-Host ""
            Write-Host "Registry key found: $installLocation" -ForegroundColor Cyan
            break
        }
    } catch {
        # Registry key doesn't exist yet
    }
    Start-Sleep -Seconds $checkInterval
    $elapsed += $checkInterval
    Write-Host "." -NoNewline -ForegroundColor Yellow
}

# Then verify that Winget-Upgrade.ps1 exists at that location
if ($installLocation) {
    $wauScriptPath = Join-Path $installLocation "Winget-Upgrade.ps1"
    
    while ($elapsed -lt $timeout) {
        if (Test-Path $wauScriptPath) {
            Write-Host ""
            Write-Host "WAU installation completed successfully!" -ForegroundColor Green
            Write-Host "Installation verified at: $wauScriptPath" -ForegroundColor Cyan
            Start-Sleep -Seconds 2
            break
        }
        Start-Sleep -Seconds $checkInterval
        $elapsed += $checkInterval
        Write-Host "." -NoNewline -ForegroundColor Yellow
    }
    
    if (-not (Test-Path $wauScriptPath)) {
        Write-Host ""
        Write-Host "Timeout: WAU script not found at $wauScriptPath" -ForegroundColor Red
    }
} else {
    Write-Host ""
    Write-Host "Timeout: WAU registry key not created within $timeout seconds" -ForegroundColor Red
}

'@

                # Create dynamic post-install script that uses $installLocation from above
                $dynamicPostInstallScript = @'

# Post-install initialization (after WAU installation)
# $installLocation is already defined from WAU detection above

if ($installLocation) {
    Write-Host ""
    Write-Host "Setting up WAU-specific shortcuts and configurations..." -ForegroundColor Yellow
    
    # Create WAU-specific shortcuts using dynamic path (Add-Shortcut function already defined in Pre-Install)
    Add-Shortcut "$installLocation" "${env:Public}\Desktop\WAU InstallDir.lnk" "" "" "WAU InstallDir"

    # Configure Regedit settings
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit" /v LastKey /t REG_SZ /d Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Romanitho\Winget-AutoUpdate /f | Out-Null
    reg.exe add "HKCU\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit\Favorites" /v WAU /t REG_SZ /d Computer\HKEY_LOCAL_MACHINE\SOFTWARE\Romanitho\Winget-AutoUpdate /f | Out-Null

    # Create AdvancedRun configuration folder and config file
    $advancedRunFolder = "${env:TEMP}\AdvancedRun"
    if (!(Test-Path $advancedRunFolder)) {
        New-Item -Path $advancedRunFolder -ItemType Directory -Force | Out-Null
    }

    # Build dynamic path to Winget-Install.ps1 using InstallLocation from registry
    $wauInstallScript = Join-Path $installLocation "Winget-Install.ps1"

    # Create AdvancedRun.cfg with WAU test configuration using dynamic path
    $configContent = "[General]`r`nCommandLine=`"-NoProfile -ExecutionPolicy bypass -File `"$wauInstallScript`" -AppIDs Notepad++.Notepad++`"`r`nStartDirectory=`r`nRunAs=4`r`nEnvironmentVariablesMode=1`r`nUseSearchPath=1`r`nRunMode=4`r`nCommandWindowMode=1"
    $configContent | Out-File -FilePath (Join-Path $advancedRunFolder "AdvancedRun.cfg") -Encoding ASCII -Force
    
    Write-Host "WAU-specific configuration completed!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "WARNING: InstallLocation not found - skipping WAU-specific shortcuts" -ForegroundColor Yellow
}

'@

                # Combine: pre-install + user script + dynamic post-install
                $fullScript = "# Pre-Install Initialization`r`n" + $sandboxPreInstallScript +
                              "`r`n" + $modifiedUserScript +
                              "`r`n# Post-Install Initialization`r`n" + $dynamicPostInstallScript
            }
            else {
                Write-Verbose "No WAU installation detected - pre-install initialization only"

                # Combine: pre-install + user script (no post-install needed)
                $fullScript = "# Pre-Install Initialization`r`n" + $sandboxPreInstallScript +
                              "`r`n# User Script`r`n" + $scriptText
            }

            # Write combined script to BoundParameterScript.ps1
            $fullScript | Out-File -FilePath (Join-Path $script:TestDataFolder -ChildPath 'BoundParameterScript.ps1') -Encoding UTF8
        }

        Write-Verbose 'Creating the script for bootstrapping the sandbox'
        @"
function Update-EnvironmentVariables {
    foreach(`$level in "Machine","User") {
        [Environment]::GetEnvironmentVariables(`$level).GetEnumerator() | % {
            if(`$_.Name -match '^Path$') {
                `$_.Value = (`$((Get-Content "Env:`$(`$_.Name)") + ";`$(`$_.Value)") -split ';' | Select -unique) -join ';'
            }
          `$_
        } | Set-Content -Path { "Env:`$(`$_.Name)" }
    }
}

Push-Location $($script:SandboxTestDataFolder)

Write-Host '================================================' -ForegroundColor Cyan
Write-Host '--> Installing WinGet $($script:AppInstallerReleaseTag)' -ForegroundColor Yellow
Write-Host '================================================' -ForegroundColor Cyan

try {
    if ($([int]$script:UsePowerShellModuleForInstall)) { throw }
    Write-Host '    [1/3] Extracting packages...' -ForegroundColor Cyan
    `$ProgressPreference = 'SilentlyContinue'

    # Only extract if not already extracted (saves time)
    `$zipFiles = Get-ChildItem -Filter '*.zip'
    foreach (`$zip in `$zipFiles) {
        `$extractedFolder = Join-Path `$PWD.Path (`$zip.BaseName)
        if (-not (Test-Path `$extractedFolder)) {
            Expand-Archive -Path `$zip.FullName -DestinationPath `$PWD.Path -Force
        }
    }

    Write-Host '    [2/3] Installing dependencies...' -ForegroundColor Cyan
    Get-ChildItem -Recurse -Filter '*.appx' | Where-Object {`$_.FullName -match 'x64'} | Add-AppxPackage -ErrorAction Stop
    Write-Host '    [3/3] Installing WinGet...' -ForegroundColor Cyan
    Add-AppxPackage './$($script:AppInstallerPFN).msixbundle' -ErrorAction Stop
    Write-Host '    WinGet installed successfully!' -ForegroundColor Green
} catch {
  Write-Host ''
  Write-Host '    Package installation failed. Using fallback method...' -ForegroundColor Yellow
  Write-Host ''
  try {
    Write-Host '    [1/3] Installing NuGet package provider...' -ForegroundColor Cyan
    `$ProgressPreference = 'SilentlyContinue'
    Install-PackageProvider -Name NuGet -Force | Out-Null
    Write-Host '    [2/3] Installing Microsoft.WinGet.Client module...' -ForegroundColor Cyan
    Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
  } catch {
    throw "Microsoft.Winget.Client was not installed successfully"
  } finally {
    if (-not(Get-Module -ListAvailable -Name Microsoft.Winget.Client)) {
      throw "Microsoft.Winget.Client was not found. Check that the Windows Package Manager PowerShell module was installed correctly."
    }
  }
  Write-Host '    [3/3] Repairing WinGet Package Manager...' -ForegroundColor Cyan
  Repair-WinGetPackageManager -Version $($script:AppInstallerReleaseTag)
  Write-Host '    WinGet installed successfully!' -ForegroundColor Green
}

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '--> Configuring Windows Sandbox' -ForegroundColor Yellow
Write-Host '================================================' -ForegroundColor Cyan

Write-Host '    [1/2] Disabling safety warnings for installers...' -ForegroundColor Cyan
New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations' -ErrorAction SilentlyContinue | Out-Null
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations' -Name 'ModRiskFileTypes' -Type 'String' -Value '.bat;.exe;.reg;.vbs;.chm;.msi;.js;.cmd' -Force | Out-Null

Write-Host '    [2/2] Applying WinGet settings...' -ForegroundColor Cyan
# Apply settings.json first so subsequent CLI toggles persist and are not overwritten
Get-ChildItem -Filter 'settings.json' | Copy-Item -Destination C:\Users\WDAGUtilityAccount\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json -ErrorAction SilentlyContinue
winget settings --Enable LocalManifestFiles | Out-Null
winget settings --Enable LocalArchiveMalwareScanOverride | Out-Null
Set-WinHomeLocation -GeoID $($script:HostGeoID)
Write-Host '    Configuration completed!' -ForegroundColor Green

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host 'Tip: Type "Update-EnvironmentVariables" to refresh' -ForegroundColor Gray
Write-Host 'environment variables after installing software.' -ForegroundColor Gray
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

`$BoundParameterScript = Get-ChildItem -Filter 'BoundParameterScript.ps1'
if (`$BoundParameterScript) {
    Write-Host ""
    Write-Host "--> Running BoundParameterScript.ps1" -ForegroundColor Yellow
    Write-Host ""
    & `$BoundParameterScript.FullName
}

Pop-Location

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Script execution completed!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press any key to close this window..." -ForegroundColor Yellow
`$null = `$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
"@ | Out-File -FilePath $(Join-Path -Path $script:TestDataFolder -ChildPath "$script:ScriptName.ps1")

                Write-Verbose 'Creating WSB file for launching the sandbox'
                $mappedFolders = @"
        <MappedFolder>
            <HostFolder>$($script:TestDataFolder)</HostFolder>
            <SandboxFolder>$($script:SandboxTestDataFolder)</SandboxFolder>
            <ReadOnly>false</ReadOnly>
        </MappedFolder>
"@

                if ($script:PrimaryMappedFolder) {
                        $mappedFolders += @"

        <MappedFolder>
            <HostFolder>$($script:PrimaryMappedFolder)</HostFolder>
            <SandboxFolder>$($script:SandboxWorkingDirectory)</SandboxFolder>
            <ReadOnly>false</ReadOnly>
        </MappedFolder>
"@
                }

        @"
<Configuration>
  <Networking>Enable</Networking>
  <MappedFolders>
$mappedFolders
  </MappedFolders>
  <LogonCommand>
  <Command>PowerShell Start-Process PowerShell -WindowStyle Maximized -WorkingDirectory '$($script:SandboxWorkingDirectory)' -ArgumentList '-ExecutionPolicy Bypass -File $($script:SandboxBootstrapFile)'</Command>
  </LogonCommand>
</Configuration>
"@ | Out-File -FilePath $script:ConfigurationFile
    Write-Verbose "WSB configuration written to: $script:ConfigurationFile"

        $mappedDirsInfo = "      - $($script:TestDataFolder) as read-and-write"
        if ($script:PrimaryMappedFolder) {
            $mappedDirsInfo += "`n      - $($script:PrimaryMappedFolder) as read-and-write"
        }

        $additionalCommands = ""

        Write-Information @"
--> Starting Windows Sandbox, and:
    - Mounting the following directories:
$mappedDirsInfo
    - Installing WinGet
    - Configuring Winget$additionalCommands
"@

        if ($Script) {
            Write-Information @"
      - Running the following script: {
$($Script.ToString())
}
"@
        }

        Write-Verbose "Invoking the sandbox using $script:ConfigurationFile"
        if ($Async) {
            # Start Sandbox and return directly
            $wsbPath = (Get-Command 'WindowsSandbox').Source
            Start-Process -FilePath $wsbPath -ArgumentList $script:ConfigurationFile -WindowStyle Normal | Out-Null
            Write-Verbose 'Sandbox launched asynchronously'
            return (Invoke-CleanExit -ExitCode 0)
        } else {
            # Start Sandbox and wait for it to exit
            Write-Verbose 'Launching Sandbox synchronously'
            $wsbPath = (Get-Command 'WindowsSandbox').Source
            $process = Start-Process -FilePath $wsbPath -ArgumentList $script:ConfigurationFile -WindowStyle Normal -PassThru
            Write-Information '--> Waiting for Windows Sandbox to complete...'
            $process.WaitForExit()
            Write-Verbose "Sandbox exited with code: $($process.ExitCode)"
            return (Invoke-CleanExit -ExitCode 0)
        }        
    }
    catch {
        Write-Error "An error occurred: $_"
        return (Invoke-CleanExit -ExitCode 1)
    }
}
