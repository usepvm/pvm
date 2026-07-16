
function Get-PHP-Info {
    param ($term = $null, $extensions = $false, $settings = $false)

    if (-not $extensions -and -not $settings) {
        $extensions = $true
        $settings = $true
    }

    $currentPHPVersion = Get-Current-PHP-Version

    if (-not $currentPHPVersion -or -not $currentPHPVersion.version -or -not $currentPHPVersion.path) {
        Write-Host -Object "`nFailed to get current PHP version." -ForegroundColor DarkYellow
        return -1
    }

    Write-Host -Object "`n- Running PHP version`t: $($currentPHPVersion.version)"
    Write-Host -Object "`n- PHP path`t`t: $($currentPHPVersion.path)"

    $iniPath = "$($currentPHPVersion.path)\php.ini"

    if ($extensions) {
        $allExtensions = Get-All-PHPExtensionsStatus -iniPath $iniPath -includeIniOnly $true

        $filteredExtensions = if ($term) {
            Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $term -includeIniOnly $true
        } else {
            $allExtensions
        }
        Show-Extensions-States -extensions $allExtensions
        Show-Installed-Extensions -extensions $filteredExtensions
    }

    if ($settings) {
        $allSettings = Get-All-PHPSettings -iniPath $iniPath
        $filteredSettings = if ($term) {
            Get-Matching-PHPSettings -iniPath $iniPath -searchKey $term
        } else {
            $allSettings
        }
        Show-Settings-States -settings $allSettings
        Show-Settings -settings $filteredSettings
    }

    return 0
}
