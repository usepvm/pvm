
function Set-PHP-Env {
    param ($name, $value)

    try {
        $content = Get-EnvVar-ByName -name $value
        if ($content) {
            $output = Set-EnvVar -name $name -value $content
        } else {
            $output = Set-EnvVar -name $name -value $value
        }
        return @{ code = $output; message = "Environment variable '$name' set to '$value' at the system level."; color = "DarkGreen" }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-PHP-Env: Failed to set environment variable '$name'" -data $_.Exception.Message
        return @{ code = -1; message = "Failed to set environment variable '$name'"; color = "DarkYellow" }
    }
}
