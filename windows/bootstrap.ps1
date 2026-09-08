#Requires -Version 7.4
[CmdletBinding(DefaultParameterSetName = 'Migrate')]
param(
    [Parameter(ParameterSetName = 'Migrate')][switch] $Apply,
    [Parameter(ParameterSetName = 'Migrate')][switch] $IncludeWindowsTerminal,
    [Parameter(Mandatory, ParameterSetName = 'Rollback')][string] $Rollback,
    [string] $HomePath = $env:USERPROFILE,
    [string] $LocalAppDataPath = $env:LOCALAPPDATA,
    [string] $ProfilePath = $PROFILE,
    [string] $BackupRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))

function Get-ExistingItem([string] $Path) {
    if (Test-Path -LiteralPath $Path) {
        return Get-Item -LiteralPath $Path -Force
    }
    # Get-Item also finds dangling symlinks, which Test-Path may miss.
    $parent = Split-Path -Parent $Path
    if (Test-Path -LiteralPath $parent -PathType Container) {
        return Get-ChildItem -LiteralPath $parent -Force |
            Where-Object Name -EQ (Split-Path -Leaf $Path) | Select-Object -First 1
    }
    return $null
}

function Assert-PlainParents([string] $Path) {
    $parent = Split-Path -Parent $Path
    while ($parent) {
        $item = Get-ExistingItem $parent
        if ($item -and (($item.LinkType -in @('SymbolicLink', 'Junction')) -or -not $item.PSIsContainer)) {
            throw "Parent must be a real directory, not a link or file: $parent"
        }
        $parent = Split-Path -Parent $parent
    }
}

function Get-Fingerprint([string] $Path) {
    $item = Get-ExistingItem $Path
    if (-not $item) { return $null }
    if ($item.LinkType -in @('SymbolicLink', 'Junction')) {
        return "$($item.LinkType):$($item.LinkTarget)"
    }
    if ($item.PSIsContainer) {
        $children = @(Get-ChildItem -LiteralPath $Path -Force | Sort-Object Name |
            ForEach-Object { "$($_.Name):$(Get-Fingerprint $_.FullName)" })
        $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($children -join "`n")))
        return "directory:$([Convert]::ToHexString($hash))"
    }
    return "sha256:$((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash)"
}

function Save-Manifest {
    $script:manifest | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath "$script:manifestPath.new" -Encoding utf8
    Move-Item -LiteralPath "$script:manifestPath.new" -Destination $script:manifestPath -Force
}

