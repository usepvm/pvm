
BeforeAll {
    $script:testEnvironment = Initialize-PVMTestEnvironment -driveName 'info'
    $script:TEST_DRIVE = $TestEnvironment.TestDrive

    $script:phpVersionPath = "$TEST_DRIVE\php-8.2"
    $script:testIniPath = "$phpVersionPath\php.ini"
    $script:extDirectory = "$phpVersionPath\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Directory -path $Global:PVMConfig.paths.directories.cache
    New-Directory -path $phpVersionPath
    New-Directory -path $extDirectory

    Mock Show-Error { }
    Mock Show-Message { }
    Mock Write-Color { }

    function Reset-IniContent {
        @"
memory_limit = 128M
;extension=php_xdebug.dll
extension=php_curl.dll
;extension=php_mysql.dll
zend_extension=php_opcache.dll
mysqli.default_port=3306
display_errors = On
max_execution_time = 30
;upload_max_filesize = 2M
"@ | Set-ContentWrapper -path $testIniPath
    }

    Reset-IniContent

    Mock Get-CurrentPHPVersion {
        return @{
            version = '8.2.0'
            path    = $phpVersionPath
        }
    }
}

AfterAll {
    Restore-PVMTestEnvironment -environment $testEnvironment
}

Describe "Get-PHPInfo" {
    BeforeEach {
        Reset-IniContent
    }

    It "Returns PHP version info successfully" {
        $result = Get-PHPInfo
        $result | Should -Be 0
    }

    It "Handles missing PHP version gracefully" {
        Mock Get-CurrentPHPVersion { return @{ version = $null; path = $null } }
        $result = Get-PHPInfo
        $result | Should -Be -1
    }

    It "Displays only matching extensions and settings" {
        $result = Get-PHPInfo -term 'sql'

        $result | Should -Be 0
    }
}
