
function Get-Data-From-Cache {
    param ($cacheFileName)
    
    $path = "$DATA_PATH\$cacheFileName.json"
    $list = @{}
    try {
        $jsonData = Get-Content $path | ConvertFrom-Json
        $jsonData.PSObject.Properties.GetEnumerator() | ForEach-Object {
            $key = $_.Name
            $value = $_.Value
            
            # Add the key-value pair to the hashtable
            $list[$key] = $value
        }
        return $list
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"
            exception = $_
        }
        return @{}
    }
}

function Cache-Data {
    param ($cacheFileName, $data, $depth = 3)
    
    try {
        $jsonString = $data | ConvertTo-Json -Depth $depth
        $path = "$DATA_PATH\$cacheFileName.json"
        $created = Make-Directory -path (Split-Path $path)
        if ($created -ne 0) {
            Write-Host "Failed to create directory $(Split-Path $path)"
            return -1
        }
        Set-Content -Path $path -Value $jsonString
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to cache data"
            exception = $_
        }
        return -1
    }
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
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get all subdirectories of '$path'"
            exception = $_
        }
        return $null
    }
}

function Get-All-EnvVars {

    try {
        return [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get all environment variables"
            exception = $_
        }
        return $null
    }
}

function Get-EnvVar-ByName {
    param ($name)

    try {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return $null
        }
        $name = $name.Trim()
        return [System.Environment]::GetEnvironmentVariable($name, [System.EnvironmentVariableTarget]::Machine)
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get environment variable '$name'"
            exception = $_
        }
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

        if (-not (Is-Admin)) {
            $command = "[System.Environment]::SetEnvironmentVariable('$name', '$value', [System.EnvironmentVariableTarget]::Machine)"
            return (Run-Command -command $command)
        }

        # We already have admin rights, proceed normally
        [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Machine)
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to set environment variable '$name'"
            exception = $_
        }
        return -1
    }
}

function Get-PHP-Path-By-Version {
    param ($version)
    
    if ([string]::IsNullOrWhiteSpace($version)) {
        return $null
    }
    
    $phpContainerPath = "$STORAGE_PATH\php"
    $version = $version.Trim()

    if (-not(Is-Directory-Exists -path $phpContainerPath) -or -not(Is-Directory-Exists -path "$phpContainerPath\$version")) {
        return $null
    }

    return "$phpContainerPath\$version"
}

function Make-Symbolic-Link {
    param($link, $target)
    
    try {
        if ([string]::IsNullOrWhiteSpace($link) -or [string]::IsNullOrWhiteSpace($target)) {
            return @{ code = -1; message = "Link and target cannot be empty!"; color = "DarkYellow" }
        }
        
        $link = $link.Trim()
        $target = $target.Trim()        
        
        if (-not (Is-Directory-Exists -path $target)) {
            return @{ code = -1; message = "Target directory '$target' does not exist!"; color = "DarkYellow" }
        }
        
        # Make sure parent directory exists
        $parent = Split-Path $link
        if (-not (Test-Path $parent)) {
            $created = Make-Directory -path $parent
        }
        # Remove old link if it exists
        if (Test-Path $link) {
            $item = Get-Item -LiteralPath $link -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                [System.IO.Directory]::Delete($link)
            } else {
                return @{ code = -1; message = "Link '$link' is not a symbolic link!"; color = "DarkYellow" }
            }
        }
        
        if (-not (Is-Admin)) {
            $command = "New-Item -ItemType SymbolicLink -Path '$link' -Target '$target'"
            $exitCode = (Run-Command -command $command)
            if ($exitCode -ne 0) {
                return @{ code = -1; message = "Failed to make symbolic link '$link' -> '$target'"; color = "DarkYellow" }
            }
            return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = "DarkGreen" }
        }

        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = "DarkGreen" }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to make symbolic link"
            exception = $_
        }
        return @{ code = -1; message = "Failed to make symbolic link '$link' -> '$target'"; color = "DarkYellow" }
    }
}

function Run-Command {
    param($command)
    
    $process = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"$command`"" -Verb RunAs -WindowStyle Hidden -PassThru -Wait
    $process.WaitForExit()
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

function Make-Directory {
    param ( [string]$path )

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return -1
        }

        $path = $path.Trim()
        if (-not (Is-Directory-Exists -path $path)) {
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

function Display-Msg-By-ExitCode {
    param($result, $message = $null)
    
    try {
        if ($result.messages -and $result.messages.Count -gt 1) {
            foreach ($msg in $result.messages) {
                if (-not $msg.color) {
                    $msg.color = "White"
                }
                Write-Host $($msg.content) -ForegroundColor $msg.color
            }
        } else {
            if ($message) {
                $result.message = $message
            }
            if (-not $result.color) {
                $result.color = "Gray"
            }
            
            Write-Host "`n$($result.message)" -ForegroundColor $result.color
        }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to display message by exit code"
            exception = $_
        }
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
        $path = Get-EnvVar-ByName -name "Path"
        if ($null -eq $path) {
            $path = ''
        }
        $oldPath = $path 
        $envVars = Get-All-EnvVars
        
        $envVars.Keys | ForEach-Object {
            $envName = $_
            $envValue = $envVars[$envName]
            
            if (
                ($null -ne $envValue) -and
                ($path.ToLower() -like "*$($envValue.ToLower())*") -and
                -not($envValue -match '(?i)\\Windows') -and
                -not($envValue -match '(?i)\\System32')
            ) {
                $envValue = [regex]::Escape($envValue.TrimEnd(';'))
                $pattern = "(?i)(?<=^|;){0}(?=;|$)" -f $envValue
                $path = [regex]::Replace($path, $pattern, "%$envName%")
            }
        }
        
        $output = 0
        if ($path -ne $oldPath) {
            # Saving Path to log
            $outputLog = Log-Data -data @{
                logPath = $PATH_VAR_BACKUP_PATH
                header = "Original PATH`n$oldPath"
            }
            if ($outputLog -eq 0) {
                Write-Host "`nOriginal Path saved to '$PATH_VAR_BACKUP_PATH'"
            }
            
            $output = Set-EnvVar -name "Path" -value $path
            if ($output -eq 0) {
                Write-Host "`nPath optimized successfully" -ForegroundColor DarkGreen
            }
        }
        
        return $output
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to optimize system PATH variable"
            exception = $_
        }
        return -1
    }
}