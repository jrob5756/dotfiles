#Requires -Version 7.4
<#
.SYNOPSIS
    Lets other machines SSH into this Dev Box as the signed-in user, through a dev tunnel.
.DESCRIPTION
    The built-in sshd service logs users in through a domain controller, which Microsoft-hosted
    Dev Boxes cannot reach, and Microsoft Entra accounts cannot use key authentication. Instead,
    sshd runs as the signed-in user inside their logon session, where it can only log in that
    same user and hands sessions their full token. sshd listens on loopback only; a dev tunnel
    that only the user's account can connect to carries the traffic. See windows/README.md.

    Previews by default. -Apply makes the changes, prompting for elevation once if needed.
#>
[CmdletBinding()]
param(
    [switch] $Apply,
    [switch] $Uninstall,
    [string] $TunnelId,
    [ValidateRange(1024, 65535)][int] $Port = 2222,
    [string] $AuthorizedKeysFile,
    [switch] $Force,
    [string] $HomePath = $env:USERPROFILE,
    [string] $DevTunnelPath,
    [Parameter(DontShow)][string] $ElevatedStep,
    [Parameter(DontShow)][string] $TaskUser,
    [Parameter(DontShow)][string] $ElevatedLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'Run this script with PowerShell 7 on Windows.' }
