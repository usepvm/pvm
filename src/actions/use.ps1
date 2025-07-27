
function Update-PHP-Version {
    param ($variableName, $variableValue)

    try {
        $phpVersion = "php$variableValue"
        $variableValueContent = Get-EnvVar-ByName -name $phpVersion
        if (-not $variableValueContent) {
            $envVars = Get-All-EnvVars
            $variableValue = $envVars.Keys | Where-Object { $_ -match $variableValue } | Sort-Object | Select-Object -First 1
            if (-not $variableValue) {
                throw "The $variableName was not set !"
            }
            $variableValueContent = $envVars[$variableValue]
        }
        if (-not $variableValueContent) {
            throw "The $variableName was not found in the environment variables!"
        }
        Set-EnvVar -name $variableName -value $variableValueContent
        return 0;
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Update-PHP-Version: Failed to update PHP version for '$variableName'" -data $_.Exception.Message
        return -1
    }
}
