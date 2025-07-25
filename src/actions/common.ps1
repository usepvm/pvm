

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


function Is-PHP-Installed {
    param ($version)

    Get-ChildItem -Path $PHP_VERSIONS_PATH -Directory | ForEach-Object {
        $split = $_.ToString().split("-")

        if ($split.Count -gt 1 -and $version -eq $split[1]) {
            return $true
        }
    }

    return $false
}
