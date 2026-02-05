

function Get-Source-Urls {

    return [ordered]@{
        "Archives" = $PHP_WIN_ARCHIVES_URL
        "Releases" = $PHP_WIN_RELEASES_URL
    }
}


function Is-PVM-Setup {

    try {
        $path = Get-EnvVar-ByName -name "Path"
        if ($null -eq $path) {
            $path = ''
        }

        $parent = Split-Path $PHP_CURRENT_VERSION_PATH
        $pathItems = $path -split ';'
        if (
            ($pathItems -notcontains $PVMRoot) -or
            ($pathItems -notcontains $PHP_CURRENT_VERSION_PATH) -or
            (-not (Test-Path $parent))
        ) {
            return $false
        }

        return $true
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to check if PVM is set up"
            exception = $_
        }
        return $false
    }
}

function Refresh-Installed-PHP-Versions-Cache {
    try {
        $installedVersions = Get-Installed-PHP-Versions-From-Directory
        $cached = Cache-Data -cacheFileName "installed_php_versions" -data $installedVersions -depth 1
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to refresh installed PHP versions cache"
            exception = $_
        }
        
        return -1
    }
}

function Get-Installed-PHP-Versions-From-Directory {
    $directories = Get-All-Subdirectories -path "$STORAGE_PATH\php"
    $installedVersions = $directories | ForEach-Object {
        if (Test-Path "$($_.FullName)\php.exe"){
            $phpInfo = Get-PHPInstallInfo -path $_.FullName
            
            return $phpInfo
        }
        return $null
    }

    $installedVersions = ($installedVersions | Sort-Object { [version]$_.Version })

    return $installedVersions
}

function Get-Installed-PHP-Versions {
    param ($arch = $null)
    try {
        $useCache = Can-Use-Cache -cacheFileName 'installed_php_versions'
        
        if ($useCache) {
            $installedVersions = Get-Data-From-Cache -cacheFileName "installed_php_versions"
            if (-not $installedVersions -or $installedVersions.Count -eq 0) {
                $installedVersions = Get-Installed-PHP-Versions-From-Directory
                $cached = Cache-Data -cacheFileName "installed_php_versions" -data $installedVersions -depth 1
            }
        } else {
            $installedVersions = Get-Installed-PHP-Versions-From-Directory
            $cached = Cache-Data -cacheFileName "installed_php_versions" -data $installedVersions -depth 1
        }
        
        if ($arch) {
            $installedVersions = $installedVersions | Where-Object { $_.Arch -eq $arch }
        }
        
        return $installedVersions
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve installed PHP versions"
            exception = $_
        }
        return @()
    }
}


function Get-UserSelected-PHP-Version {
    param($installedVersions)

    if (-not $installedVersions -or $installedVersions.Count -eq 0) {
        return $null
    }
    if ($installedVersions.Count -eq 1) {
        $version = $($installedVersions)
    } else {
        $currentVersion = Get-Current-PHP-Version
        if ($currentVersion -and $currentVersion.version) {
            $currentVersion = $currentVersion.version
        }
        Write-Host "`nInstalled versions :"
        $installedVersions | ForEach-Object {
            $versionNumber = $_
            $isCurrent = ""
            if (Is-Two-PHP-Versions-Equal -version1 $currentVersion -version2 $_) {
                $isCurrent = "(Current)"
            }
            Write-Host " - $versionNumber $isCurrent"
        }
        $response = Read-Host "`nEnter the exact version to use. (or press Enter to cancel)"
        $response = $response.Trim()
        if (-not $response) {
            return @{ code = -1; message = "Operation cancelled."; color = "DarkYellow"}
        }
        $version = $response
    }
    $phpPath = Get-PHP-Path-By-Version -version $version
    
    return @{ code = 0; version = $version; path = $phpPath }
}

function Get-Matching-PHP-Versions {
    param ($version)

    try {
        $installedVersions = Get-Installed-PHP-Versions

        $matchingVersions = $installedVersions | Where-Object { $_.Version -like "$version*" }
        
        return $matchingVersions
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to check if PHP version $version is installed"
            exception = $_
        }
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
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to check if PHP version $version is installed"
            exception = $_
        }
    }

    return $false
}
