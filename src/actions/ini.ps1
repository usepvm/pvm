
function Add-Missing-PHPExtension {
    param ($iniPath, $extName, $enable = $true)
    
    try {
        $phpCurrentVersion = Get-Current-PHP-Version
        if (-not $phpCurrentVersion -or -not $phpCurrentVersion.version) {
            Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }
        
        $iniContent = Get-Content $iniPath
        Backup-IniFile $iniPath
        
        if ($extName -like "*xdebug*") {
            $xdebugConfigured = Config-XDebug -version $phpCurrentVersion.version -phpPath $phpCurrentVersion.path
        } else {
            $extName = $extName -replace '^php_', '' -replace '\.dll$', ''
            if ([version]$phpCurrentVersion.version -lt $PhpNewExtensionNamingSince) {
                $extName = "php_$extName.dll"
            }
            
            $lines = Get-Content $iniPath
            $enabled = if ($enable) { '' } else { ';' }
            if ($extName -like "*opcache*") {
                $lines += "`n$enabled zend_extension=$extName"
            } else {
                $lines += "`n$enabled extension=$extName"
            }
            Set-Content $iniPath $lines -Encoding UTF8
            Write-Host "- '$extName' added successfully." -ForegroundColor DarkGreen
        }
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to add extension '$extName'"
            exception = $_
        }
        return -1
    }
    
}

function Get-Single-PHPExtensionStatus {
    param ($iniPath, $extName)
    
    $enabledPattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"
    $disabledPattern = "^\s*;\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"
    $lines = Get-Content $iniPath

    foreach ($line in $lines) {
        if ($line -match $enabledPattern) {
            return @{ status = "Enabled"; color = "DarkGreen" }
        }
        if ($line -match $disabledPattern) {
            return @{ status = "Disabled"; color = "DarkYellow"}
        }
    }
    
    return $null
}

function Restore-IniBackup {
    param ($iniPath)

    try {
        $backupPath = "$iniPath.bak"

        if (-not (Test-Path $backupPath)) {
            Write-Host "`nBackup file not found: $backupPath"
            return -1
        }

        Copy-Item -Path $backupPath -Destination $iniPath -Force
        Write-Host "`nRestored php.ini from backup: $backupPath"
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Restore-IniBackup: Failed to restore ini backup"
            exception = $_
        }
        Write-Host "`nFailed to restore backup: $($_.Exception.Message)"
        return -1
    }
}


function Backup-IniFile {
    param ($iniPath)

    try {
        $backup = "$iniPath.bak"
        if (-not (Test-Path $backup)) {
            Copy-Item $iniPath $backup
        }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to backup ini file"
            exception = $_
        }
        return -1
    }
}

function Get-IniSetting {
    param ($iniPath, $key)
    
    try {
        if (-not $key) {
            Write-Host "`nKey is required. Usage: pvm ini get <key>"
            return -1
        }
        
        $pattern = "^[#;]?\s*{0}\s*=\s*(.+)" -f [regex]::Escape($key)
        $lines = Get-Content $iniPath

        foreach ($line in $lines) {
            if ($line -match $pattern) {
                $value = $matches[1].Trim()
                Write-Host "- $key = $value"
                return 0
            }
        }

        Write-Host "- The setting key '$key' is not found." -ForegroundColor DarkGray
        return -1
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get ini setting '$key'"
            exception = $_
        }
        return -1
    }
}


function Set-IniSetting {
    param ($iniPath, $keyValue)
    
    try {
        if (-not ($keyValue -match '^(?<key>[^=]+)=(?<value>.+)$')) {
            Write-Host "`nInvalid format. Use key=value (e.g., memory_limit=512M)"
            return -1
        }

        $key = $matches['key'].Trim()
        $value = $matches['value'].Trim()
        $pattern = "^[#;]?\s*{0}\s*=" -f [regex]::Escape($key)
        $line = "$key = $value"
        $lines = Get-Content $iniPath

        $matched = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match $pattern) {
                $matched = $true
                return $line
            } else {
                return $_
            }
        }

        if (-not $matched) {
            Write-Host "- The setting key '$key' is not found" -ForegroundColor DarkGray
            return -1
        }
        
        Backup-IniFile $iniPath
        Set-Content $iniPath $newLines -Encoding UTF8
        Write-Host "- $key set to '$value' successfully" -ForegroundColor DarkGreen

        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to set ini setting '$key'"
            exception = $_
        }
        return -1
    }
}

