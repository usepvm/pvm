

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


function Is-PHP-Version-Installed {
    param ($version)

    try {
        $installedVersions = Get-Installed-PHP-Versions  # You should have this function

        foreach ($v in $installedVersions) {
            if ($v -like "php$version*") {
                return $true
            }
        }
    }
    catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Is-PHP-Version-Installed: Failed to check if PHP version $version is installed" -data $_.Exception.Message
    }

    return $false
}