function New-PrivateDirectory([string] $Path) {
    New-Item -ItemType Directory -Path $Path | Out-Null
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($identity)
    $acl.SetAccessRuleProtection($true, $false)
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $identity, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Restore-Migration {
    $entries = @($script:manifest.Entries)
    [array]::Reverse($entries)
    # Validate every restore before removing anything; post-migration edits must survive.
    foreach ($entry in $entries) {
        foreach ($field in @('Path', 'Backup', 'Stage', 'State')) {
            if ($entry.$field -isnot [string] -or -not $entry.$field) { throw "Invalid manifest field: $field" }
        }
        foreach ($field in @('Fingerprint', 'OriginalFingerprint')) {
            if ($field -notin $entry.PSObject.Properties.Name -or
                ($null -ne $entry.$field -and $entry.$field -isnot [string])) {
                throw "Invalid manifest fingerprint: $field"
            }
        }
        if ($entry.HadOriginal -isnot [bool] -or
            $entry.State -notin @('Staging', 'Staged', 'Installed', 'Restoring', 'Restored')) {
            throw 'Invalid migration entry state.'
        }
        $backupDirectory = Split-Path -Parent $script:manifestPath
        if ((Split-Path -Parent $entry.Backup) -ne $backupDirectory -or
            -not $entry.Stage.StartsWith("$($entry.Path).dotfiles-", [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Manifest backup or staging path is invalid.'
        }
        Assert-PlainParents $entry.Path
        Assert-PlainParents $entry.Backup
        $current = Get-Fingerprint $entry.Path
        $hasBackup = $null -ne (Get-ExistingItem $entry.Backup)
        if ($entry.State -eq 'Restored') { continue }
        if (($hasBackup -or -not $entry.HadOriginal) -and $current -and
            $current -ne $entry.Fingerprint -and $current -ne $entry.OriginalFingerprint) {
            throw "Restore would overwrite subsequent changes: $($entry.Path). Move them aside and retry."
        }
        if ($entry.HadOriginal -and -not $hasBackup -and $entry.State -in @('Installed', 'Restoring')) {
            throw "Missing original backup: $($entry.Backup)"
        }
    }
    foreach ($entry in $entries) {
        if ($entry.State -eq 'Restored') { continue }
        $hasBackup = $null -ne (Get-ExistingItem $entry.Backup)
        if ($hasBackup -or -not $entry.HadOriginal) {
            $entry.State = 'Restoring'
            Save-Manifest
            if ((Get-Fingerprint $entry.Path) -ne $entry.OriginalFingerprint) {
                $restoreStage = "$($entry.Path).dotfiles-restore-$([guid]::NewGuid().ToString('N'))"
                try {
                    if ($hasBackup) {
                        $original = Get-ExistingItem $entry.Backup
                        if ($original.LinkType -in @('SymbolicLink', 'Junction')) {
                            New-Item -ItemType $original.LinkType -Path $restoreStage -Target $original.LinkTarget | Out-Null
                        }
                        else {
                            Copy-Item -LiteralPath $entry.Backup -Destination $restoreStage -Recurse
                            Set-Acl -LiteralPath $restoreStage -AclObject (Get-Acl -LiteralPath $entry.Backup)
                        }
                    }
                    if (Get-ExistingItem $entry.Path) { Remove-Item -LiteralPath $entry.Path -Force }
                    if ($hasBackup) { Move-Item -LiteralPath $restoreStage -Destination $entry.Path }
                }
                finally {
                    $stagedRestore = Get-ExistingItem $restoreStage
                    if ($stagedRestore) {
                        if ($stagedRestore.LinkType -in @('SymbolicLink', 'Junction')) {
                            Remove-Item -LiteralPath $restoreStage -Force
                        }
                        else { Remove-Item -LiteralPath $restoreStage -Force -Recurse }
                    }
                }
            }
        }
        if (Get-ExistingItem $entry.Stage) {
            Remove-Item -LiteralPath $entry.Stage -Force
        }
        $entry.State = 'Restored'
        Save-Manifest
    }
    $directories = @($script:manifest.CreatedDirectories)
    [array]::Reverse($directories)
    foreach ($directory in $directories) {
        if ((Test-Path -LiteralPath $directory -PathType Container) -and
            @(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) {
            Remove-Item -LiteralPath $directory
        }
    }
    $script:manifest.State = 'RolledBack'
    Save-Manifest
}

if (-not $IsWindows) { throw 'Run this script with PowerShell 7 on Windows.' }
foreach ($path in @($HomePath, $LocalAppDataPath, $ProfilePath)) {
    if (-not $path -or -not [IO.Path]::IsPathFullyQualified($path)) {
        throw "Expected an absolute Windows path: '$path'"
    }
}
if (-not $BackupRoot) { $BackupRoot = Join-Path $LocalAppDataPath 'dotfiles\backups' }
$BackupRoot = [IO.Path]::GetFullPath($BackupRoot)
if ($BackupRoot.TrimEnd('\') -eq $repo.TrimEnd('\') -or
    $BackupRoot.StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Backups must be outside the repository.'
}
Assert-PlainParents (Join-Path $BackupRoot 'manifest.json')

if ($Rollback) {
    $script:manifestPath = [IO.Path]::GetFullPath($Rollback)
    Assert-PlainParents $script:manifestPath
    $script:manifest = Get-Content -LiteralPath $script:manifestPath -Raw | ConvertFrom-Json
    if ($script:manifest.Version -ne 1 -or $script:manifest.Repo -ne $repo) {
        throw 'Manifest version or repository does not match this bootstrap.'
    }
    $rollbackRoot = Split-Path -Parent (Split-Path -Parent $script:manifestPath)
    $lock = [IO.File]::Open((Join-Path $rollbackRoot 'migration.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    try {
        Restore-Migration
        Write-Host "Rolled back: $script:manifestPath"
    }
    finally { $lock.Dispose() }
    return
}

$profileSource = Join-Path $repo 'windows\powershell\Microsoft.PowerShell_profile.ps1'
$plan = [Collections.Generic.List[object]]::new()
function Add-Plan([string] $Path, [string] $Kind, [string] $Target, [string] $Content = '') {
    $Path = [IO.Path]::GetFullPath($Path)
    if ($Path -eq $repo -or $Path.StartsWith("$repo\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Destination must be outside the repository: $Path"
    }
    if ($Path -eq $BackupRoot -or
        $Path.StartsWith("$BackupRoot\", [StringComparison]::OrdinalIgnoreCase) -or
        $BackupRoot.StartsWith("$Path\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "Destination and backup root must not overlap: $Path"
    }
    foreach ($planned in $plan) {
        if ($Path -eq $planned.Path -or
            $Path.StartsWith("$($planned.Path)\", [StringComparison]::OrdinalIgnoreCase) -or
            $planned.Path.StartsWith("$Path\", [StringComparison]::OrdinalIgnoreCase)) {
            throw "Migration destinations must not overlap: $Path and $($planned.Path)"
        }
    }
    Assert-PlainParents $Path
    if ([IO.Path]::GetPathRoot($Path) -ne [IO.Path]::GetPathRoot($BackupRoot)) {
        throw "Destination and backup must be on the same volume for atomic moves: $Path"
    }
    if ($Target -and -not (Test-Path -LiteralPath $Target)) {
        throw "Required target is missing: $Target"
    }
    $existing = Get-ExistingItem $Path
    if ($existing -and $existing.LinkType -eq 'SymbolicLink' -and $Kind -eq 'Link') {
        if ($existing.ResolveLinkTarget($false).FullName -eq [IO.Path]::GetFullPath($Target)) {
            Write-Host "Unchanged: $Path"
            return
        }
    }
    if ($existing -and $Kind -ne 'Link' -and $existing.PSIsContainer) {
        throw "Expected a file, found a directory: $Path"
    }
    $plan.Add([pscustomobject]@{ Path = $Path; Kind = $Kind; Target = $Target; Content = $Content })
}

if (-not (Test-Path -LiteralPath (Join-Path $repo 'nvim') -PathType Container)) {
    throw 'Required target nvim/ is missing or not a directory.'
}
if (-not (Test-Path -LiteralPath (Join-Path $repo 'generated\starship.toml') -PathType Leaf)) {
    throw 'Required target generated/starship.toml is missing or not a file.'
}
Add-Plan (Join-Path $LocalAppDataPath 'nvim') 'Link' (Join-Path $repo 'nvim')
Add-Plan (Join-Path $HomePath '.config\starship.toml') 'Link' (Join-Path $repo 'generated\starship.toml')
if (-not (Test-Path -LiteralPath $profileSource -PathType Leaf)) {
    throw "Required target is missing: $profileSource"
}
$sourceLine = ". '$($profileSource.Replace("'", "''"))'"
$marker = '# dotfiles: writable PowerShell loader v1'
$profileItem = Get-ExistingItem $ProfilePath
$managed = $false
if ($profileItem -and -not $profileItem.LinkType -and -not $profileItem.PSIsContainer) {
    $text = Get-Content -LiteralPath $ProfilePath -Raw
    if ($text -and $text.StartsWith($marker)) {
        if ($sourceLine -notin ($text -split '\r?\n')) {
            throw "Loader points at another checkout. Update its source path manually: $ProfilePath"
        }
        $managed = $true
        Write-Host "Unchanged writable loader: $ProfilePath"
    }
}
if (-not $managed) {
    $loader = "$marker`r`n$sourceLine`r`n"
    $canonicalPrivate = "$ProfilePath.local.ps1"
    if ((Get-ExistingItem $canonicalPrivate) -and
        -not (Test-Path -LiteralPath $canonicalPrivate -PathType Leaf)) {
        throw "Private profile must be a readable file: $canonicalPrivate"
    }
    $privateProfile = $null
    $isRepoProfile = $profileItem -and $profileItem.LinkType -eq 'SymbolicLink' -and
        $profileItem.ResolveLinkTarget($false).FullName -eq $profileSource
    if ($profileItem -and -not $isRepoProfile) {
        if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
            throw "Cannot preserve unreadable or non-file profile: $ProfilePath"
        }
        $privateProfile = $canonicalPrivate
        if (Get-ExistingItem $privateProfile) {
            $privateProfile = "$ProfilePath.local.$([guid]::NewGuid().ToString('N')).ps1"
        }
        Add-Plan $privateProfile 'Copy' $ProfilePath
        $loader += ". '$($privateProfile.Replace("'", "''"))'`r`n"
    }
    if ($canonicalPrivate -ne $privateProfile -and (Get-ExistingItem $canonicalPrivate)) {
        $loader += ". '$($canonicalPrivate.Replace("'", "''"))'`r`n"
    }
    $localProfile = Join-Path (Split-Path -Parent $ProfilePath) 'profile.local.ps1'
    $loader += "`$localProfile = '$($localProfile.Replace("'", "''"))'`r`n"
    $loader += "if (Test-Path -LiteralPath `$localProfile) { . `$localProfile }`r`n"
    Add-Plan $ProfilePath 'Loader' '' $loader
}
if ($IncludeWindowsTerminal) {
    $terminalDir = Join-Path $LocalAppDataPath 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    if (-not (Test-Path -LiteralPath $terminalDir -PathType Container)) {
        throw "Windows Terminal stable package not found: $terminalDir"
    }
    $terminalSource = Join-Path $repo 'windows\windows-terminal\settings.json'
    Get-Content -LiteralPath $terminalSource -Raw | ConvertFrom-Json | Out-Null
    Add-Plan (Join-Path $terminalDir 'settings.json') 'Copy' $terminalSource
}
foreach ($entry in $plan) { Write-Host "$($entry.Kind): $($entry.Path)" }
if (-not $Apply) {
    Write-Host 'Inspection only; nothing written. Re-run with -Apply to migrate.'
    return
}
if ($plan.Count -eq 0) { Write-Host 'Already migrated; nothing to change.'; return }

$backup = Join-Path $BackupRoot "$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
$lock = [IO.File]::Open((Join-Path $BackupRoot 'migration.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    New-PrivateDirectory $backup
    $script:manifestPath = Join-Path $backup 'manifest.json'
    $script:manifest = [pscustomobject]@{
        Version = 1; Repo = $repo; State = 'Applying'
        CreatedDirectories = @(); Entries = @()
    }
    Save-Manifest
    Write-Host "Private backup / rollback manifest: $script:manifestPath"
    try {
        foreach ($item in $plan) {
            $parent = Split-Path -Parent $item.Path
            $missing = [Collections.Generic.List[string]]::new()
            while (-not (Test-Path -LiteralPath $parent)) {
                $missing.Insert(0, $parent)
                $parent = Split-Path -Parent $parent
            }
            foreach ($directory in $missing) {
                $script:manifest.CreatedDirectories += $directory
                Save-Manifest
                New-Item -ItemType Directory -Path $directory | Out-Null
            }
            $entry = [pscustomobject]@{
                Path = $item.Path
                Backup = Join-Path $backup "$($script:manifest.Entries.Count).original"
                Stage = "$($item.Path).dotfiles-$([guid]::NewGuid().ToString('N'))"
                HadOriginal = $null -ne (Get-ExistingItem $item.Path)
                OriginalFingerprint = Get-Fingerprint $item.Path
                Fingerprint = $null; State = 'Staging'
            }
            $script:manifest.Entries += $entry
            Save-Manifest
            switch ($item.Kind) {
                'Link' { New-Item -ItemType SymbolicLink -Path $entry.Stage -Target $item.Target | Out-Null }
                'Copy' { [IO.File]::WriteAllBytes($entry.Stage, [IO.File]::ReadAllBytes($item.Target)) }
                'Loader' { Set-Content -LiteralPath $entry.Stage -Value $item.Content -Encoding utf8 }
            }
            $entry.Fingerprint = Get-Fingerprint $entry.Stage
            $entry.State = 'Staged'
            Save-Manifest
        }
        # All replacements, including symlinks, must exist before any original is moved.
        foreach ($entry in $script:manifest.Entries) {
            if ($entry.HadOriginal) {
                Move-Item -LiteralPath $entry.Path -Destination $entry.Backup
            }
            Move-Item -LiteralPath $entry.Stage -Destination $entry.Path
            $entry.State = 'Installed'
            Save-Manifest
        }
        $script:manifest.State = 'Applied'
        Save-Manifest
    }
    catch {
        $failure = $_
        try { Restore-Migration }
        catch { throw "Migration failed: $failure. Automatic rollback failed: $_. Keep and restore from $script:manifestPath" }
        throw "Migration failed; changes rolled back: $failure. Manifest: $script:manifestPath"
    }
    Write-Host "Migration applied. Rollback: pwsh -NoProfile -File `"$PSCommandPath`" -Rollback `"$script:manifestPath`""
}
finally { $lock.Dispose() }
