
function Get-PHP-Status {
    param($phpPath)
    
    $status = @{ opcache = $false; xdebug = $false }
    try {
        $phpIniPath = "$phpPath\php.ini"
        if (-not (Test-Path $phpIniPath)) {
            Write-Error "php.ini not found at: $phpIniPath"
            return -1
        }

        $iniContent = Get-Content $phpIniPath
        
        foreach ($line in $iniContent) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^(;)?\s*zend_extension\s*=.*opcache.*$') {
                $status.opcache = -not $trimmed.StartsWith(';')
            }

            if ($trimmed -match '^(;)?\s*zend_extension\s*=.*xdebug.*$') {
                $status.xdebug = -not $trimmed.StartsWith(';')
            }
        }    
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-PHP-Status: Failed to retrieve PHP status" -data $_.Exception.Message
        Write-Error "An error occurred while checking PHP status: $_"
    }
    
    return $status
}

function Get-Current-PHP-Version {

    try {
        $currentPhpVersionPath = [System.Environment]::GetEnvironmentVariable($USER_ENV["PHP_CURRENT_ENV_NAME"], [System.EnvironmentVariableTarget]::Machine)
        $currentPhpVersionKey = $null
        $envVars = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
        $envVars.Keys | Where-Object { $_ -match "php\d(\.\d+)*" }  | Where-Object {
            if ($currentPhpVersionPath -eq $envVars[$_] -and -not($USER_ENV["PHP_CURRNET_ENV_NAME"] -eq $_)) {
                $currentPhpVersionKey = $_
            }
        }
        if (-not $currentPhpVersionKey) {
            if ($currentPhpVersionPath -match 'php-([\d\.]+)') {
                $currentPhpVersionKey = $matches[1]
            }
        }
        $currentPhpVersionKey = $currentPhpVersionKey -replace 'php', ''
        
        $result = @{
            version = $currentPhpVersionKey
            status = Get-PHP-Status -phpPath $currentPhpVersionPath
        }
        
        return $result
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Current-PHP-Version: Failed to retrieve current PHP version" -data $_.Exception.Message
        return @{
            version = $null
            status = @{ opcache = $false; xdebug = $false }
        }
    }
}