if (-not $HomePath -or -not [IO.Path]::IsPathFullyQualified($HomePath)) {
    throw "Expected an absolute Windows path: '$HomePath'"
}
$HomePath = $HomePath.TrimEnd('\')
if (-not $TunnelId) {
    $TunnelId = ($env:USERNAME.ToLowerInvariant() -replace '[^a-z0-9-]', '-') + '-devbox'
}
if ($TunnelId -cnotmatch '^[a-z0-9][a-z0-9-]{1,58}[a-z0-9](\.[a-z0-9]+)?$') {
    throw "Invalid tunnel ID '$TunnelId': use lowercase letters, digits and hyphens."
}
if (-not $DevTunnelPath) {
    $DevTunnelPath = (Get-Command devtunnel -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1).Source
    if (-not $DevTunnelPath) { $DevTunnelPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\devtunnel.exe' }
}

$taskName = 'DevBox SSH'
$openSsh = "$env:WINDIR\System32\OpenSSH"
$openSshKey = 'HKLM:\SOFTWARE\OpenSSH'
$pwshExe = Join-Path $PSHOME 'pwsh.exe'
$conhost = "$env:WINDIR\System32\conhost.exe"
$stateDir = Join-Path $HomePath '.ssh\devbox-sshd'
$sshdConfig = Join-Path $stateDir 'sshd_config'
$hostKey = Join-Path $stateDir 'ssh_host_ed25519_key'
$authorizedKeys = Join-Path $stateDir 'authorized_keys'
$supervisor = Join-Path $stateDir 'supervisor.ps1'
$supervisorSource = Join-Path $PSScriptRoot 'supervisor.ps1'
$userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$privateSids = @($userSid, 'S-1-5-18', 'S-1-5-32-544')
if (-not $TaskUser) { $TaskUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name }

function Get-TaskArguments {
    "--headless `"$pwshExe`" -NoProfile -ExecutionPolicy Bypass -File `"$supervisor`" " +
    "-TunnelId $TunnelId -DevTunnel `"$DevTunnelPath`""
}

function Invoke-AdminStep([string] $Name) {
    switch ($Name) {
        'InstallOpenSsh' {
            $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
            if ($capability.State -ne 'Installed') { Add-WindowsCapability -Online -Name $capability.Name | Out-Null }
        }
        'DisableSystemSshd' {
            Stop-Service sshd -ErrorAction SilentlyContinue
            Set-Service sshd -StartupType Disabled
            Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
        }
        'SetDefaultShell' {
            if (-not (Test-Path $openSshKey)) { New-Item -Path $openSshKey | Out-Null }
            New-ItemProperty -Path $openSshKey -Name DefaultShell -Value $pwshExe -PropertyType String -Force | Out-Null
        }
        'RegisterTask' {
            $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 `
                -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -MultipleInstances IgnoreNew -StartWhenAvailable
            Register-ScheduledTask -TaskName $taskName -Force `
                -Description 'User-mode sshd and dev tunnel host from dotfiles windows/devbox-ssh.' `
                -Action (New-ScheduledTaskAction -Execute $conhost -Argument (Get-TaskArguments)) `
                -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $TaskUser) `
                -Principal (New-ScheduledTaskPrincipal -UserId $TaskUser -LogonType Interactive -RunLevel Limited) `
                -Settings $settings | Out-Null
        }
        'UnregisterTask' { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false }
        default { throw "Unknown elevated step: $Name" }
    }
}

if ($ElevatedStep) {
    try {
        & {
            foreach ($step in $ElevatedStep -split ',') {
                Invoke-AdminStep $step
                "Done (elevated): $step"
            }
        } *>&1 | Out-File -LiteralPath $ElevatedLog -Append
        exit 0
    }
    catch {
        "Elevated step failed: $_" | Out-File -LiteralPath $ElevatedLog -Append
        exit 1
    }
}

function Test-IsAdmin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevated([string[]] $Steps) {
    if (-not $Steps) { return }
    if (Test-IsAdmin) {
        foreach ($step in $Steps) { Invoke-AdminStep $step; Write-Host "Done: $step" }
        return
    }
    $log = Join-Path ([IO.Path]::GetTempPath()) "devbox-ssh-$([guid]::NewGuid().ToString('N')).log"
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Force -ElevatedStep $($Steps -join ',') " +
        "-TunnelId $TunnelId -Port $Port -HomePath `"$HomePath`" -DevTunnelPath `"$DevTunnelPath`" " +
        "-TaskUser `"$TaskUser`" -ElevatedLog `"$log`""
    Write-Host "Requesting elevation for: $($Steps -join ', ')"
    $process = Start-Process $pwshExe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList $arguments
    if (Test-Path -LiteralPath $log) {
        Get-Content -LiteralPath $log | Write-Host
        Remove-Item -LiteralPath $log
    }
    if ($process.ExitCode -ne 0) { throw 'Elevated steps failed; see the output above.' }
}

function Test-Substring([string] $Text, [string] $Value) {
    $Text -and $Text.Contains($Value, [StringComparison]::OrdinalIgnoreCase)
}

function Get-RunningPart {
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='pwsh.exe' OR Name='sshd.exe' OR Name='devtunnel.exe'")
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        ForEach-Object OwningProcess)
    [pscustomobject]@{
        Supervisor = @($processes | Where-Object { $_.Name -eq 'pwsh.exe' -and (Test-Substring $_.CommandLine $supervisor) })
        Sshd = @($processes | Where-Object {
                $_.Name -eq 'sshd.exe' -and $_.ProcessId -in $listeners -and (Test-Substring $_.CommandLine $stateDir) })
        Tunnel = @($processes | Where-Object {
                $_.Name -eq 'devtunnel.exe' -and $_.CommandLine -match '\shost\s' -and
                (Test-Substring $_.CommandLine $TunnelId) })
    }
}

function Stop-RunningPart($Parts) {
    # Supervisor first, so it cannot respawn the others.
    foreach ($process in @($Parts.Supervisor) + @($Parts.Sshd) + @($Parts.Tunnel)) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

function Test-PrivateAcl([string] $Path) {
    $acl = Get-Acl -LiteralPath $Path
    if (-not $acl.AreAccessRulesProtected) { return $false }
    foreach ($rule in $acl.Access) {
        $sid = try { $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { $null }
        if ($sid -notin $privateSids) { return $false }
    }
    return $true
}

function Set-PrivateAcl([string] $Path) {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new($userSid))
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in $privateSids) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                [Security.Principal.SecurityIdentifier]::new($sid), 'FullControl',
                'ContainerInherit,ObjectInherit', 'None', 'Allow'))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Get-SshdConfig {
    $dir = $stateDir.Replace('\', '/')
    @(
        '# Managed by dotfiles windows/devbox-ssh/setup.ps1; rerun it instead of editing this file.'
        '# sshd runs as the signed-in user, so it can only log in that user. It listens on loopback'
        '# only and is reached through the dev tunnel.'
        "Port $Port"
        'ListenAddress 127.0.0.1'
        'ListenAddress ::1'
        "HostKey `"$dir/ssh_host_ed25519_key`""
        "AuthorizedKeysFile `"$dir/authorized_keys`""
        "PidFile `"$dir/sshd.pid`""
        'PubkeyAuthentication yes'
        'PasswordAuthentication no'
        'KbdInteractiveAuthentication no'
        'Subsystem sftp sftp-server.exe'
        ''
    ) -join "`r`n"
}

function Get-KeyLine([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    @(Get-Content -LiteralPath $Path | ForEach-Object Trim | Where-Object { $_ -and -not $_.StartsWith('#') })
}

function Test-DevTunnelLogin {
    (& $DevTunnelPath user show 2>&1 | Out-String) -match 'Logged in as'
}

$plan = [Collections.Generic.List[object]]::new()
function Add-Step([string] $Kind, [string] $Name, [string] $Text) {
    $plan.Add([pscustomobject]@{ Kind = $Kind; Name = $Name; Text = $Text })
}
function Test-Planned([string] $Name) { [bool]($plan | Where-Object Name -EQ $Name) }

$parts = Get-RunningPart
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$generated = @()
if (Test-Path -LiteralPath $stateDir) {
    $generated = @(Get-ChildItem -LiteralPath $stateDir -File | Where-Object Name -NE 'authorized_keys')
}

if ($Uninstall) {
    if ($AuthorizedKeysFile) { throw '-AuthorizedKeysFile cannot be combined with -Uninstall.' }
    if ($task) { Add-Step Admin UnregisterTask "unregister the '$taskName' logon task" }
    if ($parts.Supervisor -or $parts.Sshd -or $parts.Tunnel) {
        Add-Step User StopParts 'stop the supervisor, sshd and devtunnel host (drops open SSH sessions over the tunnel)'
    }
    if ($generated) {
        Add-Step User RemoveFiles "remove $($generated.Count) generated file(s) from $stateDir (keeps authorized_keys)"
    }
}
else {
    if (-not $Force -and $env:COMPUTERNAME -notlike 'CPC-*') {
        throw "'$env:COMPUTERNAME' does not look like a Dev Box (CPC-*). Re-run with -Force to set it up anyway."
    }

    if (-not (Test-Path "$openSsh\sshd.exe")) {
        Add-Step Admin InstallOpenSsh 'install the OpenSSH Server capability'
        Add-Step Admin DisableSystemSshd 'keep the SYSTEM sshd service stopped and disabled'
    }
    else {
        $service = Get-Service sshd -ErrorAction SilentlyContinue
        if ($service -and ($service.StartType -ne 'Disabled' -or $service.Status -ne 'Stopped')) {
            Add-Step Admin DisableSystemSshd 'stop and disable the SYSTEM sshd service'
        }
    }
    $defaultShell = try { Get-ItemPropertyValue -Path $openSshKey -Name DefaultShell } catch { $null }
    if ($defaultShell -ne $pwshExe) { Add-Step Admin SetDefaultShell "set the OpenSSH default shell to $pwshExe" }
    $taskAction = if ($task) { @($task.Actions)[0] } else { $null }
    if (-not $taskAction -or $taskAction.Execute -ne $conhost -or $taskAction.Arguments -ne (Get-TaskArguments)) {
        Add-Step Admin RegisterTask "register the '$taskName' logon task"
    }

    if (-not (Test-Path -LiteralPath $DevTunnelPath -PathType Leaf)) {
        Add-Step User InstallDevTunnel 'install the devtunnel CLI (winget, user scope)'
        Add-Step User Login 'sign in to dev tunnels'
        Add-Step User EnsureTunnel "create tunnel $TunnelId with port $Port if missing"
    }
    elseif (-not (Test-DevTunnelLogin)) {
        Add-Step User Login 'sign in to dev tunnels'
        Add-Step User EnsureTunnel "create tunnel $TunnelId with port $Port if missing"
    }
    else {
        & $DevTunnelPath show $TunnelId *> $null
        if ($LASTEXITCODE -ne 0) {
            Add-Step User EnsureTunnel "create tunnel $TunnelId with port $Port"
        }
        else {
            & $DevTunnelPath port show $TunnelId -p $Port *> $null
            if ($LASTEXITCODE -ne 0) { Add-Step User EnsureTunnel "add port $Port to tunnel $TunnelId" }
        }
    }

    if (-not (Test-Path -LiteralPath $stateDir)) {
        Add-Step User CreateDir "create $stateDir (current user, SYSTEM and Administrators only)"
    }
    elseif (-not (Test-PrivateAcl $stateDir)) {
        Add-Step User CreateDir "restrict $stateDir to the current user, SYSTEM and Administrators"
    }
    if (-not (Test-Path -LiteralPath $hostKey)) { Add-Step User HostKey "generate host key $hostKey" }
    $config = Get-SshdConfig
    $currentConfig = if (Test-Path -LiteralPath $sshdConfig) { Get-Content -LiteralPath $sshdConfig -Raw } else { $null }
    if ($currentConfig -ne $config) { Add-Step User WriteConfig "write $sshdConfig" }
    if (-not (Test-Path -LiteralPath $supervisor) -or
        (Get-FileHash -LiteralPath $supervisor).Hash -ne (Get-FileHash -LiteralPath $supervisorSource).Hash) {
        Add-Step User CopySupervisor "copy supervisor.ps1 to $stateDir"
    }
    $newKeys = @()
    if ($AuthorizedKeysFile) {
        & "$openSsh\ssh-keygen.exe" -l -f $AuthorizedKeysFile *> $null
        if ($LASTEXITCODE -ne 0) { throw "Not a valid public key file: $AuthorizedKeysFile" }
        $existingKeys = Get-KeyLine $authorizedKeys
        $newKeys = @(Get-KeyLine $AuthorizedKeysFile | Where-Object { $_ -notin $existingKeys })
        if ($newKeys) { Add-Step User AuthorizedKeys "add $($newKeys.Count) key(s) from $AuthorizedKeysFile" }
    }
    if (-not $newKeys -and -not (Test-Path -LiteralPath $authorizedKeys)) {
        Add-Step User AuthorizedKeys "create an empty $authorizedKeys"
    }

    $restartNeeded = (Test-Planned WriteConfig) -or (Test-Planned CopySupervisor) -or (Test-Planned RegisterTask)
    if ($restartNeeded -and ($parts.Supervisor -or $parts.Sshd -or $parts.Tunnel)) {
        Add-Step User Start 'restart the supervisor, sshd and devtunnel host (drops open SSH sessions over the tunnel)'
    }
    elseif ($restartNeeded -or -not $parts.Supervisor) {
        Add-Step User Start "start the '$taskName' task"
    }
}

foreach ($step in $plan) { Write-Host "$($step.Kind): $($step.Text)" }
if (-not $Apply) {
    if (Test-Planned WriteConfig) {
        Write-Host "`nsshd_config to write:"
        Write-Host (($config.TrimEnd() -split "`r`n" | ForEach-Object { "  $_" }) -join "`n")
    }
    if ($plan.Count) {
        Write-Host "Inspection only; nothing changed. Re-run with -Apply to $(if ($Uninstall) { 'uninstall' } else { 'set up' })."
    }
    else { Write-Host 'Nothing to change.' }
    return
}
if (-not $plan.Count) { Write-Host 'Nothing to change.' }

if ($Uninstall) {
    Invoke-Elevated @($plan | Where-Object Kind -EQ Admin | ForEach-Object Name)
    if (Test-Planned StopParts) { Stop-RunningPart (Get-RunningPart) }
    if (Test-Planned RemoveFiles) { $generated | Remove-Item -Force }
    Write-Host "Uninstalled. Left in place: the OpenSSH Server capability (its service stays disabled), the OpenSSH"
    Write-Host "default shell, $authorizedKeys, and tunnel $TunnelId (remove it with: devtunnel delete $TunnelId)."
    return
}

if (Test-Planned InstallDevTunnel) {
    winget install --exact --id Microsoft.devtunnel --source winget --scope user `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw 'winget could not install Microsoft.devtunnel.' }
    $DevTunnelPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\devtunnel.exe'
    if (-not (Test-Path -LiteralPath $DevTunnelPath)) { throw "devtunnel not found at $DevTunnelPath after install." }
}
if (Test-Planned Login) {
    # A separate console gives the Windows sign-in broker a window to attach to.
    Start-Process $DevTunnelPath -ArgumentList 'user', 'login' -Wait
    if (-not (Test-DevTunnelLogin)) { throw 'Not signed in to dev tunnels; run: devtunnel user login' }
}
if (Test-Planned EnsureTunnel) {
    & $DevTunnelPath show $TunnelId *> $null
    if ($LASTEXITCODE -ne 0) {
        & $DevTunnelPath create $TunnelId --expiration 30d -d "SSH to $env:COMPUTERNAME" | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Could not create tunnel '$TunnelId'. IDs are global; choose another with -TunnelId." }
    }
    & $DevTunnelPath port show $TunnelId -p $Port *> $null
    if ($LASTEXITCODE -ne 0) {
        & $DevTunnelPath port create $TunnelId -p $Port | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Could not add port $Port to tunnel '$TunnelId'." }
    }
}

Invoke-Elevated @($plan | Where-Object Kind -EQ Admin | ForEach-Object Name)

if (Test-Planned CreateDir) {
    if (-not (Test-Path -LiteralPath $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
    Set-PrivateAcl $stateDir
}
if (Test-Planned HostKey) {
    & "$openSsh\ssh-keygen.exe" -t ed25519 -N '' -q -C "devbox-sshd@$env:COMPUTERNAME" -f $hostKey
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen could not create the host key.' }
}
if (Test-Planned WriteConfig) { Set-Content -LiteralPath $sshdConfig -Value $config -Encoding ascii -NoNewline }
if (Test-Planned CopySupervisor) { Copy-Item -LiteralPath $supervisorSource -Destination $supervisor -Force }
if (Test-Planned AuthorizedKeys) {
    if (-not (Test-Path -LiteralPath $authorizedKeys)) { New-Item -ItemType File -Path $authorizedKeys | Out-Null }
    if ($newKeys) { Add-Content -LiteralPath $authorizedKeys -Value $newKeys -Encoding ascii }
}

& "$openSsh\sshd.exe" -t -f $sshdConfig
if ($LASTEXITCODE -ne 0) { throw "sshd rejected $sshdConfig." }

if (Test-Planned Start) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Stop-RunningPart (Get-RunningPart)
    Start-ScheduledTask -TaskName $taskName
    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Seconds 3
        $parts = Get-RunningPart
    } until (($parts.Sshd -and $parts.Tunnel) -or (Get-Date) -gt $deadline)
    if (-not $parts.Sshd) { throw 'sshd did not start; check Event Viewer > Applications and Services > OpenSSH.' }
    if (-not $parts.Tunnel) { throw "devtunnel host did not start; see $stateDir\devtunnel.err.log." }
}

Write-Host "`nReady: SSH as $TaskUser through tunnel $TunnelId (port $Port)."
Write-Host "Host key: $(& "$openSsh\ssh-keygen.exe" -l -f "$hostKey.pub")"
if (-not (Get-KeyLine $authorizedKeys)) {
    Write-Warning "No client keys yet. Add public keys to $authorizedKeys or re-run with -AuthorizedKeysFile."
}
Write-Host 'Client setup: see "SSH over dev tunnels (macOS)" in the dotfiles README.'
