
$ProgressPreference = 'SilentlyContinue'

# Load functions scripts
$scriptGroups = @(
    "$PSScriptRoot\helpers"
    "$PSScriptRoot\core"
    "$PSScriptRoot\actions"
)

foreach ($scriptGroup in $scriptGroups) {
    Get-ChildItem -Path $scriptGroup -Filter '*.ps1' -Recurse -File |
        Sort-Object -Property FullName |
        ForEach-Object -Process { . $_.FullName }
}
