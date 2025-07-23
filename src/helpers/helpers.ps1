

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
        # $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Log-Data: Failed to log data to '$logPath'" -data $_.Exception.Message
        return -1
    }
}
