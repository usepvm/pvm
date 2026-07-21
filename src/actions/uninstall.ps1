
function Uninstall-PHP {
    param ($version, $skipConfirmation = $false)

    try {
        $installedVersions = Get-MatchingPHPVersions -version $version
        $pathVersionObject = Get-UserSelectedPHPVersion -installedVersions $installedVersions

        if (-not $pathVersionObject) {
            return @{ code = -1; message = "PHP version $version was not found!"; color = 'DarkYellow' }
        }

        if ($pathVersionObject.code -ne 0) {
            return $pathVersionObject
        }

        if (-not $skipConfirmation) {
            $response = Read-Host -Prompt "`nAre you sure you want to delete PHP version '$($pathVersionObject.version)'? (y/n)"
            $response = $response.Trim()
            if (Test-NoResponse -response $response) {
                return @{ code = -1; message = 'Uninstallation cancelled'; color = 'Gray' }
            }

            $currentVersion = Get-CurrentPHPVersion
            if (Test-TwoPHPVersionsEqual -version1 $currentVersion -version2 $pathVersionObject) {
                $response = Read-Host -Prompt "`nYou are trying to uninstall the currently active PHP version ($($pathVersionObject.version)). Are you sure? (y/n)"
                $response = $response.Trim()
                if (Test-NoResponse -response $response) {
                    return @{ code = -1; message = 'Uninstallation cancelled'; color = 'Gray' }
                }
            }
        }

        Remove-Item -Path ($pathVersionObject.path) -Recurse -Force

        $null = Update-InstalledPHPVersionsCache

        return @{ code = 0; message = "PHP version $($pathVersionObject.version) has been uninstalled successfully"; color = 'DarkGreen' }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to uninstall PHP version '$version'"; exception = $_ }
        return @{ code = -1; message = "Failed to uninstall PHP version '$version'"; color = 'DarkYellow' }
    }
}
