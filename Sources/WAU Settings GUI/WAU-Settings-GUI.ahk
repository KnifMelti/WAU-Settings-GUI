#Requires AutoHotkey v2.0
#SingleInstance
;@Ahk2Exe-Set CompanyName, KnifMelti
;@Ahk2Exe-Set ProductName, WAU Settings GUI
;@Ahk2Exe-Set FileDescription, WAU Settings GUI
;@Ahk2Exe-Set FileVersion, 1.7.9.6
;@Ahk2Exe-Set ProductVersion, 1.7.9.6
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
shortcutDesktop := A_Desktop "\WAU Settings (Administrator).lnk"
shortcutStartMenu := A_ProgramsCommon "\Winget-AutoUpdate\WAU Settings (Administrator).lnk"
psScriptPath := A_WorkingDir "\" name_no_ext ".ps1"
runCommand := 'C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' psScriptPath '"'
portableCommand := 'C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' psScriptPath '" -Portable'

; Check if the script was called with -Uninstall parameter
if A_Args.Length && (A_Args[1] = "-Uninstall") {
    ; Ask the user to confirm uninstallation
    choice := MsgBox(
        "Do you want to uninstall WAU Settings GUI?" . "`n`nChoose Yes to uninstall, No to cancel.",
        name_no_ext,
        0x4  ; Yes/No
    )
    if (choice != "Yes") {
        ExitApp
    }
    ; Close all instances of WAU Settings GUI using PowerShell
    try {
        RunWait('C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -Command "Get-Process | Where-Object { $_.MainWindowTitle -like \"WAU Settings*\" } | Stop-Process -Force"', , "Hide")
    } catch {
        ; Ignore errors if no matching processes found
    }
    ; Remove shortcuts if they exist
    if FileExist(shortcutDesktop) || FileExist(shortcutStartMenu) {
        try {
            if FileExist(shortcutDesktop)
                FileDelete(shortcutDesktop)
            if FileExist(shortcutStartMenu)
                FileDelete(shortcutStartMenu)
        } catch {
            ; Ignore errors if shortcuts can't be deleted
        }
    }
    ; Check if working dir is under '\WinGet\Packages\'
    if InStr(A_WorkingDir, "\WinGet\Packages\", false) > 0 {
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
    ; Runs a command to delete the entire script folder after a short delay
    Run('cmd.exe /C ping 127.0.0.1 -n 3 > nul & rmdir /S /Q "' A_WorkingDir '"', , "Hide")
    ExitApp
}


; Check if both shortcuts exist
if FileExist(shortcutDesktop) && FileExist(shortcutStartMenu) {
    Run shortcutDesktop
} else if FileExist(shortcutDesktop) {
    ; Only desktop shortcut exists
    Run shortcutDesktop
} else if FileExist(shortcutStartMenu) {
    ; Only start menu shortcut exists
    Run shortcutStartMenu
} else {
    ; Check if running from portable media
    drive := SubStr(A_WorkingDir, 1, 2)
    driveType := DriveGetType(drive)
    
    if (driveType = "Removable" || driveType = "CDRom") {
        Run portableCommand
        ExitApp
    }

    ; Check if working dir is under '\WinGet\Packages'
    if InStr(A_WorkingDir, "\WinGet\Packages\", false) > 0 {
        FileAppend("This directory was created by 'WAU Settings GUI' WinGet installer.", A_WorkingDir "\installed.txt")
    }

    ; Check if "installed.txt" exists in working directory
    if FileExist(A_WorkingDir "\installed.txt") {
        ; Call the function to create uninstall entries in the registry
        CreateUninstall(name_no_ext, A_WorkingDir)
        Run runCommand
    } else {
        ; Ask the user if they want to install or run portable
        choice := MsgBox(
            "Do you want to install WAU Settings GUI?" . "`n`nChoose Yes to install, No to run as Portable, or Cancel to exit.",
            name_no_ext,
            0x103  ; Yes/No/Cancel with No as default
        )
        if (choice = "Cancel") {
            ExitApp
        }
        if (choice = "Yes") {
            ; Show a folder select dialog for base directory
            targetBaseDir := FileSelect("D", , "Select base directory for installation ('WAU Settings GUI' will be created here)")
            if !targetBaseDir {
                ; User cancelled
                ExitApp
            }
            ; Define the target directory as a new folder inside the selected base directory
            targetDir := targetBaseDir "\WAU Settings GUI"

            ; Create the target directory if it doesn't exist
            DirCreate(targetDir)

            ; Copy all files and subfolders from current script directory to targetDir
            CopyFilesAndFolders(A_WorkingDir, targetDir)

            ; Create installed.txt file in the target directory
            FileAppend("This directory was created by 'WAU Settings GUI' local installer.", targetDir "\installed.txt")

            ; Call the function to create uninstall entries in the registry
            CreateUninstall(name_no_ext, targetDir)

            ; Open install directory in Explorer
            Run targetDir
            MsgBox(
                "Installation complete! Please start the program by running '" name_no_ext ".exe' from the installation folder.",
                name_no_ext,
                0x40000  ; Information icon
            )
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
CreateUninstall(name_no_ext, targetDir) {
    regPath := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\" name_no_ext
    RegWrite("KnifMelti WAU Settings GUI", "REG_SZ", regPath, "DisplayName")
    RegWrite(FileGetVersion(A_ScriptFullPath), "REG_SZ", regPath, "DisplayVersion")
    RegWrite(A_ScriptFullPath, "REG_SZ", regPath, "DisplayIcon")
    RegWrite("KnifMelti", "REG_SZ", regPath, "Publisher")
    RegWrite("https://github.com/KnifMelti/" name_no_ext, "REG_SZ", regPath, "URLInfoAbout")
    RegWrite(A_ScriptFullPath " -Uninstall", "REG_SZ", regPath, "UninstallString")

    ; Create README link in installation directory
    readmeUrl := "https://github.com/KnifMelti/" name_no_ext
    urlContent := "[InternetShortcut]`nURL=" readmeUrl "`n"
    FileAppend(urlContent, targetDir "\README.url")
}