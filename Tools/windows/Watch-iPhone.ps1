<#
.SYNOPSIS
    Re-signs and reinstalls Taalhulp whenever the iPhone is connected by cable, so the
    7-day limit of a free Apple ID never runs out. Runs hidden in the background
    (Setup-AutoRefresh.ps1 starts it at every Windows logon).

    When the iPhone connects, it first downloads the newest build from the GitHub repo's
    "latest" release (made by .github/workflows/build.yml). A build the iPhone doesn't have yet
    is installed right away; the same build is only re-signed after MinHoursBetweenRefreshes.

.PARAMETER MinHoursBetweenRefreshes
    Plugging in again within this many hours of a successful refresh does nothing, unless there
    is a new build. 0 = refresh on every connection.

.PARAMETER Once
    Refresh the connected iPhone right now, then exit (for testing).

.PARAMETER Repo
    GitHub repo ("owner/name") whose "latest" release holds Taalhulp.ipa. Empty = don't download.
#>
param(
    [double]$MinHoursBetweenRefreshes = 12,
    [switch]$Once,
    [string]$Repo = 'BiggusVickus/Keyboard'
)

$ErrorActionPreference = 'Stop'
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe = Join-Path $Dir 'plumesign.exe'
$Ipa = Join-Path $Dir 'Taalhulp.ipa'
$StatePath = Join-Path $Dir 'state.json'
$InstalledPath = Join-Path $Dir 'installed.json'     # UDID -> which .ipa was last installed
$SourcePath = Join-Path $Dir 'ipa-source.txt'        # which GitHub upload Taalhulp.ipa came from
$LogPath = Join-Path $Dir 'refresh.log'
# Keep the same bundle ID as the Xcode build, so this replaces that app instead of adding a second copy
# (a free Apple ID allows only 3 sideloaded apps).
$BundleId = 'com.victorpiaskowski.taalhulp'

function Write-Log([string]$Message) {
    if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 1MB) {
        Move-Item $LogPath "$LogPath.old" -Force
    }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $Message" | Add-Content -Path $LogPath -Encoding UTF8
}

function Show-Notification([string]$Title, [string]$Text, [bool]$IsError = $false) {
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $icon = New-Object System.Windows.Forms.NotifyIcon
        $icon.Icon = [System.Drawing.SystemIcons]::Information
        $icon.Visible = $true
        $kind = if ($IsError) { 'Error' } else { 'Info' }
        $icon.ShowBalloonTip(8000, $Title, $Text, $kind)
        Start-Sleep -Seconds 8
        $icon.Dispose()
    } catch {
        Write-Log "Could not show notification: $_"
    }
}

# --- Talking to Apple's device service (usbmuxd, installed with iTunes) -------------------------

function Read-Exactly([System.IO.Stream]$Stream, [int]$Count) {
    $buffer = New-Object byte[] $Count
    $read = 0
    while ($read -lt $Count) {
        $n = $Stream.Read($buffer, $read, $Count - $read)
        if ($n -le 0) { throw 'usbmuxd closed the connection' }
        $read += $n
    }
    return ,$buffer
}

function ConvertFrom-PlistNode([System.Xml.XmlNode]$Node) {
    switch ($Node.Name) {
        'dict' {
            $result = @{}
            $children = @($Node.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })
            for ($i = 0; $i -lt $children.Count; $i += 2) {
                $result[$children[$i].InnerText] = ConvertFrom-PlistNode $children[$i + 1]
            }
            return $result
        }
        'array' { return ,@($Node.ChildNodes | Where-Object { $_.NodeType -eq 'Element' } | ForEach-Object { ConvertFrom-PlistNode $_ }) }
        'integer' { return [long]$Node.InnerText }
        'true' { return $true }
        'false' { return $false }
        default { return $Node.InnerText }
    }
}

