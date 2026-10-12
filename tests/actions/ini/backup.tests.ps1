
BeforeAll {
    if (-not $Global:CurrentTestDrive) {
        $currentFileName = Split-Path -Path $PSCommandPath -Leaf
        $msg = "`nTest Drive is not set for '$currentFileName'"
        $line = "`n$('=' * $msg.Length)"
        $errorMessage = $line + $msg + $line
        throw " `n$errorMessage"
    }

    $script:TEST_DRIVE = $Global:CurrentTestDrive

    Mock Show-Message { }
    Mock Show-Success { }
    Mock Show-Error { }
    Mock Add-LogEntry { return 0 }
    Mock Show-Warning { }
}

Describe "Invoke-PhpIniBackup" {
    It "Returns 0 and shows success when backup succeeds" {
        Mock Backup-IniFile { return 0 }

        $result = Invoke-PhpIniBackup -iniPath 'C:\php\php.ini'

        $result | Should -Be 0
        Should -Invoke Show-Message -Times 1
        Should -Invoke Show-Success -Times 1
        Should -Invoke Show-Error -Times 0
    }

    It "Returns -1 and shows error when backup fails" {
        Mock Backup-IniFile { return -1 }

        $result = Invoke-PhpIniBackup -iniPath 'C:\php\php.ini'

        $result | Should -Be -1
        Should -Invoke Show-Message -Times 1
        Should -Invoke Show-Error -Times 1
        Should -Invoke Show-Success -Times 0
    }

    It "Returns -1 and logs exception when backup throws" {
        Mock Backup-IniFile { throw 'Access denied' }

        $result = Invoke-PhpIniBackup -iniPath 'C:\php\php.ini'

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
        Should -Invoke Show-Error -Times 1
    }
}

Describe "Invoke-PhpIniBackupCleanup" {
    It "Returns 0 and shows success when cleanup succeeds" {
        Mock Clear-IniBackups { return 0 }

        $result = Invoke-PhpIniBackupCleanup -iniBackupPath 'C:\php\ini.backup'

        $result | Should -Be 0
        Should -Invoke Show-Message -Times 1
        Should -Invoke Show-Success -Times 1
        Should -Invoke Show-Warning -Times 0
        Should -Invoke Show-Error -Times 0
    }

    It "Returns 0 and shows warning when cleanup fails" {
        Mock Clear-IniBackups { return -1 }

        $result = Invoke-PhpIniBackupCleanup -iniBackupPath 'C:\php\ini.backup'

        $result | Should -Be 0
        Should -Invoke Show-Message -Times 1
        Should -Invoke Show-Warning -Times 1
        Should -Invoke Show-Success -Times 0
        Should -Invoke Show-Error -Times 0
    }

    It "Returns -1 and logs exception when cleanup throws" {
        Mock Clear-IniBackups { throw 'Access denied' }

        $result = Invoke-PhpIniBackupCleanup -iniBackupPath 'C:\php\ini.backup'

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
        Should -Invoke Show-Error -Times 1
    }
}
