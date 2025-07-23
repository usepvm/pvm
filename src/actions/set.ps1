
function Set-PHP-Env {
    param ($name, $value)

    try {
        $content = [System.Environment]::GetEnvironmentVariable($value, [System.EnvironmentVariableTarget]::Machine)
        if ($content) {
            [System.Environment]::SetEnvironmentVariable($name, $content, [System.EnvironmentVariableTarget]::Machine)
        } else {
            [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Machine)
        }
        return 0;
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-PHP-Env: Failed to set environment variable '$name'" -data $_.Exception.Message
        return -1;
    }
}