# iPhones connected by cable: @{ DeviceId = <number for this connection>; Udid = <serial> }.
function Get-UsbIPhones {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $client.Connect('127.0.0.1', 27015)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000
        $xml = '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>' +
               '<key>MessageType</key><string>ListDevices</string>' +
               '<key>ClientVersionString</key><string>taalhulp-refresh</string>' +
               '<key>ProgName</key><string>taalhulp-refresh</string></dict></plist>'
        $body = [Text.Encoding]::UTF8.GetBytes($xml)
        $header = New-Object byte[] 16
        [BitConverter]::GetBytes([int](16 + $body.Length)).CopyTo($header, 0)
        [BitConverter]::GetBytes([int]1).CopyTo($header, 4)   # protocol version: plist
        [BitConverter]::GetBytes([int]8).CopyTo($header, 8)   # message type: plist
        [BitConverter]::GetBytes([int]1).CopyTo($header, 12)  # tag
        $stream.Write($header, 0, 16)
        $stream.Write($body, 0, $body.Length)

        $replyHeader = Read-Exactly $stream 16
        $length = [BitConverter]::ToInt32($replyHeader, 0)
        $reply = [Text.Encoding]::UTF8.GetString((Read-Exactly $stream ($length - 16)))
        $reply = $reply -replace '<!DOCTYPE[^>]*>', ''
        $doc = New-Object System.Xml.XmlDocument
        $doc.LoadXml($reply)
        $plist = ConvertFrom-PlistNode $doc.DocumentElement.SelectSingleNode('dict')

        $script:serviceWarningShown = $false
        $devices = @()
        foreach ($device in @($plist['DeviceList'])) {
            if (-not $device) { continue }
            $props = $device['Properties']
            if ($props['ConnectionType'] -ne 'USB') { continue }   # cable only, not Wi-Fi sync
            $devices += [pscustomobject]@{ DeviceId = $device['DeviceID']; Udid = $props['SerialNumber'] }
        }
        return $devices
    } catch {
        # Logged once, not every 5 seconds.
        if (-not $script:serviceWarningShown) {
            Write-Log "Can't reach Apple Mobile Device Service (is iTunes installed?): $($_.Exception.Message)"
            $script:serviceWarningShown = $true
        }
        return @()
    } finally {
        $client.Close()
    }
}

# --- State: when each iPhone was last refreshed ----------------------------------------------------

function Get-State {
    if (Test-Path $StatePath) {
        $json = Get-Content $StatePath -Raw | ConvertFrom-Json
        $state = @{}
        foreach ($p in $json.PSObject.Properties) { $state[$p.Name] = [datetime]$p.Value }
        return $state
    }
    return @{}
}

function Save-State($State) {
    $out = @{}
    foreach ($k in $State.Keys) { $out[$k] = $State[$k].ToString('o') }
    $out | ConvertTo-Json | Set-Content $StatePath -Encoding UTF8
}

# Identifies one particular Taalhulp.ipa (a new download or copy changes it).
function Get-IpaStamp {
    if (-not (Test-Path $Ipa)) { return '' }
    $item = Get-Item $Ipa
    return "$($item.Length)-$($item.LastWriteTimeUtc.Ticks)"
}

function Get-Installed {
    $installed = @{}
    if (Test-Path $InstalledPath) {
        $json = Get-Content $InstalledPath -Raw | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $installed[$p.Name] = [string]$p.Value }
    }
    return $installed
}

function Save-Installed($Installed) {
    $Installed | ConvertTo-Json | Set-Content $InstalledPath -Encoding UTF8
}

# --- New builds from GitHub ------------------------------------------------------------------------

# Downloads Taalhulp.ipa from the repo's "latest" release when it changed since the last download.
# Offline or no release yet: logs it and keeps the current .ipa.
function Update-IpaFromGitHub {
    if (-not $Repo) { return }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/tags/latest" `
            -Headers @{ 'User-Agent' = 'taalhulp-refresh' } -TimeoutSec 15 -UseBasicParsing
        $asset = @($release.assets | Where-Object { $_.name -eq 'Taalhulp.ipa' })[0]
        if (-not $asset) { return }
        $source = "$($asset.id)-$($asset.updated_at)"
        if ((Test-Path $Ipa) -and (Test-Path $SourcePath) -and (Get-Content $SourcePath -Raw).Trim() -eq $source) { return }

        $download = "$Ipa.download"
        Invoke-WebRequest $asset.browser_download_url -OutFile $download -TimeoutSec 300 -UseBasicParsing
        Move-Item $download $Ipa -Force
        (Get-Item $Ipa).LastWriteTime = Get-Date   # marks it as a new build for Get-IpaStamp
        Set-Content $SourcePath $source -Encoding UTF8
        Write-Log "Downloaded a new build from GitHub: $($release.body)"
    } catch {
        Write-Log "Could not check GitHub for a new build: $($_.Exception.Message)"
    }
}

# --- The refresh itself ----------------------------------------------------------------------------

