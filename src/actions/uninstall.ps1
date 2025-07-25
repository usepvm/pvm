

function Uninstall-PHP {
    param ($version)

    try {
        $name = "php$version"
        $phpPath = [System.Environment]::GetEnvironmentVariable($name, [System.EnvironmentVariableTarget]::Machine)

        if (-not $phpPath) {
            return -2
        }

        Remove-Item -Path $phpPath -Recurse -Force
        [System.Environment]::SetEnvironmentVariable($name, $null, [System.EnvironmentVariableTarget]::Machine);
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Uninstall-PHP: Failed to uninstall PHP version '$version'" -data $_.Exception.Message
        return -1
    }
}
