
function Get-All-Subdirectories {
    param ($path)
    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $null
        }
        $path = $path.Trim()
        return Get-ChildItem -Path $path -Directory
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-All-Subdirectories: Failed to get all subdirectories of '$path'" -data $_.Exception.Message
        return $null
    }
}

function Get-All-EnvVars {

    try {
        return [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-All-EnvVars: Failed to get all environment variables" -data $_.Exception.Message
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-EnvVar-ByName: Failed to get environment variable '$name'" -data $_.Exception.Message
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
            $process = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"$command`"" -Verb RunAs -WindowStyle Hidden -PassThru -Wait
            # $process.WaitForExit()
            return $process.ExitCode
        }

        # We already have admin rights, proceed normally
        [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Machine);
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-EnvVar: Failed to set environment variable '$name'" -data $_.Exception.Message
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
            return -1
        }
        
        $link = $link.Trim()
        $target = $target.Trim()        
        # Make sure parent directory exists
        $parent = Split-Path $link
        if (-not (Test-Path $parent)) {
            $created = Make-Directory -path $parent
        }
        # Remove old link if it exists
        if (Test-Path $link) {
            Remove-Item -Path $link -Recurse -Force
        }
        
        if (-not (Is-Admin)) {
            $command = "New-Item -ItemType SymbolicLink -Path '$Link' -Target '$Target'"
            $process = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"$command`"" -Verb RunAs -WindowStyle Hidden -PassThru -Wait
            $process.WaitForExit()
            return $process.ExitCode
        }

        New-Item -ItemType SymbolicLink -Path $Link -Target $Target | Out-Null
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Make-Symbolic-Link: Failed to make symbolic link" -data $_.Exception.Message
        return -1
    }
}


function Is-Directory-Exists {
    param ($path)
    
    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }
        $path = $path.Trim()
        return [System.IO.Directory]::Exists($path)
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
        if (-not ([System.IO.Directory]::Exists($path))) {
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
        if ($message) {
            $result.message = $message
        }
        if (-not $result.color) {
            $result.color = "Gray"
        }
        
        Write-Host "`n$($result.message)" -ForegroundColor $result.color
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Display-Msg-By-ExitCode: Failed to display message by exit code" -data $_.Exception.Message
    }
}



function Log-Data {
    param ($logPath, $message, $data)
    
    try {
        $created = Make-Directory -path (Split-Path $logPath)
        if ($created -ne 0) {
            Write-Host "Failed to create directory $(Split-Path $logPath)"
            return -1
        }
        Add-Content -Path $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message :`n$data`n"
        return 0
    } catch {
        return -1
    }
}

function Optimize-SystemPath {
    param($shouldOverwrite = $false)
    
    try {
        $path = Get-EnvVar-ByName -name "Path"
        $envVars = Get-All-EnvVars

        # Saving Path to log
        $outputLog = Log-Data -logPath $PATH_VAR_BACKUP_PATH -message "Original PATH" -data $path
        if ($outputLog -eq 0) {
            Write-Host "`nOriginal Path saved to '$PATH_VAR_BACKUP_PATH'"
        }
        
        $envVars.Keys | ForEach-Object {
            $envName = $_
            $envValue = $envVars[$envName]
            
            if (
                ($null -ne $envValue) -and
                ($path -like "*$envValue*") -and
                -not($envValue -like "*\Windows*") -and
                -not($envValue -like "*\System32*")
            ) {
                $envValue = [regex]::Escape($envValue.TrimEnd(';'))
                $pattern = "(?<=^|;){0}(?=;|$)" -f $envValue
                $path = [regex]::Replace($path, $pattern, "%$envName%")
            }
        }
        $output = Set-EnvVar -name "Path" -value $path
        if ($output -eq 0) {
            Write-Host "`nPath optimized successfully"
        }
        
        return $output
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Optimize-SystemPath: Failed to optimize system PATH variable" -data $_.Exception.Message
        return -1
    }
}