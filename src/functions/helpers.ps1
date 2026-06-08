
function Get-Zend-Extensions-List {
    return @('xdebug', 'opcache')
}

function Can-Use-Cache {
    param ($cacheFileName)

    try {
        $path = "$CACHE_PATH\$cacheFileName.json"
        $useCache = $false

        if (Is-File-Exists -path $path) {
            $fileAgeHours = (New-TimeSpan -Start (Get-Item $path).LastWriteTime -End (Get-Date)).TotalHours
            $useCache = ($fileAgeHours -lt $CACHE_MAX_HOURS)
        }

        return $useCache
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }

        return $false
    }
}

function Get-Data-From-Cache {
    param ($cacheFileName)

    try {
        $jsonData = Get-Content "$CACHE_PATH\$cacheFileName.json" -Raw | ConvertFrom-Json
        return $jsonData
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }
        return @{}
    }
}

function Cache-Data {
    param ($cacheFileName, $data, $depth = 3)

    try {
        $jsonString = $data | ConvertTo-Json -Depth $depth
        $path = "$CACHE_PATH\$cacheFileName.json"
        $created = Make-Directory -path (Split-Path $path)
        if ($created -ne 0) {
            Write-Host "Failed to create directory $(Split-Path $path)"
            return -1
        }
        Set-Content -Path $path -Value $jsonString
        return 0
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to cache data"; exception = $_ }
        return -1
    }
}

function Get-OrUpdateCache {
    param ($cacheFileName, $compute, $depth = 3)

    $useCache = Can-Use-Cache -cacheFileName $cacheFileName

    if ($useCache) {
        $data = Get-Data-From-Cache -cacheFileName $cacheFileName
        if ($null -ne $data -and $data.Count -gt 0) {
            return $data
        }
    }

    $data = & $compute

    if ($null -ne $data) {
        $cached = Cache-Data -cacheFileName $cacheFileName -data $data -depth $depth
    }

    return $data
}

function Get-All-Subdirectories {
    param ($path)
    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $null
        }
        $path = $path.Trim()
        return Get-ChildItem -Path $path -Directory
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get all subdirectories of '$path'"; exception = $_ }
        return $null
    }
}

function Get-All-EnvVars {

    try {
        return [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get all environment variables"; exception = $_ }
        return $null
    }
}

function Get-EnvVar-ByName {
    param ($name, $optimized = $false)

    try {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return $null
        }
        $name = $name.Trim()
        $value = [System.Environment]::GetEnvironmentVariable($name, [System.EnvironmentVariableTarget]::Machine)

        if ($optimized -eq $true) {
            $value = Get-Optimized-Env -name $name -value $value
        }

        return $value
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get environment variable '$name'"; exception = $_ }
        return $null
    }
}

function Set-EnvVar {
    param ($name, $value)

    try {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return -1
        }
        $name = $name.Trim()

        if (Is-Not-Admin) {
            $command = "[System.Environment]::SetEnvironmentVariable('$name', '$value', [System.EnvironmentVariableTarget]::Machine)"
            return (Run-PS-Command -command $command)
        }

        # We already have admin rights, proceed normally
        [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Machine)
        return 0
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set environment variable '$name'"; exception = $_ }
        return -1
    }
}

function Make-Symbolic-Link {
    param ($link, $target)

    try {
        if ([string]::IsNullOrWhiteSpace($link) -or [string]::IsNullOrWhiteSpace($target)) {
            return @{ code = -1; message = 'Link and target cannot be empty!'; color = 'DarkYellow' }
        }

        $link = $link.Trim()
        $target = $target.Trim()

        if (Is-Directory-Not-Exists -path $target) {
            return @{ code = -1; message = "Target directory '$target' does not exist!"; color = 'DarkYellow' }
        }

        # Make sure parent directory exists
        $parent = Split-Path $link
        if (Is-Directory-Not-Exists -path $parent) {
            $created = Make-Directory -path $parent
        }
        # Remove old link if it exists
        if (Test-Path $link) {
            $item = Get-Item -LiteralPath $link -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                [System.IO.Directory]::Delete($link)
            } else {
                return @{ code = -1; message = "Link '$link' is not a symbolic link!"; color = 'DarkYellow' }
            }
        }

        if (Is-Not-Admin) {
            $command = "New-Item -ItemType SymbolicLink -Path '$link' -Target '$target'"
            $exitCode = (Run-Ps-Command -command $command)
            if ($exitCode -ne 0) {
                return @{ code = -1; message = "Failed to make symbolic link '$link' -> '$target'"; color = 'DarkYellow' }
            }
            return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = 'DarkGreen' }
        }

        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = 'DarkGreen' }
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to make symbolic link"; exception = $_ }
        return @{ code = -1; message = "Failed to make symbolic link '$link' -> '$target'"; color = 'DarkYellow' }
    }
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

function Is-Directory-Exists {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }
        $path = $path.Trim()
        return (Test-Path -Path $path -PathType Container)
    } catch {
        return $false
    }
}

