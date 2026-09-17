
function Initialize-PVM {
    try {
        $path = Get-EnvVarByName -name 'Path' -optimized $true
        if ($null -eq $path) { $path = '' }
        $newPath = $path
        $pathEntries = $path -split ';' | Where-Object -FilterScript { $_ -ne '' }

        $parent = Split-Path -Path $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH -Parent
        $created = New-Directory -path $parent
        if ($created -ne 0) {
            Show-Error -message 'Failed to create directory for PHP version.'
            return -1
        }

        $pvmEnvVarContent = Get-EnvVarByName -name 'PVM'

        if (($null -eq $pvmEnvVarContent) -or ($pvmEnvVarContent -ne "$($Global:PVMConfig.rootPath);$($Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH)")) {
            $null = Set-EnvVar -name $Global:PVMConfig.env.PVM_ENV_VAR_NAME -value "$($Global:PVMConfig.rootPath);$($Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH)"
        }

        if ($pathEntries -notcontains "%$($Global:PVMConfig.env.PVM_ENV_VAR_NAME)%") {
            $newPath += ";%$($Global:PVMConfig.env.PVM_ENV_VAR_NAME)%"
        }

        if ($newPath -ne $path) {
            $code = Set-EnvVar -name 'Path' -value $newPath
            if ($code -ne 0) {
                Show-Error -message 'Failed to set Path environment variable.'
                return -1
            }
        }

        Show-Success -message 'PVM environment has been set up.'
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set up PVM environment"; exception = $_ }
        return @{ code = -1; message = 'Failed to set up PVM environment.'; color = 'DarkYellow' }
    }
}

function Initialize-PVMDirectories {
    $dirs = @(
        $Global:PVMConfig.paths.directories.storage,
        $Global:PVMConfig.paths.directories.testDrive,
        $Global:PVMConfig.paths.directories.php,
        $Global:PVMConfig.paths.directories.data,
        $Global:PVMConfig.paths.directories.templates,
        $Global:PVMConfig.paths.directories.cache,
        $Global:PVMConfig.paths.directories.profiles,
        $Global:PVMConfig.paths.directories.log,
        $Global:PVMConfig.paths.directories.state
    )

    Show-Message -message "`nPVM environment directories:"
    $codes = @()
    $maxNameLength = ($dirs | ForEach-Object -Process { $_.Length } | Measure-Object -Maximum).Maximum + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
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

    $codes += $code = New-ProfileExample
    if ($code -eq 0) {
        Show-Success -message "`nExample profile created successfully at '$($Global:PVMConfig.paths.files.profileExample)'."
        Show-Message -message "- Use 'pvm help profile' to learn more."
    } else {
        Show-Error -message "`nFailed to create example profile."
    }

    $codes += $code = New-ProfileTemplate
    if ($code -eq 0) {
        Show-Success -message "`nProfile template created successfully at '$($Global:PVMConfig.paths.files.profileTemplate)'."
        Show-Message -message '- Feel free to modify it.'
    } else {
        Show-Error -message "`nFailed to create profile template."
    }

    $codes += $code = Set-ZendExtensionsList
    if ($code -eq 0) {
        Show-Success -message "`nZend extensions list created successfully at '$($Global:PVMConfig.paths.files.zendExtensionsList)'."
    } else {
        Show-Error -message "`nFailed to create zend extensions list."
    }

    $codes += $code = Set-AliasesList
    if ($code -eq 0) {
        Show-Success -message "`nAliases list created successfully at '$($Global:PVMConfig.paths.files.aliasesList)'."
        Show-Message -message "- Use 'pvm aliases' to see available aliases."
        Show-Message -message "- Feel free to modify it."
    } else {
        Show-Error -message "`nFailed to create aliases list."
    }

    $codes += $code = Set-ScriptsList
    if ($code -eq 0) {
        Show-Success -message "`nScripts list created successfully at '$($Global:PVMConfig.paths.files.scriptsList)'."
        Show-Message -message "- Use 'pvm run list' to see available scripts."
        Show-Message -message "- Feel free to modify it."
    } else {
        Show-Error -message "`nFailed to create scripts list."
    }

    return $codes
}

function Initialize-EnvironmentDirectoriesAndFiles {
    $codes = @()

    $codes += Initialize-PVMDirectories
    $codes += Initialize-PVMFiles

    if ($codes | Where-Object -FilterScript { $_ -ne 0 }) { return -1 }
    return 0
}

function New-EnvFile {
    param ($overwrite = $false)

    try {
        if (Test-FileNotExists -path "$($Global:PVMConfig.rootPath)\.env.example") {
            Show-Error -message "`nFailed to find .env.example file."
            return -1
        }

        if ((Test-FileExists -path "$($Global:PVMConfig.rootPath)\.env") -and ($overwrite -eq $false)) {
            $response = Read-HostWrapper -prompt "`n.env file already exists. Overwrite? (y/n)" -notifyUser
            if (Test-NoResponse -response $response) {
                return -1
            }
        }
        Copy-ItemWrapper -path "$($Global:PVMConfig.rootPath)\.env.example" -destination "$($Global:PVMConfig.rootPath)\.env"
        Show-Success -message "`nCreated .env file."

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create .env file"; exception = $_ }
        return -1
    }
}

function Wait-ForEnvEdit {
    Show-Info -message "`nEdit $($Global:PVMConfig.rootPath)\.env now if you want custom settings, then press Enter to continue..."
    Read-HostWrapper -notifyUser | Out-Null
    $Global:PVMConfig = Get-Config -rootPath $Global:PVMConfig.rootPath
}
