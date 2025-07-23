

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


function Get-Env {
    
    try {
        $envData = @{}
        Get-Content $ENV_FILE | Where-Object { $_ -match "(.+)=(.+)" } | ForEach-Object {
            $key, $value = $_ -split '=', 2
            $envData[$key.Trim()] = $value.Trim()
        }
        return $envData
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Env: Failed to retrieve environment variables" -data $_.Exception.Message
        return @{}
    }
}


function Set-Env {
    param ($key, $value)

    try {
        # Read the file into an array of lines
        $envLines = Get-Content $ENV_FILE

        # Modify the line with the key
        $envLines = $envLines | ForEach-Object {
            if ($_ -match "^$key=") { "$key=$value" }
            else { $_ }
        }

        # Write the modified lines back to the .env file
        $envLines | Set-Content $ENV_FILE
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-Env: Failed to set environment variable '$key'" -data $_.Exception.Message
    }

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
        $path = [Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
        $envVars = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
        $pathBak = [Environment]::GetEnvironmentVariable($PATH_VAR_BACKUP_NAME, [System.EnvironmentVariableTarget]::Machine)

        if (($pathBak -eq $null) -or $shouldOverwrite) {
            [Environment]::SetEnvironmentVariable($PATH_VAR_BACKUP_NAME, $path, [System.EnvironmentVariableTarget]::Machine)
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
        [Environment]::SetEnvironmentVariable("Path", $path, [System.EnvironmentVariableTarget]::Machine)
        
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Optimize-SystemPath: Failed to optimize system PATH variable" -data $_.Exception.Message
        return -1
    }
}