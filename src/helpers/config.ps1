
function Get-EnvConfig {
    param ($rootPath)

    $envFile = "$rootPath\.env"

    if (Is-File-Not-Exists -path $envFile) {
        Copy-Item -Path "$rootPath\.env.example" -Destination $envFile
    } else {
        Write-Verbose "Using .env from: $envFile"
    }

    $config = @{}

    # Read the file and parse key=value pairs
    Get-Content -Path $envFile | ForEach-Object {
        # Skip empty lines and comments
        if ($_ -match '^\s*$' -or $_ -match '^\s*#') {
            return
        }

        # Parse key=value format
        if ($_ -match '^([^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()

            # Remove quotes if present (ensures matching quote types)
            if ($value -match "^([""'])(.*)\1$") {
                $value = $matches[2]
            }

            $config[$key] = $value
        }
    }

    return $config
}

function Set-Aliases-List {
    try {
        $jsonContent = $PVMConfig.defaults.aliases | ConvertTo-Json -Depth 10
        Set-Content -Path $PVMConfig.paths.aliasesList -Value $jsonContent -Encoding UTF8

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create aliases list"; exception = $_ }
        return -1
    }
}

function Get-Aliases {
    try {
        if (Is-File-Exists -path $PVMConfig.paths.aliasesList) {
            $data = (Get-Content -Path $PVMConfig.paths.aliasesList -Raw | ConvertFrom-Json)
            if ($null -ne $data) {
                $ordered = [ordered]@{}
                $data.PSObject.Properties | ForEach-Object { $ordered[$_.Name] = $_.Value }
                if ($ordered.Count -gt 0) { return $ordered }
            }
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get aliases list"; exception = $_ }
    }

    return $PVMConfig.defaults.aliases
}

function Get-FlagMap {
    return $PVMConfig.defaults.flags
}

function Get-Scripts {
    return $PVMConfig.defaults.scripts
}

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
            PHP_CURRENT_VERSION_PATH    = $env['PHP_CURRENT_VERSION_PATH']
            PVM_ENV_VAR_NAME            = $env['PVM_ENV_VAR_NAME']
            CACHE_MAX_HOURS             = [int] $env['CACHE_MAX_HOURS']
            DEFAULT_LOG_PAGE_SIZE       = [int] $env['DEFAULT_LOG_PAGE_SIZE']
            DEFAULT_PARTIAL_LIST_SIZE   = [int] $env['DEFAULT_PARTIAL_LIST_SIZE']
            MIN_PAD_RIGHT_LENGTH        = [int] $env['MIN_PAD_RIGHT_LENGTH']
            MIN_LINE_LENGTH             = [int] $env['MIN_LINE_LENGTH']
            ENABLE_UPDATE_CHECK         = [bool] $env['ENABLE_UPDATE_CHECK']
            UPDATE_CHECK_INTERVAL_HOURS = [int] $env['UPDATE_CHECK_INTERVAL_HOURS']
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
                '?' = 'help'; 'h' = 'help';
                'ver' = 'version'; 'init' = 'setup'
                'cur' = 'current'; 'active' = 'current';
                'ls' = 'list'; 'i' = 'install'; 'u' = 'uninstall'; 'switch' = 'use'
                'on' = 'enable'; 'off' = 'disable'
                'a' = 'add'; '+' = 'add'; 'rm' = 'remove'; '-' = 'remove'
                'del' = 'delete'; 'cls' = 'clear'
                'logs' = 'log'; 'upgrade' = 'update'
                'fix' = 'repair';
            }
            flags          = [ordered]@{
                '--version' = 'version'
                '-v'        = 'version'
                '--help'    = 'help'
                '-h'        = 'help'
            }
            scripts        = [ordered]@{
                'test:quiet'        = 'test --verbosity=None'
                'test:cov'          = 'test --coverage=75'
                'test:cov80'        = 'test --coverage=80'
                'test:cov90'        = 'test --coverage=90'
                'test:full'         = 'test --coverage=85 --verbosity=Detailed --sort=coverage --group=folder'
            }
        }
    }
}
