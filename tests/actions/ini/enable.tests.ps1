
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\enable-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.paths.directories.cache -Force | Out-Null

    Mock Show-Warning {}
    Mock Show-Info {}
    Mock Show-Message {}
    Mock Write-Color {}

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

Describe "Enable-IniExtension" {
    BeforeEach {
        Mock Test-DirectoryExists -ParameterFilter { $path -eq $extDirectory } -MockWith { return $true }
        Reset-IniContent
        Remove-ItemWrapper -path $testBackupPath -ErrorAction SilentlyContinue
    }

    It "Enables commented extension" {
        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$extDirectory\php_xdebug.dll" } )
        }
        Enable-IniExtension -iniPath $testIniPath -extNames @('xdebug') | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^extension=php_xdebug.dll' | Should -Be $true
    }

    It "Returns 0 for already enabled extension" {
        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_curl'; Name = 'php_curl.dll'; FullName = "$extDirectory\php_curl.dll" } )
        }

        Enable-IniExtension -iniPath $testIniPath -extNames @('curl') | Should -Be 0
    }

    It "Returns 0 immediately when extension is already enabled" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'php_curl'; status = 'Enabled'; color = 'DarkGreen'; line = 'extension=php_curl.dll'; lineNumber = 1 }
            )
        }
        Mock Set-ContentWrapper { }

        Enable-IniExtension -iniPath $testIniPath -extNames @('curl') | Should -Be 0
        Should -Invoke Set-ContentWrapper -Times 0
    }

    It "Returns 0 when line does not match for modification (file already has correct state)" {
        # Test the branch where $modified remains false because line pattern doesn't match
        @"
extension=php_xdebug.dll
extension=php_curl.dll
"@ | Set-ContentWrapper -path $testIniPath

        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$extDirectory\php_xdebug.dll" } )
        }
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'php_xdebug'; status = 'Disabled'; line = 'nonexistent_line'; lineNumber = 999 }
            )
        }

        Enable-IniExtension -iniPath $testIniPath -extNames @('xdebug') | Should -Be 0
        # File should remain unchanged since line didn't match
        (Get-ContentWrapper -path $testIniPath) | Should -Contain 'extension=php_xdebug.dll'
    }

    It "Returns -1 for non-existent extension" {
        Mock Get-ChildItemWrapper { return @() }
        Enable-IniExtension -iniPath $testIniPath -extNames @('nonexistent_ext') | Should -Be -1
    }

    It "Requires extension name" {
        Enable-IniExtension -iniPath $testIniPath -extNames '' | Should -Be -1
        Enable-IniExtension -iniPath $testIniPath -extNames $null | Should -Be -1
    }

    It "Handles zend_extension" {
        @"
;zend_extension=php_opcache.dll
extension=php_curl.dll
"@ | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_opcache'; Name = 'php_opcache.dll'; FullName = "$extDirectory\php_opcache.dll" } )
        }
        Enable-IniExtension -iniPath $testIniPath -extNames @('opcache') | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^zend_extension=php_opcache.dll' | Should -Be $true
    }

    It "Prompts user to select extension if multiple matches found" {
        @"
;extension=pdo_mysql
extension=pdo_pgsql
;extension=pdo_sqlite
;extension=pgsql
extension=sqlite3
"@ | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper {
            param ($path)
            return @(
                @{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = 'pdo_pgsql'; Name = 'pdo_pgsql.dll'; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = 'pdo_sqlite'; Name = 'pdo_sqlite.dll'; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = 'pgsql'; Name = 'pgsql.dll'; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = 'sqlite3'; Name = 'sqlite3.dll'; FullName = "$extDirectory\sqlite3.dll" }
            )
        }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nSelect a number" } -MockWith { return '0' }

        Enable-IniExtension -iniPath $testIniPath -extNames @('sql') | Should -Be 0

        (Get-ContentWrapper -path $testIniPath) -match '^extension\s*=\s*pdo_mysql' | Should -Be $true
    }

    It "Prints error message for non-valid number" {
        @"
;extension=pdo_mysql
extension=pdo_pgsql
;extension=pdo_sqlite
;extension=pgsql
extension=sqlite3
"@ | Set-ContentWrapper -path $testIniPath

        $script:callCount = 0
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nSelect a number" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { return 'A' }
            if ($script:callCount -eq 2) { return '-1' }
            else { return '3' }
        }

        Mock Get-ChildItemWrapper {
            param ($path)
            return @(
                @{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = 'pdo_pgsql'; Name = 'pdo_pgsql.dll'; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = 'pdo_sqlite'; Name = 'pdo_sqlite.dll'; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = 'pgsql'; Name = 'pgsql.dll'; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = 'sqlite3'; Name = 'sqlite3.dll'; FullName = "$extDirectory\sqlite3.dll" }
            )
        }

        Enable-IniExtension -iniPath $testIniPath -extNames @('sql') | Should -Be 0

        (Get-ContentWrapper -path $testIniPath) -match '^extension\s*=\s*pgsql' | Should -Be $true
    }

    It "Creates backup before modifying" {
        Enable-IniExtension -iniPath $testIniPath -extNames @('xdebug')
        Test-Path $testBackupPath | Should -Be $true
    }

    It "Returns -1 on error" {
        Mock Get-ContentWrapper { throw 'Access denied' }
        Enable-IniExtension -iniPath $testIniPath -extNames @('xdebug') | Should -Be -1
    }
}
