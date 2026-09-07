
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\info-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:phpVersionPath = "$TEST_DRIVE\php-8.2"
    $script:testIniPath = "$phpVersionPath\php.ini"
    $script:extDirectory = "$phpVersionPath\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.paths.directories.cache -Force | Out-Null
    New-Item -ItemType Directory -Path $phpVersionPath -Force | Out-Null
    New-Item -ItemType Directory -Path $extDirectory -Force | Out-Null

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
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
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
