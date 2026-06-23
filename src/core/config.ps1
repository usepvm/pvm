
function Get-Config {
    param([string] $rootPath)

    $env = Get-EnvConfig -rootPath $rootPath

    $storage = "$rootPath\storage"
    $data = "$storage\data"
    $profiles = "$data\profiles"
    $templates = "$data\templates"
    $logs = "$storage\logs"

    return @{
        version  = '2.6' # PVM version

        paths    = [ordered]@{
            storage            = $storage
            php                = "$storage\php"
            data               = $data
            templates          = $templates
            cache              = "$data\cache"
            profiles           = $profiles
            exampleProfile     = "$profiles\example-profile.json"
            profileTemplate    = "$templates\profile-template.json"
            zendExtensionsList = "$templates\zend_extensions.json"
            aliasesList        = "$templates\aliases.json"
            log                = $logs
            logError           = "$logs\error.log"
            pathVarBackup      = "$logs\path.bak.log"
        }

        links    = [ordered]@{
            xdebugBase         = 'http://xdebug.org'
            xdebugDownload     = 'http://xdebug.org/download'
            xdebugHistorical   = 'http://xdebug.org/download/historical'
            phpWinBase         = 'https://windows.php.net'
            phpWinArchives     = 'https://windows.php.net/downloads/releases/archives'
            phpWinReleases     = 'https://windows.php.net/downloads/releases'
            peclBase           = 'https://pecl.php.net'
            peclPackageRoot    = 'https://pecl.php.net/package'
            peclPackages       = 'https://pecl.php.net/packages.php'
            peclWinExtDownload = 'https://downloads.php.net/~windows/pecl/releases'
        }

        env      = [ordered]@{
            PHP_CURRENT_VERSION_PATH  = $env['PHP_CURRENT_VERSION_PATH']
            PVM_ENV_VAR_NAME          = $env['PVM_ENV_VAR_NAME']
            CACHE_MAX_HOURS           = [int] $env['CACHE_MAX_HOURS']
            DEFAULT_LOG_PAGE_SIZE     = [int] $env['DEFAULT_LOG_PAGE_SIZE']
            DEFAULT_PARTIAL_LIST_SIZE = [int] $env['DEFAULT_PARTIAL_LIST_SIZE']
            MIN_PAD_RIGHT_LENGTH      = [int] $env['MIN_PAD_RIGHT_LENGTH']
            MIN_LINE_LENGTH           = [int] $env['MIN_LINE_LENGTH']
        }

        defaults = @{
            zendExtensions = @('opcache', 'xdebug')
            extensions     = @(
                'curl', 'fileinfo', 'gd', 'gettext', 'intl', 'mbstring', 'exif',
                'openssl', 'mysqli', 'pdo_mysql', 'pdo_pgsql', 'pdo_sqlite',
                'pgsql', 'sodium', 'sqlite3', 'zip', 'opcache', 'xdebug'
            )
            settings       = @(
                'memory_limit', 'max_execution_time', 'max_input_time',
                'post_max_size', 'upload_max_filesize', 'max_file_uploads',
                'display_errors', 'error_reporting', 'log_errors',
                'opcache.enable', 'opcache.enable_cli', 'opcache.memory_consumption',
                'opcache.max_accelerated_files'
            )
            aliases        = [ordered]@{
                '?' = 'help'; 'h' = 'help'; 'init' = 'setup'
                'cur' = 'current'; 'active' = 'current'
                'ls' = 'list'; 'i' = 'install'; 'u' = 'uninstall'; 'switch' = 'use'
                'on' = 'enable'; 'off' = 'disable'
                'a' = 'add'; '+' = 'add'; 'rm' = 'remove'; '-' = 'remove'
                'del' = 'delete'; 'cls' = 'clear'
            }
            flags          = [ordered]@{
                '--version' = 'version'
                '-v'        = 'version'
                '--help'    = 'help'
                '-h'        = 'help'
            }
        }
    }
}

# Root path of the PVM script
$Global:PVMRoot = (Resolve-Path -Path "$PSScriptRoot\..\..").Path

$Global:PVMConfig = Get-Config -rootPath $PVMRoot
