
function Invoke-PhpIniBackup {
    param ($iniPath)

    try {
        Show-Message -message "`nCreating backup of php.ini..."

        $result = Backup-IniFile -iniPath $iniPath

        if ($result -eq 0) {
            $phpDirectory = Split-Path -Path $iniPath -Parent
            $iniBackupPath = "$phpDirectory\$($Global:PVMConfig.constants.INI_BACKUP_DIR_NAME)"
            Show-LabelledSuccess -message "`nBackup created successfully at $iniBackupPath"
            return 0
        } else {
            Show-LabelledError -message "`nFailed to create backup."
            return -1
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to invoke php.ini backup"; exception = $_ }
        Show-LabelledError -message "`nFailed to create backup."
        return -1
    }
}

function Invoke-PhpIniBackupCleanup {
    param ($iniBackupPath)

    try {
        Show-Message -message "`nCleaning up old backups..."

        $result = Clear-IniBackups -iniBackupPath $iniBackupPath

        if ($result -eq 0) {
            Show-LabelledSuccess -message "Backup cleanup completed successfully."
            return 0
        } else {
            Show-LabelledWarning -message "No backups found or cleanup not needed."
            return 0
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to invoke php.ini backup cleanup"; exception = $_ }
        Show-LabelledError -message "`nFailed to cleanup backups."
        return -1
    }
}
