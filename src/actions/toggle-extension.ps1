
function Toggle-PHP-Extension {
    param($extensionName)

    $currentPhpVersionPath = [System.Environment]::GetEnvironmentVariable($USER_ENV["PHP_CURRENT_ENV_NAME"], [System.EnvironmentVariableTarget]::Machine)
    if (-not $currentPhpVersionPath) {
        Write-Host "`nNo PHP version is currently set. Please use 'pvm use <version>' to set a version."
        return 1
    }
    
    $phpIniPath = "$currentPhpVersionPath\php.ini"
    if (-not (Test-Path $phpIniPath)) {
        Write-Host "`nphp.ini not found at: $phpIniPath"
        return 1
    }
    
    $iniContent = Get-Content $phpIniPath
    $newContent = @()
    $found = $false
    foreach ($line in $iniContent) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^(;)?\s*zend_extension\s*=.*$extensionName.*$") {
            if ($trimmed.StartsWith(';')) {
                $newContent += $trimmed.Substring(1)  # Remove the semicolon to enable
            } else {
                $newContent += ";$trimmed"  # Add a semicolon to disable
            }
            $found = $true
        } else {
            $newContent += $line
        }
    }
    if (-not $found) {
        Write-Host "`nExtension '$extensionName' not found in php.ini."
        return 1
    }
    Set-Content -Path $phpIniPath -Value $newContent
    
    return 0
}