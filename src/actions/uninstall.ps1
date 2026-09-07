
function Uninstall-PHP {
    param ($version, $skipConfirmation = $false)

    try {
        $installedVersions = Get-MatchingPHPVersions -version $version
        $pathVersionObject = Get-UserSelectedPHPVersion -installedVersions $installedVersions

        if (-not $pathVersionObject) {
            Show-Error -message "PHP version $version was not found!"
            return -1
        }

        if ($pathVersionObject.code -ne 0) {
            Write-Color -message $pathVersionObject.message -foreColor $pathVersionObject.color
            return -1
        }

        if (-not $skipConfirmation) {
            $response = Read-HostWrapper -prompt "`nAre you sure you want to delete PHP version '$($pathVersionObject.version)'? (y/n)" -notifyUser
            if (Test-NoResponse -response $response) {
                Write-Gray -message "`nUninstallation cancelled"
                return -1
            }

            $currentVersion = Get-CurrentPHPVersion
            if (Test-TwoPHPVersionsEqual -version1 $currentVersion -version2 $pathVersionObject) {
                $response = Read-HostWrapper -prompt "`nYou are trying to uninstall the currently active PHP version ($($pathVersionObject.version)). Are you sure? (y/n)" -notifyUser
                if (Test-NoResponse -response $response) {
                    Write-Gray -message 'Uninstallation cancelled'
                    return -1
                }
            }
        }

        Remove-ItemWrapper -path $pathVersionObject.path

        $null = Update-InstalledPHPVersionsCache

        Show-Success -message "PHP version $($pathVersionObject.version) has been uninstalled successfully"
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to uninstall PHP version '$version'"; exception = $_ }
        Show-Error -message "Failed to uninstall PHP version '$version'"
        return -1
    }
}
