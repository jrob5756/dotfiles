# Keeps the user-mode sshd and the dev tunnel host running; installed and started by setup.ps1.
# Runs from the state directory that holds sshd_config, so it never depends on the dotfiles checkout.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $TunnelId,
    [Parameter(Mandatory)][string] $DevTunnel
)

$dir = $PSScriptRoot
$sshd = "$env:WINDIR\System32\OpenSSH\sshd.exe"
$sshdProc = $null
$tunnelProc = $null
$tunnelStarted = [datetime]::MinValue
$lastHealthCheck = [datetime]::MinValue
$lastRenewal = [datetime]::MinValue

while ($true) {
    if (-not $sshdProc -or $sshdProc.HasExited) {
        $sshdProc = Start-Process $sshd -ArgumentList '-f', "`"$dir\sshd_config`"" -NoNewWindow -PassThru
    }

    # Tunnels expire after at most 30 days; pushing the expiration out daily keeps this one alive.
    if (((Get-Date) - $lastRenewal).TotalHours -ge 24) {
        & $DevTunnel update $TunnelId --expiration 30d *> "$dir\devtunnel-renew.log"
        if ($LASTEXITCODE -eq 0) { $lastRenewal = Get-Date }
    }

    # A host can lose the tunnel without exiting (another host took it over, or the relay dropped
    # it across sleep). If the service reports no host for a minute-old host, start a fresh one.
    $now = Get-Date
    if ($tunnelProc -and -not $tunnelProc.HasExited -and ($now - $tunnelStarted).TotalSeconds -ge 60 -and
        ($now - $lastHealthCheck).TotalSeconds -ge 60) {
        $lastHealthCheck = $now
        $json = & $DevTunnel show $TunnelId -j 2>$null | Out-String
        $hosts = if ($LASTEXITCODE -eq 0) { try { ($json | ConvertFrom-Json).tunnel.hostConnections } catch { $null } }
        if ($hosts -eq 0) {
            "$(Get-Date -Format o) tunnel reports no host; restarting devtunnel host" | Add-Content "$dir\supervisor.log"
            Stop-Process -Id $tunnelProc.Id -Force -ErrorAction SilentlyContinue
            $tunnelProc = $null
        }
    }

    if (-not $tunnelProc -or $tunnelProc.HasExited) {
        $tunnelProc = Start-Process $DevTunnel -ArgumentList 'host', $TunnelId -NoNewWindow -PassThru `
            -RedirectStandardOutput "$dir\devtunnel.log" -RedirectStandardError "$dir\devtunnel.err.log"
        $tunnelStarted = Get-Date
    }

    Start-Sleep -Seconds 15
}
