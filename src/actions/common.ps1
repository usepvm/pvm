

function Get-Source-Urls {

    return [ordered]@{
        "Archives" = "https://windows.php.net/downloads/releases/archives"
        "Releases" = "https://windows.php.net/downloads/releases"
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

function Get-Installed-PHP-Versions {
    
    try {
        $directories = Get-All-Subdirectories -path "$STORAGE_PATH\php"
        $names = $directories | ForEach-Object {
            if (Test-Path "$($_.FullName)\php.exe"){
                return $_.Name
            }
            return $null
        }
        return ($names | Sort-Object { [version]$_ })        
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
            if ($currentVersion -eq $versionNumber) {
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
        $installedVersions = Get-Installed-PHP-Versions  # You should have this function

        $matchingVersions = @()
        foreach ($v in $installedVersions) {
            if ($v -like "$version*") {
                $matchingVersions += ($v -replace 'php', '')
            }
        }

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
        $installedVersions = Get-Matching-PHP-Versions -version $version
        return ($installedVersions -contains $version)
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to check if PHP version $version is installed"
            exception = $_
        }
    }

    return $false
}
