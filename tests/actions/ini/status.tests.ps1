
BeforeAll {
    $script:PVMConfigBackup = $PVMConfig.Clone()

    $script:testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $script:testIniPath = "$testDrivePath\php.ini"
    $script:extDirectory = "$testDrivePath\ext"
    $script:testBackupPath = "$testIniPath.bak"

    $PVMConfig.paths.cache = 'TestDrive:\cache'
    New-Item -ItemType Directory -Path $PVMConfig.paths.cache -Force | Out-Null

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
    $PVMConfig.paths.logError = "$testDrivePath\error.log"
    $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$testDrivePath\php"

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$testDrivePath\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
    Copy-Item -Path $testIniPath "$phpVersionPath\php.ini" -Force
}

AfterAll {
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-IniExtensionStatus" {
    BeforeEach {
        Reset-Ini-Content
    }

    It "Detects enabled extension" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(
                @{ name = 'curl'; id='curl'; status='Enabled'; color='DarkGreen'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extNames @('curl') | Should -Be 0
    }

    It "Detects disabled extension" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(
                @{ name = 'xdebug'; id='xdebug'; status='Disabled'; color='DarkYellow'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extNames @('xdebug') | Should -Be 0
    }

    It "Detects enabled zend_extension" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(
                @{ name = 'opcache'; id='opcache'; status='Enabled'; color='DarkGreen'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extNames @('opcache') | Should -Be 0
    }

    It "Returns -1 for non-existent extension" {
        Mock Read-Host { return 'n' }
        Get-IniExtensionStatus -iniPath $testIniPath -extNames @('nonexistent_ext') | Should -Be -1
    }

    It "Requires extension name" {
        Get-IniExtensionStatus -iniPath $testIniPath -extNames '' | Should -Be -1
        Get-IniExtensionStatus -iniPath $testIniPath -extNames $null | Should -Be -1
    }

    It "Returns -1 on error" {
        Mock Get-Content { throw 'Access denied' }
        Get-IniExtensionStatus -iniPath $testIniPath -extNames @('curl') | Should -Be -1
    }
}
