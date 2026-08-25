
function Get-PHPStatus {
    param ($phpPath, $version = $null)

    try {
        $status = @()
        $phpIniPath = "$phpPath\php.ini"
        if (Test-FileNotExists -path $phpIniPath) {
            return $status
        }

        if ($version -like '8.5*') {
            $status += @{ name = 'Zend OPcache'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
        } else {
            $opcacheData = Get-MatchingPHPExtensionsStatus -iniPath $phpIniPath -extName 'opcache'
            $status += if ($opcacheData) { $opcacheData.name = 'Zend OPcache'; $opcacheData } else { @{ name = 'Zend OPcache'; color = 'DarkGray'; text = 'Not Found' } }
        }

        $xdebugData = Get-MatchingPHPExtensionsStatus -iniPath $phpIniPath -extName 'xdebug'
        $status += if ($xdebugData) { $xdebugData.name = 'Xdebug'; $xdebugData } else { @{ name = 'Xdebug'; color = 'DarkGray'; text = 'Not Found' } }

        return $status
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve PHP status"; exception = $_ }
        Show-Error -message "An error occurred while checking PHP status: $_"
        return @()
    }
}

function Get-CurrentPHPVersion {
    try {
        $emptyResult = @{
            version = $null; path = $null;
            status = @(
                @{ Name = 'opcache'; Version = $null; Copyright = $null; Enabled = $false }
                @{ Name = 'xdebug'; Version = $null; Copyright = $null; Enabled = $false }
            )
        }
        $currentPhpVersionLink = Get-ItemWrapper -path $PVMConfig.env.PHP_CURRENT_VERSION_PATH
        if (-not $currentPhpVersionLink) {
            return $emptyResult
        }

        $currentPhpVersionPath = $currentPhpVersionLink.Target
        if (Test-DirectoryNotExists -path $currentPhpVersionPath) {
            return $emptyResult
        }
        $phpInfo = Get-PHPInstallInfo -path $currentPhpVersionPath

        return @{
            version   = $phpInfo.Version
            arch      = $phpInfo.Arch
            buildType = $phpInfo.BuildType
            path      = $phpInfo.InstallPath
            link      = $currentPhpVersionLink.FullName
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve current PHP version"; exception = $_ }
        return $emptyResult
    }
}
