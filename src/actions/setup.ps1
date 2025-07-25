


function Setup-PVM {

    try {
        $path = $newPath = Get-EnvVar-ByName -name "Path"

        $phpEnvValue = Get-EnvVar-ByName -name $PHP_CURRENT_ENV_NAME
        if ($phpEnvValue -eq $null -or $path -notlike "*$phpEnvValue*") {
            $newPath += ";%$PHP_CURRENT_ENV_NAME%"
            Set-EnvVar -name $PHP_CURRENT_ENV_NAME -value 'null'
        }

        $pvmPath = $PVMRoot
        if ($path -notlike "*$pvmPath*") {
            $newPath += ";%pvm%"
        }
        $pvmEnvValue = Get-EnvVar-ByName -name "pvm"
        if ($pvmEnvValue -eq $null) {
            Set-EnvVar -name "pvm" -value $pvmPath
        }
        
        if ($newPath -ne $path) {
            Set-EnvVar -name "Path" -value $newPath
            return 0
        }
        return 1
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Setup-PVM: Failed to set up PVM environment" -data $_.Exception.Message
        return -1
    }
}
