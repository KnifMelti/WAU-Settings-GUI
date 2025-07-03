powershell -WindowStyle Hidden -Command "Start-Process PowerShell -WindowStyle Hidden -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0WAU-Settings-GUI.ps1\"' -Verb RunAs"
del "%~f0"
