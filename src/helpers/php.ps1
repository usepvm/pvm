
function Get-PHPInstallInfo {
    param ($path)

    $tsDll = Get-ChildItemWrapper -path "$path\php*ts.dll" |
    Where-Object -FilterScript { $_.Name -notmatch 'nts\.dll$' } |
    Select-Object -First 1

    if ($tsDll) {
        $buildType = 'TS'
        $dll = $tsDll
    } else {
        $dll = Get-ChildItemWrapper -path "$path\php*.dll" |
        Where-Object -FilterScript { $_.Name -notmatch 'phpdbg' } |
        Select-Object -First 1
        $buildType = 'NTS'
    }

    if (-not $dll) {
        return $null
    }

    return @{
        Version     = $dll.VersionInfo.ProductVersion
        Arch        = Get-BinaryArchitectureFromDLL -path $dll.FullName
        BuildType   = $buildType
        Dll         = $dll.Name
        InstallPath = $path
    }
}

function Get-BinaryArchitectureFromDLL {
    param ($path)

    if (Test-FileNotExists -path $path) {
        return 'Unknown'
    }

    $bytes = [System.IO.File]::ReadAllBytes($path)

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)

    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)

    switch ($machine) {
        0x8664 { 'x64' }
        0x014c { 'x86' }
        default { 'Unknown' }
    }
}

function Test-TwoPHPVersionsEqual {
    param ($version1, $version2)

    if ($null -eq $version1 -or $null -eq $version2) {
        return $false
    }

    return (($version1.version -eq $version2.version) -and
        ($version1.arch -eq $version2.arch) -and
        ($version1.buildType -eq $version2.buildType))
}

function Set-ZendExtensionsList {
    try {
        $jsonContent = $PVMConfig.defaults.zendExtensions | ConvertTo-Json -Depth 10
        Set-ContentWrapper -path $PVMConfig.paths.zendExtensionsList -value $jsonContent

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create zend extensions list"; exception = $_ }
        return -1
    }
}

