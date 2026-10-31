
function Uninstall-PHP {
    param ($version, $skipConfirmation = $false)

    try {
        $installedVersions = Get-MatchingPHPVersions -version $version
        $pathVersionObject = Get-UserSelectedPHPVersion -installedVersions $installedVersions

        if (-not $pathVersionObject) {
            Show-LabelledError -message "PHP version $version was not found!"
            return -1
        }

        if ($pathVersionObject.code -ne 0) {
            Show-LabelledError -message $pathVersionObject.message
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
                    Write-Gray -message "`nUninstallation cancelled"
                    return -1
                }
            }
        }

        $code = Remove-ItemWrapper -path $pathVersionObject.path
        if ($code -ne 0) {
            Show-LabelledError -message "Failed to remove PHP version $($pathVersionObject.version)!"
            return -1
        }

        $null = Update-InstalledPHPVersionsCache

        Show-LabelledSuccess -message "PHP version $($pathVersionObject.version) has been uninstalled successfully"
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to uninstall PHP version '$version'"; exception = $_ }
        Show-LabelledError -message "Failed to uninstall PHP version '$version'"
        return -1
    }
}
