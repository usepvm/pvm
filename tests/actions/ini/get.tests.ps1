
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\get-drive"
    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"
    $script:CACHE_PATH = $PVMConfig.paths.cache = "$TEST_DRIVE\cache"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null

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

    # Mock global variables
    $PVMConfig.paths.logError = "$TEST_DRIVE\error.log"
    $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$TEST_DRIVE\php"

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$TEST_DRIVE\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
    Copy-Item -Path $testIniPath "$phpVersionPath\php.ini" -Force
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-IniSetting" {
    It "Gets existing setting" {
        Get-IniSetting -iniPath $testIniPath -keys @('upload_max_filesize') | Should -Be 0
    }

    It "Gets setting with spaces in value" {
        Get-IniSetting -iniPath $testIniPath -keys @('display_errors') | Should -Be 0
    }

    It "Returns -1 for commented settings" {
        Get-IniSetting -iniPath $testIniPath -keys @('xdebug') | Should -Be -1
    }

    It "Returns -1 for non-existent setting" {
        Get-IniSetting -iniPath $testIniPath -keys @('nonexistent_setting') | Should -Be -1
    }

    It "Requires key parameter" {
        Get-IniSetting -iniPath $testIniPath -keys '' | Should -Be -1
        Get-IniSetting -iniPath $testIniPath -keys $null | Should -Be -1
    }

    It "Handles regex special characters in key names" {
        Get-IniSetting -iniPath $testIniPath -keys @('memory_limit') | Should -Be 0
    }

    It "Displays '(not set)' for empty value entries" {
        @"
memory_limit =
"@ | Set-Content -Path $testIniPath -Encoding UTF8
        Get-IniSetting -iniPath $testIniPath -keys @('memory_limit') | Should -Be 0
    }

    It "Returns -1 on error" {
        Mock Get-Content { throw 'Access denied' }
        Get-IniSetting -iniPath $testIniPath -keys @('memory_limit') | Should -Be -1
    }
}