function Enable-IniExtension {
    param ($iniPath, $extName)
    
    try {
        
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to enable"
            return -1
        }
        
        $status = Get-Single-PHPExtensionStatus -iniPath $iniPath -extName $extName
        
        if (-not $status) {
            Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray
            $response = Read-Host "`nWould you like to add '$extName' to the extensions list? (y/n)"
            if ($response -eq "y" -or $response -eq "Y") {
                $extensionAdded = Add-Missing-PHPExtension -iniPath $iniPath -extName $extName -enable $false
            }
        } elseif ($status -and $status.status -eq "Enabled") {
            Write-Host "- '$extName' already enabled. check with 'pvm ini status $extName'" -ForegroundColor DarkGray
            return -1
        }
        
        $lines = Get-Content $iniPath
        $pattern = "^\s*[#;]+\s*(zend_)?extension\s*=\s*([`"']?)(?![^\s`"';]*[/\\])[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"

        $modified = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match $pattern -and -not $modified) {
                $modified = $true
                return $_ -replace "^[#;]\s*", ""
            }
            return $_
        }

        if (-not $modified) {
            Write-Host "- '$extName' is already enabled or not found. check with 'pvm ini status $extName'" -ForegroundColor DarkGray
            return -1
        }

        Backup-IniFile $iniPath
        Set-Content $iniPath $newLines -Encoding UTF8
        Write-Host "- '$extName' enabled successfully." -ForegroundColor DarkGreen

        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to enable extension '$extName'"
            exception = $_
        }
        return -1
    }
}

function Disable-IniExtension {
    param ($iniPath, $extName)

    try {
        
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to disable"
            return -1
        }
        
        $status = Get-Single-PHPExtensionStatus -iniPath $iniPath -extName $extName
        if (-not $status) {
            Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray
            $response = Read-Host "`nWould you like to add '$extName' to the extensions list? (y/n)"
            if ($response -eq "y" -or $response -eq "Y") {
                $extensionAdded = Add-Missing-PHPExtension -iniPath $iniPath -extName $extName -enable $true
            }
        } elseif ($status -and $status.status -eq "Disabled") {
            Write-Host "- '$extName' is already disabled. check with 'pvm ini status $extName'" -ForegroundColor DarkGray
            return -1
        }
        
        $lines = Get-Content $iniPath
        $pattern = "^\s*(zend_)?extension\s*=\s*([`"']?)(?![^\s`"';]*[/\\])[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"

        $updatedLines = @()

        $modified = $false
        $updatedLines = $lines | ForEach-Object {
            if (($_ -match $pattern) -and ($_ -notmatch '^\s*;')) {
                $modified = $true
                return ";$_"
            }
            return $_
        }

        if (-not $modified) {
            Write-Host "- '$extName' is already disabled or not found. check with 'pvm ini status $extName'" -ForegroundColor DarkGray
            return -1
        }
        
        Backup-IniFile $iniPath
        Set-Content $iniPath $updatedLines -Encoding UTF8
        Write-Host "- '$extName' disabled successfully." -ForegroundColor DarkGreen
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to disable extension '$extName'"
            exception = $_
        }
        return -1
    }
}

function Get-IniExtensionStatus {
    param ($iniPath, $extName)

    try {
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to check status"
            return -1
        }

        $status = Get-Single-PHPExtensionStatus -iniPath $iniPath -extName $extName
        if ($status) {
            Write-Host "- $extName`: $($status.status)" -ForegroundColor $status.color
            return 0
        }

        Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray

        $response = Read-Host "`nWould you like to add '$extName' to the extensions list? (y/n)"
        if ($response -eq "y" -or $response -eq "Y") {
            return (Add-Missing-PHPExtension -iniPath $iniPath -extName $extName)
        }

        return -1
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to check status for '$extName'"
            exception = $_
        }
        return -1
    }
}


