
# Root path of the PVM script
$Global:PVMRoot = (Resolve-Path -Path "$PSScriptRoot\..\..").Path

$Global:PVMConfig = Get-Config -rootPath $PVMRoot
