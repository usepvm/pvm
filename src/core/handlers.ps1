
function Invoke-Setup {
    $result = @{ code = 0; message = 'PVM is already setup' }
    if (Test-PVM-Not-Setup) {
        $null = Initialize-Environment-Directories-And-Files
        $envCode = New-Env-File -overwrite $true

        if ($envCode -eq 0) { Wait-ForEnvEdit }

        $result = Initialize-PVM
    }
    $optimized = Optimize-SystemPath
    if ($optimized -ne 0) {
        Show-Error -Message "`nFailed to optimize system path."
    }

    Show-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-Repair {
    $codes = @()
    $codes += Initialize-Environment-Directories-And-Files

    $envCode = New-Env-File
    if ($envCode -eq 0) { Wait-ForEnvEdit }
    $codes += if ($envCode -eq -1) { -1 } else { 0 }

    if ($codes | Where-Object { $_ -ne 0 }) { return -1 }
    return 0
}

function Invoke-Current {
    $result = Get-Current-PHP-Version
    if (-not $result.version) {
        Show-Warning -message "`nNo PHP version is currently set. Please use 'pvm use <version>' to set a version."
        return -1
    }
    $text = "`nRunning version: PHP $($result.version)"
    if ($result.buildType) {
        $text += " $($result.buildType)"
    }
    if ($result.arch) {
        $text += " $($result.arch)"
    }
    Show-Host -message $text

    if (-not $result.status) {
        Show-Warning -message 'No status information available for the current PHP version.'
        return -1
    }

    # Display zend extensions
    $hasVersionInfo = $result.status | Where-Object { $_.Version }
    foreach ($ext in $result.status) {
        $statusText = if ($ext.Enabled) { 'Enabled' } else { 'Disabled' }
        $color = if ($ext.Enabled) { 'DarkGreen' } else { 'DarkYellow' }
        $extName = if ($ext.Name -eq 'opcache') { 'Zend OPcache' } else { (Get-Culture).TextInfo.ToTitleCase($ext.Name) }

        if ($hasVersionInfo) {
            $textInfo = "  $extName v$($ext.Version) ".PadRight(($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 4), '.')
        } else {
            $textInfo = "  $extName ".PadRight(($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 4), '.')
        }

        Write-Color -message "$textInfo $statusText" -foreColor $color
    }

    Show-Host -message "`nPath: $($result.path)"
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
        $result = Select-PHP-Version-Automatically

        if ($result.code -eq 0) {
            $version = $result.version
            Show-Msg-By-ExitCode -result $result -message "php $version is already installed!"
            return -1
        }

        $version = $result.version
    } elseif ($version -eq 'latest') {
        $latestVersion = Get-Latest-PHP-Version -arch $arch -buildType $buildType
        if (-not $latestVersion) {
            Show-Error -message "`nFailed to find the latest PHP version"
            return -1
        }

        $version = $latestVersion.version
        Show-Host -message "`nLatest available PHP version is $version"
    }

    if (-not $version) {
        Show-Warning -message "`nPlease provide a PHP version to install"
        return -1
    }

    $result = Install-PHP -version $version -arch $arch -buildType $buildType
    Show-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-Uninstall {
    param ($arguments)

    $version = $arguments[0]

    if (-not $version) {
        Show-Warning -message "`nPlease provide a PHP version to uninstall"
        return -1
    }

    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }
    $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)

    $result = Uninstall-PHP -version $version -skipConfirmation $skipConfirmation

    Show-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-Use {
    param ($arguments)

    $version = $arguments[0]

    if (-not $version) {
        Show-Warning -message "`nPlease provide a PHP version to use"
        return -1
    }

    if ($version -eq 'auto') {
        $result = Select-PHP-Version-Automatically
        if ($result.code -ne 0) {
            Show-Msg-By-ExitCode -result $result
            return -1
        }
        $version = $result.version
    }

    $result = Update-PHP-Version -version $version

    Show-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-Ini {
    param ($arguments)

    $action = $arguments[0]
    if (-not $action) {
        Show-Warning -message "`nPlease specify an action for 'pvm ini'. Use 'info', 'set', 'get', 'status', 'enable', 'disable', 'add', 'remove', 'list' or 'restore'."
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

    $options = @{
        exclude   = $null
        verbosity = 'Normal'
        coverage  = $false
        tag       = $null
        target    = 75
        sortBy    = $null
        groupBy   = $null
    }
    $exclude = $null
    $pesterVersion = $null
    $testsNames = $arguments | Where-Object {
        if (($_ -join (',') -match '^--exclude=(.+)$')) {
            $exclude = $Matches[1] -split ','
            return $false
        }
        if ($_ -match '^--sort=(.+)$') {
            $options.sortBy = $Matches[1]
            return $false
        }
        if ($_ -match '^--group=(.+)$') {
            $options.groupBy = $Matches[1]
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
        if ($_ -match '^--pester=(.+)$') {
            $pesterVersion = $Matches[1]
            return $false
        }
        if ($_ -match '^-{1,2}') {
            return $false
        }
        return $true
    }

    if ($options.target -lt 0 -or $options.target -gt 100) {
        Show-Warning -message "`nInvalid coverage value : $($options.target) | Min: 0, Max: 100"
        return -1
    }

    return Initialize-Tests -testsNames $testsNames -options $options -exclude $exclude -pesterVersion $pesterVersion
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
            Show-Warning -message "`nNo usage information available for the '$command' command."
            return -1
        }
        foreach ($key in $usage.Keys) {
            Show-Info -message "`n$key`:"
            if ($usage[$key] -is [array]) {
                $($usage.$key) | ForEach-Object { Show-Host -message "  $_" }
            } else {
                Show-Host -message "  $($usage[$key])"
            }
        }
    } else {
        Show-Usage -arguments $arguments
    }

    return 0
}

function Invoke-Profile {
    param ($arguments)

    $action = $arguments[0]

    if (-not $action) {
        Show-Warning -message "`nPlease specify an action for 'pvm profile'. Use 'save', 'load', 'list', 'show', 'delete', 'clear', 'export', or 'import'."
        return -1
    }

    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

    $action = Resolve-Alias -alias $action.ToLower()

    switch ($action.ToLower()) {
        'save' {
            if ($remainingArgs.Count -eq 0) {
                Show-Warning -message "`nPlease provide a profile name: pvm profile save <name> [description]"
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $description = if ($remainingArgs.Count -gt 1) { ($remainingArgs[1..($remainingArgs.Count - 1)] -join ' ') } else { $null }
            return (Save-PHP-Profile -profileName $profileName -description $description)
        }
        'load' {
            if ($remainingArgs.Count -eq 0) {
                Show-Warning -message "`nPlease provide a profile name: pvm profile load <name>"
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            return (Use-PHP-Profile -profileName $profileName)
        }
        'list' {
            return (Show-PHP-Profiles)
        }
        'show' {
            if ($remainingArgs.Count -eq 0) {
                Show-Warning -message "`nPlease provide a profile name: pvm profile show <name>"
                return -1
            }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }

            return (Show-PHP-Profile -profileName $profileName)
        }
        'delete' {
            if ($remainingArgs.Count -eq 0) {
                Show-Warning -message "`nPlease provide a profile name: pvm profile delete <name>"
                return -1
            }

            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
            return (Remove-PHP-Profile -profileName $profileName -skipConfirmation $skipConfirmation)
        }
        'clear' {
            $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
            return (Clear-PHP-Profiles -skipConfirmation $skipConfirmation)
        }
        'export' {
            if ($remainingArgs.Count -eq 0) {
                Show-Warning -message "`nPlease provide a profile name: pvm profile export <name> [path]"
                return -1
            }

            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $exportPath = if ($remainingArgs.Count -gt 1) { $remainingArgs[1] } else { $null }

            return (Export-PHP-Profile -profileName $profileName -exportPath $exportPath)
        }
        'import' {
            if ($remainingArgs.Count -eq 0) {
                Show-Warning -message "`nPlease provide a file path: pvm profile import <path> [name]"
                return -1
            }
            $importPath = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $profileName = if ($remainingArgs.Count -gt 1) { $remainingArgs[1] } else { $null }

            return (Import-PHP-Profile -importPath $importPath -profileName $profileName)
        }
        default {
            Show-Error -message "`nUnknown action '$action'. Use 'save', 'load', 'list', 'show', 'delete', 'clear', 'export', or 'import'."
            return -1
        }
    }
}

function Invoke-Cache {
    param ($arguments)

    $action = $arguments[0]

    if (-not $action) {
        Show-Warning -message "`nPlease specify an action for 'pvm cache'. Use 'list', 'show', 'delete', 'clear'."
        return -1
    }

    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

    $action = Resolve-Alias -alias $action.ToLower()

    switch ($action.ToLower()) {
        'list' {
            return (Show-Cache-Files)
        }
        'show' {
            if ($remainingArgs.Count -eq 0) {
                Show-Warning -message "`nPlease provide a cache name: pvm cache show <name>"
                return -1
            }
            $cacheName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            return (Show-Save-Cached-Data -cacheName $cacheName)
        }
        'delete' {
            if ($remainingArgs.Count -eq 0) {
                Show-Warning -message "`nPlease provide a cache name: pvm cache delete <name>"
                return -1
            }

            $cacheName = if ($remainingArgs.Count -gt 1) { $remainingArgs[0] } else { $remainingArgs }
            $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
            return (Remove-Cache-File -cacheName $cacheName -skipConfirmation $skipConfirmation)
        }
        'clear' {
            $skipConfirmation = [bool]($remainingArgs | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
            return (Clear-Cache-Files -skipConfirmation $skipConfirmation)
        }
        default {
            Show-Error -message "`nUnknown action '$action'. Use 'list', 'show', 'delete', or 'clear'."
            return -1
        }
    }
}

function Invoke-Aliases {
    $aliases = Get-Aliases

    if ($aliases.Count -eq 0) {
        Show-Error -Message 'No aliases found.'
        return -1
    }

    Show-Host -message "`n`nAvailable Aliases:`n"
    $maxAliasLength = ($aliases.Keys | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
    $aliases.Keys | ForEach-Object {
        $alias = "$_ ".PadRight($maxAliasLength, '.')
        $command = $aliases[$_]

        Show-Host -message "  $alias $command"
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

    Show-Info -message "`n`nPVM status:`n"
    foreach ($var in $config.GetEnumerator()) {
        $key = "$($var.Key) ".PadRight($maxNameLength, '.')
        $rel = $var.Value
        Show-Host -message "- $key $rel"
    }

    if ($arguments -contains '--verbose') {
        $PVM_PATHS = $PVMConfig.paths
        $PVM_PATHS["Current PHP Path"] = $PVMConfig.env.PHP_CURRENT_VERSION_PATH

        Show-Info -message "`n`nPVM paths:`n"
        foreach ($entry in $PVM_PATHS.GetEnumerator()) {
            $key = "$($entry.Key) ".PadRight($maxNameLength, '.')
            $rel = $entry.Value.Replace("$PVMRoot\", '')
            Show-Host -message "- $key $rel"
        }
    }

    return 0
}

function Invoke-Update {
    param ($arguments)

    $checkOnly = $arguments -contains '--check'

    $result = Update-PVM -checkOnly $checkOnly
    Show-Msg-By-ExitCode -result $result
    return $result.code
}