function Get-PHP-Info {
    
    $currentPHPVersion = Get-Current-PHP-Version
    
    if (-not $currentPHPVersion -or -not $currentPHPVersion.version -or -not $currentPHPVersion.path) {
        Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
        return -1
    }
    
    Write-Host "`n- Running PHP version`t: $($currentPHPVersion.version)"
    Write-Host "`n- PHP path`t`t: $($currentPHPVersion.path)"
    $extensions = Get-PHPExtensionsStatus -PhpIniPath "$($currentPHPVersion.path)\php.ini"
    
    # Pre-count for summary
    $enabledCount = @($extensions | Where-Object Enabled).Count
    $disabledCount = $extensions.Count - $enabledCount
    
    # Calculate max length dynamically
    $maxNameLength = ($extensions.Extension | Measure-Object -Maximum Length).Maximum
    $maxLineLength = $maxNameLength + 10  # padding
    
    Write-Host "`n- Extensions`t`t: Enabled: $enabledCount  |  Disabled: $disabledCount  |  Total: $($extensions.Count)`n"
    $extensions |
    Sort-Object @{Expression = { -not $_.Enabled }; Ascending = $true }, `
                @{Expression = { $_.Extension }; Ascending = $true } |
    ForEach-Object {
        $dotsCount = $maxLineLength - $_.Extension.Length
        if ($dotsCount -lt 0) { $dotsCount = 0 }
        $dots = '.' * $dotsCount

        if ($_.Enabled) {
            $status = "Enabled "
            $color = "DarkGreen"
        } else {
            $status = "Disabled"
            $color = "DarkGray"
        }

        Write-Host "  $($_.Extension) $dots " -NoNewline
        Write-Host $status -ForegroundColor $color
    }
    
    return 0
}

function Get-PHPExtensionsStatus {
    param($PhpIniPath)

    if (-not (Test-Path $PhpIniPath)) {
        throw "php.ini file not found at: $PhpIniPath"
    }

    $iniContent = Get-Content $PhpIniPath
    
    $extensions = foreach ($line in $iniContent) {
        # Match both enabled and commented lines
        if ($line -match '^\s*(;)?(zend_extension|extension)\s*=\s*"?([^";]+?)"?\s*(?:;.*)?$') {
            $rawPath = $matches[3]
            $extensionName = [System.IO.Path]::GetFileName($rawPath)
            [PSCustomObject]@{
                Extension = $extensionName
                Type      = $matches[2] # extension or zend_extension
                Enabled   = -not $matches[1]
            }
        }
    }

    return $extensions
}

function Install-IniExtension {
    param ($iniPath, $extName)
    
    try {
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to check status"
            return -1
        }
        
        $baseUrl = "https://windows.php.net"
        $url = "$baseUrl/downloads/pecl/releases/$extName"
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links | Where-Object {
            $_.href -match "/downloads/pecl/releases/$extName"
        }
        if ($links.Count -eq 0) {
            Write-Host "`nFailed to fetch versions for $extName" -ForegroundColor DarkYellow
            return -1
        }
        
        Write-Host "`nAvailable versions for '$extName':"
        $links | ForEach-Object {
            $text = ($_.outerHTML -replace '<.*?>','').Trim()
            Write-Host $text
        }
        $response = Read-Host "`nInsert the version number you want to install"
        if ([string]::IsNullOrWhiteSpace($response)) {
            Write-Host "`nInstallation cancelled"
            return -1
        }
        $html = Invoke-WebRequest -Uri "https://windows.php.net/downloads/pecl/releases/$extName/$response"
        $links = $html.Links | Where-Object {
            $_.href -match "/downloads/pecl/releases/$extName/$response"-and
            $_.href -match ".zip$"
        }
        if ($links.Count -eq 0) {
            Write-Host "`nFailed to fetch versions for $response" -ForegroundColor DarkYellow
            return -1
        }
        
        $index = 0
        $links | ForEach-Object {
            $text = ($_.outerHTML -replace '<.*?>|.zip','').Trim()
            Write-Host "[$index] $text"
            $index++
        }
        
        $response = Read-Host "`nInsert the [number] you want to install"
        if ([string]::IsNullOrWhiteSpace($response)) {
            Write-Host "`nInstallation cancelled"
            return -1
        }
        
        $chosenItem = $links[$response]
        if (-not $chosenItem) {
            Write-Host "`nFailed to fetch versions for $response" -ForegroundColor DarkYellow
            return -1
        }
        
        Invoke-WebRequest -Uri "$baseUrl/$($chosenItem.href.TrimStart('/'))" -OutFile "$STORAGE_PATH\php"
        $fileNamePath = ($chosenItem.outerHTML -replace '<.*?>|.zip','').Trim()
        Extract-Zip -zipPath "$STORAGE_PATH\php\$fileNamePath.zip" -extractPath "$STORAGE_PATH\php\$fileNamePath"
        Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath.zip"
        $files = Get-ChildItem -Path "$STORAGE_PATH\php\$fileNamePath"
        $extFile = $files | Where-Object {
            ($_.Name -match "($extName|php_$extName).dll")
        }
        if (-not $extFile) {
            Write-Host "`nFailed to find $extName" -ForegroundColor DarkYellow
            return -1
        }
        $phpPath = ($iniPath | Split-Path -Parent)
        if (Test-Path "$phpPath\ext\$($extFile.Name)") {
            $response = Read-Host "`n$($extFile.Name) already exists. Would you like to overwrite it? (y/n)"
            if ($response -ne "y" -and $response -ne "Y") {
                Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath" -Force -Recurse
                Write-Host "`nInstallation cancelled"
                return -1
            }
        }
        Move-Item -Path $extFile.FullName -Destination "$phpPath\ext"
        Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath" -Force -Recurse
        $code = Add-Missing-PHPExtension -iniPath $iniPath -extName $extName -enable $false
        if ($code -ne 0) {
            Write-Host "`nFailed to add $extName" -ForegroundColor DarkYellow
            return -1
        }
        
        Write-Host "`n$extName installed successfully"        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to install '$extName'"
            exception = $_
        }
        return -1
    }
}

