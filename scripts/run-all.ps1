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

$target    = if ($Release) { 'release' } else { 'debug' }
$buildArgs = if ($Release) { @('build', '--release', '--bin', 'server', '--bin', 'bots') } `
                      else { @('build', '--bin', 'server', '--bin', 'bots') }

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
    Write-Host "[run-all] Building binaries…"
    Push-Location $ServerDir
    try { & cargo @buildArgs } finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "[run-all] Starting server…"
    $procs += Start-Process -FilePath "$ServerDir\target\$target\server.exe" `
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
    $procs += Start-Process -FilePath "$ServerDir\target\$target\bots.exe" `
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
