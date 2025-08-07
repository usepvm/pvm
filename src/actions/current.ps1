
function Get-PHP-Status {
    param($phpPath)
    
    $status = @{ opcache = $false; xdebug = $false }
    try {
        $phpIniPath = "$phpPath\php.ini"
        if (-not (Test-Path $phpIniPath)) {
            Write-Host "`nphp.ini not found at: $phpIniPath"
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
        $currentPhpVersionPath = Get-Item $PHP_CURRENT_VERSION_PATH
        if ($currentPhpVersionPath) {
            $currentPhpVersionPath = $currentPhpVersionPath.Target
        }
        
        return @{
            version = $(Split-Path $currentPhpVersionPath -Leaf)
            path = $currentPhpVersionPath
            status = Get-PHP-Status -phpPath $currentPhpVersionPath
        }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Current-PHP-Version: Failed to retrieve current PHP version" -data $_.Exception.Message
        return @{
            version = $null
            path = $null
            status = @{ opcache = $false; xdebug = $false }
        }
    }
}