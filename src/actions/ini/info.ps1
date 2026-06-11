
function Get-PHP-Info {
    param ($term = $null, $extensions = $false, $settings = $false)

    if (-not $extensions -and -not $settings) {
        $extensions = $true
        $settings = $true
    }

    $currentPHPVersion = Get-Current-PHP-Version

    if (-not $currentPHPVersion -or -not $currentPHPVersion.version -or -not $currentPHPVersion.path) {
        Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
        return -1
    }

    Write-Host "`n- Running PHP version`t: $($currentPHPVersion.version)"
    Write-Host "`n- PHP path`t`t: $($currentPHPVersion.path)"
    $phpIniData = Get-PHP-Data -PhpIniPath "$($currentPHPVersion.path)\php.ini"

    if ($extensions) {
        $extensions = $phpIniData.extensions | Where-Object { $_.Extension -like "*$term*" }
        Display-Extensions-States -extensions $phpIniData.extensions
        Display-Installed-Extensions -extensions $extensions
    }

    if ($settings) {
        $settings = $phpIniData.settings | Where-Object { $_.Name -like "*$term*" }
        Display-Settings-States -settings $phpIniData.settings
        Display-Settings -settings $settings
    }

    return 0
}
