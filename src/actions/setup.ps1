
function Setup-PVM {
    try {
        $path = Get-EnvVar-ByName -name 'Path' -optimized $true
        if ($null -eq $path) { $path = '' }
        $newPath = $path
        $pathEntries = $path -split ';' | Where-Object { $_ -ne '' }

        $parent = Split-Path -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH
        $created = Make-Directory -path $parent
        if ($created -ne 0) {
            return @{ code = -1; message = 'Failed to create directory for PHP version.'; color = 'DarkYellow' }
        }

        $pvmEnvVarContent = Get-EnvVar-ByName -name 'PVM'

        if (($null -eq $pvmEnvVarContent) -or ($pvmEnvVarContent -ne "$PVMRoot;$($PVMConfig.env.PHP_CURRENT_VERSION_PATH)")) {
            $null = Set-EnvVar -name $PVMConfig.env.PVM_ENV_VAR_NAME -value "$PVMRoot;$($PVMConfig.env.PHP_CURRENT_VERSION_PATH)"
        }

        if ($pathEntries -notcontains "%$($PVMConfig.env.PVM_ENV_VAR_NAME)%") {
            $newPath += ";%$($PVMConfig.env.PVM_ENV_VAR_NAME)%"
        }

        $result = @{ code = 0; message = 'PVM environment has been set up.'; color = 'DarkGreen' }
        if ($newPath -ne $path) {
            $result.code = Set-EnvVar -name 'Path' -value $newPath
        }

        return $result
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set up PVM environment"; exception = $_ }
        return @{ code = -1; message = 'Failed to set up PVM environment.'; color = 'DarkYellow' }
    }
}

function Initialize-PVMDirectories {
    $dirs = @($PVMConfig.paths.storage, $PVMConfig.paths.data, $PVMConfig.paths.templates, $PVMConfig.paths.cache, $PVMConfig.paths.profiles)

    Write-Host "`nPVM environment directories:"
    $codes = @()
    $maxNameLength = ($dirs | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
    foreach ($dir in $dirs) {
        $codes += $code = Make-Directory -path $dir

        $dirName = "- $dir ".PadRight($maxNameLength, '.')
        if ($code -eq 0) {
            Write-Host -Object "$dirName Created." -ForegroundColor DarkGreen
        } else {
            Write-Host -Object "$dirName Not created." -ForegroundColor DarkYellow
        }
    }

    return $codes
}

function Initialize-PVMFiles {
    $codes = @()

    $codes += $code = Create-Example-PHP-Profile
    if ($code -eq 0) {
        Write-Host -Object "`nExample profile created successfully at '$($PVMConfig.paths.profiles)\example-profile.json'." -ForegroundColor DarkGreen
        Write-Host -Object "- Use 'pvm help profile' to learn more." -ForegroundColor Gray
    } else {
        Write-Host -Object "`nFailed to create example profile." -ForegroundColor DarkYellow
    }

    $codes += $code = Create-Profile-Template
    if ($code -eq 0) {
        Write-Host -Object "`nProfile template created successfully at '$($PVMConfig.paths.profileTemplate)'." -ForegroundColor DarkGreen
        Write-Host -Object '- Feel free to modify it.' -ForegroundColor Gray
    } else {
        Write-Host -Object "`nFailed to create profile template." -ForegroundColor DarkYellow
    }

    $codes += $code = Set-Zend-Extensions-List
    if ($code -eq 0) {
        Write-Host -Object "`nZend extensions list created successfully at '$($PVMConfig.paths.zendExtensionsList)'." -ForegroundColor DarkGreen
    } else {
        Write-Host -Object "`nFailed to create zend extensions list." -ForegroundColor DarkYellow
    }

    $codes += $code = Set-Aliases-List
    if ($code -eq 0) {
        Write-Host -Object "`nAliases list created successfully at '$($PVMConfig.paths.aliasesList)'." -ForegroundColor DarkGreen
        Write-Host -Object "- Use 'pvm aliases' to see available aliases." -ForegroundColor Gray
        Write-Host -Object "- Feel free to modify it." -ForegroundColor Gray
    } else {
        Write-Host -Object "`nFailed to create aliases list." -ForegroundColor DarkYellow
    }

    return $codes
}

function Setup-Environment-Directories-And-Files {
    $codes = @()

    $codes += Initialize-PVMDirectories
    $codes += Initialize-PVMFiles

    if ($codes | Where-Object { $_ -ne 0 }) { return -1 }
    return 0
}
