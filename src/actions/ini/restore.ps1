
function Restore-IniBackup {
    param ($iniPath)

    try {
        $phpDirectory = Split-Path -Path $iniPath -Parent
        $iniBackupPath = "$phpDirectory\$($Global:PVMConfig.constants.INI_BACKUP_DIR_NAME)"

        if (Test-DirectoryNotExists -path $iniBackupPath) {
            Show-LabelledError -message "Backup directory not found: $iniBackupPath"
            return -1
        }

        $backupFiles = @(Get-ChildItemWrapper -path $iniBackupPath -filter 'php.ini_*.bak' -file | Sort-Object -Property CreationTime -Descending)

        if (-not $backupFiles -or $backupFiles.Count -eq 0) {
            Show-LabelledError -message "No backup files found in: '$iniBackupPath'"
            return -1
        }

        $backupList = [System.Collections.Generic.List[object]]::new()
        foreach ($file in $backupFiles) {
            $backupList.Add(@{
                file     = $file
                niceTime = Format-NiceTimestamp -timestamp $file.CreationTime.ToString('o')
                size     = "$([math]::Round($file.Length / 1KB, 2)) KB"
            })
        }

        Show-Message -message "`nBackup path : $iniBackupPath"
        Write-Cyan -message "`nAvailable backups: ($($backupList.Count))" -underlined
        for ($i = 0; $i -lt $backupList.Count; $i++) {
            $backup = $backupList[$i]
            Show-Message -message "  [$i] $($backup.file.Name)" -noNewLine
            Write-Gray " | ($($backup.niceTime.Relative)) ($($backup.size))"
        }

        $choiceRaw = Read-HostWrapper -prompt "`nSelect backup to restore (0-$($backupList.Count - 1))"
        $choice = $null

        if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
            Show-Warning -message "`nPlease enter a valid positive number."
            return -1
        }

        if ($choice -lt 0 -or $choice -gt $backupList.Count - 1) {
            Show-Warning -message "`nNumber must be between 0 and $($backupList.Count - 1)."
            return -1
        }

        $selectedBackup = $backupList[$choice]
        $code = Copy-ItemWrapper -path $selectedBackup.file.FullName -destination $iniPath
        if ($code -ne 0) {
            Show-LabelledError -message "Failed to restore php.ini from backup: '$($selectedBackup.file.FullName)'!"
            return -1
        }

        Show-LabelledSuccess -message "Restored php.ini from backup: $($selectedBackup.file.Name)"
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Restore-IniBackup: Failed to restore ini backup"; exception = $_ }
        Show-LabelledError -message "Failed to restore backup: $($_.Exception.Message)"
        return -1
    }
}
