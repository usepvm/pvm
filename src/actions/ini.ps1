
function Restore-IniBackup {
    param ($iniPath)

    try {
        $backupPath = "$iniPath.bak"

        if (-not (Test-Path $backupPath)) {
            Write-Host "`nBackup file not found: $backupPath"
            exit 1
        }

        Copy-Item -Path $backupPath -Destination $iniPath -Force
        Write-Host "`nRestored php.ini from backup: $backupPath"
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Restore-IniBackup: Failed to restore ini backup" -data $_.Exception.Message
        Write-Host "`nFailed to restore backup: $_"
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
            exit 1
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
            exit 1
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
            exit 1
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
            exit 1
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
            exit 1
        }

        $lines = Get-Content $iniPath
        $enabledPattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"
        $disabledPattern = "^\s*;\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"

        foreach ($line in $lines) {
            if ($line -match $enabledPattern) {
                Write-Host "- $extName`: enabled" -ForegroundColor DarkGreen
                return 0
            }
            if ($line -match $disabledPattern) {
                Write-Host "- $extName`: disabled" -ForegroundColor DarkYellow
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


function Invoke-PVMIniAction {
    param ( $action, $params )

    try {
        $exitCode = 1
        
        $currentPhpVersionPath = Get-EnvVar-ByName -name $PHP_CURRENT_ENV_NAME
        $iniPath = "$currentPhpVersionPath\php.ini"
        
        if (-not (Test-Path $iniPath)) {
            Write-Host "php.ini not found at: $currentPhpVersionPath"
            exit 1
        }

        switch ($action) {
            "get" {
                if ($params.Count -lt 1) {
                    Write-Host "`nPlease specify at least one setting name ('pvm ini get memory_limit)."
                    exit 1
                }
                
                Write-Host "`nRetrieving ini setting..."
                foreach ($extName in $params) {
                    $exitCode = Get-IniSetting -iniPath $iniPath -key $extName
                }
            }
            "set" {
                if ($params.Count -lt 1) {
                    Write-Host "`nPlease specify at least one 'key=value' (pvm ini set memory_limit=512M)."
                    exit 1
                }

                Write-Host "`nSetting ini value..."
                foreach ($keyValue in $params) {
                    $exitCode = Set-IniSetting -iniPath $iniPath -keyValue $keyValue
                }
            }
            "enable" {
                if ($params.Count -lt 1) {
                    Write-Host "`nPlease specify at least one extension (pvm ini enable curl)."
                    exit 1
                }
                
                Write-Host "`nEnabling extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    Enable-IniExtension -iniPath $iniPath -extName $extName
                }
                $exitCode = 0
            }
            "disable" {
                if ($params.Count -lt 1) {
                    Write-Host "`nPlease specify at least one extension (pvm ini disable xdebug)."
                    exit 1
                }
                
                Write-Host "`nDisabling extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    Disable-IniExtension -iniPath $iniPath -extName $extName
                }
                $exitCode = 0
            }
            "status" {
                if ($params.Count -lt 1) {
                    Write-Host "`nPlease specify at least one extension (pvm ini status opcache)."
                    exit 1
                }
                
                Write-Host "`nChecking status of extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    Get-IniExtensionStatus -iniPath $iniPath -extName $extName
                }
                $exitCode = 0
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