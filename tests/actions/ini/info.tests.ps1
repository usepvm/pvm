
BeforeAll {
    $testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $testIniPath = "$testDrivePath\php.ini"
    $extDirectory = "$testDrivePath\ext"
    $testBackupPath = "$testIniPath.bak"

    $global:CACHE_PATH = 'TestDrive:\cache'
    New-Item -ItemType Directory -Path $global:CACHE_PATH -Force | Out-Null

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

    # Mock global variables
    $script:LOG_ERROR_PATH = "$testDrivePath\error.log"
    $script:PHP_CURRENT_VERSION_PATH = "$testDrivePath\php"

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$testDrivePath\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
    Copy-Item $testIniPath "$phpVersionPath\php.ini" -Force

    # Mock Get-Current-PHP-Version function
    function script:Get-Current-PHP-Version {
        return @{
            version = '8.2.0'
            path = $phpVersionPath
        }
    }
}

Describe "Get-PHP-Info" {
    BeforeEach {
        Reset-Ini-Content
    }

    It "Returns PHP version info successfully" {
        Mock Get-PHP-Data {
            return @{
                extensions = @(
                    @{ Extension = 'curl'; Enabled = $true }
                    @{ Extension = 'xdebug'; Enabled = $false }
                )
                settings = @(
                    @{ Name = 'memory_limit'; Value = '128M'; Enabled = $true }
                    @{ Name = 'max_execution_time'; Value = '30'; Enabled = $false }
                )
            }
        }
        $result = Get-PHP-Info
        $result | Should -Be 0
    }

    It "Handles missing PHP version gracefully" {
        Mock Get-Current-PHP-Version { return @{ version = $null; path = $null } }
        $result = Get-PHP-Info
        $result | Should -Be -1
    }
}
