# Windows PowerShell profile.
#
# Install to $PROFILE (see windows/bootstrap.ps1).
#
# Deliberately generic: this repo is public, so keep work-specific paths, repo
# names, machine names and internal tooling OUT of this file. Put those in
# $PROFILE.local instead, which bootstrap.ps1 leaves untracked and this file
# sources at the end.

# PSReadLine — PS7-only prediction options, ConsoleHost only.
if ($host.Name -eq 'ConsoleHost') {
    Import-Module PSReadLine

    # CompletionPredictor is optional; don't fail the profile if it's absent.
    if (Get-Module -ListAvailable -Name CompletionPredictor) {
        Import-Module CompletionPredictor
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    }
    else {
        Set-PSReadLineOption -PredictionSource History
    }

    Set-PSReadLineOption -PredictionViewStyle ListView
    Set-PSReadLineOption -EditMode Windows
}

# Copilot / Claude CLI helpers, matching the `c` and `a` shell aliases on Unix.
function c { copilot --yolo @args }
function a { agency copilot --yolo @args }

# Starship prompt. Reads ~/.config/starship.toml, which bootstrap.ps1 links to
# generated/starship.toml — rendered from modules/starship-settings.nix so the
# prompt matches WSL, Linux and macOS.
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

# Machine-specific and work-specific configuration, untracked.
$localProfile = Join-Path (Split-Path -Parent $PROFILE) 'profile.local.ps1'
if (Test-Path $localProfile) {
    . $localProfile
}
