
function Update-PHPVersion {
    param ($version)

    try {
        $installedVersions = Get-MatchingPHPVersions -version $version
        $pathVersionObject = Get-UserSelectedPHPVersion -installedVersions $installedVersions

        if (-not $pathVersionObject) {
            Show-Error -message "`nPHP version $version was not found!"
            return -1
        }

        if ($pathVersionObject.code -ne 0) {
            Write-Gray -message $pathVersionObject.message
            return -1
        }

        $currentVersion = Get-CurrentPHPVersion
        if ($currentVersion -and $currentVersion.version) {
            if (Test-TwoPHPVersionsEqual -version1 $currentVersion -version2 $pathVersionObject) {
                Show-Info -message "`nAlready using PHP $($pathVersionObject.version)"
                return 0
            }
        }

        $linkCreated = New-SymbolicLink -link $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH -target $pathVersionObject.path
        if ($linkCreated.code -ne 0) {
            Write-Color -message $linkCreated.message -foreColor $linkCreated.color
            return -1
        }
        $text = ("Now using PHP $($pathVersionObject.version) $($pathVersionObject.buildType) $($pathVersionObject.arch)").Trim()
        Show-Success -message "`n$text"

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to update PHP version to '$version'"; exception = $_ }
        Show-Error -message "`nNo matching PHP versions found for '$version', Use 'pvm list' to see installed versions."
        return -1
    }
}
