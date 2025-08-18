

function Get-Source-Urls {

    return [ordered]@{
        "Archives" = "https://windows.php.net/downloads/releases/archives"
        "Releases" = "https://windows.php.net/downloads/releases"
    }
}


function Is-PVM-Setup {

    try {
        $path = Get-EnvVar-ByName -name "Path"
        $phpEnvValue = Get-EnvVar-ByName -name $PHP_CURRENT_ENV_NAME
        $pvmPath = Get-EnvVar-ByName -name "pvm"

        $parent = Split-Path $PHP_CURRENT_VERSION_PATH
        $pathItems = $path -split ';'
        if (
            (
                ($null -eq $pvmPath) -or
                (($pathItems -notcontains $pvmPath) -and
                ($pathItems -notcontains "%pvm%"))
            ) -or
            (
                ($null -eq $phpEnvValue) -or
                (($pathItems -notcontains $phpEnvValue) -and
                ($pathItems -notcontains "%$PHP_CURRENT_ENV_NAME%"))
            ) -or 
            (-not (Test-Path $parent))
        ) {
            return $false
        }

        return $true
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Is-PVM-Setup: Failed to check if PVM is set up" -data $_.Exception.Message
        return $false
    }
}

function Get-Installed-PHP-Versions {
    
    try {
        $directories = Get-All-Subdirectories -path "$STORAGE_PATH\php"
        $names = $directories | ForEach-Object { $_.Name }
        return ($names | Sort-Object { [version]$_ })        
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Installed-PHP-Versions: Failed to retrieve installed PHP versions" -data $_.Exception.Message
        return @()
    }
}


function Get-UserSelected-PHP-Version {
    if (-not $installedVersions) {
        return $null
    }
    if ($installedVersions.Count -eq 1) {
        $version = $installedVersions
    } else {
        Write-Host "`nInstalled versions :"
        $installedVersions | ForEach-Object { Write-Host " - $_" }
        $response = Read-Host "`nEnter the exact version to use. (or press Enter to cancel)"
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Matching-PHP-Versions: Failed to check if PHP version $version is installed" -data $_.Exception.Message
    }

    return $null
}

function Is-PHP-Version-Installed {
    param ($version)

    try {
        $installedVersions = Get-Matching-PHP-Versions -version $version
        return ($installedVersions -contains $version)
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Is-PHP-Version-Installed: Failed to check if PHP version $version is installed" -data $_.Exception.Message
    }

    return $false
}
