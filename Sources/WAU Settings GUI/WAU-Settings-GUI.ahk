#Requires AutoHotkey v2.0
#SingleInstance
;@Ahk2Exe-Set CompanyName, KnifMelti
;@Ahk2Exe-Set ProductName, WAU Settings GUI
;@Ahk2Exe-Set FileDescription, WAU Settings GUI
;@Ahk2Exe-Set FileVersion, 1.8.1.2
;@Ahk2Exe-Set ProductVersion, 1.8.1.2
;@Ahk2Exe-Set InternalName, WAU-Settings-GUI
;@Ahk2Exe-SetMainIcon ..\assets\WAU Settings GUI.ico
;@Ahk2Exe-UpdateManifest 1

SetWorkingDir A_ScriptDir  ; Ensures a consistent starting directory.
SplitPath(A_ScriptName, , , , &name_no_ext)
FileEncoding "UTF-8"
; Initialize the tray menu
A_TrayMenu.Delete() ; Remove all default menu items
A_TrayMenu.Add("Exit", (*) => ExitApp())

; name_no_ext contains the Script name to use

;Variables
; Check if we are started from PowerShell for UnInst.exe creation
fromPS := (A_Args.Length && A_Args[1] = "/FROMPS")
shortcutDesktop := A_Desktop "\WAU Settings (Administrator).lnk"
shortcutStartMenu := A_ProgramsCommon "\Winget-AutoUpdate\WAU Settings (Administrator).lnk"
shortcutOpenLogs := A_ProgramsCommon "\Winget-AutoUpdate\Open Logs.lnk"
shortcutAppInstaller := A_ProgramsCommon "\Winget-AutoUpdate\WAU App Installer.lnk"

; Original: 4 shortcuts for Run WAU and updates.log
; wauRunWau := A_ProgramsCommon "\Winget-AutoUpdate\Run WAU.lnk" ; C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Winget-AutoUpdate\User-Run.ps1"
; wauOpenLog := A_ProgramsCommon "\Winget-AutoUpdate\Open log.lnk" ; ""C:\Program Files\Winget-AutoUpdate\logs\updates.log""
; wauDesktop := A_DesktopCommon "\Run WAU.lnk" ; C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Winget-AutoUpdate\User-Run.ps1"
; wauAppInstaller := A_DesktopCommon "\WAU App Installer.lnk" ; C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\Winget-AutoUpdate\WAU-Installer-GUI.ps1"

psScriptPath := A_WorkingDir "\" name_no_ext ".ps1"
uninstPath := A_WorkingDir "\UnInst.exe"
runCommand := 'C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' psScriptPath '"'
portableCommand := 'C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' psScriptPath '" -Portable'

