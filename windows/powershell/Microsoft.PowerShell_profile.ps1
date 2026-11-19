# Public defaults; the writable bootstrap loader sources private overrides afterward.

# PSReadLine — PS7-only prediction options, interactive ConsoleHost only.
# With redirected stdin (e.g. `ssh host 'cmd'`), CompletionPredictor's runspace keeps pwsh from exiting.
if ($host.Name -eq 'ConsoleHost' -and -not [Console]::IsInputRedirected) {
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

# Windows can refuse to traverse agency's user-created CurrentVersion junction
# ("untrusted mount point"), so put the junction's real target on PATH instead.
$agencyLink = Get-Item "$env:APPDATA\agency\CurrentVersion" -ErrorAction SilentlyContinue
if ($agencyLink -and $agencyLink.Target) {
    $agencyDir = @($agencyLink.Target)[0]
    if (($env:Path -split ';') -notcontains $agencyDir) { $env:Path = "$agencyDir;$env:Path" }
}

function c { claude --dangerously-skip-permissions @args }
function a { agency copilot --yolo @args }

# Starship prompt. Reads ~/.config/starship.toml, which bootstrap.ps1 links to
# generated/starship.toml — rendered from modules/starship-settings.nix so the
# prompt matches WSL, Linux and macOS.
if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
