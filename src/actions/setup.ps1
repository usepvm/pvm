
function Initialize-PVM {
    try {
        $path = Get-EnvVarByName -name 'Path' -optimized $true
        if ($null -eq $path) { $path = '' }
        $newPath = $path
        $pathEntries = $path -split ';' | Where-Object -FilterScript { $_ -ne '' }

        $parent = Split-Path -Path $Global:PVMConfig.paths.directories.phpCurrent -Parent
        $created = New-Directory -path $parent -allowOutsideRoot
        if ($created -ne 0) {
            Show-Error -message 'Failed to create directory for PHP version.'
            return -1
        }

        $pvmEnvVarContent = Get-EnvVarByName -name 'PVM'

        if (($null -eq $pvmEnvVarContent) -or ($pvmEnvVarContent -ne "$($Global:PVMConfig.rootPath);$($Global:PVMConfig.paths.directories.phpCurrent)")) {
            $null = Set-EnvVar -name $Global:PVMConfig.env.PVM_ENV_VAR_NAME -value "$($Global:PVMConfig.rootPath);$($Global:PVMConfig.paths.directories.phpCurrent)"
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

function Get-PVMDirectoryItems {
    $dirs        = $Global:PVMConfig.paths.directories
    $rootPattern = [regex]::Escape("$($Global:PVMConfig.rootPath)\")

    $items = @()
    foreach ($key in 'storage', 'testDrive', 'phpVersions', 'data', 'templates',
                     'cache', 'profiles', 'log', 'state', 'temp') {
        $path = $dirs.$key
        $items += @{
            Label  = $path -replace $rootPattern, ''
            Action = 'New-Directory'
            Args   = @{ path = $path }
        }
    }

    return $items
}

function Get-PVMFileItems {
    $files = $Global:PVMConfig.paths.files
    $rootPattern = [regex]::Escape("$($Global:PVMConfig.rootPath)\")

    $creators = [ordered]@{
        profileExample     = 'New-ProfileExample'
        profileTemplate    = 'New-ProfileTemplate'
        zendExtensionsList = 'Set-ZendExtensionsList'
        aliasesList        = 'Set-AliasesList'
        scriptsList        = 'Set-ScriptsList'
    }

    $items = @()
    foreach ($entry in $creators.GetEnumerator()) {
        $path = $files.($entry.Key)
        $items += @{
            Label  = $path -replace $rootPattern, '' #Split-Path -Path $files.($entry.Key) -Leaf
            Action = $entry.Value
            Args   = @{}
        }
    }

    return $items
}

function Invoke-PVMSection {
    param($title, $items, $width)

    Write-Cyan -message $title -underlined

    foreach ($item in $items) {
        $splat = $item.Args
        $code = & $item.Action @splat

        Write-White -message ("- $($item.Label) ".PadRight($width, '.') + ' ') -noNewLine
    if ($code -eq 0) {
            Show-Success -message 'Created'
    } else {
            Show-Error -message 'Not created'
        }

        $code
    }
}

function Initialize-EnvironmentDirectoriesAndFiles {
    $dirs = @(Get-PVMDirectoryItems)
    $files = @(Get-PVMFileItems)

    # Shared width so dots line up across both sections
    $max   = (($dirs + $files).Label | ForEach-Object -Process { $_.Length } | Measure-Object -Maximum).Maximum
    $width = $max + 3 + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)

    $codes  = @(Invoke-PVMSection -title "`nPVM environment directories:" -items $dirs -width $width)
    $codes += @(Invoke-PVMSection -title "`nPVM environment files:" -items $files -width $width)

    Show-LabelledInfo -message "`nPath: $($Global:PVMConfig.paths.directories.storage)" -label 'CHECK' -noNewLine

    if ($codes | Where-Object -FilterScript { $_ -ne 0 }) { return -1 }
    return 0
}

function New-EnvFile {
    param ($overwrite = $false)

    try {
        if (Test-FileNotExists -path "$($Global:PVMConfig.rootPath)\.env.example") {
            Show-LabelledError -message 'Failed to find .env.example file.'
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
            Show-LabelledError -message 'Failed to create .env file!'
            return -1
        }

        Show-LabelledSuccess -message 'Created .env file.' -noNewLine
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create .env file"; exception = $_ }
        return -1
    }
}

function Wait-ForEnvEdit {
    Show-LabelledWarning -label 'TODO' -message "Edit '$($Global:PVMConfig.rootPath)\.env' now if you want custom settings, then press Enter to continue..."
    Read-HostWrapper -notifyUser | Out-Null
    $Global:PVMConfig = Get-Config -rootPath $Global:PVMConfig.rootPath
}
