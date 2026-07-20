
function Initialize-PVM {
    try {
        $path = Get-EnvVar-ByName -name 'Path' -optimized $true
        if ($null -eq $path) { $path = '' }
        $newPath = $path
        $pathEntries = $path -split ';' | Where-Object { $_ -ne '' }

        $parent = Split-Path -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH
        $created = New-Directory -path $parent
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
            $code = Set-EnvVar -name 'Path' -value $newPath
            if ($code -ne 0) {
                $result = @{ code = -1; message = 'Failed to set Path environment variable.'; color = 'DarkYellow' }
            }
        }

        return $result
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set up PVM environment"; exception = $_ }
        return @{ code = -1; message = 'Failed to set up PVM environment.'; color = 'DarkYellow' }
    }
}

function Initialize-PVMDirectories {
    $dirs = @(
        $PVMConfig.paths.storage,
        $PVMConfig.paths.fakeStorage,
        $PVMConfig.paths.php,
        $PVMConfig.paths.data,
        $PVMConfig.paths.templates,
        $PVMConfig.paths.cache,
        $PVMConfig.paths.profiles,
        $PVMConfig.paths.log
    )

    Show-Message -message "`nPVM environment directories:"
    $codes = @()
    $maxNameLength = ($dirs | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
    foreach ($dir in $dirs) {
        $codes += $code = New-Directory -path $dir

        $dirName = "- $dir ".PadRight($maxNameLength, '.')
        if ($code -eq 0) {
            Show-Success -message "$dirName Created."
        } else {
            Show-Error -message "$dirName Not created."
        }
    }

    return $codes
}

function Initialize-PVMFiles {
    $codes = @()

    $codes += $code = New-Example-PHP-Profile
    if ($code -eq 0) {
        Show-Success -message "`nExample profile created successfully at '$($PVMConfig.paths.exampleProfile)'."
        Show-Message -message "- Use 'pvm help profile' to learn more."
    } else {
        Show-Error -message "`nFailed to create example profile."
    }

    $codes += $code = New-Profile-Template
    if ($code -eq 0) {
        Show-Success -message "`nProfile template created successfully at '$($PVMConfig.paths.profileTemplate)'."
        Show-Message -message '- Feel free to modify it.'
    } else {
        Show-Error -message "`nFailed to create profile template."
    }

    $codes += $code = Set-Zend-Extensions-List
    if ($code -eq 0) {
        Show-Success -message "`nZend extensions list created successfully at '$($PVMConfig.paths.zendExtensionsList)'."
    } else {
        Show-Error -message "`nFailed to create zend extensions list."
    }

    $codes += $code = Set-Aliases-List
    if ($code -eq 0) {
        Show-Success -message "`nAliases list created successfully at '$($PVMConfig.paths.aliasesList)'."
        Show-Message -message "- Use 'pvm aliases' to see available aliases."
        Show-Message -message "- Feel free to modify it."
    } else {
        Show-Error -message "`nFailed to create aliases list."
    }

    $codes += $code = Set-Scripts-List
    if ($code -eq 0) {
        Write-Host -Object "`nScripts list created successfully at '$($PVMConfig.paths.scriptsList)'." -ForegroundColor DarkGreen
        Write-Host -Object "- Use 'pvm scripts' to see available scripts." -ForegroundColor Gray
        Write-Host -Object "- Feel free to modify it." -ForegroundColor Gray
    } else {
        Write-Host -Object "`nFailed to create scripts list." -ForegroundColor DarkYellow
    }

    return $codes
}

function Initialize-Environment-Directories-And-Files {
    $codes = @()

    $codes += Initialize-PVMDirectories
    $codes += Initialize-PVMFiles

    if ($codes | Where-Object { $_ -ne 0 }) { return -1 }
    return 0
}

function New-Env-File {
    param ($overwrite = $false)

    try {
        if (Test-File-Not-Exists -path "$PVMRoot\.env.example") {
            Show-Error -message "`nFailed to find .env.example file."
            return -1
        }

        if ((Test-File-Exists -path "$PVMRoot\.env") -and ($overwrite -eq $false)) {
            $response = Read-Host -Prompt "`n.env file already exists. Overwrite? (y/n)"
            $response = $response.Trim()
            if ($response -ne 'y' -and $response -ne 'Y') {
                return -1
            }
        }
        Copy-Item -Path "$PVMRoot\.env.example" -Destination "$PVMRoot\.env"
        Show-Success -message "`nCreated .env file."

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create .env file"; exception = $_ }
        return -1
    }
}

function Wait-ForEnvEdit {
    Show-Info -message "`nEdit $PVMRoot\.env now if you want custom settings, then press Enter to continue..."
    Read-Host | Out-Null
    $Global:PVMConfig = Get-Config -rootPath $PVMRoot
}