function Get-ZendExtensionsList {
    try {
        if (Test-FileExists -path $PVMConfig.paths.zendExtensionsList) {
            $data = (Get-ContentWrapper -path $PVMConfig.paths.zendExtensionsList -raw | ConvertFrom-Json)
            if ($null -ne $data -and $data.Count -gt 0) {
                return $data
            }
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get zend extensions list"; exception = $_ }
    }

    return $PVMConfig.defaults.zendExtensions
}

function Update-InstalledPHPVersionsCache {
    try {
        $installedVersions = Get-InstalledPHPVersionsFromDisk
        $code = Save-CachedData -cacheFileName 'installed_php_versions' -data $installedVersions -depth 1

        return $code
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to refresh installed PHP versions cache"; exception = $_ }
        return -1
    }
}

function Get-InstalledPHPVersionsFromDisk {
    return Show-SpinnerWhileJob -scriptBlock {
        $directories = Get-AllSubdirectories -path $PVMConfig.paths.php
        $installedVersions = $directories | ForEach-Object -Process {
            if (Test-FileExists -path "$($_.FullName)\php.exe") {
                $phpInfo = Get-PHPInstallInfo -path $_.FullName

                return $phpInfo
            }
            return $null
        }

        $installedVersions = ($installedVersions | Sort-Object { [version]$_.Version })

        return @{ pvmData = $installedVersions }
    } -rethrow $true
}

function Get-InstalledPHPVersions {
    param ($arch = $null, $buildType = $null)

    try {
        $installedVersions = Get-OrUpdateCache -cacheFileName 'installed_php_versions' -depth 1 -compute {
            return Get-InstalledPHPVersionsFromDisk
        }

        if (Test-HasNoData -data $installedVersions) {
            return @()
        }

        if ($arch) {
            $installedVersions = $installedVersions | Where-Object -FilterScript { $_.Arch -eq $arch }
        }

        if ($buildType) {
            $installedVersions = $installedVersions | Where-Object -FilterScript { $_.BuildType -eq $buildType }
        }

        $installedVersions = $installedVersions | Sort-Object { [version]$_.Version }

        return $installedVersions
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve installed PHP versions"; exception = $_ }
        return @()
    }
}

function Get-UserSelectedPHPVersion {
    param ($installedVersions)

    if (-not $installedVersions -or $installedVersions.Count -eq 0) {
        return $null
    }
    if ($installedVersions.Length -eq 1) {
        $versionObj = $($installedVersions)
    } else {
        $currentVersion = Get-CurrentPHPVersion
        $index = 0
        Show-Message -message "`nInstalled versions :"
        $maxNameLength = ($installedVersions.version | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        $installedVersions | ForEach-Object -Process {
            $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
            $isCurrent = ''
            if (Test-TwoPHPVersionsEqual -version1 $currentVersion -version2 $_) {
                $isCurrent = '(Current)'
            }
            $metaData = ''
            if ($_.Arch) {
                $metaData += $_.Arch + ' '
            }
            if ($_.BuildType) {
                $metaData += $_.BuildType
            }
            $versionNumber = "$($_.version) ".PadRight($maxNameLength, '.')
            Show-Message -message " [$index] $versionNumber $metaData $isCurrent"
            $index++
        }
        $response = Read-HostWrapper -prompt "`nInsert the [number] of the version you want to use (or press Enter to cancel)"
        if (-not $response) {
            return @{ code = -1; message = 'Operation cancelled.'; color = 'Gray' }
        }
        $versionObj = $installedVersions | Where-Object -FilterScript { $_.index -eq $response }
    }

    return @{ code = 0; version = $versionObj.version; arch = $versionObj.arch; buildType = $versionObj.BuildType; path = $versionObj.InstallPath }
}

function Get-MatchingPHPVersions {
    param ($version)

    try {
        $installedVersions = Get-InstalledPHPVersions

        $matchingVersions = $installedVersions | Where-Object -FilterScript { $_.Version -like "$version*" }

        return $matchingVersions
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check if PHP version $version is installed"; exception = $_ }
        return $null
    }
}

function Test-PHPVersionInstalled {
    param ($version)

    try {
        $installedVersions = Get-MatchingPHPVersions -version $version.version
        return ($installedVersions | Where-Object -FilterScript {
                $_.Version -eq $version.version -and
                $_.Arch -eq $version.arch -and
                $_.BuildType -eq $version.BuildType
            }
        )
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check if PHP version $version is installed"; exception = $_ }
        return $false
    }
}

function Get-SourceUrls {
    return [ordered]@{
        'Archives' = $PVMConfig.links.phpWinArchives
        'Releases' = $PVMConfig.links.phpWinReleases
    }
}

function Get-ZendExtensionsInfo {
    param ($phpPath)

    $extPath = "$phpPath\ext"
    if (Test-DirectoryNotExists -path $extPath) {
        return @()
    }

    # Check php.ini for enabled status
    $phpIniPath = "$phpPath\php.ini"
    $enabledStatus = @{}
    $zendExtensionsList = Get-ZendExtensionsList
    if (Test-FileExists -path $phpIniPath) {
        $iniContent = Get-ContentWrapper -path $phpIniPath
        foreach ($line in $iniContent) {
            $trimmed = $line.Trim()
            foreach ($zendExtensionItem in $zendExtensionsList) {
                if ($trimmed -match "^(;)?\s*zend_extension\s*=.*$zendExtensionItem.*$") {
                    $enabledStatus[$zendExtensionItem] = -not $trimmed.StartsWith(';')
                }
            }
        }
    }

    $zendExtensions = @()

    foreach ($name in $zendExtensionsList) {
        $dll = Get-ChildItemWrapper -path "$extPath\*$name*.dll" | Select-Object -First 1
        if ($dll) {
            $zendExtensions += @{
                Name      = $name
                Version   = $dll.VersionInfo.ProductVersion
                Copyright = if ($dll.VersionInfo.LegalCopyright) { $dll.VersionInfo.LegalCopyright } else { '' }
                Enabled   = if ($enabledStatus.ContainsKey($name)) { $enabledStatus[$name] } else { $false }
            }
        }
    }

    return $zendExtensions
}

function Get-PHPData {
    param ($PhpIniPath)

    $iniContent = Get-ContentWrapper -path $PhpIniPath

    $phpIniData = @{
        extensions = @()
        settings   = @()
    }

    foreach ($line in $iniContent) {
        # Match both enabled and commented lines
        if ($line -match '^\s*(;)?(zend_extension|extension)\s*=\s*"?([^";]+?)"?\s*(?:;.*)?$') {
            $rawPath = $matches[3]
            $extensionName = [System.IO.Path]::GetFileName($rawPath)
            $phpIniData.extensions += @{
                Section   = 'extension'
                Extension = $extensionName
                Type      = $matches[2] # extension or zend_extension
                Enabled   = -not $matches[1]
            }
        } elseif ($line -match '^\s*(;)?([A-Za-z0-9_.]+)\s*=\s*("?[^";]+?"?)\s*(?:;.*)?$') {
            $phpIniData.settings += @{
                Section = 'setting'
                Name    = $matches[2]   # e.g. memory_limit
                Type    = 'setting'
                Value   = $matches[3].Trim('"') # strip quotes if present
                Enabled = -not $matches[1]      # false if line starts with ;
            }
        }
    }

    return $phpIniData
}

function Test-PHPVersionFormat {
    param ($version)

    return $version -match '^\d+(\.\d+){0,2}$'
}
