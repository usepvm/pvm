
function Is-PVM-Setup {
    try {
        $pvmEnvVarContent = Get-EnvVar-ByName -name 'PVM'

        if ($null -eq $pvmEnvVarContent) {
            return $false
        }

        $pvmEnvEntries = $pvmEnvVarContent -split ';' | Where-Object { $_ -ne '' }
        if ($pvmEnvEntries -notcontains $PVMRoot -or $pvmEnvEntries -notcontains $PVMConfig.env.PHP_CURRENT_VERSION_PATH) {
            return $false
        }

        $path = Get-EnvVar-ByName -name 'Path' -optimized $true
        if ($null -eq $path) {
            $path = ''
        }

        $parent = Split-Path -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH
        $pathEntries = $path -split ';' | Where-Object { $_ -ne '' }
        if (
            (
                ($path -notlike "*$pvmEnvVarContent*") -and
                ($pathEntries -notcontains "%$($PVMConfig.env.PVM_ENV_VAR_NAME)%")
            ) -or
            (Is-Directory-Not-Exists -path $parent)
        ) {
            return $false
        }

        return $true
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check if PVM is set up"; exception = $_ }
        return $false
    }
}

function Is-PVM-Not-Setup {
    return -not (Is-PVM-Setup)
}

function Run-PS-Command {
    param ($command)

    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-Command', $command
        ) `
        -Verb RunAs `
        -PassThru `
        -Wait `
        -WindowStyle Hidden

    return $process.ExitCode
}

function Is-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    return $isAdmin
}

function Is-Not-Admin {
    return -not (Is-Admin)
}

function Display-Msg-By-ExitCode {
    param ($result, $message = $null)

    try {
        if ($result.messages -and $result.messages.Count -gt 1) {
            foreach ($msg in $result.messages) {
                if (-not $msg.color) {
                    $msg.color = 'White'
                }
                Write-Host -Object $($msg.content) -ForegroundColor $msg.color
            }
        } else {
            if ($message) {
                $result.message = $message
            }
            if (-not $result.color) {
                $result.color = 'Gray'
            }

            Write-Host -Object "`n$($result.message)" -ForegroundColor $result.color
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to display message by exit code"; exception = $_ }
    }
}

function Log-Data {
    param ($data)

    try {
        $logPath = if ($data.logPath) { $data.logPath } else { $PVMConfig.paths.logError }
        $created = Make-Directory -path (Split-Path -Path $logPath)
        if ($created -ne 0) {
            Write-Host -Object "Failed to create directory $(Split-Path -Path $logPath)"
            return -1
        }
        $content = "`n--------------------------"
        $content += "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($data.header)"
        if ($data.exception) {
            $content += "`nMessage: $($data.exception.Exception.Message)"
            $content += "`nPosition: $($data.exception.InvocationInfo.PositionMessage)"
        }
        Add-Content -Path $logPath -Value $content
        return 0
    } catch {
        return -1
    }
}

function Format-Seconds {
    param ($totalSeconds)

    try {
        if ($null -ne $totalSeconds) {
            $totalSeconds = [Single] $totalSeconds
        }

        if ($null -eq $totalSeconds -or $totalSeconds -lt 0) {
            $totalSeconds = 0
        }

        if ($totalSeconds -lt 60) {
            $rounded = [math]::Round($totalSeconds, 1)
            return '{0}s' -f $rounded
        }

        $hours = [int][math]::Floor($totalSeconds / 3600)
        $minutes = [int][math]::Floor(($totalSeconds % 3600) / 60)
        $seconds = [int][math]::Floor($totalSeconds % 60)

        if ($hours -gt 0) {
            return '{0:D2}:{1:D2}:{2:D2}' -f $hours, $minutes, $seconds
        }

        return '{0:D2}:{1:D2}' -f $minutes, $seconds
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to format seconds"; exception = $_ }
        return -1
    }
}

function Resolve-BuildType {
    param ($arguments, $choseDefault = $false)

    $buildType = $arguments | Where-Object { @('ts', 'nts') -contains $_ } | Select-Object -First 1

    if ($null -eq $buildType -and $choseDefault) {
        $buildType = 'ts';
    }

    if ($null -ne $buildType) {
        $buildType = $buildType.ToLower()
    }

    return $buildType
}

function Resolve-Arch {
    param ($arguments, $choseDefault = $false)

    $arch = $arguments | Where-Object { @('x86', 'x64') -contains $_ } | Select-Object -First 1

    if ($null -eq $arch -and $choseDefault) {
        $arch = if (Is-OS-64Bit) { 'x64' } else { 'x86' }
    }

    if ($null -ne $arch) {
        $arch = $arch.ToLower()
    }

    return $arch
}

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

function Resolve-Alias {
    param ($alias)

    if ([string]::IsNullOrWhiteSpace($alias)) {
        return $null
    }

    $alias = $alias.Trim().ToLower()
    $aliases = Get-Aliases

    if ($aliases.Contains($alias)) {
        return $aliases[$alias]
    }

    return $alias
}

function Get-FlagMap {
    return $PVMConfig.defaults.flags
}

function Resolve-FlagCommand {
    param ($arguments)

    $flagMap = Get-FlagMap

    $flag = $arguments | Where-Object { $flagMap.Contains($_) } | Select-Object -First 1

    if ($flag) {
        return $flagMap[$flag]
    }

    return $null
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
                '?' = 'help'; 'h' = 'help';
                'ver' = 'version'; 'init' = 'setup'
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

function Get-Web-Response {
    param ($uri, $outFile = $null)

    $uri = $uri.Trim()

    $params = @{
        Uri = $uri
        UseBasicParsing = $true
    }

    if ($outFile) {
        $params.OutFile = $outFile
    }

    return Invoke-WebRequest @params
}

function Get-Console-Width {
    return $Host.UI.RawUI.WindowSize.Width
}
