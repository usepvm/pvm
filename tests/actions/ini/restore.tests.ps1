
BeforeAll {
    $testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $testIniPath = "$testDrivePath\php.ini"
    $extDirectory = "$testDrivePath\ext"
    $testBackupPath = "$testIniPath.bak"

    Mock Write-Host {}

    function Reset-Ini-Content {
    # Create a test php.ini file
    @"
memory_limit = 128M
;extension=php_xdebug.dll
extension=php_curl.dll
zend_extension=php_opcache.dll
display_errors = On
max_execution_time = 30
;upload_max_filesize = 2M
"@ | Set-Content -Path $testIniPath -Encoding UTF8
    }

    # Create initial ini content first
    Reset-Ini-Content
}

Describe "Restore-IniBackup" {
    It "Creates backup and restores successfully" {
        Reset-Ini-Content
        # Create backup first
        Backup-IniFile -iniPath $testIniPath

        # Modify original
        'modified content' | Set-Content -Path $testIniPath
        Restore-IniBackup -iniPath $testIniPath | Should -Be 0
        (Get-Content -Path $testIniPath) | Should -Not -Be 'modified content'
    }

    It "Fails when backup doesn't exist" {
        Remove-Item -Path $testBackupPath -ErrorAction SilentlyContinue
        Restore-IniBackup -iniPath $testIniPath | Should -Be -1
    }

    It "Returns -1 on error" {
        Mock Test-Path { return $true }
        Mock Copy-Item { throw 'Access denied' }
        Backup-IniFile -iniPath $testIniPath
        Restore-IniBackup -iniPath $testIniPath | Should -Be -1
    }
}
