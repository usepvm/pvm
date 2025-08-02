

function Uninstall-PHP {
    param ($version)

    try {
        $name = "php$version"
        $phpPath = Get-EnvVar-ByName -name $name

        if (-not $phpPath) {
            return -2
        }

        $currentVersion = (Get-Current-PHP-Version).version
        if ($currentVersion -and ($version -eq $currentVersion)) {
            $output = Set-EnvVar -name $PHP_CURRENT_ENV_NAME -value 'null'
        }

        Remove-Item -Path $phpPath -Recurse -Force
        return Set-EnvVar -name $name -value $null
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Uninstall-PHP: Failed to uninstall PHP version '$version'" -data $_.Exception.Message
        return -1
    }
}
