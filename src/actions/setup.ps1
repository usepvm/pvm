
function Initialize-PVM {
    try {
        $path = Get-EnvVarByName -name 'Path' -optimized $true
        if ($null -eq $path) { $path = '' }
        $newPath = $path
        $pathEntries = $path -split ';' | Where-Object -FilterScript { $_ -ne '' }

        $parent = Split-Path -Path $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH -Parent
        $created = New-Directory -path $parent -allowOutsideRoot
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
        $Global:PVMConfig.paths.directories.temp
    )

    Write-Cyan -message "`nPVM environment directories:" -underlined
    $codes = @()
    $maxNameLength = ($dirs | ForEach-Object -Process { $_.Length } | Measure-Object -Maximum).Maximum + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
    foreach ($dir in $dirs) {
        $codes += $code = New-Directory -path $dir

        $dirName = "- $dir ".PadRight($maxNameLength, '.')
        Write-White -message "$dirName " -noNewLine
        if ($code -eq 0) {
            Show-Success -message "Created."
        } else {
            Show-Error -message "Not created."
        }
    }

    return $codes
}

function Initialize-PVMFiles {
    $codes = @()

    $codes += $code = New-ProfileExample
    if ($code -eq 0) {
        $msg = "`nExample profile created successfully at '$($Global:PVMConfig.paths.files.profileExample)'."
        $msg += "`nUse 'pvm help profile' to learn more."
        Show-LabelledSuccess -message $msg -noNewLine
    } else {
        Show-LabelledError -message "Failed to create example profile." -noNewLine
    }

    $codes += $code = New-ProfileTemplate
    if ($code -eq 0) {
        $msg = "`nProfile template created successfully at '$($Global:PVMConfig.paths.files.profileTemplate)'."
        $msg += "`nFeel free to modify it."
        Show-LabelledSuccess -message $msg -noNewLine
    } else {
        Show-LabelledError -message "Failed to create profile template." -noNewLine
    }

    $codes += $code = Set-ZendExtensionsList
    if ($code -eq 0) {
        Show-LabelledSuccess -message "Zend extensions list created successfully at '$($Global:PVMConfig.paths.files.zendExtensionsList)'."-noNewLine
    } else {
        Show-LabelledError -message "Failed to create zend extensions list."-noNewLine
    }

    $codes += $code = Set-AliasesList
    if ($code -eq 0) {
        $msg = "`nAliases list created successfully at '$($Global:PVMConfig.paths.files.aliasesList)'."
        $msg += "`nUse 'pvm aliases' to see available aliases."
        $msg += "`nFeel free to modify it."
        Show-LabelledSuccess -message $msg -noNewLine
    } else {
        Show-LabelledError -message "Failed to create aliases list." -noNewLine
    }

    $codes += $code = Set-ScriptsList
    if ($code -eq 0) {
        $msg = "`nScripts list created successfully at '$($Global:PVMConfig.paths.files.scriptsList)'."
        $msg += "`nUse 'pvm run list' to see available scripts."
        $msg += "`nFeel free to modify it.";
        Show-LabelledSuccess -message $msg -noNewLine
    } else {
        Show-LabelledError -message "Failed to create scripts list." -noNewLine
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
            Show-LabelledError -message "Failed to find .env.example file."
            return -1
        }

        if ((Test-FileExists -path "$($Global:PVMConfig.rootPath)\.env") -and ($overwrite -eq $false)) {
            $response = Read-HostWrapper -prompt "`n.env file already exists. Overwrite? (y/n)" -notifyUser
            if (Test-NoResponse -response $response) {
                return -1
            }
        }
        $code = Copy-ItemWrapper -path "$($Global:PVMConfig.rootPath)\.env.example" -destination "$($Global:PVMConfig.rootPath)\.env"
        if ($code -ne 0) {
            Show-LabelledError -message "Failed to create .env file!"
            return -1
        }

        Show-LabelledSuccess -message "Created .env file."
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