function Is-Directory-Not-Exists {
    param ($path)

    return -not (Is-Directory-Exists -path $path)
}

function Is-File-Exists {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }
        $path = $path.Trim()
        return (Test-Path -Path $path -PathType Leaf)
    } catch {
        return $false
    }
}

function Is-File-Not-Exists {
    param ($path)

    return -not (Is-File-Exists -path $path)
}

function Make-Directory {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return -1
        }

        $path = $path.Trim()
        if (Is-Directory-Not-Exists -path $path) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

        return 0
    } catch {
        return -1
    }
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
                Write-Host $($msg.content) -ForegroundColor $msg.color
            }
        } else {
            if ($message) {
                $result.message = $message
            }
            if (-not $result.color) {
                $result.color = 'Gray'
            }

            Write-Host "`n$($result.message)" -ForegroundColor $result.color
        }
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to display message by exit code"; exception = $_ }
    }
}

function Log-Data {
    param ($data)

    try {
        $logPath = if ($data.logPath) { $data.logPath } else { $LOG_ERROR_PATH }
        $created = Make-Directory -path (Split-Path $logPath)
        if ($created -ne 0) {
            Write-Host "Failed to create directory $(Split-Path $logPath)"
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

function Optimize-SystemPath {
    try {
        $path = Get-EnvVar-ByName -name 'Path' -optimized $true
        if ($null -eq $path) {
            $path = ''
        }

        $oldPath = $path
        $path = Remove-PathDuplicates -path $path

        # Saving Path to log
        $outputLog = Log-Data -data @{
            logPath = $PATH_VAR_BACKUP_PATH
            header = "Original PATH`n$oldPath"
        }
        if ($outputLog -eq 0) {
            Write-Host "`nOriginal Path saved to '$PATH_VAR_BACKUP_PATH'"
        }

        $output = 0
        if ($path -ne $oldPath) {
            $output = Set-EnvVar -name 'Path' -value $path
            if ($output -eq 0) {
                Write-Host "`nPath optimized successfully" -ForegroundColor DarkGreen
            }
        }

        return $output
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to optimize system PATH variable"; exception = $_ }
        return -1
    }
}

function Remove-PathDuplicates {
    param ($path)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $entries = $Path -split ';' |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Where-Object { $seen.Add($_) }

    return ($entries -join ';')
}

function Get-Optimized-Env {
    param ($name, $value)

    $envVars = Get-All-EnvVars

    $envVars.Keys | ForEach-Object {
        $envName = $_
        $envValue = $envVars[$envName]

        if ($name.ToLower() -eq $envName.ToLower()) { return }
        if (-not $envValue) { return }
        if ($value.ToLower() -notlike "*$($envValue.ToLower())*") { return }
        if ($envValue -match '(?i)\\Windows|\\System32') { return }

        $envValue = [regex]::Escape($envValue.TrimEnd(';'))
        $pattern = "(?i)(?<=^|;){0}(?=;|$)" -f $envValue
        $value = [regex]::Replace($value, $pattern, "%$envName%")
    }

    return $value
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
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to format seconds"; exception = $_ }
        return -1
    }
}

function Is-OS-64Bit {
    return [System.Environment]::Is64BitOperatingSystem
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

function Get-PHPInstallInfo {
    param ($path)

    $tsDll = Get-ChildItem "$path\php*ts.dll" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'nts\.dll$' } |
        Select-Object -First 1

    if ($tsDll) {
        $buildType = 'TS'
        $dll = $tsDll
    }
    else {
        $dll = Get-ChildItem "$path\php*.dll" |
            Where-Object { $_.Name -notmatch 'phpdbg' } |
            Select-Object -First 1
        $buildType = 'NTS'
    }

    if (-not $dll) {
        return $null
    }

    return @{
        Version      = $dll.VersionInfo.ProductVersion
        Arch         = Get-BinaryArchitecture-From-DLL -path $dll.FullName
        BuildType    = $buildType
        Dll          = $dll.Name
        InstallPath  = $path
    }
}

function Get-BinaryArchitecture-From-DLL {
    param ($path)

    $bytes = [System.IO.File]::ReadAllBytes($path)

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)

    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)

    switch ($machine) {
        0x8664 { 'x64' }
        0x014c { 'x86' }
        default { 'Unknown' }
    }
}

function Is-Two-PHP-Versions-Equal {
    param ($version1, $version2)

    if ($null -eq $version1 -or $null -eq $version2) {
        return $false
    }

    return (($version1.version -eq $version2.version) -and
            ($version1.arch -eq $version2.arch) -and
            ($version1.buildType -eq $version2.buildType))
}

function Get-EnvConfig {
    param ($rootPath)

    $envFile = "$rootPath\.env"

    if (-not (Test-Path $envFile)) {
        throw ".env file not found in: $rootPath"
    } else {
        Write-Verbose "Using .env from: $envFile"
    }

    $config = @{}

    # Read the file and parse key=value pairs
    Get-Content $envFile | ForEach-Object {
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
