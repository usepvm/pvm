
function Invoke-Setup {
    $result = @{ code = 0; message = 'PVM is already setup' }
    if (Is-PVM-Not-Setup) {
        $result = Setup-PVM
        $null = Setup-Environment-Directories-And-Files
        $null = Create-Env-File -overwrite $true
    }
    $optimized = Optimize-SystemPath
    if ($optimized -ne 0) {
        Write-Host -Object "`nFailed to optimize system path." -ForegroundColor DarkYellow
    }

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-Repair {
    $codes = @()
    $codes += Setup-Environment-Directories-And-Files
    $codes += Create-Env-File

    if ($codes | Where-Object { $_ -ne 0 }) { return -1 }
    return 0
}

function Invoke-Current {
    $result = Get-Current-PHP-Version
    if (-not $result.version) {
        Write-Host -Object "`nNo PHP version is currently set. Please use 'pvm use <version>' to set a version."
        return -1
    }
    $text = "`nRunning version: PHP $($result.version)"
    if ($result.buildType) {
        $text += " $($result.buildType)"
    }
    if ($result.arch) {
        $text += " $($result.arch)"
    }
    Write-Host -Object $text

    if (-not $result.status) {
        Write-Host -Object 'No status information available for the current PHP version.' -ForegroundColor Yellow
        return -1
    }

    foreach ($ext in $result.status.Keys) {
        if ($result.status[$ext]) {
            Write-Host -Object "- $ext is enabled" -ForegroundColor DarkGreen
        } else {
            Write-Host -Object "- $ext is disabled" -ForegroundColor DarkYellow
        }
    }

    Write-Host -Object "`nPath: $($result.path)" -ForegroundColor Gray
    return 0
}

function Invoke-List {
    param ($arguments)

    $arch = Resolve-Arch -arguments $arguments
    $buildType = Resolve-BuildType -arguments $arguments

    $term = ($arguments | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
    $result = Get-PHP-Versions-List -available ($arguments -contains 'available') -term $term -arch $arch -buildType $buildType

    return $result
}

function Invoke-Install {
    param ($arguments)

    $version = $arguments[0]
    $arch = Resolve-Arch -arguments $arguments
    $buildType = Resolve-BuildType -arguments $arguments

    if ($version -eq 'auto') {
        $result = Auto-Select-PHP-Version

        if ($result.code -eq 0) {
            $version = $result.version
            Display-Msg-By-ExitCode -result $result -message "php $version is already installed!"
            return -1
        }

        $version = $result.version
    } elseif ($version -eq 'latest') {
        $latestVersion = Get-Latest-PHP-Version -arch $arch -buildType $buildType
        if (-not $latestVersion) {
            Write-Host -Object "`nFailed to find the latest PHP version"
            return -1
        }

        $version = $latestVersion.version
        Write-Host -Object "`nLatest available PHP version is $version"
    }

    if (-not $version) {
        Write-Host -Object "`nPlease provide a PHP version to install"
        return -1
    }

    $result = Install-PHP -version $version -arch $arch -buildType $buildType
    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-Uninstall {
    param ($arguments)

    $version = $arguments[0]

    if (-not $version) {
        Write-Host -Object "`nPlease provide a PHP version to uninstall"
        return -1
    }

    $result = Uninstall-PHP -version $version

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-Use {
    param ($arguments)

    $version = $arguments[0]

    if (-not $version) {
        Write-Host -Object "`nPlease provide a PHP version to use"
        return -1
    }

    if ($version -eq 'auto') {
        $result = Auto-Select-PHP-Version
        if ($result.code -ne 0) {
            Display-Msg-By-ExitCode -result $result
            return -1
        }
        $version = $result.version
    }

    $result = Update-PHP-Version -version $version

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-Ini {
    param ($arguments)

    $action = $arguments[0]
    if (-not $action) {
        Write-Host -Object "`nPlease specify an action for 'pvm ini'. Use 'info', 'set', 'get', 'status', 'enable', 'disable', 'add', 'remove', 'list' or 'restore'."
        return -1
    }

    $remainingArgs = if ($arguments.Count -gt 1) {
        $arguments[1..($arguments.Count - 1)] | Where-Object { $_ -ne $arch }
    } else { @() }

    $exitCode = Invoke-IniAction -action $action -params $remainingArgs
    return $exitCode
}

function Invoke-Test {
    param ($arguments)

    if (-not (Get-Module -Name Pester -ListAvailable)) {
        Write-Host -Object "`nInstalling Pester..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -SkipPublisherCheck
    }

    $options = @{
        exclude   = $null
        verbosity = 'Normal'
        coverage  = $false
        tag       = $null
        target    = 75
        sortBy    = $null
    }
    $exclude = $null
    $testsNames = $arguments | Where-Object {
        if (($_ -join (',') -match '^--exclude=(.+)$')) {
            $exclude = $Matches[1] -split ','
            return $false
        }
        if ($_ -match '^--sort=(.+)$') {
            $options.sortBy = $Matches[1]
            return $false
        }
        if ($_ -match '^--tag=(.+)$') {
            $options.tag = $Matches[1]
            return $false
        }
        if ($_ -match '^--coverage(?:=(\-?\d+(?:\.\d+)?))?$') {
            $options.coverage = $true
            if ($Matches[1]) {
                $options.target = [decimal] $Matches[1]
            }
            return $false
        }
        if ($_ -match '^--verbosity=(.+)$') {
            $options.verbosity = $Matches[1]
            return $false
        }
        return $true
    }

    if ($options.target -lt 0 -or $options.target -gt 100) {
        Write-Host -Object "`nInvalid coverage value : $($options.target) | Min: 0, Max: 100" -ForegroundColor Yellow
        return -1
    }

    return Prepare-Tests -testsNames $testsNames -options $options -exclude $exclude
}

function Invoke-Log {
    param ($arguments)

    $pageSizeArg = $arguments | Where-Object { $_ -match '^--pageSize=(.+)$' }
    if ($pageSizeArg) {
        $pageSize = $pageSizeArg -replace '^--pageSize=', ''
    } else {
        $pageSize = $PVMConfig.env.DEFAULT_LOG_PAGE_SIZE
    }

    $term = ($arguments | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
    $code = Show-Log -pageSize $pageSize -term $term
    return $code
}

function Invoke-Version {
    Show-PVM-Version
    return 0
}

function Invoke-Help {
    param ($arguments)

    $command = $arguments[0]
    if ($command) {
        $usage = $actions[$command].usage
        if ($null -eq $usage) {
            Write-Host -Object "`nNo usage information available for the '$command' command." -ForegroundColor Yellow
            return -1
        }
        foreach ($key in $usage.Keys) {
            Write-Host -Object "`n$key`:" -ForegroundColor Cyan
            if ($usage[$key] -is [array]) {
                $($usage.$key) | ForEach-Object { Write-Host -Object "  $_" }
            } else {
                Write-Host -Object "  $($usage[$key])"
            }
        }
    } else {
        Show-Usage
    }

    return 0
}

function Invoke-Profile {
    param ($arguments)

    $action = $arguments[0]

    if (-not $action) {
        Write-Host -Object "`nPlease specify an action for 'pvm profile'. Use 'save', 'load', 'list', 'show', 'delete', 'export', or 'import'." -ForegroundColor Yellow
        return -1
    }

    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

    $action = Resolve-Alias -alias $action.ToLower()

    switch ($action.ToLower()) {
        'save' {
            if ($remainingArgs.Count -eq 0) {
                Write-Host -Object "`nPlease provide a profile name: pvm profile save <name> [description]" -ForegroundColor Yellow
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $description = if ($remainingArgs.Count -gt 1) { ($remainingArgs[1..($remainingArgs.Count - 1)] -join ' ') } else { $null }
            return (Save-PHP-Profile -profileName $profileName -description $description)
        }
        'load' {
            if ($remainingArgs.Count -eq 0) {
                Write-Host -Object "`nPlease provide a profile name: pvm profile load <name>" -ForegroundColor Yellow
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            return (Load-PHP-Profile -profileName $profileName)
        }
        'list' {
            return (List-PHP-Profiles)
        }
        'show' {
            if ($remainingArgs.Count -eq 0) {
                Write-Host -Object "`nPlease provide a profile name: pvm profile show <name>" -ForegroundColor Yellow
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }

            return (Show-PHP-Profile -profileName $profileName)
        }
        'delete' {
            if ($remainingArgs.Count -eq 0) {
                Write-Host -Object "`nPlease provide a profile name: pvm profile delete <name>" -ForegroundColor Yellow
                return -1
            }

            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
            return (Delete-PHP-Profile -profileName $profileName -skipConfirmation $skipConfirmation)
        }
        'clear' {
            $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
            return (Clear-PHP-Profiles -skipConfirmation $skipConfirmation)
        }
        'export' {
            if ($remainingArgs.Count -eq 0) {
                Write-Host -Object "`nPlease provide a profile name: pvm profile export <name> [path]" -ForegroundColor Yellow
                return -1
            }

            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $exportPath = if ($remainingArgs.Count -gt 1) { $remainingArgs[1] } else { $null }

            return (Export-PHP-Profile -profileName $profileName -exportPath $exportPath)
        }
        'import' {
            if ($remainingArgs.Count -eq 0) {
                Write-Host -Object "`nPlease provide a file path: pvm profile import <path> [name]" -ForegroundColor Yellow
                return -1
            }
            $importPath = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[1] } else { $null }

            return (Import-PHP-Profile -importPath $importPath -profileName $profileName)
        }
        default {
            Write-Host -Object "`nUnknown action '$action'. Use 'save', 'load', 'list', 'show', 'delete', 'clear', 'export', or 'import'." -ForegroundColor Yellow
            return -1
        }
    }
}

function Invoke-Cache {
    param ($arguments)

    $action = $arguments[0]

    if (-not $action) {
        Write-Host -Object "`nPlease specify an action for 'pvm cache'. Use 'list', 'show', 'delete', 'clear'." -ForegroundColor Yellow
        return -1
    }

    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

    $action = Resolve-Alias -alias $action.ToLower()

    switch ($action.ToLower()) {
        'list' {
            return (List-Cache-Files)
        }
        'show' {
            if ($remainingArgs.Count -eq 0) {
                Write-Host -Object "`nPlease provide a cache name: pvm cache show <name>" -ForegroundColor Yellow
                return -1
            }
            $cacheName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            return (Show-Cache-Data -cacheName $cacheName)
        }
        'delete' {
            if ($remainingArgs.Count -eq 0) {
                Write-Host -Object "`nPlease provide a cache name: pvm cache delete <name>" -ForegroundColor Yellow
                return -1
            }

            $cacheName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
            return (Delete-Cache-File -cacheName $cacheName -skipConfirmation $skipConfirmation)
        }
        'clear' {
            $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
            return (Clear-Cache-Files -skipConfirmation $skipConfirmation)
        }
        default {
            Write-Host -Object "`nUnknown action '$action'. Use 'list', 'show', 'delete', or 'clear'." -ForegroundColor Yellow
            return -1
        }
    }
}

function Invoke-Aliases {
    $aliases = Get-Aliases

    if ($aliases.Count -eq 0) {
        Write-Host -Object 'No aliases found.' -ForegroundColor DarkYellow
        return -1
    }

    Write-Host -Object "`n`nAvailable Aliases:`n"
    $maxAliasLength = ($aliases.Keys | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
    $aliases.Keys | ForEach-Object {
        $alias = "$_ ".PadRight($maxAliasLength, '.')
        $command = $aliases[$_]

        Write-Host -Object "  $alias $command"
    }

    return 0
}

function Invoke-Info {
    param ($arguments)

    $currentPHP = Get-Current-PHP-Version
    $installedPHP = Get-Installed-PHP-Versions-From-Disk
    $currentPhpVersion = 'Not Set'
    $currentPhpPath = 'Not Set'
    if ($currentPHP) {
        if ($currentPHP.version) {
            $currentPhpVersion = $currentPHP.version
            if ($currentPHP.arch -and $currentPHP.buildType) {
                $currentPhpVersion = "$currentPhpVersion ($($currentPHP.arch) $($currentPHP.buildType))"
            }
        }

        if ($currentPHP.path) {
            $currentPhpPath = $currentPHP.path
        }
    }

    $config = [ordered]@{
        'PVM Version'      = $PVMConfig.version
        'PVM Root'         = $PVMRoot
        'Storage Path'     = $PVMConfig.paths.storage
        'Current PHP'      = $currentPhpVersion
        'Real PHP Path'    = $currentPhpPath
        'Active PHP Path'  = $PVMConfig.env.PHP_CURRENT_VERSION_PATH
        'Installed PHPs'   = @($installedPHP).Count
        'Cache TTL'        = "$($PVMConfig.env.CACHE_MAX_HOURS) hours"
        'Profiles'         = @(Get-Profile-Files).Count
        'Cached Files'     = @(Get-Cache-Files).Count
    }
    $allKeys = $config.Keys + $PVMConfig.paths.Keys + $PVMConfig.env.Keys
    $maxNameLength = ($allKeys | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)

    Write-Host -Object "`n`nPVM status:`n" -ForegroundColor Cyan
    foreach ($var in $config.GetEnumerator()) {
        $key = "$($var.Key) ".PadRight($maxNameLength, '.')
        $rel = $var.Value
        Write-Host -Object "- $key $rel"
    }

    if ($arguments -contains '--verbose') {
        $PVM_PATHS = $PVMConfig.paths
        $PVM_PATHS["Current PHP Path"] = $PVMConfig.env.PHP_CURRENT_VERSION_PATH

        Write-Host -Object "`n`nPVM paths:`n" -ForegroundColor Cyan
        foreach ($entry in $PVM_PATHS.GetEnumerator()) {
            $key = "$($entry.Key) ".PadRight($maxNameLength, '.')
            $rel = $entry.Value.Replace("$PVMRoot\", '')
            Write-Host -Object "- $key $rel"
        }
    }

    return 0
}
