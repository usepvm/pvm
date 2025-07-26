
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
        $logger = Log-Data -logPath $LOG_ERROR_PATH -message "Restore-IniBackup: Failed to restore ini backup" -data $_.Exception.Message
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
                Write-Host "`n$key = $value"
                return 0
            }
        }

        Write-Host "`n$key not found in `"$iniPath`""
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
            $newLines += $line
        }

        Backup-IniFile $iniPath
        Set-Content $iniPath $newLines -Encoding UTF8

        Write-Host "`n$key set to '$value' successfully in `"$iniPath`""

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

        if ($modified) {
            Backup-IniFile $iniPath
            Set-Content $iniPath $newLines -Encoding UTF8
            Write-Host "`nExtension '$extName' enabled successfully."
        } else {
            Write-Host "`nExtension '$extName' is already enabled or not found in `"$iniPath`""
            return -1
        }

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

        if ($modified) {
            Backup-IniFile $iniPath
            Set-Content $iniPath $updatedLines -Encoding UTF8
            Write-Host "`nExtension '$extName' disabled successfully."
        } else {
            Write-Host "`nExtension '$extName' is already disabled or not found in `"$iniPath`""
            return -1
        }

        
        return 0
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Disable-IniExtension: Failed to disable extension '$extName'" -data $_.Exception.Message
        return -1
    }
}

function Invoke-PVMIni {
    param ( $action, $arguments )

    try {
        $exitCode = 1
        
        $currentPhpVersionPath = Get-EnvVar-ByName -name $PHP_CURRENT_ENV_NAME
        $iniPath = "$currentPhpVersionPath\php.ini"
        
        if (-not (Test-Path $iniPath)) {
            Write-Host "php.ini not found at: $iniPath"
            exit 1
        }

        switch ($action) {
            "get" {
                $exitCode = Get-IniSetting -iniPath $iniPath -key $arguments
            }
            "set" {
                $exitCode = Set-IniSetting -iniPath $iniPath -keyValue $arguments
            }
            "enable" {
                $exitCode = Enable-IniExtension -iniPath $iniPath -extName $arguments
            }
            "disable" {
                $exitCode = Disable-IniExtension -iniPath $iniPath -extName $arguments
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
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Invoke-PVMIni: Failed to invoke ini action '$action'" -data $_.Exception.Message
        Write-Host "`nFailed to perform action '$action' on ini settings." -ForegroundColor Red
        return -1
    }
}