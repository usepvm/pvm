
# PHP Version Manager (PVM) - A PowerShell script to manage multiple PHP versions on Windows.

param ($command)

# Load functions scripts
. "$PSScriptRoot\imports.ps1"

# Check if running in subprocess mode
$params = $args
$Global:PVMConfig.subprocess.enabled = $params -contains '--pvm-subprocess'
if ($Global:PVMConfig.subprocess.enabled) {
    $params = $params | Where-Object -FilterScript { $_ -ne '--pvm-subprocess' }
    $Global:PVMConfig.subprocess.structuredOutput = @()
}

$exitCode = Start-PVM -command $command -arguments $params

# If in subprocess mode, output structured data
if ($Global:PVMConfig.subprocess.enabled) {
    $Global:PVMConfig.subprocess.structuredOutput | ConvertTo-Json -Depth 10
}

exit $exitCode
