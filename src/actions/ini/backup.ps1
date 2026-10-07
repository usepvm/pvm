
function Invoke-PhpIniBackup {
    param ($iniPath)

    try {
        Show-Message -message "`nCreating backup of php.ini..."

        $result = Backup-IniFile -iniPath $iniPath

        if ($result -eq 0) {
            Show-Success -message "Backup created successfully."
            return 0
        } else {
            Show-Error -message "Failed to create backup."
            return -1
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to invoke php.ini backup"; exception = $_ }
        Show-Error -message "Failed to create backup."
        return -1
    }
}

function Invoke-PhpIniBackupCleanup {
    param ($iniBackupPath)

    try {
        Show-Message -message "`nCleaning up old backups..."

        $result = Clear-IniBackups -iniBackupPath $iniBackupPath

        if ($result -eq 0) {
            Show-Success -message "Backup cleanup completed successfully."
            return 0
        } else {
            Show-Warning -message "No backups found or cleanup not needed."
            return 0
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to invoke php.ini backup cleanup"; exception = $_ }
        Show-Error -message "Failed to cleanup backups."
        return -1
    }
}
