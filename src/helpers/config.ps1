
function Set-AliasesList {
    try {
        $jsonContent = $PVMConfig.defaults.aliases | ConvertTo-Json -Depth 10
        Set-Content-Wrapper -path $PVMConfig.paths.aliasesList -value $jsonContent

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create aliases list"; exception = $_ }
        return -1
    }
}

function Get-Aliases {
    try {
        if (Test-FileExists -path $PVMConfig.paths.aliasesList) {
            $data = (Get-Content -Path $PVMConfig.paths.aliasesList -Raw | ConvertFrom-Json)
            if ($null -ne $data) {
                $ordered = [ordered]@{}
                $data.PSObject.Properties | ForEach-Object { $ordered[$_.Name] = $_.Value }
                if ($ordered.Count -gt 0) { return $ordered }
            }
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get aliases list"; exception = $_ }
    }

    return $PVMConfig.defaults.aliases
}

function Get-FlagMap {
    return $PVMConfig.defaults.flags
}

function Set-ScriptsList {
    try {
        $jsonContent = $PVMConfig.defaults.scripts | ConvertTo-Json -Depth 10
        Set-Content-Wrapper -path $PVMConfig.paths.scriptsList -value $jsonContent

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create scripts list"; exception = $_ }
        return -1
    }
}

function Get-Scripts {
    try {
        if (Test-FileExists -path $PVMConfig.paths.scriptsList) {
            $data = (Get-Content -Path $PVMConfig.paths.scriptsList -Raw | ConvertFrom-Json)
            if ($null -ne $data) {
                $ordered = [ordered]@{}
                $data.PSObject.Properties | ForEach-Object { $ordered[$_.Name] = $_.Value }
                if ($ordered.Count -gt 0) { return $ordered }
            }
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get scripts list"; exception = $_ }
    }

    return $PVMConfig.defaults.scripts
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

function Get-EnvConfig {
    param ($rootPath)

    $envFile = "$rootPath\.env"

    if (Test-FileNotExists -path $envFile) {
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

function Get-Config {
    param ($rootPath)

    $envConfig = Get-EnvConfig -rootPath $rootPath

    $storage = "$rootPath\storage"
    $data = "$storage\data"
    $profiles = "$data\profiles"
    $templates = "$data\templates"
    $logs = "$storage\logs"
    $fakeStorage = $envConfig['TEST_DRIVE']

    $isValidPathFormat = -not [string]::IsNullOrWhiteSpace($fakeStorage) `
        -and $fakeStorage -match '^[A-Za-z]+:' `
        -and $fakeStorage.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -eq -1

    if (-not $isValidPathFormat) {
        $fakeStorage = "$storage\tests"
    }

    return @{
        version  = '2.6' # PVM version

        paths    = [ordered]@{
            pvmRoot            = $rootPath
            storage            = $storage
            fakeStorage        = $fakeStorage
            php                = "$storage\php"
            data               = $data
            templates          = $templates
            cache              = "$data\cache"
            profiles           = $profiles
            profileExample     = "$profiles\profile-example.json"
            profileTemplate    = "$templates\profile-template.json"
            zendExtensionsList = "$templates\zend_extensions.json"
            aliasesList        = "$templates\aliases.json"
            scriptsList        = "$templates\scripts.json"
            log                = $logs
            logError           = "$logs\error.log"
            pathVarBackup      = "$logs\path.bak.log"
            assets             = "$rootPath\assets"
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
            PHP_CURRENT_VERSION_PATH    = $envConfig['PHP_CURRENT_VERSION_PATH']
            PVM_ENV_VAR_NAME            = $envConfig['PVM_ENV_VAR_NAME']
            CACHE_MAX_HOURS             = Get-EnvInt -value $envConfig['CACHE_MAX_HOURS'] -default 168
            DEFAULT_LOG_PAGE_SIZE       = Get-EnvInt -value $envConfig['DEFAULT_LOG_PAGE_SIZE'] -default 5
            DEFAULT_PARTIAL_LIST_SIZE   = Get-EnvInt -value $envConfig['DEFAULT_PARTIAL_LIST_SIZE'] -default 10
            MIN_PAD_RIGHT_LENGTH        = Get-EnvInt -value $envConfig['MIN_PAD_RIGHT_LENGTH'] -default 10
            MIN_LINE_LENGTH             = Get-EnvInt -value $envConfig['MIN_LINE_LENGTH'] -default 50
            ENABLE_UPDATE_CHECK         = Get-EnvBool -value $envConfig['ENABLE_UPDATE_CHECK'] -default $true
            UPDATE_CHECK_INTERVAL_HOURS = Get-EnvInt -value $envConfig['UPDATE_CHECK_INTERVAL_HOURS'] -default 24
            SOUNDS_DISABLED             = Get-EnvBool -value $envConfig['SOUNDS_DISABLED'] -default $false
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
                'test:quiet'        = @('test --verbosity=None --coverage=85 --sort=coverage --group=folder')
                'test:cov80'        = @('test --verbosity=None --coverage=80 --sort=coverage --group=folder')
                'test:cov90'        = @('test --verbosity=None --coverage=90 --sort=coverage --group=folder')
                'test:duration'     = @('test --verbosity=None --sort=-duration --group=folder')
                'test:verbose'      = @('test --verbosity=Detailed --coverage=85 --sort=coverage --group=folder')
                'test:shell'        = @(
                    'test --verbosity=None --coverage=85 --sort=coverage --group=folder --shell=powershell'
                    'test --verbosity=None --coverage=85 --sort=coverage --group=folder --shell=pwsh'
                )
                'test:pester'       = @(
                    'test --verbosity=None --coverage=85 --sort=coverage --group=folder --pester=5.7.1'
                    'test --verbosity=None --coverage=85 --sort=coverage --group=folder --pester=6.0.0'
                )
                'test:matrix'       = @(
                    'test --verbosity=None --coverage=85 --sort=coverage --group=folder --shell=powershell --pester=5.7.1'
                    'test --verbosity=None --coverage=85 --sort=coverage --group=folder --shell=pwsh --pester=5.7.1'
                    'test --verbosity=None --coverage=85 --sort=coverage --group=folder --shell=pwsh --pester=6.0.0'
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
            setFakePaths = {
                param ($root)

                $fakeStorage = "$root\storage"
                $fakeData = "$fakeStorage\data"
                $fakeProfiles = "$fakeData\profiles"
                $fakeTemplates = "$fakeData\templates"
                $fakeLogs = "$fakeStorage\logs"

                $PVMConfig.paths.pvmRoot = $root
                $PVMConfig.paths.storage = $fakeStorage
                $PVMConfig.paths.fakeStorage = $fakeStorage
                $PVMConfig.paths.php = "$fakeStorage\php"
                $PVMConfig.paths.data = $fakeData
                $PVMConfig.paths.templates = $fakeTemplates
                $PVMConfig.paths.cache = "$fakeData\cache"
                $PVMConfig.paths.profiles = $fakeProfiles
                $PVMConfig.paths.profileExample = "$fakeProfiles\profile-example.json"
                $PVMConfig.paths.profileTemplate = "$fakeTemplates\profile-template.json"
                $PVMConfig.paths.zendExtensionsList = "$fakeTemplates\zend_extensions.json"
                $PVMConfig.paths.aliasesList = "$fakeTemplates\aliases.json"
                $PVMConfig.paths.scriptsList = "$fakeTemplates\scripts.json"
                $PVMConfig.paths.log = $fakeLogs
                $PVMConfig.paths.logError = "$fakeLogs\error.log"
                $PVMConfig.paths.pathVarBackup = "$fakeLogs\path.bak.log"
                $PVMConfig.paths.assets = "$root\assets"

                $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$root\pvm\php"
            }
        }
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
        return @($object | ForEach-Object { Copy-ObjectDeep -object $_ })
    }

    if ($object -is [scriptblock]) {
        # Recreate a new scriptblock
        return [scriptblock]::Create($object.ToString())
    }

    return $object
}
