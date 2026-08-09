
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\status-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.paths.cache -Force | Out-Null

    Mock Show-Warning {}
    Mock Write-Color {}
    Mock Show-Error {}
    Mock Show-Message {}

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

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$TEST_DRIVE\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
    Copy-ItemWrapper -path $testIniPath -destination "$phpVersionPath\php.ini"
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-IniExtensionStatus" {
    BeforeEach {
        Reset-IniContent
    }

    It "Detects enabled extension" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'curl'; id='curl'; status='Enabled'; color='DarkGreen'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extNames @('curl') | Should -Be 0
    }

    It "Detects disabled extension" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'xdebug'; id='xdebug'; status='Disabled'; color='DarkYellow'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extNames @('xdebug') | Should -Be 0
    }

    It "Detects enabled zend_extension" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'opcache'; id='opcache'; status='Enabled'; color='DarkGreen'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extNames @('opcache') | Should -Be 0
    }

    It "Returns -1 for non-existent extension" {
        Mock Read-HostWrapper { return 'n' }
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
