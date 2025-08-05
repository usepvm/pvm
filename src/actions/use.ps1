
function Get-UserSelected-PHP-Version {
    if (-not $installedVersions) {
        return $null
    }
    if ($installedVersions.Count -eq 1) {
        $variableValue = $installedVersions
    } else {
        Write-Host "`nInstalled versions :"
        $installedVersions | ForEach-Object { Write-Host " - $_" }
        $response = Read-Host "`nEnter the exact version to use. (or press Enter to cancel)"
        if (-not $response) {
            return @{ code = -1; message = "Operation cancelled."; color = "DarkYellow"}
        }
        $variableValue = $response
    }
    $variableValueContent = Get-EnvVar-ByName -name "php$variableValue"
    
    return @{ name = $variableValue; value = $variableValueContent }
}

function Update-PHP-Version {
    param ($variableName, $variableValue)

    try {
        $variableValueContent = Get-EnvVar-ByName -name "php$variableValue"
        if (-not $variableValueContent) {
            $installedVersions = Get-Matching-PHP-Versions -version $variableValue
            $variableValueContent = Get-UserSelected-PHP-Version -installedVersions $installedVersions
        }
        if (-not $variableValueContent) {
            return @{ code = -1; message = "Version $variableValue was not found!"; color = "DarkYellow"}
        }
        $output = Set-EnvVar -name $variableName -value $variableValueContent
        return @{ code = $output; message = "Now using PHP $variableValue"; color = "DarkGreen"}
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
    
    if (-not $selectedVersion.value) {
        return @{ code = -1; message = "Version $($selectedVersion.name) was not found!"; color = "DarkYellow" }
    }

    return @{ code = 0; version = $selectedVersion.name}
}