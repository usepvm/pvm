

function Uninstall-PHP {
    param ($version)

    try {
        $name = "php$version"
        $phpPath = Get-EnvVar-ByName -name $name

        if (-not $phpPath) {
            return -2
        }

        Remove-Item -Path $phpPath -Recurse -Force
        Set-EnvVar -name $name -value $null
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Uninstall-PHP: Failed to uninstall PHP version '$version'" -data $_.Exception.Message
        return -1
    }
}
