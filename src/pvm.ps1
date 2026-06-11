
# PHP Version Manager (PVM) - A PowerShell script to manage multiple PHP versions on Windows.

param ($operation)


$ProgressPreference = 'SilentlyContinue'


# Load functions scripts
Get-ChildItem "$PSScriptRoot\helpers\*.ps1" -Recurse -File | ForEach-Object { . $_.FullName }

# Load configuration
Get-ChildItem "$PSScriptRoot\core\*.ps1" -Recurse -File | ForEach-Object { . $_.FullName }

# Load actions scripts
Get-ChildItem "$PSScriptRoot\actions\*.ps1" -Recurse -File | ForEach-Object { . $_.FullName }

$exitCode = Start-PVM -operation $operation -arguments $args
exit $exitCode
