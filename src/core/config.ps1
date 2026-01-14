

# PVM version
$Global:PVM_VERSION = "2.5"

# Root path of the PVM script
$Global:PVMRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$Global:PVMEntryPoint = "$PVMRoot\src\pvm.ps1"

# Storage paths
$Global:STORAGE_PATH = "$PVMRoot\storage"
$Global:DATA_PATH = "$STORAGE_PATH\data"

# Log paths
$Global:LOG_ERROR_PATH = "$STORAGE_PATH\logs\error.log"
$Global:PATH_VAR_BACKUP_PATH = "$STORAGE_PATH\logs\path.bak.log"
$Global:CACHE_PATH = "$DATA_PATH\cache"
$Global:PROFILES_PATH = "$DATA_PATH\profiles"

# Environment variable names
$Global:PATH_VAR_BACKUP_NAME = "Path.bak"
$Global:PHP_CURRENT_VERSION_PATH = "C:\pvm\php"
$Global:CACHE_MAX_HOURS = 168 # Cached available versions expiration in hours (default 1 week)
$Global:DEFAULT_LOG_PAGE_SIZE = 5 # Default page size for log display
$Global:LATEST_VERSION_COUNT = 10

# Links
$Global:XDEBUG_BASE_URL = "http://xdebug.org"
$Global:XDEBUG_DOWNLOAD_URL = "$XDEBUG_BASE_URL/download"
$Global:XDEBUG_HISTORICAL_URL = "$XDEBUG_DOWNLOAD_URL/historical"
$Global:PHP_WIN_BASE_URL = "https://windows.php.net"
$Global:PHP_WIN_ARCHIVES_URL = "$PHP_WIN_BASE_URL/downloads/releases/archives"
$Global:PHP_WIN_RELEASES_URL = "$PHP_WIN_BASE_URL/downloads/releases"
$Global:PECL_BASE_URL = "https://pecl.php.net"
$Global:PECL_PACKAGE_ROOT_URL = "$PECL_BASE_URL/package"
$Global:PECL_PACKAGES_URL = "$PECL_BASE_URL/packages.php"
$Global:PECL_WIN_EXT_DOWNLOAD_URL = "https://downloads.php.net/~windows/pecl/releases"