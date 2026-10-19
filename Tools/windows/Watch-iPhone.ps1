<#
.SYNOPSIS
    Re-signs and reinstalls Taalhulp whenever the iPhone is connected by cable, so the
    7-day limit of a free Apple ID never runs out. Runs hidden in the background
    (Setup-AutoRefresh.ps1 starts it at every Windows logon).

.PARAMETER MinHoursBetweenRefreshes
    Plugging in again within this many hours of a successful refresh does nothing.
    0 = refresh on every connection.

.PARAMETER Once
    Refresh the connected iPhone right now, then exit (for testing).
#>
param(
    [double]$MinHoursBetweenRefreshes = 12,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
$Dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe = Join-Path $Dir 'plumesign.exe'
$Ipa = Join-Path $Dir 'Taalhulp.ipa'
$StatePath = Join-Path $Dir 'state.json'
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

if ($Once) {
    $devices = @(Get-UsbIPhones)
    if ($devices.Count -eq 0) { Write-Host 'No iPhone connected by cable.'; exit 1 }
    foreach ($d in $devices) {
        if (Invoke-Refresh $d) { $state[$d.Udid] = Get-Date; Save-State $state }
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
            }
            # Give the phone a few seconds after plugging in (trust, pairing) before installing.
            if (($now - $connected[$d.Udid]).TotalSeconds -lt 5) { continue }

            $last = $state[$d.Udid]
            $due = (-not $last) -or (($now - $last).TotalHours -ge $MinHoursBetweenRefreshes)
            # Once tried during this connection, wait 30 minutes before trying again.
            $tried = $lastAttempt[$d.Udid]
            $retryOk = (-not $tried) -or ($tried -lt $connected[$d.Udid]) -or (($now - $tried).TotalMinutes -ge 30)
            if ($due -and $retryOk) {
                $lastAttempt[$d.Udid] = $now
                if (Invoke-Refresh $d) {
                    $state[$d.Udid] = Get-Date
                    Save-State $state
                }
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
