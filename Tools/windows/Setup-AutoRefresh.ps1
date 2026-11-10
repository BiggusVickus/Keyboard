<#
.SYNOPSIS
    One-time setup on Windows: after this, plugging the iPhone into this PC re-signs Taalhulp
    for another 7 days, with nothing to click.

.DESCRIPTION
    1. Checks that Apple's device drivers are installed (they come with iTunes).
    2. Downloads plumesign (the command-line part of Impactor, an open-source sideloading tool).
    3. Signs you in to your Apple ID once (password + 2FA code). Only the resulting session
       token is stored, by plumesign, in %APPDATA%\PlumeImpactor. Your password is not saved.
    4. Installs a hidden background task that starts at every Windows logon and watches for the
       iPhone on USB (Watch-iPhone.ps1).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Setup-AutoRefresh.ps1 -AppleId you@example.com -Ipa .\Taalhulp.ipa

.EXAMPLE
    # Apple sign-in expired (the refresh notification says so):
    powershell -ExecutionPolicy Bypass -File .\Setup-AutoRefresh.ps1 -LoginOnly -AppleId you@example.com

.EXAMPLE
    # New build from the Mac: just replace the .ipa
    powershell -ExecutionPolicy Bypass -File .\Setup-AutoRefresh.ps1 -Ipa .\Taalhulp.ipa -UpdateIpaOnly
#>
param(
    [string]$AppleId,
    [string]$Ipa,
    [switch]$LoginOnly,
    [switch]$UpdateIpaOnly,
    [switch]$Uninstall,
    [double]$MinHoursBetweenRefreshes = 12
)

$ErrorActionPreference = 'Stop'
$Dir = Join-Path $env:LOCALAPPDATA 'TaalhulpRefresh'
$Exe = Join-Path $Dir 'plumesign.exe'
$TaskName = 'Taalhulp auto-refresh'
# Pinned release; update deliberately, after checking the release notes.
$PlumeVersion = 'v2.7.2'   # 2.7.1 got HTTP 403 from Apple's GrandSlam login; 2.7.2 fixes logins

function Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*Watch-iPhone.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Write-Host "Removed the background task. Files are still in $Dir (delete the folder to remove them)."
    exit 0
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null

if ($UpdateIpaOnly) {
    if (-not $Ipa) { throw 'Pass -Ipa <path to Taalhulp.ipa>.' }
    Copy-Item $Ipa (Join-Path $Dir 'Taalhulp.ipa') -Force
    Write-Host 'Updated. The next time the iPhone is plugged in and a refresh is due, this build is installed.'
    Write-Host "To install it right away: powershell -ExecutionPolicy Bypass -File `"$Dir\Watch-iPhone.ps1`" -Once"
    exit 0
}

if (-not $LoginOnly) {
    Step 'Checking Apple device drivers'
    if (-not (Get-Service -Name 'Apple Mobile Device Service' -ErrorAction SilentlyContinue)) {
        Write-Host 'Apple Mobile Device Service was not found. Install iTunes first:' -ForegroundColor Yellow
        Write-Host '  https://support.apple.com/en-us/106372'
        Write-Host 'Then connect the iPhone once, tap "Trust" on the phone, and run this script again.'
        exit 1
    }

    Step "Downloading plumesign $PlumeVersion"
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x86_64' }
    $url = "https://github.com/claration/Impactor/releases/download/$PlumeVersion/plumesign-windows-$arch.exe"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $Exe -UseBasicParsing
    $hash = (Get-FileHash $Exe -Algorithm SHA256).Hash
    Write-Host "Saved $Exe"
    Write-Host "SHA-256: $hash"

    Step 'Copying the app'
    if (-not $Ipa) { throw 'Pass -Ipa <path to Taalhulp.ipa> (built on the Mac with Tools/build_ipa.sh).' }
    Copy-Item $Ipa (Join-Path $Dir 'Taalhulp.ipa') -Force
    Copy-Item (Join-Path $PSScriptRoot 'Watch-iPhone.ps1') (Join-Path $Dir 'Watch-iPhone.ps1') -Force
}

Step 'Signing in to your Apple ID (once)'
if (-not $AppleId) { $AppleId = Read-Host 'Apple ID e-mail' }
Write-Host 'plumesign asks for your password and then the 2FA code from your iPhone.'
Write-Host 'Use your normal Apple ID password; app-specific passwords do not work for this.'
& $Exe account login -u $AppleId
if ($LASTEXITCODE -ne 0) {
    throw "Sign-in failed (plumesign exit code $LASTEXITCODE). The lines plumesign printed just above give the actual reason; a wrong password or code is only one possibility."
}

if ($LoginOnly) {
    Write-Host "`nSigned in again. The next refresh will work." -ForegroundColor Green
    exit 0
}

Step 'Installing the background task'
$watcher = Join-Path $Dir 'Watch-iPhone.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
    "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass " +
    "-File `"$watcher`" -MinHoursBetweenRefreshes $MinHoursBetweenRefreshes")
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description 'Re-signs Taalhulp when the iPhone is connected by USB.' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "`nAll set." -ForegroundColor Green
Write-Host 'Plug in the iPhone (unlocked, the first time) and Taalhulp is refreshed for 7 days.'
Write-Host 'A Windows notification tells you when it is done.'
Write-Host "Log: $Dir\refresh.log"
Write-Host "Refresh right now: powershell -ExecutionPolicy Bypass -File `"$watcher`" -Once"