function Invoke-PVMIniAction {
    param ( $action, $params )

    try {
        $exitCode = 1
        
        $currentPhpVersion = Get-Current-PHP-Version
        
        if (-not $currentPhpVersion -or -not $currentPhpVersion.version -or -not $currentPhpVersion.path) {
            Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }
        
        $iniPath = "$($currentPhpVersion.path)\php.ini"
        if (-not (Test-Path $iniPath)) {
            Write-Host "php.ini not found at: $($currentPhpVersion.path)"
            return -1
        }

        switch ($action) {
            "info" {
                $exitCode = Get-PHP-Info
            }
            "get" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one setting name ('pvm ini get memory_limit)."
                    return -1
                }
                
                Write-Host "`nRetrieving ini setting..."
                foreach ($extName in $params) {
                    $exitCode = Get-IniSetting -iniPath $iniPath -key $extName
                }
            }
            "set" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one 'key=value' (pvm ini set memory_limit=512M)."
                    return -1
                }

                Write-Host "`nSetting ini value..."
                foreach ($keyValue in $params) {
                    $exitCode = Set-IniSetting -iniPath $iniPath -keyValue $keyValue
                }
            }
            "enable" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini enable curl)."
                    return -1
                }
                
                Write-Host "`nEnabling extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Enable-IniExtension -iniPath $iniPath -extName $extName
                }
            }
            "disable" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini disable xdebug)."
                    return -1
                }
                
                Write-Host "`nDisabling extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Disable-IniExtension -iniPath $iniPath -extName $extName
                }
            }
            "status" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini status opcache)."
                    return -1
                }
                
                Write-Host "`nChecking status of extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Get-IniExtensionStatus -iniPath $iniPath -extName $extName
                }
            }
            "restore" {
                $exitCode = Restore-IniBackup -iniPath $iniPath
            }
            "install" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini install xdebug)."
                    return -1
                }
                
                Write-Host "`nInstalling extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Install-IniExtension -iniPath $iniPath -extName $extName
                }
            }
            default {
                Write-Host "`nUnknown action '$action' for 'pvm ini'. Use 'set', 'enable', or 'disable'."
            }
        }
        
        return $exitCode
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to invoke ini action '$action'"
            exception = $_
        }
        Write-Host "`nFailed to perform action '$action' on ini settings." -ForegroundColor Red
        return -1
    }
}