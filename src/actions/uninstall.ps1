

function Uninstall-PHP {
    param ($version)

    try {
        
        $currentVersion = Get-Current-PHP-Version
        if ($currentVersion -and ($version -eq $currentVersion.version)) {
            Read-Host "`nYou are trying to uninstall the currently active PHP version ($version). Press Enter to continue or Ctrl+C to cancel."
            Remove-Item -Path $PHP_CURRENT_VERSION_PATH
        }
        
        $phpPath = Get-PHP-Path-By-Version -version $version

        if (-not $phpPath) {
            $installedVersions = Get-Matching-PHP-Versions -version $version
            $pathVersionObject = Get-UserSelected-PHP-Version -installedVersions $installedVersions
        } else {
            $pathVersionObject = @{ code = 0; version = $variableValue; path = $phpPath }
        }
        
        if (-not $pathVersionObject) {
            return @{ code = -1; message = "PHP version $version was not found!"; color = "DarkYellow"}
        }
        
        if ($pathVersionObject.code -ne 0) {
            return $pathVersionObject
        }
        
        if (-not $pathVersionObject.path) {
            return @{ code = -1; message = "PHP version $($pathVersionObject.version) was not found!"; color = "DarkYellow"}
        }

        Remove-Item -Path ($pathVersionObject.path) -Recurse -Force
        
        return @{ code = 0; message = "PHP version $version has been uninstalled successfully"; color = "DarkGreen" }
    } catch {
        
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to uninstall PHP version '$version'"
            exception = $_
        }
        return @{ code = -1; message = "Failed to uninstall PHP version '$version'"; color = "DarkYellow" }
    }
}
