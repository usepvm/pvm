
function Get-PHPInfo {
    param ($term = $null, $extensions = $false, $settings = $false)

    if (-not $extensions -and -not $settings) {
        $extensions = $true
        $settings = $true
    }

    $currentPHPVersion = Get-CurrentPHPVersion

    if (-not $currentPHPVersion -or -not $currentPHPVersion.version -or -not $currentPHPVersion.path) {
        Show-Error -Message "`nFailed to get current PHP version."
        return -1
    }

    Show-Message -message "`n- Running PHP version`t: $($currentPHPVersion.version)"
    Show-Message -message "`n- PHP path`t`t: $($currentPHPVersion.path)"

    $iniPath = "$($currentPHPVersion.path)\php.ini"

    if ($extensions) {
        $allExtensions = Get-AllPHPExtensionsStatus -iniPath $iniPath -includeIniOnly $true

        $filteredExtensions = if ($term) {
            Get-MatchingPHPExtensionsStatus -iniPath $iniPath -extName $term -includeIniOnly $true
        } else {
            $allExtensions
        }
        Show-ExtensionsStates -extensions $allExtensions
        Show-InstalledExtensions -extensions $filteredExtensions
    }

    if ($settings) {
        $allSettings = Get-AllPHPSettings -iniPath $iniPath
        $filteredSettings = if ($term) {
            Get-MatchingPHPSettings -iniPath $iniPath -searchKey $term
        } else {
            $allSettings
        }
        Show-SettingsStates -settings $allSettings
        Show-Settings -settings $filteredSettings
    }

    return 0
}