function Invoke-Refresh($Device) {
    if (-not (Test-Path $Ipa)) {
        Write-Log "Missing $Ipa. Build it on the Mac with Tools/build_ipa.sh and copy it here."
        Show-Notification 'Taalhulp not refreshed' "Taalhulp.ipa is missing in $Dir" $true
        return $false
    }
    Write-Log "Refreshing on $($Device.Udid) (connection $($Device.DeviceId))..."
    $env:RUST_LOG = 'info'
    # plumesign logs to stderr; Windows PowerShell would treat that as an error under 'Stop'.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $output = & $Exe sign --package $Ipa --apple-id --register-and-install `
        --udid "$($Device.DeviceId)" --custom-identifier $BundleId 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    $output | ForEach-Object { Write-Log "  $_" }

    if ($code -eq 0) {
        $until = (Get-Date).AddDays(7).ToString('dddd d MMM')
        Write-Log "Done. Valid until about $until."
        Show-Notification 'Taalhulp refreshed' "Works until about $until. You can unplug."
        return $true
    }
    $hint = if (($output -join "`n") -match 'login|session|auth|401|token') {
        'Apple sign-in expired: run Setup-AutoRefresh.ps1 -LoginOnly.'
    } else {
        "See $LogPath"
    }
    Write-Log "Failed (exit code $code). $hint"
    Show-Notification 'Taalhulp refresh failed' $hint $true
    return $false
}

# --- Main loop -------------------------------------------------------------------------------------

$state = Get-State
$installed = Get-Installed

function Complete-Refresh($Device, [string]$Stamp) {
    $state[$Device.Udid] = Get-Date
    Save-State $state
    $installed[$Device.Udid] = $Stamp
    Save-Installed $installed
}

if ($Once) {
    $devices = @(Get-UsbIPhones)
    if ($devices.Count -eq 0) { Write-Host 'No iPhone connected by cable.'; exit 1 }
    Update-IpaFromGitHub
    foreach ($d in $devices) {
        $stamp = Get-IpaStamp
        if (Invoke-Refresh $d) { Complete-Refresh $d $stamp }
    }
    Get-Content $LogPath -Tail 5
    exit 0
}

Write-Log 'Watcher started.'
$connected = @{}      # UDID -> time it was first seen in this connection
$lastAttempt = @{}    # UDID -> last attempt (success or not)
while ($true) {
    try {
        $now = Get-Date
        $devices = @(Get-UsbIPhones)
        $present = @{}
        foreach ($d in $devices) {
            $present[$d.Udid] = $true
            if (-not $connected.ContainsKey($d.Udid)) {
                $connected[$d.Udid] = $now
                Write-Log "iPhone connected: $($d.Udid)"
                # Once per connection: fetch a newer build if GitHub has one.
                Update-IpaFromGitHub
            }
            # Give the phone a few seconds after plugging in (trust, pairing) before installing.
            if (($now - $connected[$d.Udid]).TotalSeconds -lt 5) { continue }

            $last = $state[$d.Udid]
            $stamp = Get-IpaStamp
            # A build this iPhone doesn't have yet goes on right away; the same build waits for the
            # re-sign interval. (No record yet = installed before this was tracked: compare dates.)
            $newBuild = if ($installed.ContainsKey($d.Udid)) { $installed[$d.Udid] -ne $stamp }
                        else { $last -and (Test-Path $Ipa) -and (Get-Item $Ipa).LastWriteTime -gt $last }
            $due = (-not $last) -or $newBuild -or (($now - $last).TotalHours -ge $MinHoursBetweenRefreshes)
            # Once tried during this connection, wait 30 minutes before trying again.
            $tried = $lastAttempt[$d.Udid]
            $retryOk = (-not $tried) -or ($tried -lt $connected[$d.Udid]) -or (($now - $tried).TotalMinutes -ge 30)
            if ($due -and $retryOk) {
                $lastAttempt[$d.Udid] = $now
                if ($newBuild) { Write-Log 'New build: installing now.' }
                if (Invoke-Refresh $d) { Complete-Refresh $d $stamp }
            }
        }
        foreach ($udid in @($connected.Keys)) {
            if (-not $present.ContainsKey($udid)) {
                $connected.Remove($udid)
                Write-Log "iPhone disconnected: $udid"
            }
        }
    } catch {
        Write-Log "Error: $_"
    }
    Start-Sleep -Seconds 5
}
