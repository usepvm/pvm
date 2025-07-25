
function Get-All-EnvVars {

    try {
        return [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-All-EnvVars: Failed to get all environment variables" -data $_.Exception.Message
        return $null
    }
}

function Get-EnvVar-ByName {
    param ( [string]$name )

    try {
        return [System.Environment]::GetEnvironmentVariable($name, [System.EnvironmentVariableTarget]::Machine)
    }
    catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Env-ByName: Failed to get environment variable '$name'" -data $_.Exception.Message
        return $null
    }
}

function Set-EnvVar {
    param ( [string]$name, [string]$value )

    try {
        [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Machine);
    }
    catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-EnvVar: Failed to set environment variable '$name'" -data $_.Exception.Message
        return -1
    }
}


function Make-Directory {
    param ( [string]$path )

    if (-not (Test-Path -Path $path -PathType Container)) {
        mkdir $path | Out-Null
    }
}

function Make-File {
    param ( [string]$filePath )

    if (-not (Test-Path -Path $filePath -PathType Leaf)) {
        New-Item -Path $filePath -ItemType File | Out-Null
    }
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
            Write-Host "`n$msgSuccess"
        } else {
            Write-Host "`n$msgError"
        }
        Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1 -Global
        Update-SessionEnvironment
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Display-Msg-By-ExitCode: Failed to display message by exit code" -data $_.Exception.Message
    }
    exit $exitCode
}



function Log-Data {
    param ($logPath, $message, $data)
    
    try {
        Make-Directory -path (Split-Path $logPath)
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
            Set-EnvVar -name $PATH_VAR_BACKUP_NAME -value $path
        }
        
        # Saving Path to log
        $output = Log-Data -logPath $PATH_VAR_BACKUP_PATH -message "Original PATH" -data $path

        $envVars.Keys | ForEach-Object {
            $envName = $_
            $envValue = $envVars[$envName]
            
            if (
                ($null -ne $envValue) -and
                ($path -like "*$envValue*") -and
                ($envValue -notlike "*\Windows*") -and
                ($envValue -notlike "*\System32*")
            ) {
                $envValue = $envValue.TrimEnd(';')
                $envValue = [regex]::Escape($envValue)
                $path = $path -replace ";$envValue;", ";%$envName%;"
            }
        }
        Set-EnvVar -name "Path" -value $path
        
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Optimize-SystemPath: Failed to optimize system PATH variable" -data $_.Exception.Message
        return -1
    }
}