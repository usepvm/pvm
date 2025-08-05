

function Uninstall-PHP {
    param ($version)

    try {
        $name = "php$version"
        $phpPath = Get-EnvVar-ByName -name $name

        if (-not $phpPath) {
            return @{ code = -1; message = "PHP version '$version' is not installed."; color = "DarkYellow" }
        }

        $currentVersion = (Get-Current-PHP-Version).version
        if ($currentVersion -and ($version -eq $currentVersion)) {
            $output = Set-EnvVar -name $PHP_CURRENT_ENV_NAME -value 'null'
        }

        Remove-Item -Path $phpPath -Recurse -Force
        $output = Set-EnvVar -name $name -value $null
        
        return @{ code = $output; message = "PHP version $version has been uninstalled successfully"; color = "DarkGreen" }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Uninstall-PHP: Failed to uninstall PHP version '$version'" -data $_.Exception.Message
        return @{ code = -1; message = "Failed to uninstall PHP version '$version'"; color = "DarkYellow" }
    }
}
