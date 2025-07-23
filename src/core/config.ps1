

$ProgressPreference = 'SilentlyContinue'

. $PSScriptRoot\..\helpers\helpers.ps1


$Global:PVMRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$Global:PVMEntryPoint = "$PVMRoot\src\pvm.ps1"
$Global:ENV_FILE = "$PVMRoot\.env"
$Global:USER_ENV = Get-Env

# Make-Directory -path "$PVMRoot\storage\logs"
# Make-Directory -path "$PVMRoot\storage\data"
# Make-File -filePath "$PVMRoot\storage\logs\error.log" 


$Global:STORAGE_PATH = "$PVMRoot\storage"
$Global:DATA_PATH = "$STORAGE_PATH\data"
$Global:LOG_PATH = "$STORAGE_PATH\logs"
$Global:LOG_ERROR_PATH = "$LOG_PATH\error.log"
$Global:PATH_VAR_BACKUP_PATH = "$LOG_PATH\path.bak.log"
$Global:PATH_VAR_BACKUP_NAME = "Path.bak"
