#Requires AutoHotkey v2.0
#SingleInstance
;@Ahk2Exe-Set CompanyName, KnifMelti
;@Ahk2Exe-Set ProductName, WAU Settings GUI
;@Ahk2Exe-Set FileDescription, WAU Settings GUI
;@Ahk2Exe-Set FileVersion, 1.7.9.2
;@Ahk2Exe-Set ProductVersion, 1.7.9.2
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
runCommand := '*RunAs C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' psScriptPath '"'
portableCommand := '*RunAs C:\Windows\System32\conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' psScriptPath '" -Portable'

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

    ; Check if working dir is under 'C:\Program Files\WinGet\Packages'
    if InStr(A_WorkingDir, "\WinGet\Packages\", false) > 0 {
        FileAppend("This directory was created by 'WAU Settings GUI' WinGet installer.", A_WorkingDir "\installed.txt")
    }

    ; Check if "installed.txt" exists in working directory
    if FileExist(A_WorkingDir "\installed.txt") {
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

            ; Open install directory in Explorer
            Run targetDir
            MsgBox(
                "Installation complete! Please start the program by running 'WAU-Settings-GUI.exe' from the installation folder.",
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
