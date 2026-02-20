

function Uninstall-PHP {
    param ($version)

    try {
        
        $installedVersions = Get-Matching-PHP-Versions -version $version
        $pathVersionObject = Get-UserSelected-PHP-Version -installedVersions $installedVersions

        if (-not $pathVersionObject) {
            return @{ code = -1; message = "PHP version $version was not found!"; color = "DarkYellow"}
        }
        
        if ($pathVersionObject.code -ne 0) {
            return $pathVersionObject
        }
        
        $currentVersion = Get-Current-PHP-Version
        if (Is-Two-PHP-Versions-Equal -version1 $currentVersion -version2 $pathVersionObject) {
            $response = Read-Host "`nYou are trying to uninstall the currently active PHP version ($($pathVersionObject.version)). Are you sure? (y/n)"
            $response = $response.Trim()
            if ($response -ne "y" -and $response -ne "Y") {
                return @{ code = -1; message = "Uninstallation cancelled"}
            }
        }

        Remove-Item -Path ($pathVersionObject.path) -Recurse -Force
        
        $cacheRefreshed = Refresh-Installed-PHP-Versions-Cache
        
        return @{ code = 0; message = "PHP version $($pathVersionObject.version) has been uninstalled successfully"; color = "DarkGreen" }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to uninstall PHP version '$version'"
            exception = $_
        }
        return @{ code = -1; message = "Failed to uninstall PHP version '$version'"; color = "DarkYellow" }
    }
}
