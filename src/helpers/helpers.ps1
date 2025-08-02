
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
        [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Machine);
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-EnvVar: Failed to set environment variable '$name'" -data $_.Exception.Message
        return -1
    }
}


function Make-Directory {
    param ( [string]$path )

    try {
        if ([string]::IsNullOrWhiteSpace($path.Trim())) {
            return 1
        }

        if (-not (Test-Path -Path $path -PathType Container)) {
            mkdir $path | Out-Null
        }
    } catch {
        return 1
    }
    
    return 0
}


function Is-Admin {

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    return $isAdmin
}

function Display-Msg-By-ExitCode {
    param($msgSuccess, $msgError, $exitCode)
    
    try {
        if ($exitCode -eq 0) {
            Write-Host $msgSuccess
        } else {
            Write-Host $msgError
        }
        Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1 -Global
        Update-SessionEnvironment
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
        $pathBak = Get-EnvVar-ByName -name $PATH_VAR_BACKUP_NAME

        if (($pathBak -eq $null) -or $shouldOverwrite) {
            $output = Set-EnvVar -name $PATH_VAR_BACKUP_NAME -value $path
        }
        
        # Saving Path to log
        $outputLog = Log-Data -logPath $PATH_VAR_BACKUP_PATH -message "Original PATH" -data $path

        $envVars.Keys | ForEach-Object {
            $envName = $_
            $envValue = $envVars[$envName]
            
            if (
                ($null -ne $envValue) -and
                ($path -like "*$envValue*") -and
                ($envValue -notlike "*\Windows*") -and
                ($envValue -notlike "*\System32*")
            ) {
                $envValue = [regex]::Escape($envValue.TrimEnd(';'))
                $pattern = "(?<=^|;){0}(?=;|$)" -f $envValue
                $path = [regex]::Replace($path, $pattern, "%$envName%")
            }
        }
        $output = Set-EnvVar -name "Path" -value $path
        
        return $output
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Optimize-SystemPath: Failed to optimize system PATH variable" -data $_.Exception.Message
        return -1
    }
}