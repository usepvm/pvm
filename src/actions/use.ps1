
function Find-PHPVersionFromProject {
    try {
        # 1. Check .php-version
        if (Test-FileExists -path '.php-version') {
            $version = (Get-ContentWrapper -path '.php-version' | Select-Object -First 1).Trim()
            if (Test-PHPVersionFormat -version $version) {
                return $version
            }
            Show-Error -message "`nInvalid version '$version' in .php-version"
        }

        # 2. Check composer.json
        if (Test-FileExists -path 'composer.json') {
            try {
                $json = Get-ContentWrapper -path 'composer.json' -raw | ConvertFrom-Json
                if ($json.require.php -and $json.require.php.Trim() -match '(\d+(\.\d+(\.\d+)?)?)') {
                    return $matches[1]
                }
            } catch {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to parse composer.json"; exception = $_ }
                Show-Error -message "`nFailed to parse composer.json: $_"
                throw $_
            }
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to detect PHP version from project"; exception = $_ }
    }

    return $null
}

function Update-PHPVersion {
    param ($version)

    try {
        $installedVersions = Get-MatchingPHPVersions -version $version
        $pathVersionObject = Get-UserSelectedPHPVersion -installedVersions $installedVersions

        if (-not $pathVersionObject) {
            Show-Error -message "PHP version $version was not found!"
            return -1
        }

        if ($pathVersionObject.code -ne 0) {
            return $pathVersionObject
        }

        $currentVersion = Get-CurrentPHPVersion
        if ($currentVersion -and $currentVersion.version) {
            if (Test-TwoPHPVersionsEqual -version1 $currentVersion -version2 $pathVersionObject) {
                Show-Info -message "Already using PHP $($pathVersionObject.version)"
                return 0
            }
        }

        $linkCreated = New-SymbolicLink -link $PVMConfig.env.PHP_CURRENT_VERSION_PATH -target $pathVersionObject.path
        if ($linkCreated.code -ne 0) {
            Write-Color -message $linkCreated.message -foreColor $linkCreated.color
            return -1
        }
        $text = ("Now using PHP $($pathVersionObject.version) $($pathVersionObject.buildType) $($pathVersionObject.arch)").Trim()

        Show-Success -message $text
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to update PHP version to '$version'"; exception = $_ }
        Show-Error -message "No matching PHP versions found for '$version', Use 'pvm list' to see installed versions."
        return -1
    }
}

function Select-PHPVersionAutomatically {
    $version = Find-PHPVersionFromProject

    if (-not $version) {
        $version = Read-HostWrapper -prompt "`nCould not detect PHP version. Enter a version to use (e.g. 8.3 or 8.3.1)" -notifyUser

        if (-not (Test-PHPVersionFormat -version $version)) {
            return @{ code = -1; message = "Invalid version format: '$version'. Expected e.g. 8, 8.3 or 8.3.1"; color = 'DarkYellow' }
        }

        $response = Read-HostWrapper -prompt "`nSave as project default in .php-version? (y/n)"
        if (Test-YesResponse -response $response) {
            Set-ContentWrapper -path '.php-version' -value $version
        }
    }

    Show-Message -message "`nUsing PHP version: $version"

    $installedVersions = Get-MatchingPHPVersions -version $version
    if (-not $installedVersions) {
        $message = "PHP '$version' is not installed."
        $message += "`nRun: pvm install $version"
        return @{ code = -1; version = $version; message = $message; }
    }

    return @{ code = 0; version = $version }
}
