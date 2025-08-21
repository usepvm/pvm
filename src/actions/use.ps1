function Detect-PHP-VersionFromProject {
    
    try {
        # 1. Check .php-version
        if (Test-Path ".php-version") {
            $version = Get-Content ".php-version" | Select-Object -First 1
            return $version.Trim()
        }

        # 2. Check composer.json
        if (Test-Path "composer.json") {
            try {
                $json = Get-Content "composer.json" -Raw | ConvertFrom-Json
                if ($json.require.php) {
                    $constraint = $json.require.php.Trim()
                    # Extract first PHP version number in the string (e.g. from "^8.3" or ">=8.1 <8.3")
                    if ($constraint -match "(\d+\.\d+(\.\d+)?)") {
                        return $matches[1]
                    }
                }
            } catch {
                Write-Host "`nFailed to parse composer.json: $_"
            }
        }
    } catch {
        
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name): Failed to detect PHP version from project"
            exception = $_
        }
    }

    return $null
}

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
            return @{ code = -1; message = "PHP version $variableValue was not found!"; color = "DarkYellow"}
        }
        
        if ($pathVersionObject.code -ne 0) {
            return $pathVersionObject
        }
        
        if (-not $pathVersionObject.path) {
            return @{ code = -1; message = "PHP version $($pathVersionObject.version) was not found!"; color = "DarkYellow"}
        }
        $linkCreated = Make-Symbolic-Link -link $PHP_CURRENT_VERSION_PATH -target $pathVersionObject.path
        if ($linkCreated.code -ne 0) {
            return $linkCreated
        }
        return @{ code = 0; message = "Now using PHP $($pathVersionObject.version)"; color = "DarkGreen"}
    } catch {
        
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name): Failed to update PHP version for '$variableName'"
            exception = $_
        }
        return @{ code = -1; message = "No matching PHP versions found for '$version', Use 'pvm list' to see installed versions."; color = "DarkYellow"}
    }
}

function Auto-Select-PHP-Version {
    
    $version = Detect-PHP-VersionFromProject
    
    if (-not $version) {
        return @{ code = -1; message = "Could not detect PHP version from .php-version or composer.json"; color = "DarkYellow"}
    }
    
    Write-Host "`nDetected PHP version from project: $version"
    
    $installedVersions = Get-Matching-PHP-Versions -version $version
    if (-not $installedVersions) {
        $message = "PHP '$version' is not installed."
        $message += "`nRun: pvm install $version"
        return @{ code = -1; message = $message; }
    }
    
    return @{ code = 0; version = $version; }
}