
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Restore-IniBackup: Failed to restore ini backup" -data $_.Exception.Message
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Backup-IniFile: Failed to backup ini file" -data $_.Exception.Message
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-IniSetting: Failed to get ini setting '$key'" -data $_.Exception.Message
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-IniSetting: Failed to set ini setting '$key'" -data $_.Exception.Message
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
        
        $lines = Get-Content $iniPath
        $pattern = "^\s*[#;]+\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"

        $modified = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match $pattern) {
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Enable-IniExtension: Failed to enable extension '$extName'" -data $_.Exception.Message
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
        
        $lines = Get-Content $iniPath
        $pattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"

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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Disable-IniExtension: Failed to disable extension '$extName'" -data $_.Exception.Message
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

        $lines = Get-Content $iniPath
        $enabledPattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"
        $disabledPattern = "^\s*;\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"

        foreach ($line in $lines) {
            if ($line -match $enabledPattern) {
                Write-Host "- $extName`: Enabled" -ForegroundColor DarkGreen
                return 0
            }
            if ($line -match $disabledPattern) {
                Write-Host "- $extName`: Disabled" -ForegroundColor DarkYellow
                return 0
            }
        }

        Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray
        return -1
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-IniExtensionStatus: Failed to check status for '$extName'" -data $_.Exception.Message
        return -1
    }
}


function Get-PHP-Info {
    
    $currentPHPVersion = Get-Current-PHP-Version
    $currentPHPVersion.version
    
    Write-Host "`n- Running PHP version`t: $($currentPHPVersion.version)"
    Write-Host "`n- PHP path`t`t: $($currentPHPVersion.path)"
    $extensions = Get-PHPExtensionsStatus -PhpIniPath "$($currentPHPVersion.path)\php.ini"
    
    # Pre-count for summary
    $enabledCount = ($extensions | Where-Object Enabled).Count
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

function Invoke-PVMIniAction {
    param ( $action, $params )

    try {
        $exitCode = 1
        
        $currentPhpVersionPath = Get-Item $PHP_CURRENT_VERSION_PATH
        if (-not $currentPhpVersionPath) {
            Write-Host "Current PHP version not found at: $PHP_CURRENT_VERSION_PATH"
            return -1
        }
        $currentPhpVersionPath = $currentPhpVersionPath.Target
        $iniPath = "$currentPhpVersionPath\php.ini"
        
        if (-not (Test-Path $iniPath)) {
            Write-Host "php.ini not found at: $currentPhpVersionPath"
            return -1
        }

        switch ($action) {
            "info" {
                $exitCode = Get-PHP-Info
            }
            "get" {
                if ($params.Count -lt 1) {
                    Write-Host "`nPlease specify at least one setting name ('pvm ini get memory_limit)."
                    return -1
                }
                
                Write-Host "`nRetrieving ini setting..."
                foreach ($extName in $params) {
                    $exitCode = Get-IniSetting -iniPath $iniPath -key $extName
                }
            }
            "set" {
                if ($params.Count -lt 1) {
                    Write-Host "`nPlease specify at least one 'key=value' (pvm ini set memory_limit=512M)."
                    return -1
                }

                Write-Host "`nSetting ini value..."
                foreach ($keyValue in $params) {
                    $exitCode = Set-IniSetting -iniPath $iniPath -keyValue $keyValue
                }
            }
            "enable" {
                if ($params.Count -lt 1) {
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
            default {
                Write-Host "`nUnknown action '$action' for 'pvm ini'. Use 'set', 'enable', or 'disable'."
            }
        }
        
        return $exitCode
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Invoke-PVMIniAction: Failed to invoke ini action '$action'" -data $_.Exception.Message
        Write-Host "`nFailed to perform action '$action' on ini settings." -ForegroundColor Red
        return -1
    }
}