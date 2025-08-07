

function Update-PHP-Version {
    param ($variableName, $variableValue)

    try {
        $phpPath = Get-PHP-Path-By-Version -version $variableValue
        if (-not $phpPath) {
            $installedVersions = Get-Matching-PHP-Versions -version $variableValue
            $pathVersionObject = Get-UserSelected-PHP-Version -installedVersions $installedVersions
        } else {
            $pathVersionObject = @{ code = 0; version = $variableValue; path = $phpPath }
        }
        
        if (-not $pathVersionObject) {
            return @{ code = -1; message = "Version $variableValue was not found!"; color = "DarkYellow"}
        }
        
        if ($pathVersionObject.code -ne 0) {
            return $pathVersionObject
        }
        
        if (-not $pathVersionObject.path) {
            return @{ code = -1; message = "Version $($pathVersionObject.version) was not found!"; color = "DarkYellow"}
        }
        Make-Symbolic-Link -link $PHP_CURRENT_VERSION_PATH -target $pathVersionObject.path
        return @{ code = $output; message = "Now using PHP $($pathVersionObject.version)"; color = "DarkGreen"}
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Update-PHP-Version: Failed to update PHP version for '$variableName'" -data $_.Exception.Message
        return @{ code = -1; message = "No matching PHP versions found for '$version', Use 'pvm list' to see installed versions."; color = "DarkYellow"}
    }
}

function Auto-Select-PHP-Version {
    param ($version)
    
    $version = Detect-PHP-VersionFromProject
    
    if (-not $version) {
        return @{ code = -1; message = "Could not detect PHP version from .php-version or composer.json"; color = "DarkYellow"}
    }
    
    Write-Host "`nDetected PHP version from project: $version"
    
    $installedVersions = Get-Matching-PHP-Versions -version $version
    if (-not $installedVersions) {
        $message = "Detected PHP version '$version' from project, but it is not installed."
        $message += "`nRun: pvm install $version"
        return @{ code = -1; message = $message; }
    }
    
    $selectedVersion = Get-UserSelected-PHP-Version -installedVersions $installedVersions
    
    if ($selectedVersion.code -ne 0) {
        return @{ code = -1; message = "Version $($selectedVersion.name) was not found!"; color = "DarkYellow" }
    }    

    return $selectedVersion
}