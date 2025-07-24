

function Get-Source-Urls {

    return [ordered]@{
        "Archives" = "https://windows.php.net/downloads/releases/archives"
        "Releases" = "https://windows.php.net/downloads/releases"
    }
}


function Is-PVM-Setup {

    try {
        $phpEnvName = $PHP_CURRENT_ENV_NAME
        $path = [Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
        $phpEnvValue = [Environment]::GetEnvironmentVariable($phpEnvName, [System.EnvironmentVariableTarget]::Machine)
        $pvmPath = [Environment]::GetEnvironmentVariable("pvm", [System.EnvironmentVariableTarget]::Machine)
        
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