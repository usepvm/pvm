

# PVM version
$Global:PVM_VERSION = "2.0"

# Root path of the PVM script
$Global:PVMRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$Global:PVMEntryPoint = "$PVMRoot\src\pvm.ps1"

# Storage paths
$Global:STORAGE_PATH = "$PVMRoot\storage"
$Global:DATA_PATH = "$STORAGE_PATH\data"

# Log paths
$Global:LOG_ERROR_PATH = "$STORAGE_PATH\logs\error.log"
$Global:PATH_VAR_BACKUP_PATH = "$STORAGE_PATH\logs\path.bak.log"

# Environment variable names
$Global:PATH_VAR_BACKUP_NAME = "Path.bak"
$Global:PHP_CURRENT_ENV_NAME = "php"
$Global:PHP_CURRENT_VERSION_PATH = "C:\pvm\php"
$Global:CacheMaxHours = 24 # Cached available versions expiration in hours