; Check if the script was called with '/UNINSTALL' or '/UNINSTALL /S' parameter
if A_Args.Length && (A_Args[1] = "/UNINSTALL") {
    silent := (A_Args.Length > 1 && (A_Args[2] = "/S"))
    if !silent {
        choice := MsgBox(
            "Do you want to uninstall WAU Settings GUI?`n`nWAU will be automatically reinstalled afterward`nrestoring the original current showing shortcuts.",
            name_no_ext,
            0x21  ; OK/Cancel with Question icon
        )
        if (choice != "OK") {
            ExitApp
        }
    }

    ; Close all instances of WAU Settings GUI using PowerShell
    try {
        RunWait('C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -Command "Get-Process | Where-Object { $_.MainWindowTitle -like \"WAU Settings*\" } | Stop-Process -Force"', , "Hide")
    } catch {
        ; Ignore errors if no matching processes found
    }

    ; Remove WAU Settings (Administrator) shortcuts if they exist
    if FileExist(shortcutDesktop) || FileExist(shortcutStartMenu) {
            try {
                if FileExist(shortcutDesktop)
                FileDelete(shortcutDesktop)
                if FileExist(shortcutStartMenu)
                FileDelete(shortcutStartMenu)
                if FileExist(shortcutOpenLogs)
                FileDelete(shortcutOpenLogs)
                if FileExist(shortcutAppInstaller)
                FileDelete(shortcutAppInstaller)
            } catch {
                ; Ignore errors from MSI subsystem
            }
    }


    ; Check if working dir is under '\WinGet\Packages\'
    if InStr(A_WorkingDir, "\WinGet\Packages\", false) > 0 {
         ; Remove registry key for WinGet uninstall local manifest entry (SandboxTest.ps1)
        try {
            RegDeleteKey("HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\KnifMelti.WAU-Settings-GUI__DefaultSource")
        } catch {
            ; Ignore errors if registry key can't be deleted
        }
        ; Remove registry key for WinGet uninstall entry
        try {
            RegDeleteKey("HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\KnifMelti.WAU-Settings-GUI_Microsoft.Winget.Source_8wekyb3d8bbwe")
        } catch {
            ; Ignore errors if registry key can't be deleted
        }
    }

    ; Remove registry key for WAU Settings GUI uninstall entry
    try {
        RegDeleteKey("HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\WAU-Settings-GUI")
    } catch {
        ; Ignore errors if registry key can't be deleted
    }

    ; MSI uninstall/install to restore WAU from current showing shortcut settings in the GUI
    try {
        ; Use PowerShell to find the product code (GUID) for Winget-AutoUpdate
        psCommand := 'powershell.exe -NoProfile -Command "$pkg = Get-Package -Name \"Winget-AutoUpdate\" -ProviderName msi -ErrorAction SilentlyContinue; if ($pkg) { $productCode = $pkg.Metadata[\"ProductCode\"]; $installSource = (Get-ItemProperty -Path \"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$productCode\" -Name \"InstallSource\" -ErrorAction SilentlyContinue).InstallSource; Write-Host \"ProductCode: $productCode\"; Write-Host \"InstallSource: $installSource\"; Write-Host \"Version: $($pkg.Version)\" }"'
        tempFile := A_Temp "\wau_guid.tmp"
        
        ; Run the command, redirecting output to a temporary file
        RunWait(A_ComSpec ' /c "' psCommand ' > "' tempFile '"', , "Hide")
        
        wauGUID := ""
        wauSource := ""
        wauVersion := ""
        if FileExist(tempFile) {
            fileContent := Trim(FileRead(tempFile))
            FileDelete(tempFile)
            
            ; Parse the three lines to extract ProductCode, InstallSource and Version
            lines := StrSplit(fileContent, "`n")
            for line in lines {
                line := Trim(line)
                if InStr(line, "ProductCode: ") = 1 {
                    wauGUID := SubStr(line, 14)  ; Extract after "ProductCode: "
                } else if InStr(line, "InstallSource: ") = 1 {
                    wauSource := RTrim(SubStr(line, 16), "\")  ; Extract after "InstallSource: " and remove trailing backslash
                } else if InStr(line, "Version: ") = 1 {
                    wauLongVersion := "v" . SubStr(line, 10)  ; Extract after "Version: " (keep full version, including last dot and numbers)
                    wauVersion := "v" . RegExReplace(SubStr(line, 10), "\.\d+$", "")  ; Extract after "Version: ", add "v" prefix, remove last dot and numbers
                }
            }
        }
        
        if (wauGUID != "") {
            ; Delete existing Startmenu
            try {
                if FileExist(A_ProgramsCommon "\Winget-AutoUpdate")
                    FileDelete(A_ProgramsCommon "\Winget-AutoUpdate")
            } catch {
                ; Ignore errors from MSI subsystem
            }

            ; Check if WAU.msi exists in the install source before attempting uninstall/install
            if (wauSource != "" && FileExist(wauSource "\WAU.msi")) {
                ; Copy WAU.msi to %ProgramData%\Package Cache folder for MSI uninstall/install
                cacheDir := A_AppDataCommon "\Package Cache\" wauGUID wauLongVersion "\Installers"
                if !DirExist(cacheDir) {
                    DirCreate(cacheDir)
                }
                cacheMsiPath := cacheDir "\WAU.msi"
                ; Only copy if wauSource is NOT under Package Cache
                if InStr(wauSource, "\Package Cache\" wauGUID wauLongVersion "\Installers", false) = 0 {
                    FileCopy(wauSource "\WAU.msi", cacheMsiPath, 1)
                }

                msiParams := GetMSIParams()

                ; Uninstall using the found GUID and install from the copied WAU.msi in the Package Cache folder
                if !silent {
                    RunWait('msiexec /x' wauGUID ' /qb', , "Hide")
                    RunWait('msiexec /i "' cacheMsiPath '" /qb' msiParams, , "Hide")
                }                
                else {
                    RunWait('msiexec /x' wauGUID ' /qn', , "Hide")
                    RunWait('msiexec /i "' cacheMsiPath '" /qn' msiParams, , "Hide")
                }
            } else if (IsInternetAvailable()) {
                ; WAU.msi not found in original source, download the original version and trigger MSI reinstall
                downloadUrl := "https://github.com/Romanitho/Winget-AutoUpdate/releases/download/" wauVersion "/WAU.msi"
                wauMsiPath := A_WorkingDir "\WAU.msi"
                try {
                    Download(downloadUrl, wauMsiPath)
                    ; Check MSI file signature (first 8 bytes should be MSI signature)
                    try {
                        f := FileOpen(wauMsiPath, "r")
                        if !f {
                            throw Error("Could not open downloaded file for validation.")
                        }
                        ; Read first 8 bytes as hex values
                        signature := ""
                        Loop 8 {
                            signature .= Format("{:02X}", f.ReadUChar())
                        }
                        f.Close()
                        if (signature != "D0CF11E0A1B11AE1") { ; OLE/COM compound document signature
                            throw Error("Downloaded file is not a valid MSI file (invalid signature).")
                        }
                    } catch as e {
                        throw Error("Failed to validate MSI file signature: " e.Message)
                    }
                } catch as e {
                    throw Error("Failed to download WAU.msi from GitHub: " downloadUrl "`nError: " e.Message)
                }

                wauSource := A_WorkingDir
                ; Copy WAU.msi to %ProgramData%\Package Cache folder for MSI repair (msi folder will be deleted later)
                cacheDir := A_AppDataCommon "\Package Cache\" wauGUID wauLongVersion "\Installers"
                if !DirExist(cacheDir) {
                    DirCreate(cacheDir)
                }
                cacheMsiPath := cacheDir "\WAU.msi"
                FileCopy(wauSource "\WAU.msi", cacheMsiPath, 1)

                wauSource := cacheDir

                msiParams := GetMSIParams()

                ; Uninstall using the found GUID and install from the copied WAU.msi in the Package Cache folder
                if !silent {
                    RunWait('msiexec /x' wauGUID ' /qn', , "Hide")
                    RunWait('msiexec /i "' cacheMsiPath '" /qb' msiParams, , "Hide")
                }                
                else {
                    RunWait('msiexec /x' wauGUID ' /qn', , "Hide")
                    RunWait('msiexec /i "' cacheMsiPath '" /qn' msiParams, , "Hide")
                }
            } else {
                throw Error("WAU.msi not found in install source: " (wauSource != "" ? wauSource : "Unknown") " and couldn't be downloaded.`nPlease check your internet connection or download WAU.msi manually from GitHub.")
            }
        } else {
            throw Error("WAU GUID not found via PowerShell")
        }
            
    } catch as e {
        if !silent {
            MsgBox("Failed to trigger MSI repair. Please repair WAU manually from Apps & Features.`n`nError: " e.Message, name_no_ext, 0x10)
        }
    }

    ; Runs a command to delete the entire script folder after a short delay
    Run('cmd.exe /C ping 127.0.0.1 -n 3 > nul & rmdir /S /Q "' A_WorkingDir '"', , "Hide")

    ExitApp
}

; Check if we are started from PowerShell for UnInst.exe creation
if fromPS {
    ; Create UnInst.exe and registry, relaunch after info!
    if FileExist(A_WorkingDir "\installed.txt") {
        if !FileExist(uninstPath) {
            FileCopy(A_ScriptFullPath, uninstPath, 1)
            CreateUninstall(uninstPath, name_no_ext, A_WorkingDir)
        }
    }
    MsgBox(
        "UnInst.exe and registry uninstall entry`nhave been created successfully.`n`nRestarting the program to apply changes.`n`n(This dialog will close automatically in 5 seconds)",
        name_no_ext,
        "0x40 T5"  ; Information icon + 5 second timeout
    )

    if FileExist(shortcutDesktop) && FileExist(shortcutStartMenu) {
        Run shortcutDesktop
    } else if FileExist(shortcutDesktop) {
        Run shortcutDesktop
    } else if FileExist(shortcutStartMenu) {
        Run shortcutStartMenu
    }
    else {
        ; If no shortcuts exist, run the script directly
        Run runCommand
    }

    ExitApp
}

if FileExist(shortcutDesktop) && FileExist(shortcutStartMenu) {
    Run shortcutDesktop
} else if FileExist(shortcutDesktop) {
    Run shortcutDesktop
} else if FileExist(shortcutStartMenu) {
    Run shortcutStartMenu
} else {    
    ; Check if running from portable media
    drive := SubStr(A_WorkingDir, 1, 2)
    driveType := DriveGetType(drive)
    if (driveType = "Removable" || driveType = "CDRom") {
        Run portableCommand
        ExitApp
    }

    ; Create installed.txt if missing
    if InStr(A_WorkingDir, "\WinGet\Packages\", false) > 0 && !FileExist(A_WorkingDir "\installed.txt") {
        FileAppend("This directory was created by 'WAU Settings GUI' WinGet installer.", A_WorkingDir "\installed.txt")
        ; Set installed.txt as hidden and system file
        FileSetAttrib("+HS", A_WorkingDir "\installed.txt")
    }

    ; If installed.txt exists, create UnInst.exe and registry if missing
    if FileExist(A_WorkingDir "\installed.txt") {
        if !FileExist(uninstPath) {
            FileCopy(A_ScriptFullPath, uninstPath, 1)
            CreateUninstall(uninstPath, name_no_ext, A_WorkingDir)
        }
        ; Start PowerShell-GUI if UnInst.exe now exists
        if FileExist(uninstPath) {
            if FileExist(shortcutDesktop) && FileExist(shortcutStartMenu) {
                Run shortcutDesktop
            } else if FileExist(shortcutDesktop) {
                Run shortcutDesktop
            } else if FileExist(shortcutStartMenu) {
                Run shortcutStartMenu
            }
            else {
                ; If no shortcuts exist, run the script directly
                Run runCommand
            }
        }
        ExitApp
    } else {
        ; Ask user about installation or portable mode
        choice := MsgBox(
            "Do you want to install WAU Settings GUI?" . "`n`nChoose Yes to install, No to run as Portable, or Cancel to exit.",
            name_no_ext,
            0x123  ; Yes/No/Cancel with Question icon, No as default
        )
        if (choice = "Cancel") {
            ExitApp
        }
        if (choice = "Yes") {
            targetBaseDir := FileSelect("D", , "Select base directory for installation ('WAU Settings GUI' will be created here)")
            if !targetBaseDir {
                ExitApp
            }
            targetDir := RTrim(targetBaseDir, "\") "\WAU Settings GUI"
            DirCreate(targetDir)
            CopyFilesAndFolders(A_WorkingDir, targetDir)
            FileAppend("This directory was created by 'WAU Settings GUI' local installer.", targetDir "\installed.txt")
            FileSetAttrib("+HS", targetDir "\installed.txt")
            uninstPath := targetDir "\UnInst.exe"
            FileCopy(targetDir "\" name_no_ext ".exe", uninstPath, 1)
            CreateUninstall(uninstPath, name_no_ext, targetDir)
            MsgBox(
                "Installation complete!`n`nRunning '" name_no_ext ".exe'`nfrom the installation folder.`n`n(This dialog will close automatically in 5 seconds)",
                name_no_ext,
                "0x40 T5"  ; Information icon + 5 second timeout
            )
            Run targetDir "\" name_no_ext ".exe"
            ExitApp
        } else {
            Run portableCommand
        }
    }
}

; Helper function to recursively copy files and folders
CopyFilesAndFolders(src, dst) {
    ; First, copy all files and folders
    Loop Files src "\*", "FR" {
        relPath := SubStr(A_LoopFileFullPath, StrLen(src) + 2)
        destPath := dst "\" relPath
        if (A_LoopFileAttrib ~= "D") {
            DirCreate(destPath)
        } else {
            ; Ensure parent directories exist
            parts := StrSplit(destPath, "\")
            if (parts.Length > 1) {
                parentDir := parts[1]
                Loop parts.Length - 1 {
                    parentDir .= "\" parts[A_Index + 1]
                }
                parentDir := SubStr(parentDir, 1, -StrLen(parts[parts.Length]) - 1)
                DirCreate(parentDir)
            }
            FileCopy(A_LoopFileFullPath, destPath, 1)
        }
    }
    
    ; Remove Zone.Identifier from all copied files in one operation
    try {
        ; Try PowerShell Unblock-File (works on most systems)
        RunWait('powershell.exe -NoProfile -Command "Get-ChildItem -Path \"' dst '\" -Recurse -File | Unblock-File"', , "Hide")
    } catch {
        ; If Unblock-File fails, try removing the stream directly
        try {
            RunWait('powershell.exe -NoProfile -Command "Get-ChildItem -Path \"' dst '\" -Recurse -File | ForEach-Object { Remove-Item -Path ($_.FullName + \":Zone.Identifier\") -ErrorAction SilentlyContinue }"', , "Hide")
        } catch {
            ; Last resort: process each file individually
            Loop Files dst "\*", "FR" {
                if !(A_LoopFileAttrib ~= "D") {  ; Only process files, not directories
                    try {
                        ; Try to delete the Zone.Identifier stream for each file
                        RunWait('powershell.exe -NoProfile -Command "Remove-Item -Path \"' A_LoopFileFullPath ':Zone.Identifier\" -ErrorAction SilentlyContinue"', , "Hide")
                    } catch {
                        ; Ignore individual file failures
                    }
                }
            }
        }
    }
}

; Helper function to create uninstall entries in the registry
CreateUninstall(uninstPath, name_no_ext, targetDir) {
    regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\" name_no_ext
    RegWrite("KnifMelti WAU Settings GUI", "REG_SZ", regPath, "DisplayName")
    RegWrite(FileGetVersion(uninstPath), "REG_SZ", regPath, "DisplayVersion")
    RegWrite(uninstPath, "REG_SZ", regPath, "DisplayIcon")
    RegWrite("KnifMelti", "REG_SZ", regPath, "Publisher")
    RegWrite("https://github.com/KnifMelti/" name_no_ext, "REG_SZ", regPath, "HelpLink")
    RegWrite("https://github.com/KnifMelti/" name_no_ext "/issues", "REG_SZ", regPath, "URLInfoAbout")
    RegWrite(uninstPath " /UNINSTALL", "REG_SZ", regPath, "UninstallString")
    RegWrite(uninstPath " /UNINSTALL /SILENT", "REG_SZ", regPath, "QuietUninstallString")
    RegWrite("1", "REG_DWORD", regPath, "NoModify")
    RegWrite("1", "REG_DWORD", regPath, "NoRepair")

    ; Create README link in installation directory and delete README.md if it exists
    readmeUrl := "https://github.com/KnifMelti/" name_no_ext
    urlContent := "[InternetShortcut]`nURL=" readmeUrl "`n"
    FileAppend(urlContent, targetDir "\README.url")
    if FileExist(targetDir "\README.md") {
        FileDelete(targetDir "\README.md")
    }
}

; Helper function to check internet connectivity using Windows API
IsInternetAvailable() {
    return DllCall("wininet.dll\InternetGetConnectedState", "UInt*", 0, "UInt", 0)
}

GetMSIParams() {
    startMenu := ""
    desktopWAU := ""
    desktopAppInstaller := ""

    try {
        shortcutFlag := RegRead("HKLM\SOFTWARE\Romanitho\Winget-AutoUpdate", "WAU_StartMenuShortcut")
    } catch {
        shortcutFlag := 0
    }
    if shortcutFlag = 1 {
        startMenu := "STARTMENUSHORTCUT=1"
    }

    try {
        shortcutFlag := RegRead("HKLM\SOFTWARE\Romanitho\Winget-AutoUpdate", "WAU_DesktopShortcut")
    } catch {
        shortcutFlag := 0
    }
    if shortcutFlag = 1 {
        desktopWAU := "DESKTOPSHORTCUT=1"
    }

    try {
        shortcutFlag := RegRead("HKLM\SOFTWARE\Romanitho\Winget-AutoUpdate", "WAU_AppInstallerShortcut")
    } catch {
        shortcutFlag := 0
    }
    if shortcutFlag = 1 {
        desktopAppInstaller := "APPINSTALLERSHORTCUT=1"
    }

    msiParams := ""
    if (startMenu != "")
        msiParams .= " " startMenu
    if (desktopWAU != "")
        msiParams .= " " desktopWAU
    if (desktopAppInstaller != "")
        msiParams .= " " desktopAppInstaller

    return msiParams
}
