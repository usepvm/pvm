
function Setup-PVM {
    try {
        $path = Get-EnvVar-ByName -name 'Path' -optimized $true
        if ($null -eq $path) {
            $path = ''
        }
        $newPath = $path
        $pathEntries = $path -split ';' | Where-Object { $_ -ne '' }

        $parent = Split-Path -Path $PHP_CURRENT_VERSION_PATH
        $created = Make-Directory -path $parent
        if ($created -ne 0) {
            return @{ code = -1; message = 'Failed to create directory for PHP version.'; color = 'DarkYellow'}
        }

        $pvmEnvVarContent = Get-EnvVar-ByName -name 'PVM'

        if (($null -eq $pvmEnvVarContent) -or ($pvmEnvVarContent -ne "$PVMRoot;$PHP_CURRENT_VERSION_PATH")) {
            $null = Set-EnvVar -name $PVM_ENV_VAR_NAME -value "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
        }

        if ($pathEntries -notcontains "%$PVM_ENV_VAR_NAME%") {
            $newPath += ";%$PVM_ENV_VAR_NAME%"
        }

        $result = @{ code = 0; message = 'PVM environment has been set up.'; color = 'DarkGreen'}
        if ($newPath -ne $path) {
            $result.code = Set-EnvVar -name 'Path' -value $newPath
        }

        return $result
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set up PVM environment"; exception = $_ }
        return @{ code = -1; message = 'Failed to set up PVM environment.'; color = 'DarkYellow'}
    }
}

function Setup-Environment-Directories-And-Files {
    $codes = @()
    $codes += Make-Directory -path $STORAGE_PATH
    $codes += Make-Directory -path $DATA_PATH
    $codes += Make-Directory -path $TEMPLATES_PATH
    $codes += Make-Directory -path $CACHE_PATH
    $codes += Make-Directory -path $PROFILES_PATH
    $codes += Create-Example-PHP-Profile
    $codes += Create-Profile-Template
    $codes += Set-Zend-Extensions-List
    $codes += Set-Aliases-List

    foreach ($code in $codes) {
        if ($code -ne 0) {
            return -1
        }
    }

    return 0
}
