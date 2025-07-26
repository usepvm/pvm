
function Get-PHP-Status {
    param($phpPath)
    
    $status = @{ opcache = $false; xdebug = $false }
    try {
        $phpIniPath = "$phpPath\php.ini"
        if (-not (Test-Path $phpIniPath)) {
            Write-Host "php.ini not found at: $phpIniPath"
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
        Write-Host "An error occurred while checking PHP status: $_"
    }
    
    return $status
}

function Get-Current-PHP-Version {

    try {
        $currentPhpVersionPath = Get-EnvVar-ByName -name $PHP_CURRENT_ENV_NAME
        $currentPhpVersionKey = $null
        $envVars = Get-All-EnvVars
        $envVars.Keys | Where-Object { $_ -match "php\d(\.\d+)*" }  | Where-Object {
            if ($currentPhpVersionPath -eq $envVars[$_] -and -not($PHP_CURRENT_ENV_NAME -eq $_)) {
                $currentPhpVersionKey = $_
            }
        }
        if (-not $currentPhpVersionKey) {
            if ($currentPhpVersionPath -match 'php-([\d\.]+)') {
                $currentPhpVersionKey = $matches[1]
            }
        }
        if ($currentPhpVersionKey -eq $null) {
            return @{
                version = $null
                status = $null
            }
        }
        
        $currentPhpVersionKey = $currentPhpVersionKey -replace 'php', ''
        
        return @{
            version = $currentPhpVersionKey
            path = $currentPhpVersionPath
            status = Get-PHP-Status -phpPath $currentPhpVersionPath
        }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Current-PHP-Version: Failed to retrieve current PHP version" -data $_.Exception.Message
        return @{
            version = $null
            status = @{ opcache = $false; xdebug = $false }
        }
    }
}