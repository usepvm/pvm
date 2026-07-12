
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\info-drive"
    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"
    $script:CACHE_PATH = $PVMConfig.paths.cache = "$TEST_DRIVE\cache"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null

    Mock Write-Host {}

    function Reset-Ini-Content {
        # Create a test php.ini file
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
"@ | Set-Content -Path $testIniPath -Encoding UTF8
    }

    # Create initial ini content first
    Reset-Ini-Content

    # Mock global variables
    $PVMConfig.paths.logError = "$TEST_DRIVE\error.log"
    $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$TEST_DRIVE\php"

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$TEST_DRIVE\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
    Copy-Item -Path $testIniPath "$phpVersionPath\php.ini" -Force

    # Mock Get-Current-PHP-Version function
    Mock Get-Current-PHP-Version {
        return @{
            version = '8.2.0'
            path    = $phpVersionPath
        }
    }
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-PHP-Info" {
    BeforeEach {
        Reset-Ini-Content
    }

    It "Returns PHP version info successfully" {
        $result = Get-PHP-Info
        $result | Should -Be 0
    }

    It "Handles missing PHP version gracefully" {
        Mock Get-Current-PHP-Version { return @{ version = $null; path = $null } }
        $result = Get-PHP-Info
        $result | Should -Be -1
    }

    It "Displays only matching extensions and settings" {
        $result = Get-PHP-Info -term 'sql'

        $result | Should -Be 0
    }
}
