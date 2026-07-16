
function Restore-IniBackup {
    param ($iniPath)

    try {
        $backupPath = "$iniPath.bak"

        if (Test-File-Not-Exists -path $backupPath) {
            Print-Error -message "`nBackup file not found: $backupPath"
            return -1
        }

        Copy-Item -Path $backupPath -Destination $iniPath -Force
        Print-Success -message "`nRestored php.ini from backup: $backupPath"
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Restore-IniBackup: Failed to restore ini backup"; exception = $_ }
        Print-Error -message "`nFailed to restore backup: $($_.Exception.Message)"
        return -1
    }
}
