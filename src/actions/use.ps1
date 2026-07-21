
function Find-PHPVersionFromProject {
    try {
        # 1. Check .php-version
        if (Test-FileExists -path '.php-version') {
            $version = (Get-Content -Path '.php-version' | Select-Object -First 1).Trim()
            if (Test-PHPVersionFormat -version $version) {
                return $version
            }
            Show-Error -message "`nInvalid version '$version' in .php-version"
        }

        # 2. Check composer.json
        if (Test-FileExists -path 'composer.json') {
            try {
                $json = Get-Content -Path 'composer.json' -Raw | ConvertFrom-Json
                if ($json.require.php -and $json.require.php.Trim() -match '(\d+(\.\d+(\.\d+)?)?)') {
                    return $matches[1]
                }
            } catch {
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
            return @{ code = -1; message = "PHP version $version was not found!"; color = 'DarkYellow' }
        }

        if ($pathVersionObject.code -ne 0) {
            return $pathVersionObject
        }

        $currentVersion = Get-CurrentPHPVersion
        if ($currentVersion -and $currentVersion.version) {
            if (Test-TwoPHPVersionsEqual -version1 $currentVersion -version2 $pathVersionObject) {
                return @{ code = 0; message = "Already using PHP $($pathVersionObject.version)"; color = 'DarkCyan' }
            }
        }

        $linkCreated = New-SymbolicLink -link $PVMConfig.env.PHP_CURRENT_VERSION_PATH -target $pathVersionObject.path
        if ($linkCreated.code -ne 0) {
            return $linkCreated
        }
        $text = ("Now using PHP $($pathVersionObject.version) $($pathVersionObject.buildType) $($pathVersionObject.arch)").Trim()

        return @{ code = 0; message = $text; color = 'DarkGreen' }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to update PHP version to '$version'"; exception = $_ }
        return @{ code = -1; message = "No matching PHP versions found for '$version', Use 'pvm list' to see installed versions."; color = 'DarkYellow' }
    }
}

function Select-PHPVersionAutomatically {
    $version = Find-PHPVersionFromProject

    if (-not $version) {
        $version = Read-Host -Prompt "`nCould not detect PHP version. Enter a version to use (e.g. 8.3 or 8.3.1)"

        if (-not (Test-PHPVersionFormat -version $version)) {
            return @{ code = -1; message = "Invalid version format: '$version'. Expected e.g. 8, 8.3 or 8.3.1"; color = 'DarkYellow' }
        }

        $response = Read-Host -Prompt "`nSave as project default in .php-version? (y/n)"
        $response = $response.Trim()
        if (Test-YesResponse -response $response) {
            Set-Content-Wrapper -path '.php-version' -value $version
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
