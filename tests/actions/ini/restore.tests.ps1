
BeforeAll {
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\restore-drive"
    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    Mock Write-Host {}

    function Reset-IniContent {
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
    Reset-IniContent
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
}

Describe "Restore-IniBackup" {
    It "Creates backup and restores successfully" {
        Reset-IniContent
        # Create backup first
        $null = Backup-IniFile -iniPath $testIniPath

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
        $null = Backup-IniFile -iniPath $testIniPath
        Restore-IniBackup -iniPath $testIniPath | Should -Be -1
    }
}
