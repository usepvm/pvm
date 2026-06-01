


function Setup-PVM {

    try {
        $path = Get-EnvVar-ByName -name "Path" -optimized $true
        if ($null -eq $path) {
            $path = ''
        }
        $newPath = $path
        $pathEntries = $path -split ';' | Where-Object { $_ -ne '' }

        $parent = Split-Path $PHP_CURRENT_VERSION_PATH
        $created = Make-Directory -path $parent
        if ($created -ne 0) {
            return @{ code = -1; message = "Failed to create directory for PHP version."; color = "DarkYellow"}
        }

        $pvmEnvVarContent = Get-EnvVar-ByName -name "PVM"

        if (($null -eq $pvmEnvVarContent) -or ($pvmEnvVarContent -ne "$PVMRoot;$PHP_CURRENT_VERSION_PATH")) {
            $pvmEnvVarContent = "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            $output = Set-EnvVar -name $PVM_ENV_VAR_NAME -value $pvmEnvVarContent
        }

        if ($pathEntries -notcontains "%$PVM_ENV_VAR_NAME%") {
            $newPath += ";%$PVM_ENV_VAR_NAME%"
        }

        $result = @{ code = 0; message = "PVM environment has been set up."; color = "DarkGreen"}
        if ($newPath -ne $path) {
            $output = Set-EnvVar -name "Path" -value $newPath
            $result.code = $output
        }

        return $result
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to set up PVM environment"
            exception = $_
        }
        return @{ code = -1; message = "Failed to set up PVM environment."; color = "DarkYellow"}
    }
}
