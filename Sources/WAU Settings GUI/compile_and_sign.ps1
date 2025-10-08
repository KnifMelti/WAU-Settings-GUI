param([Parameter(Mandatory)]$InputFile)

$inputPath = $InputFile
$outputPath = $InputFile -replace '\.ahk$', '.exe'
$signScript = Join-Path (Split-Path $InputFile -Parent) "sign_exe.ps1"

# AutoHotkey compiler
$ahk2exe = "${env:ProgramFiles}\AutoHotkey\Compiler\Ahk2Exe.exe"

if (-not $ahk2exe) {
    Write-Host "[ERROR] AutoHotkey compiler not found!" -ForegroundColor Red
    exit 1
}

if (-not $inputPath.EndsWith('.ahk')) {
    Write-Host "[ERROR] Please open the .ahk file before building" -ForegroundColor Red
    exit 1
}

# Compile the executable
Write-Host "[COMPILE] Processing $(Split-Path $InputFile -Leaf)..." -ForegroundColor Cyan
$arguments = @("/in", "`"$inputPath`"", "/out", "`"$outputPath`"")
$processInfo = Start-Process -FilePath $ahk2exe -ArgumentList $arguments -Wait -PassThru -NoNewWindow

if ($processInfo.ExitCode -eq 0 -and (Test-Path $outputPath)) {
    Write-Host "[SUCCESS] Compilation successful" -ForegroundColor Green
    
    # Sign executable if script exists
    if (Test-Path $signScript) {
        Write-Host "[SIGN] Signing executable..." -ForegroundColor Cyan
        & $signScript $outputPath
    }
    
    Write-Host "[DONE] Build complete!" -ForegroundColor Green
}
else {
    Write-Host "[ERROR] Compilation failed" -ForegroundColor Red
    exit 1
}