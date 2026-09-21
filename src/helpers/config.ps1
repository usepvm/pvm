
function Set-AliasesList {
    try {
        $jsonContent = $Global:PVMConfig.defaults.aliases | ConvertTo-Json -Depth 10
        Set-ContentWrapper -path $Global:PVMConfig.paths.files.aliasesList -value $jsonContent

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create aliases list"; exception = $_ }
        return -1
    }
}

function Get-Aliases {
    try {
        if (Test-FileExists -path $Global:PVMConfig.paths.files.aliasesList) {
            $data = (Get-ContentWrapper -path $Global:PVMConfig.paths.files.aliasesList -raw | ConvertFrom-Json)
            if ($null -ne $data) {
                $ordered = [ordered]@{}
                $data.PSObject.Properties | ForEach-Object -Process { $ordered[$_.Name] = $_.Value }
                if ($ordered.Count -gt 0) { return $ordered }
            }
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get aliases list"; exception = $_ }
    }

    return $Global:PVMConfig.defaults.aliases
}

function Get-FlagMap {
    return $Global:PVMConfig.defaults.flags
}

function Set-ScriptsList {
    try {
        $jsonContent = $Global:PVMConfig.defaults.scripts | ConvertTo-Json -Depth 10
        Set-ContentWrapper -path $Global:PVMConfig.paths.files.scriptsList -value $jsonContent

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create scripts list"; exception = $_ }
        return -1
    }
}

function Get-Scripts {
    try {
        if (Test-FileExists -path $Global:PVMConfig.paths.files.scriptsList) {
            $data = (Get-ContentWrapper -path $Global:PVMConfig.paths.files.scriptsList -raw | ConvertFrom-Json)
            if ($null -ne $data) {
                $ordered = [ordered]@{}
                $data.PSObject.Properties | ForEach-Object -Process { $ordered[$_.Name] = $_.Value }
                if ($ordered.Count -gt 0) { return $ordered }
            }
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get scripts list"; exception = $_ }
    }

    return $Global:PVMConfig.defaults.scripts
}

function Get-EnvBool {
    param ($value, $default = $false)

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $default
    }

    $parsed = $false
    if ([bool]::TryParse($value, [ref]$parsed)) {
        return $parsed
    }

    return $default
}

function Get-EnvInt {
    param ($value, $default = 0)

    $parsed = 0
    if ([int]::TryParse($value, [ref]$parsed)) {
        return $parsed
    }

    return $default
}

function Get-EnvPath {
    param ($value, $default)

    if ($null -ne $value) { $value = $value.Trim() }

    $isValidPathFormat = -not [string]::IsNullOrWhiteSpace($value) `
        -and $value -match '^[A-Za-z]+:' `
        -and $value.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -eq -1

    if (-not $isValidPathFormat) {
        return $default
    }

    return $value
}

function Get-EnvConfig {
    param ($rootPath)

    $envFile = "$rootPath\.env"

    if (Test-FileNotExists -path $envFile) {
        Copy-ItemWrapper -path "$rootPath\.env.example" -destination $envFile
    } else {
        Write-Verbose "Using .env from: $envFile"
    }

    $config = @{}

    # Read the file and parse key=value pairs
    Get-ContentWrapper -path $envFile | ForEach-Object -Process {
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

function Get-EnvDefaults {
    return @{
        PHP_CURRENT_VERSION_PATH    = 'C:\pvm\php'
        PVM_ENV_VAR_NAME            = 'PVM'
        CACHE_MAX_HOURS             = 168
        DEFAULT_LOG_PAGE_SIZE       = 5
        DEFAULT_PARTIAL_LIST_SIZE   = 10
        MIN_PAD_RIGHT_LENGTH        = 10
        MIN_LINE_LENGTH             = 50
        MIN_CACHE_FREE_SPACE_MB = 10
        ENABLE_UPDATE_CHECK         = $true
        UPDATE_CHECK_INTERVAL_HOURS = 24
        SOUNDS_DISABLED             = $false
    }
}

function Get-Config {
    param ($rootPath)

    $envConfig = Get-EnvConfig -rootPath $rootPath
    $envDefaults = Get-EnvDefaults

    $storage = "$rootPath\storage"
    $data = "$storage\data"
    $profiles = "$data\profiles"
    $templates = "$data\templates"
    $logs = "$storage\logs"
    $state = "$data\state"

    return @{
        version  = '2.7' # PVM version

        rootPath = $rootPath

        paths    = [ordered]@{
            directories = @{
                root               = $rootPath
                storage            = $storage
                testDrive          = Get-EnvPath -value $envConfig['TEST_DRIVE'] -default "$storage\tests"
                php                = "$storage\php"
                data               = $data
                templates          = $templates
                cache              = "$data\cache"
                profiles           = $profiles
                log                = $logs
                state              = $state
                assets             = "$rootPath\assets"
            }
            files       = @{
                profileExample     = "$profiles\profile-example.json"
                profileTemplate    = "$templates\profile-template.json"
                zendExtensionsList = "$templates\zend_extensions.json"
                aliasesList        = "$templates\aliases.json"
                scriptsList        = "$templates\scripts.json"
                logError           = "$logs\error.log"
                pathVarBackup      = "$state\path.bak.log"
                lastUpdateCheck    = "$state\last_update_check.txt"
            }
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
            PHP_CURRENT_VERSION_PATH    = Get-EnvPath -value $envConfig['PHP_CURRENT_VERSION_PATH'] -default $envDefaults.PHP_CURRENT_VERSION_PATH
            PVM_ENV_VAR_NAME            = $envConfig['PVM_ENV_VAR_NAME']
            CACHE_MAX_HOURS             = Get-EnvInt -value $envConfig['CACHE_MAX_HOURS'] -default $envDefaults.CACHE_MAX_HOURS
            DEFAULT_LOG_PAGE_SIZE       = Get-EnvInt -value $envConfig['DEFAULT_LOG_PAGE_SIZE'] -default $envDefaults.DEFAULT_LOG_PAGE_SIZE
            DEFAULT_PARTIAL_LIST_SIZE   = Get-EnvInt -value $envConfig['DEFAULT_PARTIAL_LIST_SIZE'] -default $envDefaults.DEFAULT_PARTIAL_LIST_SIZE
            MIN_PAD_RIGHT_LENGTH        = Get-EnvInt -value $envConfig['MIN_PAD_RIGHT_LENGTH'] -default $envDefaults.MIN_PAD_RIGHT_LENGTH
            MIN_LINE_LENGTH             = Get-EnvInt -value $envConfig['MIN_LINE_LENGTH'] -default $envDefaults.MIN_LINE_LENGTH
            MIN_CACHE_FREE_SPACE_MB = Get-EnvInt -value $envConfig['MIN_CACHE_FREE_SPACE_MB'] -default $envDefaults.MIN_CACHE_FREE_SPACE_MB
            ENABLE_UPDATE_CHECK         = Get-EnvBool -value $envConfig['ENABLE_UPDATE_CHECK'] -default $envDefaults.ENABLE_UPDATE_CHECK
            UPDATE_CHECK_INTERVAL_HOURS = Get-EnvInt -value $envConfig['UPDATE_CHECK_INTERVAL_HOURS'] -default $envDefaults.UPDATE_CHECK_INTERVAL_HOURS
            SOUNDS_DISABLED             = Get-EnvBool -value $envConfig['SOUNDS_DISABLED'] -default $envDefaults.SOUNDS_DISABLED
        }

        constants = [ordered]@{
            LOG_SEPARATOR = '=' * 100
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
                'test:quiet'        = @('--verbosity=None --coverage=85 --sort=coverage --group=folder')
                'test:cov80'        = @('--verbosity=None --coverage=80 --sort=coverage --group=folder')
                'test:cov90'        = @('--verbosity=None --coverage=90 --sort=coverage --group=folder')
                'test:duration'     = @('--verbosity=None --sort=-duration --group=folder')
                'test:verbose'      = @('--verbosity=Detailed --coverage=85 --sort=coverage --group=folder')
                'test:shell'        = @(
                    '--verbosity=None --coverage=85 --sort=coverage --group=folder --shell=powershell'
                    '--verbosity=None --coverage=85 --sort=coverage --group=folder --shell=pwsh'
                )
                'test:pester'       = @(
                    '--verbosity=None --coverage=85 --sort=coverage --group=folder --pester=5.7.1'
                    '--verbosity=None --coverage=85 --sort=coverage --group=folder --pester=6.0.0'
                )
                'test:matrix'       = @(
                    '--verbosity=None --coverage=85 --sort=coverage --group=folder --shell=powershell --pester=5.7.1'
                    '--verbosity=None --coverage=85 --sort=coverage --group=folder --shell=pwsh --pester=5.7.1'
                    '--verbosity=None --coverage=85 --sort=coverage --group=folder --shell=pwsh --pester=6.0.0'
                )
            }
        }

        test    = @{
            verbosity = @{
                default = 'Normal'
                options = @('None', 'Normal', 'Detailed', 'Diagnostic')
            }
            coverage = @{
                default = 75
                enabled = $false
            }
        }

        subprocess = @{ enabled = $false; structuredOutput = @() }
    }
}

function Copy-ObjectDeep {
    param($object)

    if ($null -eq $object) {
        return $null
    }

    if ($object -is [System.Collections.Specialized.OrderedDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $object.Keys) {
            $copy[$key] = Copy-ObjectDeep -object $object[$key]
        }
        return $copy
    }

    if ($object -is [hashtable]) {
        $copy = @{}
        foreach ($key in $object.Keys) {
            $copy[$key] = Copy-ObjectDeep -object $object[$key]
        }
        return $copy
    }

    if ($object -is [array]) {
        return @($object | ForEach-Object -Process { Copy-ObjectDeep -object $_ })
    }

    if ($object -is [scriptblock]) {
        # Recreate a new scriptblock
        return [scriptblock]::Create($object.ToString())
    }

    if ($object -is [System.Management.Automation.PSCustomObject]) {
        $copy = [PSCustomObject]@{}
        foreach ($prop in $object.PSObject.Properties) {
            $copy | Add-Member -MemberType NoteProperty -Name $prop.Name -Value (Copy-ObjectDeep -object $prop.Value)
        }
        return $copy
    }

    return $object
}
