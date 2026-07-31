
# PHP Version Manager (PVM) - A PowerShell script to manage multiple PHP versions on Windows.

param ($command)

# Load functions scripts
. "$PSScriptRoot\import.ps1"

# Check if running in subprocess mode
$params = $args
$PVMSubprocess.mode = $params -contains '--pvm-subprocess'
if ($PVMSubprocess.mode) {
    $params = $params | Where-Object { $_ -ne '--pvm-subprocess' }
    $PVMSubprocess.structuredOutput = @()
}

$exitCode = Start-PVM -command $command -arguments $params

# If in subprocess mode, output structured data
if ($PVMSubprocess.mode) {
    $PVMSubprocess.structuredOutput | ConvertTo-Json -Depth 10
}

exit $exitCode
