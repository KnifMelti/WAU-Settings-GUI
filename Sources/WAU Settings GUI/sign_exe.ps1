param([Parameter(Mandatory)]$ExePath)

$certSHA1 = "349C0D33B7934F917AA0A36B1340A288AB56179E"
$timestampUrl = "http://timestamp.digicert.com" 
$signtool = (Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin\" -Filter signtool.exe -Recurse | 
    Where-Object { $_.FullName -match "\\x64\\" } |
    ForEach-Object {
        if ($_.FullName -match "\\bin\\(?<version>[0-9\.]+)\\") {
            [PSCustomObject]@{
                Path = $_.FullName
                Version = [Version]$matches['version']
            }
        }
    } |
    Sort-Object Version -Descending |
    Select-Object -First 1).Path

if (-not (Test-Path $ExePath)) {
    Write-Host "[ERROR] File not found: $ExePath" -ForegroundColor Red
    exit 1
}

# Sign the executable (quiet mode except for errors)
$result = & $signtool sign /sha1 $certSHA1 /t $timestampUrl /fd SHA256 /q $ExePath 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "[SUCCESS] Successfully signed with KnifMelti certificate" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Signing failed: $result" -ForegroundColor Red
    exit 1
}
