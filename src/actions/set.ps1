
function Set-PHP-Env {
    param ($name, $value)

    try {
        $content = Get-EnvVar-ByName -name $value
        if ($content) {
            Set-EnvVar -name $name -value $content
        } else {
            Set-EnvVar -name $name -value $value
        }
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-PHP-Env: Failed to set environment variable '$name'" -data $_.Exception.Message
        return -1
    }
}
