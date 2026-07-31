
# PHP Version Manager (PVM) - A PowerShell script to manage multiple PHP versions on Windows.

param ($command)

# Load functions scripts
. "$PSScriptRoot\import.ps1"

# Check if running in subprocess mode
$params = $args
$script:PVMSubprocessMode = $params -contains '--pvm-subprocess'
if ($script:PVMSubprocessMode) {
    $params = $params | Where-Object { $_ -ne '--pvm-subprocess' }
    $script:StructuredOutput = @()
}

$exitCode = Start-PVM -command $command -arguments $params

# If in subprocess mode, output structured data
if ($script:PVMSubprocessMode) {
    $script:StructuredOutput | ConvertTo-Json -Depth 10
}

exit $exitCode
