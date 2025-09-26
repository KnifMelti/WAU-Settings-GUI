function SandboxTest {
    [CmdletBinding()]
    param(
        [ScriptBlock] $Script,
        [string] $MapFolder,
        [string] $SandboxFolderName,
        [string] $WinGetVersion,
        [string] $WinGetOptions,
        [switch] $Prerelease,
        [switch] $EnableExperimentalFeatures,
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
    
    .PARAMETER WinGetOptions
    Additional options for WinGet.
    
    .PARAMETER Prerelease
    Include prerelease versions of WinGet.
    
    .PARAMETER EnableExperimentalFeatures
    Enable experimental features in WinGet.
    
    .PARAMETER Clean
    Clean existing cached dependencies before starting.
    
    .EXAMPLE
    SandboxTest -Script { Start-Process cmd.exe -ArgumentList "/c del /Q ""$env:USERPROFILE\Desktop\WAU-install\*.log"" & ""$env:USERPROFILE\Desktop\WAU-install\InstallWSB.cmd"" && explorer ""$env:USERPROFILE\Desktop\WAU-install""" } -Verbose
    
    .EXAMPLE
    SandboxTest -MapFolder "D:\WAU Settings GUI\msi\2.8.0" -EnableExperimentalFeatures
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
    $script:WinGetOptions  = $WinGetOptions

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
    $sandboxLeaf = if ($SandboxFolderName) { $SandboxFolderName } elseif ($script:PrimaryMappedFolder) { ($script:PrimaryMappedFolder | Split-Path -Leaf) } else { '' }
    $script:SandboxWorkingDirectory = if ($script:PrimaryMappedFolder) { Join-Path -Path $script:SandboxDesktopFolder -ChildPath $sandboxLeaf } else { $script:SandboxDesktopFolder }
    $script:SandboxTestDataFolder = Join-Path -Path $script:SandboxDesktopFolder -ChildPath $($script:TestDataFolder | Split-Path -Leaf)
    $script:SandboxBootstrapFile = Join-Path -Path $script:SandboxTestDataFolder -ChildPath "$script:ScriptName.ps1"
    $script:HostGeoID = (Get-WinHomeLocation).GeoID

    # Misc
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Ensure the System.Net.Http assembly is loaded
    Add-Type -AssemblyName System.Net.Http
    $script:HttpClient = New-Object System.Net.Http.HttpClient
    $script:CleanupPaths = @()

    # The experimental features get updated later based on a switch that is set
    $script:SandboxWinGetSettings = @{
        '$schema'            = 'https://aka.ms/winget-settings.schema.json'
        logging              = @{
            level = 'verbose'
        }
        experimentalFeatures = @{
            fonts = $false
        }
    }

    # Default list of experimental features to enable when -EnableExperimentalFeatures is used.
    # Note: Winget will ignore unknown keys based on the active schema. This list is conservative and safe.
    $script:ExperimentalFeaturesList = @(
        'fonts',              # Already present; improves font handling scenarios
        'dependencies',       # Enable dependency support in manifests
        'directMSI',          # Allow direct MSI handling improvements
        'unpackagedInstall',  # Support for unpackaged installers
        'restSource',         # Enable REST source (newer source protocol)
        'zipInstall'          # Allow zip-based installer flows
    )

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
        $releasesAPIResponse = Invoke-RestMethod -Uri $script:ReleasesApiUrl
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
            $response = Invoke-WebRequest -Uri $URL -Method Head -ErrorAction SilentlyContinue
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
        Stop-NamedProcess -ProcessName 'vmmemSandbox'
        Start-Sleep -Milliseconds 5000

        Write-Verbose 'Cleaning up previous test data'
        # Invoke-FileCleanup -FilePaths $script:TestDataFolder  # Temporarily disabled due to file locking

        # Wait longer for processes to fully terminate and release file handles
        Start-Sleep -Milliseconds 3000

        if (!(Initialize-Folder $script:TestDataFolder)) { throw 'Could not create folder for mapping files into the sandbox' }
        if (!(Initialize-Folder $script:DependenciesCacheFolder)) { throw 'Could not create folder for caching dependencies' }

        if ($EnableExperimentalFeatures) {
            Write-Debug 'Setting Experimental Features to Enabled'
            foreach ($feature in $script:ExperimentalFeaturesList) {
                # Ensure the key exists and is set to true in the JSON that will be copied into the Sandbox
                $script:SandboxWinGetSettings.experimentalFeatures[$feature] = $true
            }
            Write-Verbose ("Enabled experimental features: {0}" -f ($script:ExperimentalFeaturesList -join ', '))
        }

        Write-Verbose "Copying assets into $script:TestDataFolder"
        $script:SandboxWinGetSettings | ConvertTo-Json | Out-File -FilePath (Join-Path -Path $script:TestDataFolder -ChildPath 'settings.json') -Encoding ascii
        foreach ($dependency in $script:AppInstallerDependencies) { 
            if (Test-Path -Path $dependency.SaveTo) {
                Copy-Item -Path $dependency.SaveTo -Destination $script:TestDataFolder -ErrorAction SilentlyContinue 
            }
        }

        if ($Script) {
            Write-Verbose "Creating script file from 'Script' argument"
            $Script.ToString() | Out-File -FilePath (Join-Path $script:TestDataFolder -ChildPath 'BoundParameterScript.ps1')
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
Write-Host @'
--> Installing WinGet
'@
`$ProgressPreference = 'SilentlyContinue'

try {
    if ($([int]$script:UsePowerShellModuleForInstall)) { throw }
    Get-ChildItem -Filter '*.zip' | Expand-Archive
    Get-ChildItem -Recurse -Filter '*.appx' | Where-Object {`$_.FullName -match 'x64'} | Add-AppxPackage -ErrorAction Stop
    Add-AppxPackage './$($script:AppInstallerPFN).msixbundle' -ErrorAction Stop
} catch {
  Write-Host -ForegroundColor Red 'Could not install from cached packages. Falling back to Repair-WinGetPackageManager cmdlet'
  try {
    Install-PackageProvider -Name NuGet -Force | Out-Null
    Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
  } catch {
    throw "Microsoft.Winget.Client was not installed successfully"
  } finally {
    if (-not(Get-Module -ListAvailable -Name Microsoft.Winget.Client)) {
      throw "Microsoft.Winget.Client was not found. Check that the Windows Package Manager PowerShell module was installed correctly."
    }
  }
  Repair-WinGetPackageManager -Version $($script:AppInstallerReleaseTag)
}

Write-Host @'
--> Disabling safety warning when running installers
'@
New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations' | Out-Null
New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Associations' -Name 'ModRiskFileTypes' -Type 'String' -Value '.bat;.exe;.reg;.vbs;.chm;.msi;.js;.cmd' | Out-Null

Write-Host @'
Tip: you can type 'Update-EnvironmentVariables' to update your environment variables, such as after installing a new software.
'@

Write-Host @'

--> Configuring Winget
'@
# Apply settings.json first so subsequent CLI toggles persist and are not overwritten
Get-ChildItem -Filter 'settings.json' | Copy-Item -Destination C:\Users\WDAGUtilityAccount\AppData\Local\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json
winget settings --Enable LocalManifestFiles
winget settings --Enable LocalArchiveMalwareScanOverride
Set-WinHomeLocation -GeoID $($script:HostGeoID)

`$BoundParameterScript = Get-ChildItem -Filter 'BoundParameterScript.ps1'
if (`$BoundParameterScript) {
    Write-Host @'

--> Running the following script: {
`$(Get-Content -Path `$BoundParameterScript.FullName)
}

'@
& `$BoundParameterScript.FullName
}

Pop-Location
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
  <Command>PowerShell Start-Process PowerShell -WindowStyle Hidden -WorkingDirectory '$($script:SandboxWorkingDirectory)' -ArgumentList '-ExecutionPolicy Bypass -File $($script:SandboxBootstrapFile)'</Command>
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
            WindowsSandbox $script:ConfigurationFile
            return (Invoke-CleanExit -ExitCode 0)
        }        
    }
    catch {
        Write-Error "An error occurred: $_"
        return (Invoke-CleanExit -ExitCode 1)
    }
}
