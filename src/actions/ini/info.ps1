
function Get-PHP-Info {
    param ($term = $null, $extensions = $false, $settings = $false)

    if (-not $extensions -and -not $settings) {
        $extensions = $true
        $settings = $true
    }

    $currentPHPVersion = Get-Current-PHP-Version

    if (-not $currentPHPVersion -or -not $currentPHPVersion.version -or -not $currentPHPVersion.path) {
        Print-Error -Message "`nFailed to get current PHP version."
        return -1
    }

    Print-Message -message "`n- Running PHP version`t: $($currentPHPVersion.version)"
    Print-Message -message "`n- PHP path`t`t: $($currentPHPVersion.path)"

    $iniPath = "$($currentPHPVersion.path)\php.ini"

    if ($extensions) {
        $allExtensions = Get-All-PHPExtensionsStatus -iniPath $iniPath -includeIniOnly $true

        $filteredExtensions = if ($term) {
            Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $term -includeIniOnly $true
        } else {
            $allExtensions
        }
        Display-Extensions-States -extensions $allExtensions
        Display-Installed-Extensions -extensions $filteredExtensions
    }

    if ($settings) {
        $allSettings = Get-All-PHPSettings -iniPath $iniPath
        $filteredSettings = if ($term) {
            Get-Matching-PHPSettings -iniPath $iniPath -searchKey $term
        } else {
            $allSettings
        }
        Display-Settings-States -settings $allSettings
        Display-Settings -settings $filteredSettings
    }

    return 0
}
