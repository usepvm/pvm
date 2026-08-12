
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\restore-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    Mock Show-Error {}
    Mock Show-Success {}

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
"@ | Set-ContentWrapper -path $testIniPath
    }

    # Create initial ini content first
    Reset-IniContent
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Restore-IniBackup" {
    It "Creates backup and restores successfully" {
        Reset-IniContent
        # Create backup first
        $null = Backup-IniFile -iniPath $testIniPath

        # Modify original
        'modified content' | Set-ContentWrapper -path $testIniPath
        Restore-IniBackup -iniPath $testIniPath | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) | Should -Not -Be 'modified content'
    }

    It "Fails when backup doesn't exist" {
        Remove-ItemWrapper -path $testBackupPath -ErrorAction SilentlyContinue
        Restore-IniBackup -iniPath $testIniPath | Should -Be -1
    }

    It "Returns -1 on error" {
        Mock Test-Path { return $true }
        Mock Copy-ItemWrapper { throw 'Access denied' }
        $null = Backup-IniFile -iniPath $testIniPath
        Restore-IniBackup -iniPath $testIniPath | Should -Be -1
    }
}
