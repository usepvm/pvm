
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:testIniPath = "$script:TEST_DRIVE\php.ini"
    $script:extDirectory = "$script:TEST_DRIVE\ext"
    $script:testBackupPath = "$script:testIniPath.bak"

    Mock Show-Error { }
    Mock Show-Success { }

    function Reset-IniContent {
        @(
            'memory_limit = 128M'
            ';extension=php_xdebug.dll'
            'extension=php_curl.dll'
            'zend_extension=php_opcache.dll'
            'display_errors = On'
            'max_execution_time = 30'
            ';upload_max_filesize = 2M'
        ) -join "`n" | Set-ContentWrapper -path $script:testIniPath
    }

    Reset-IniContent
}

Describe "Restore-IniBackup" {
    It "Creates backup and restores successfully" {
        Reset-IniContent
        # Create backup first
        $null = Backup-IniFile -iniPath $script:testIniPath

        # Modify original
        'modified content' | Set-ContentWrapper -path $script:testIniPath
        $code = Restore-IniBackup -iniPath $script:testIniPath
        $code | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) | Should -Not -Be 'modified content'
    }

    It "Fails when backup doesn't exist" {
        Remove-ItemWrapper -path $script:testBackupPath
        $code = Restore-IniBackup -iniPath $script:testIniPath
        $code | Should -Be -1
    }

    It "Returns -1 on error" {
        Mock Add-LogEntry { return 0 }
        Mock Test-FileNotExists { return $false }
        Mock Copy-ItemWrapper { throw 'Access denied' }
        $null = Backup-IniFile -iniPath $script:testIniPath
        $code = Restore-IniBackup -iniPath $script:testIniPath
        $code | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
    }
}
