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

    if (-not $tunnelProc -or $tunnelProc.HasExited) {
        $tunnelProc = Start-Process $DevTunnel -ArgumentList 'host', $TunnelId -NoNewWindow -PassThru `
            -RedirectStandardOutput "$dir\devtunnel.log" -RedirectStandardError "$dir\devtunnel.err.log"
    }

    Start-Sleep -Seconds 15
}
