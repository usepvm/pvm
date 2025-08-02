

function Get-Source-Urls {

    return [ordered]@{
        "Archives" = "https://windows.php.net/downloads/releases/archives"
        "Releases" = "https://windows.php.net/downloads/releases"
    }
}


function Is-PVM-Setup {

    try {
        $phpEnvName = $PHP_CURRENT_ENV_NAME
        $path = Get-EnvVar-ByName -name "Path"
        $phpEnvValue = Get-EnvVar-ByName -name $phpEnvName
        $pvmPath = Get-EnvVar-ByName -name "pvm"

        if (
            (($pvmPath -eq $null) -or
                (($path -notlike "*$pvmPath*") -and
                ($path -notlike "*pvm*"))) -or
            (($phpEnvValue -eq $null) -or
                (($path -notlike "*$phpEnvValue*") -and
                ($path -notlike "*$phpEnvName*")))
        ) {
            return $false
        }

        return $true;
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Is-PVM-Setup: Failed to check if PVM is set up" -data $_.Exception.Message
        return $false
    }
}

function Get-Installed-PHP-Versions {
    
    try {
        $envVars = Get-All-EnvVars
        return $envVars.Keys | Where-Object { $_ -match "php\d(\.\d+)*" } | Sort-Object { [version](($_ -replace 'php', '') + '.0') }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Installed-PHP-Versions: Failed to retrieve installed PHP versions" -data $_.Exception.Message
        return @()
    }
}



function Get-Matching-PHP-Versions {
    param ($version)

    try {
        $installedVersions = Get-Installed-PHP-Versions  # You should have this function

        $matchingVersions = @()
        foreach ($v in $installedVersions) {
            if ($v -like "php$version*") {
                $matchingVersions += ($v -replace 'php', '')
            }
        }

        return $matchingVersions
    }
    catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-Matching-PHP-Versions: Failed to check if PHP version $version is installed" -data $_.Exception.Message
    }

    return $null
}

function Is-PHP-Version-Installed {
    param ($version)

    try {
        $installedVersions = Get-Matching-PHP-Versions -version $version
        return ($installedVersions -contains $version)
    }
    catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Is-PHP-Version-Installed: Failed to check if PHP version $version is installed" -data $_.Exception.Message
    }

    return $false
}
