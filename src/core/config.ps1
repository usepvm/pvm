
# PVM version
$Global:PVM_VERSION = '2.5'

# Root path of the PVM script
$Global:PVMRoot = (Resolve-Path -Path "$PSScriptRoot\..\..").Path

# Storage paths
$Global:STORAGE_PATH = "$PVMRoot\storage"
$Global:DATA_PATH = "$STORAGE_PATH\data"
$Global:TEMPLATES_PATH = "$DATA_PATH\templates"
$Global:CACHE_PATH = "$DATA_PATH\cache"
$Global:PROFILES_PATH = "$DATA_PATH\profiles"
$Global:PROFILE_TEMPLATE_PATH = "$TEMPLATES_PATH\profile-template.json"
$Global:ZEND_EXTENSIONS_LIST_PATH = "$TEMPLATES_PATH\zend_extensions.json"

# Log paths
$Global:LOG_PATH = "$STORAGE_PATH\logs"
$Global:LOG_ERROR_PATH = "$LOG_PATH\error.log"
$Global:PATH_VAR_BACKUP_PATH = "$LOG_PATH\path.bak.log"

# Links
$Global:XDEBUG_BASE_URL = 'http://xdebug.org'
$Global:XDEBUG_DOWNLOAD_URL = "$XDEBUG_BASE_URL/download"
$Global:XDEBUG_HISTORICAL_URL = "$XDEBUG_DOWNLOAD_URL/historical"
$Global:PHP_WIN_BASE_URL = 'https://windows.php.net'
$Global:PHP_WIN_ARCHIVES_URL = "$PHP_WIN_BASE_URL/downloads/releases/archives"
$Global:PHP_WIN_RELEASES_URL = "$PHP_WIN_BASE_URL/downloads/releases"
$Global:PECL_BASE_URL = 'https://pecl.php.net'
$Global:PECL_PACKAGE_ROOT_URL = "$PECL_BASE_URL/package"
$Global:PECL_PACKAGES_URL = "$PECL_BASE_URL/packages.php"
$Global:PECL_WIN_EXT_DOWNLOAD_URL = 'https://downloads.php.net/~windows/pecl/releases'

$envConfig = Get-EnvConfig -rootPath $PVMRoot

$Global:PHP_CURRENT_VERSION_PATH = $envConfig['PHP_CURRENT_VERSION_PATH']
$Global:PVM_ENV_VAR_NAME = $envConfig['PVM_ENV_VAR_NAME']
$Global:CACHE_MAX_HOURS = [int] $envConfig['CACHE_MAX_HOURS']
$Global:DEFAULT_LOG_PAGE_SIZE = [int] $envConfig['DEFAULT_LOG_PAGE_SIZE']
$Global:DEFAULT_PARTIAL_LIST_SIZE = [int] $envConfig['DEFAULT_PARTIAL_LIST_SIZE']
$Global:MIN_PAD_RIGHT_LENGTH = [int] $envConfig['MIN_PAD_RIGHT_LENGTH']
$Global:MIN_LINE_LENGTH = [int] $envConfig['MIN_LINE_LENGTH']

$Global:DEFAULT_ZEND_EXTENSIONS = @('opcache', 'xdebug')
$Global:DEFAULT_EXTENSIONS = @(
    'curl', 'fileinfo', 'gd', 'gettext', 'intl', 'mbstring', 'exif',
    'openssl', 'mysqli', 'pdo_mysql', 'pdo_pgsql', 'pdo_sqlite',
    'pgsql', 'sodium', 'sqlite3', 'zip', 'opcache', 'xdebug'
)
$Global:DEFAULT_SETTINGS = @(
    'memory_limit', 'max_execution_time', 'max_input_time',
    'post_max_size', 'upload_max_filesize', 'max_file_uploads',
    'display_errors', 'error_reporting', 'log_errors',
    'opcache.enable', 'opcache.enable_cli', 'opcache.memory_consumption', 'opcache.max_accelerated_files'
)
