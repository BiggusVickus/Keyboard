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
    # New build from the Mac: just replace the .ipa (builds from GitHub are downloaded by themselves)
    powershell -ExecutionPolicy Bypass -File .\Setup-AutoRefresh.ps1 -Ipa .\Taalhulp.ipa -UpdateIpaOnly

.EXAMPLE
    # After changing Watch-iPhone.ps1: install the new watcher and restart it (no sign-in)
    powershell -ExecutionPolicy Bypass -File .\Setup-AutoRefresh.ps1 -UpdateWatcher
#>
param(
    [string]$AppleId,
    [string]$Ipa,
    [switch]$LoginOnly,
    [switch]$UpdateIpaOnly,
    [switch]$UpdateWatcher,
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

function Stop-Watcher {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*Watch-iPhone.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

# Starts the watcher at logon, and every 15 minutes in case it was stopped (a watcher that is
# already running is left alone).
function Install-Task {
    Step 'Installing the background task'
    Copy-Item (Join-Path $PSScriptRoot 'Watch-iPhone.ps1') (Join-Path $Dir 'Watch-iPhone.ps1') -Force
    $watcher = Join-Path $Dir 'Watch-iPhone.ps1'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass " +
        "-File `"$watcher`" -MinHoursBetweenRefreshes $MinHoursBetweenRefreshes")
    $triggers = @(
        (New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"),
        (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15))
    )
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Stop-Watcher
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings `
        -Principal $principal -Description 'Re-signs Taalhulp when the iPhone is connected by USB.' -Force | Out-Null
    Start-ScheduledTask -TaskName $TaskName
}

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Stop-Watcher
    Write-Host "Removed the background task. Files are still in $Dir (delete the folder to remove them)."
    exit 0
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null

if ($UpdateWatcher) {
    Install-Task
    Write-Host "`nThe new watcher is running. Plug in the iPhone to get the newest build." -ForegroundColor Green
    exit 0
}

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

    if ($Ipa) {
        Step 'Copying the app'
        Copy-Item $Ipa (Join-Path $Dir 'Taalhulp.ipa') -Force
    } else {
        Write-Host 'No -Ipa given: the newest build is downloaded from GitHub when the iPhone is plugged in.'
    }
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

Install-Task
$watcher = Join-Path $Dir 'Watch-iPhone.ps1'

Write-Host "`nAll set." -ForegroundColor Green
Write-Host 'Plug in the iPhone (unlocked, the first time) and Taalhulp is refreshed for 7 days.'
Write-Host 'A Windows notification tells you when it is done.'
Write-Host "Log: $Dir\refresh.log"
Write-Host "Refresh right now: powershell -ExecutionPolicy Bypass -File `"$watcher`" -Once"
