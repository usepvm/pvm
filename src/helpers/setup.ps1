
function Is-PVM-Setup {
    try {
        $pvmEnvVarContent = Get-EnvVar-ByName -name 'PVM'

        if ($null -eq $pvmEnvVarContent) {
            return $false
        }

        $pvmEnvEntries = $pvmEnvVarContent -split ';' | Where-Object { $_ -ne '' }
        if ($pvmEnvEntries -notcontains $PVMRoot -or $pvmEnvEntries -notcontains $PVMConfig.env.PHP_CURRENT_VERSION_PATH) {
            return $false
        }

        $path = Get-EnvVar-ByName -name 'Path' -optimized $true
        if ($null -eq $path) {
            $path = ''
        }

        $parent = Split-Path -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH
        $pathEntries = $path -split ';' | Where-Object { $_ -ne '' }
        if (
            (
                ($path -notlike "*$pvmEnvVarContent*") -and
                ($pathEntries -notcontains "%$($PVMConfig.env.PVM_ENV_VAR_NAME)%")
            ) -or
            (Is-Directory-Not-Exists -path $parent)
        ) {
            return $false
        }

        return $true
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check if PVM is set up"; exception = $_ }
        return $false
    }
}

function Is-PVM-Not-Setup {
    return -not (Is-PVM-Setup)
}
