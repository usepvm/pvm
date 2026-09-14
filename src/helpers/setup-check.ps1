
function Test-PVMSetup {
    try {
        $pvmEnvVarContent = Get-EnvVarByName -name $Global:PVMConfig.env.PVM_ENV_VAR_NAME

        if ($null -eq $pvmEnvVarContent) {
            return $false
        }

        $pvmEnvEntries = $pvmEnvVarContent -split ';' | Where-Object -FilterScript { $_ -ne '' }
        if ($pvmEnvEntries -notcontains $Global:PVMConfig.rootPath -or $pvmEnvEntries -notcontains $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH) {
            return $false
        }

        $path = Get-EnvVarByName -name 'Path' -optimized $true
        if ($null -eq $path) {
            $path = ''
        }

        $parent = Split-Path -Path $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH -Parent
        $pathEntries = $path -split ';' | Where-Object -FilterScript { $_ -ne '' }
        if (
            (
                ($path -notlike "*$pvmEnvVarContent*") -and
                ($pathEntries -notcontains "%$($Global:PVMConfig.env.PVM_ENV_VAR_NAME)%")
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
