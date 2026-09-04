# Links the Windows-side configs out of this repo.
#
# Windows is the one platform Nix cannot manage, so it consumes the repo the
# same way it always has: a clone plus symlinks. Run from an elevated shell, or
# with Developer Mode enabled (Settings -> Privacy & Security -> For developers).
#
#   pwsh -File windows\bootstrap.ps1

#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot

function New-ConfigLink {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $Target
    )

    if (-not (Test-Path $Target)) {
        Write-Warning "skipping $Path — target missing: $Target"
        return
    }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    if (Test-Path $Path) {
        $existing = Get-Item $Path -Force
        if ($existing.LinkType -ne 'SymbolicLink') {
            # Never clobber a real file: it may be the only copy of hand-written
            # config that was never committed.
            Write-Warning "skipping $Path — exists and is not a symlink; move it aside first"
            return
        }
        Remove-Item $Path -Force
    }

    New-Item -ItemType SymbolicLink -Path $Path -Target $Target | Out-Null
    Write-Host "linked $Path -> $Target"
}

# Neovim: plain Lua, shared verbatim with WSL/macOS/Linux.
New-ConfigLink -Path "$env:LOCALAPPDATA\nvim" -Target "$repo\nvim"

# Starship: generated from Nix, committed so Windows can consume it.
New-ConfigLink -Path "$env:USERPROFILE\.config\starship.toml" -Target "$repo\generated\starship.toml"

# PowerShell profile.
New-ConfigLink -Path $PROFILE -Target "$repo\windows\powershell\Microsoft.PowerShell_profile.ps1"

# Windows Terminal rewrites settings.json in place whenever you change anything
# in its UI, which would write straight through a symlink into the repo. Copy it
# instead, and re-run to pick up repo changes.
$wtDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
if (Test-Path $wtDir) {
    Write-Host "Windows Terminal settings are NOT linked (it rewrites the file in place)."
    Write-Host "To apply this repo's copy:  Copy-Item '$repo\windows\windows-terminal\settings.json' '$wtDir\settings.json'"
}
