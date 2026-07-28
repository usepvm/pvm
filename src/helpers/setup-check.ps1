
function Test-PVMSetup {
    try {
        $pvmEnvVarContent = Get-EnvVarByName -name $PVMConfig.env.PVM_ENV_VAR_NAME

        if ($null -eq $pvmEnvVarContent) {
            return $false
        }

        $pvmEnvEntries = $pvmEnvVarContent -split ';' | Where-Object { $_ -ne '' }
        if ($pvmEnvEntries -notcontains $PVMRoot -or $pvmEnvEntries -notcontains $PVMConfig.env.PHP_CURRENT_VERSION_PATH) {
            return $false
        }

        $path = Get-EnvVarByName -name 'Path' -optimized $true
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
            (Test-DirectoryNotExists -path $parent)
        ) {
            return $false
        }

        return $true
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check if PVM is set up"; exception = $_ }
        return $false
    }
}

function Test-PVMNotSetup {
    return -not (Test-PVMSetup)
}
