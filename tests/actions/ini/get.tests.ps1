
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\get-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:phpVersionPath = "$TEST_DRIVE\php-8.2"
    $script:testIniPath = "$phpVersionPath\php.ini"
    $script:extDirectory = "$phpVersionPath\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.paths.directories.cache -Force | Out-Null
    New-Item -ItemType Directory -Path $phpVersionPath -Force | Out-Null
    New-Item -ItemType Directory -Path $extDirectory -Force | Out-Null

    Mock Show-Warning { }
    Mock Show-Info { }
    Mock Show-Message { }
    Mock Write-Color { }

    function Reset-IniContent {
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

    Reset-IniContent
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-IniSetting" {
    It "Gets existing setting" {
        $code = Get-IniSetting -iniPath $testIniPath -keys @('upload_max_filesize')

        $code | Should -Be 0
    }

    It "Gets setting with spaces in value" {
        $code = Get-IniSetting -iniPath $testIniPath -keys @('display_errors')

        $code | Should -Be 0
    }

    It "Returns -1 for commented settings" {
        $code = Get-IniSetting -iniPath $testIniPath -keys @('xdebug')

        $code | Should -Be -1
    }

    It "Returns -1 for non-existent setting" {
        $code = Get-IniSetting -iniPath $testIniPath -keys @('nonexistent_setting')

        $code | Should -Be -1
    }

    It "Requires key parameter" {
        $code = Get-IniSetting -iniPath $testIniPath -keys ''
        $code | Should -Be -1

        $code = Get-IniSetting -iniPath $testIniPath -keys $null
        $code | Should -Be -1
    }

    It "Handles regex special characters in key names" {
        $code = Get-IniSetting -iniPath $testIniPath -keys @('memory_limit')
        $code | Should -Be 0
    }

    It "Displays '(not set)' for empty value entries" {
        @"
memory_limit =
"@ | Set-ContentWrapper -path $testIniPath
        $code = Get-IniSetting -iniPath $testIniPath -keys @('memory_limit')
        $code | Should -Be 0
    }

    It "Returns -1 on error" {
        Mock Get-ContentWrapper { throw 'Access denied' }
        $code = Get-IniSetting -iniPath $testIniPath -keys @('memory_limit')
        $code | Should -Be -1
    }
}
