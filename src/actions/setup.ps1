


function Setup-PVM {

    try {
        $path = $newPath = [Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

        $phpEnvName = $PHP_CURRENT_ENV_NAME
        $phpEnvValue = [Environment]::GetEnvironmentVariable($phpEnvName, [System.EnvironmentVariableTarget]::Machine)
        if ($phpEnvValue -eq $null -or $path -notlike "*$phpEnvValue*") {
            $newPath += ";%$phpEnvName%"
            [Environment]::SetEnvironmentVariable($phpEnvName, 'null', [System.EnvironmentVariableTarget]::Machine)
        }

        $pvmPath = $PVMRoot
        if ($path -notlike "*$pvmPath*") {
            $newPath += ";%pvm%"
        }
        $pvmEnvValue = [Environment]::GetEnvironmentVariable("pvm", [System.EnvironmentVariableTarget]::Machine)
        if ($pvmEnvValue -eq $null) {
            [Environment]::SetEnvironmentVariable("pvm", $pvmPath, [System.EnvironmentVariableTarget]::Machine)
        }
        
        if ($newPath -ne $path) {
            [Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::Machine)
            return 0
        }
        return 1
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Setup-PVM: Failed to set up PVM environment" -data $_.Exception.Message
        return -1
    }
}
