


function Setup-PVM {

    try {
        $path = Get-EnvVar-ByName -name "Path"
        if ($path -eq $null) {
            $path = ''
        }
        $path = $newPath = $path.ToLower()

        $phpEnvValue = Get-EnvVar-ByName -name $PHP_CURRENT_ENV_NAME
        if ($phpEnvValue -eq $null) {
            $output = Set-EnvVar -name $PHP_CURRENT_ENV_NAME -value 'null'
            $phpEnvValue = 'null'
        }
        $phpEnvValue = $phpEnvValue.ToLower()
        $phpActiveEnvName = $PHP_CURRENT_ENV_NAME.ToLower()
        if (($phpEnvValue -and ($path -notlike "*$phpEnvValue*")) -and $path -notlike "*%$phpActiveEnvName%*") {
            $newPath += ";%$PHP_CURRENT_ENV_NAME%"
        } 

        $pvmPath = $PVMRoot.ToLower()
        if ($path -notlike "*$pvmPath*" -and $path -notlike "*%pvm%*") {
            $newPath += ";%pvm%"
        }
        $pvmEnvValue = Get-EnvVar-ByName -name "pvm"
        if ($pvmEnvValue -eq $null) {
            $output = Set-EnvVar -name "pvm" -value $PVMRoot
        }
        
        if ($newPath -ne $path) {
            $output = Set-EnvVar -name "Path" -value $newPath
            return $output
        }
        return 1
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Setup-PVM: Failed to set up PVM environment" -data $_.Exception.Message
        return -1
    }
}
