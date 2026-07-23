
# PHP Version Manager (PVM) - A PowerShell script to manage multiple PHP versions on Windows.

param ($command)

$ProgressPreference = 'SilentlyContinue'

# Check if running in subprocess mode
$params = $args
$script:PVMSubprocessMode = $params -contains '--pvm-subprocess'
if ($script:PVMSubprocessMode) {
    $params = $params | Where-Object { $_ -ne '--pvm-subprocess' }
    $script:StructuredOutput = @()
}

# Load functions scripts
Get-ChildItem -Path "$PSScriptRoot\helpers\*.ps1" -Recurse -File | ForEach-Object { . $_.FullName }

# Load configuration
Get-ChildItem -Path "$PSScriptRoot\core\*.ps1" -Recurse -File | ForEach-Object { . $_.FullName }

# Load actions scripts
Get-ChildItem -Path "$PSScriptRoot\actions\*.ps1" -Recurse -File | ForEach-Object { . $_.FullName }

$exitCode = Start-PVM -command $command -arguments $params

# If in subprocess mode, output structured data
if ($script:PVMSubprocessMode) {
    $script:StructuredOutput | ConvertTo-Json -Depth 10
}

exit $exitCode
