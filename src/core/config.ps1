


# Root path of the PVM script
$Global:PVMRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$Global:PVMEntryPoint = "$PVMRoot\src\pvm.ps1"

# Storage paths
$Global:STORAGE_PATH = "$PVMRoot\storage"
$Global:DATA_PATH = "$STORAGE_PATH\data"
$Global:LOG_PATH = "$STORAGE_PATH\logs"

# PHP & Xdebug paths
$Global:PHP_VERSIONS_PATH = "$STORAGE_PATH\php\versions"
$Global:PHP_XDEBUG_PATH = "$STORAGE_PATH\php\xdebug"

# Log paths
$Global:LOG_ERROR_PATH = "$LOG_PATH\error.log"
$Global:PATH_VAR_BACKUP_PATH = "$LOG_PATH\path.bak.log"

# Environment variable names
$Global:PATH_VAR_BACKUP_NAME = "Path.bak"
$Global:PHP_CURRENT_ENV_NAME = "php"
