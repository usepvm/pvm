
function Toggle-PHP-Extension {
    param($extensionsNames)
    
    try {
        $currentPhpVersionPath = [System.Environment]::GetEnvironmentVariable($USER_ENV["PHP_CURRENT_ENV_NAME"], [System.EnvironmentVariableTarget]::Machine)
        if (-not $currentPhpVersionPath) {
            Write-Host "`nNo PHP version is currently set. Please use 'pvm use <version>' to set a version."
            return 1
        }
        
        $phpIniPath = "$currentPhpVersionPath\php.ini"
        if (-not (Test-Path $phpIniPath)) {
            Write-Host "`nphp.ini not found at: $phpIniPath"
            return 1
        }
        
        $iniContent = Get-Content $phpIniPath
        $newContent = @()
        $foundAny = $false
        $status = @{}
        foreach ($extensionName in $extensionsNames) {
            $status[$extensionName] = $false
        }

        foreach ($line in $iniContent) {
            $trimmed = $line.Trim()
            $matched = $false

            foreach ($extensionName in $extensionsNames) {
                if ($trimmed -match "^(;)?\s*zend_extension\s*=.*$extensionName.*$") {
                    $matched = $true
                    $foundAny = $true
                    if ($trimmed.StartsWith(';')) {
                        $newContent += $trimmed.Substring(1)  # Enable
                    } else {
                        $newContent += ";$trimmed"  # Disable
                    }
                    $status[$extensionName] = $trimmed.StartsWith(';')
                    break
                }
            }

            if (-not $matched) {
                $newContent += $line
            }
        }

        if (-not $foundAny) {
            Write-Host "`nNone of the specified extensions were found in php.ini." -ForegroundColor Yellow
            return 1
        }
        Set-Content -Path $phpIniPath -Value $newContent
        
        return @{ exitCode = 0; status = $status }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Toggle-PHP-Extension: Failed to toggle PHP extension" -data $_.Exception.Message
        return @{ exitCode = 1; status = @{ opcache = $false; xdebug = $false } }
    }
}
