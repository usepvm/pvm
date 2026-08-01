
# PHP Version Manager (PVM) - A PowerShell script to manage multiple PHP versions on Windows.

param ($command)

# Load functions scripts
. "$PSScriptRoot\imports.ps1"

# Check if running in subprocess mode
$params = $args
$Global:PVMSubprocess.mode = $params -contains '--pvm-subprocess'
if ($Global:PVMSubprocess.mode) {
    $params = $params | Where-Object { $_ -ne '--pvm-subprocess' }
    $Global:PVMSubprocess.structuredOutput = @()
}

$exitCode = Start-PVM -command $command -arguments $params

# If in subprocess mode, output structured data
if ($Global:PVMSubprocess.mode) {
    $Global:PVMSubprocess.structuredOutput | ConvertTo-Json -Depth 10
}

exit $exitCode
