# Launches the server, the bots, and the Godot client.
# Usage: pwsh scripts/run-all.ps1 [-Release]
#
# Override the Godot binary with the GODOT env var (default: "godot").
[CmdletBinding()]
param(
    [switch]$Release
)

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$ServerDir = Join-Path $RepoRoot 'Server'
$ClientDir = Join-Path $RepoRoot 'Client'
$GodotBin  = if ($env:GODOT) { $env:GODOT } else { 'godot' }

$cargoArgs = @('run', '--bin', 'server')
$botsArgs  = @('run', '--bin', 'bots')
if ($Release) {
    $cargoArgs = @('run', '--release', '--bin', 'server')
    $botsArgs  = @('run', '--release', '--bin', 'bots')
}

$procs = @()

function Stop-All {
    Write-Host "`n[run-all] Stopping child processes…"
    foreach ($p in $procs) {
        if ($p -and -not $p.HasExited) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

try {
    Write-Host "[run-all] Starting server…"
    $procs += Start-Process -FilePath 'cargo' -ArgumentList $cargoArgs `
        -WorkingDirectory $ServerDir -PassThru -NoNewWindow

    Write-Host "[run-all] Waiting for server on ws://localhost:8080…"
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $iar = $client.BeginConnect('localhost', 8080, $null, $null)
            if ($iar.AsyncWaitHandle.WaitOne(500) -and $client.Connected) {
                $client.Close()
                break
            }
            $client.Close()
        } catch {}
        Start-Sleep -Milliseconds 500
    }

    Write-Host "[run-all] Starting bots…"
    $procs += Start-Process -FilePath 'cargo' -ArgumentList $botsArgs `
        -WorkingDirectory $ServerDir -PassThru -NoNewWindow

    Write-Host "[run-all] Starting Godot client ($GodotBin)…"
    $procs += Start-Process -FilePath $GodotBin -ArgumentList @('--path', $ClientDir) `
        -WorkingDirectory $ClientDir -PassThru

    Write-Host "[run-all] All processes launched. Ctrl+C to stop."
    while ($true) {
        Start-Sleep -Seconds 1
        $alive = $procs | Where-Object { $_ -and -not $_.HasExited }
        if (-not $alive) { break }
    }
}
finally {
    Stop-All
}
