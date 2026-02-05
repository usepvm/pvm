
function Get-PHP-Status {
    param($phpPath)
    
    $status = @{ opcache = $false; xdebug = $false }
    try {
        $phpIniPath = "$phpPath\php.ini"
        if (-not (Test-Path $phpIniPath)) {
            return $status
        }

        $iniContent = Get-Content $phpIniPath
        
        foreach ($line in $iniContent) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^(;)?\s*zend_extension\s*=.*opcache.*$') {
                $status.opcache = -not $trimmed.StartsWith(';')
            }

            if ($trimmed -match '^(;)?\s*zend_extension\s*=.*xdebug.*$') {
                $status.xdebug = -not $trimmed.StartsWith(';')
            }
        }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve PHP status"
            exception = $_
        }
        Write-Host "An error occurred while checking PHP status: $_"
    }
    
    return $status
}

function Get-Current-PHP-Version {

    try {
        $emptyResult = @{ version = $null; path = $null; status = @{ opcache = $false; xdebug = $false } }
        $currentPhpVersionPath = Get-Item $PHP_CURRENT_VERSION_PATH
        if (-not $currentPhpVersionPath) {
            return $emptyResult
        }

        $currentPhpVersionPath = $currentPhpVersionPath.Target
        if (-not (Is-Directory-Exists -path $currentPhpVersionPath)) {
            return $emptyResult
        }
        $phpInfo = Get-PHPInstallInfo -path $currentPhpVersionPath
        
        return @{
            version = $phpInfo.Version
            arch = $phpInfo.Arch
            buildType = $phpInfo.BuildType
            path = $phpInfo.InstallPath
            status = Get-PHP-Status -phpPath $currentPhpVersionPath
        }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve current PHP version"
            exception = $_
        }
        return $emptyResult
    }
}