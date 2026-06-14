
function Get-PHPInstallInfo {
    param ($path)

    $tsDll = Get-ChildItem -Path "$path\php*ts.dll" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'nts\.dll$' } |
        Select-Object -First 1

    if ($tsDll) {
        $buildType = 'TS'
        $dll = $tsDll
    }
    else {
        $dll = Get-ChildItem -Path "$path\php*.dll" |
            Where-Object { $_.Name -notmatch 'phpdbg' } |
            Select-Object -First 1
        $buildType = 'NTS'
    }

    if (-not $dll) {
        return $null
    }

    return @{
        Version      = $dll.VersionInfo.ProductVersion
        Arch         = Get-BinaryArchitecture-From-DLL -path $dll.FullName
        BuildType    = $buildType
        Dll          = $dll.Name
        InstallPath  = $path
    }
}

function Get-BinaryArchitecture-From-DLL {
    param ($path)

    if (Is-File-Not-Exists -path $path) {
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

function Is-Two-PHP-Versions-Equal {
    param ($version1, $version2)

    if ($null -eq $version1 -or $null -eq $version2) {
        return $false
    }

    return (($version1.version -eq $version2.version) -and
            ($version1.arch -eq $version2.arch) -and
            ($version1.buildType -eq $version2.buildType))
}

function Create-Zend-Extensions-List {
    try {
        $jsonContent = $DEFAULT_ZEND_EXTENSIONS | ConvertTo-Json -Depth 10
        Set-Content -Path $ZEND_EXTENSIONS_LIST_PATH -Value $jsonContent -Encoding UTF8

        return 0
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create zend extensions list"; exception = $_ }
        Write-Host -Object "`nFailed to create zend extensions list: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Get-Zend-Extensions-List {
    if (Is-File-Exists -path $ZEND_EXTENSIONS_LIST_PATH) {
        $data = (Get-Content -Path $ZEND_EXTENSIONS_LIST_PATH -Raw | ConvertFrom-Json)
        if ($null -ne $data -and $data.Count -gt 0) {
            return $data
        }
    }

    return $DEFAULT_ZEND_EXTENSIONS
}

function Refresh-Installed-PHP-Versions-Cache {
    try {
        $installedVersions = Get-Installed-PHP-Versions-From-Directory
        $cached = Cache-Data -cacheFileName 'installed_php_versions' -data $installedVersions -depth 1

        return 0
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to refresh installed PHP versions cache"; exception = $_ }

        return -1
    }
}

function Get-Installed-PHP-Versions-From-Directory {
    $directories = Get-All-Subdirectories -path "$STORAGE_PATH\php"
    $installedVersions = $directories | ForEach-Object {
        if (Is-File-Exists -path "$($_.FullName)\php.exe") {
            $phpInfo = Get-PHPInstallInfo -path $_.FullName

            return $phpInfo
        }
        return $null
    }

    $installedVersions = ($installedVersions | Sort-Object { [version]$_.Version })

    $cached = Cache-Data -cacheFileName 'installed_php_versions' -data $installedVersions -depth 1

    return $installedVersions
}

function Get-Installed-PHP-Versions {
    param ($arch = $null, $buildType = $null)

    try {
        $installedVersions = Get-OrUpdateCache -cacheFileName 'installed_php_versions' -depth 1 -compute {
            Get-Installed-PHP-Versions-From-Directory
        }

        if ($null -eq $installedVersions) {
            return @()
        }

        if ($arch) {
            $installedVersions = $installedVersions | Where-Object { $_.Arch -eq $arch }
        }

        if ($buildType) {
            $installedVersions = $installedVersions | Where-Object { $_.BuildType -eq $buildType }
        }

        $installedVersions = $installedVersions | Sort-Object { [version]$_.Version }

        return $installedVersions
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve installed PHP versions"; exception = $_ }
        return @()
    }
}

function Get-UserSelected-PHP-Version {
    param ($installedVersions)

    if (-not $installedVersions -or $installedVersions.Count -eq 0) {
        return $null
    }
    if ($installedVersions.Length -eq 1) {
        $versionObj = $($installedVersions)
    } else {
        $currentVersion = Get-Current-PHP-Version
        $index = 0
        Write-Host -Object "`nInstalled versions :"
        $installedVersions | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'index' -NotePropertyValue $index -Force
            $isCurrent = ''
            if (Is-Two-PHP-Versions-Equal -version1 $currentVersion -version2 $_) {
                $isCurrent = '(Current)'
            }
            $metaData = ''
            if ($_.Arch) {
                $metaData += $_.Arch + ' '
            }
            if ($_.BuildType) {
                $metaData += $_.BuildType
            }
            $versionNumber = "$($_.version) ".PadRight(15, '.')
            Write-Host -Object " [$index] $versionNumber $metaData $isCurrent"
            $index++
        }
        $response = Read-Host -Prompt "`nInsert the [number] of the version you want to use (or press Enter to cancel)"
        $response = $response.Trim()
        if (-not $response) {
            return @{ code = -1; message = 'Operation cancelled.'; color = 'DarkYellow'}
        }
        $versionObj = $installedVersions | Where-Object { $_.index -eq $response }
    }

    return @{ code = 0; version = $versionObj.version; arch = $versionObj.arch; buildType = $versionObj.BuildType; path = $versionObj.InstallPath }
}

function Get-Matching-PHP-Versions {
    param ($version)

    try {
        $installedVersions = Get-Installed-PHP-Versions

        $matchingVersions = $installedVersions | Where-Object { $_.Version -like "$version*" }

        return $matchingVersions
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check if PHP version $version is installed"; exception = $_ }
    }

    return $null
}

function Is-PHP-Version-Installed {
    param ($version)

    try {
        $installedVersions = Get-Matching-PHP-Versions -version $version.version
        return ($installedVersions | Where-Object {
            $_.Version -eq $version.version -and
            $_.Arch -eq $version.arch -and
            $_.BuildType -eq $version.BuildType
        })
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check if PHP version $version is installed"; exception = $_ }
    }

    return $false
}

function Get-Source-Urls {
    return [ordered]@{
        'Archives' = $PHP_WIN_ARCHIVES_URL
        'Releases' = $PHP_WIN_RELEASES_URL
    }
}

function Get-PHP-Data {
    param ($PhpIniPath)

    $iniContent = Get-Content -Path $PhpIniPath

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
                Section   = 'setting'
                Name      = $matches[2]   # e.g. memory_limit
                Type      = 'setting'
                Value     = $matches[3].Trim('"') # strip quotes if present
                Enabled   = -not $matches[1]      # false if line starts with ;
            }
        }
    }

    return $phpIniData
}
