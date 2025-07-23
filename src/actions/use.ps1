
function Update-PHP-Version {
    param ($variableName, $variableValue)

    try {
        $phpVersion = "php$variableValue"
        $variableValueContent = [System.Environment]::GetEnvironmentVariable($phpVersion, [System.EnvironmentVariableTarget]::Machine)
        if (-not $variableValueContent) {
            $envVars = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
            $variableValue = $envVars.Keys | Where-Object { $_ -match $variableValue } | Sort-Object | Select-Object -First 1
            if (-not $variableValue) {
                Write-Host "`nThe $variableName was not set !"
                return -1;
            }
            $variableValueContent = $envVars[$variableValue]
        }
        if (-not $variableValueContent) {
            Write-Host "`nThe $variableName was not found in the environment variables!"
            return -1;
        }
        [System.Environment]::SetEnvironmentVariable($variableName, $variableValueContent, [System.EnvironmentVariableTarget]::Machine)
        return 0;
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Update-PHP-Version: Failed to update PHP version for '$variableName'" -data $_.Exception.Message
        return -1
    }
}
