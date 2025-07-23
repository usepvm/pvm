

function Get-Current-PHP-Version {

    try {
        $currentPhpVersion = [System.Environment]::GetEnvironmentVariable($USER_ENV["PHP_CURRENT_ENV_NAME"], [System.EnvironmentVariableTarget]::Machine)
        $currentPhpVersionKey = $null
        $envVars = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
        $envVars.Keys | Where-Object { $_ -match "php\d(\.\d+)*" }  | Where-Object {
            if ($currentPhpVersion -eq $envVars[$_] -and -not($USER_ENV["PHP_CURRNET_ENV_NAME"] -eq $_)) {
                $currentPhpVersionKey = $_
            }
        }
        if (-not $currentPhpVersionKey) {
            if ($currentPhpVersion -match 'php-([\d\.]+)') {
                $currentPhpVersionKey = $matches[1]
            }
        }
        $currentPhpVersionKey = $currentPhpVersionKey -replace 'php', ''
        return $currentPhpVersionKey
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Current-PHP-Version: Failed to retrieve current PHP version" -data $_.Exception.Message
        return $null
    }
}