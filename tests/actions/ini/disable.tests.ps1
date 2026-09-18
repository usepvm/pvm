
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:phpVersionPath = "$script:TEST_DRIVE\php-8.2"
    $script:testIniPath = "$script:phpVersionPath\php.ini"
    $script:extDirectory = "$script:phpVersionPath\ext"
    $script:testBackupPath = "$script:testIniPath.bak"

    New-Directory -path $Global:PVMConfig.paths.directories.cache
    New-Directory -path $script:phpVersionPath
    New-Directory -path $script:extDirectory

    Mock Show-Warning { }
    Mock Show-Info { }
    Mock Show-Message { }
    Mock Write-Color { }

    function Reset-IniContent {
        @(
        'memory_limit = 128M'
        ';extension=php_xdebug.dll'
        'extension=php_curl.dll'
        'zend_extension=php_opcache.dll'
        'display_errors = On'
        'max_execution_time = 30'
        ';upload_max_filesize = 2M'
        ) -join "`n" | Set-ContentWrapper -path $script:testIniPath
    }

    Reset-IniContent
}

Describe "Disable-IniExtension" {
    BeforeEach {
        Mock Test-DirectoryExists -ParameterFilter { $path -eq $script:extDirectory } -MockWith { return $true }
        Reset-IniContent
        Remove-ItemWrapper -path $script:testBackupPath
    }

    It "Disables enabled extension" {
        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_curl'; Name = 'php_curl.dll'; FullName = "$script:extDirectory\php_curl.dll" } )
        }
        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('curl')
        $code | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) -match '^;extension=php_curl.dll' | Should -Be $true
    }

    It "Returns -1 for already disabled extension" {
        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('xdebug')
        $code | Should -Be -1
    }

    It "Returns 0 immediately when extension is already disabled" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'php_xdebug'; status = 'Disabled'; color = 'DarkYellow'; line = ';extension=php_xdebug.dll'; lineNumber = 1 }
            )
        }
        Mock Set-ContentWrapper { }

        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('xdebug')
        $code | Should -Be 0
        Should -Invoke Set-ContentWrapper -Times 0
    }

    It "Returns -1 for non-existent extension" {
        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('nonexistent_ext')
        $code | Should -Be -1
    }

    It "Requires extension name" {
        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames ''
        $code | Should -Be -1
        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames $null
        $code | Should -Be -1
    }

    It "Handles zend_extension" {
        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_opcache'; Name = 'php_opcache.dll'; FullName = "$script:extDirectory\php_opcache.dll" } )
        }
        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('opcache')
        $code | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) -match '^;zend_extension=php_opcache.dll' | Should -Be $true
    }

    It "Returns 0 when no line modification occurs while disabling extension" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'php_curl'; status = 'Enabled'; color = 'DarkGreen'; line = 'extension=php_curl.dll'; lineNumber = 10 }
            )
        }
        Mock Get-ContentWrapper { return @('extension=php_curl.dll') }
        Mock Set-ContentWrapper { }

        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('curl')
        $code | Should -Be 0
        Should -Invoke Set-ContentWrapper -Times 0
    }

    It "Prompts user to select extension if multiple matches found" {
        @(
            'extension=pdo_mysql'
            ';extension=pdo_pgsql'
            'extension=pdo_sqlite'
            'extension=pgsql'
            ';extension=sqlite3'
        ) -join "`n" | Set-ContentWrapper -path $script:testIniPath
        Mock Get-ChildItemWrapper {
            param ($path)
            return @(
                @{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$script:extDirectory\pdo_mysql.dll" }
                @{ BaseName = 'pdo_pgsql'; Name = 'pdo_pgsql.dll'; FullName = "$script:extDirectory\pdo_pgsql.dll" }
                @{ BaseName = 'pdo_sqlite'; Name = 'pdo_sqlite.dll'; FullName = "$script:extDirectory\pdo_sqlite.dll" }
                @{ BaseName = 'pgsql'; Name = 'pgsql.dll'; FullName = "$script:extDirectory\pgsql.dll" }
                @{ BaseName = 'sqlite3'; Name = 'sqlite3.dll'; FullName = "$script:extDirectory\sqlite3.dll" }
            )
        }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nSelect a number" } -MockWith { return '0' }

        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('sql')
        $code | Should -Be 0

        (Get-ContentWrapper -path $script:testIniPath) -match '^;extension\s*=\s*pdo_mysql' | Should -Be $true
    }

    It "Prints error message for non-valid number" {
        @(
            'extension=pdo_mysql'
            ';extension=pdo_pgsql'
            'extension=pdo_sqlite'
            'extension=pgsql'
            ';extension=sqlite3'
        ) -join "`n" | Set-ContentWrapper -path $script:testIniPath

        $script:callCount = 0
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nSelect a number" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { return 'A' }
            if ($script:callCount -eq 2) { return '-1' }
            else { return '3' }
        }

        $dllFiles = @(
            @{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$script:extDirectory\pdo_mysql.dll" }
            @{ BaseName = 'pdo_pgsql'; Name = 'pdo_pgsql.dll'; FullName = "$script:extDirectory\pdo_pgsql.dll" }
            @{ BaseName = 'pdo_sqlite'; Name = 'pdo_sqlite.dll'; FullName = "$script:extDirectory\pdo_sqlite.dll" }
            @{ BaseName = 'pgsql'; Name = 'pgsql.dll'; FullName = "$script:extDirectory\pgsql.dll" }
            @{ BaseName = 'sqlite3'; Name = 'sqlite3.dll'; FullName = "$script:extDirectory\sqlite3.dll" }
        )
        Mock Get-ChildItemWrapper {
            param ($path)
            return $dllFiles
        }
        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('sql')
        $code | Should -Be 0

        (Get-ContentWrapper -path $script:testIniPath) -match '^;extension\s*=\s*pgsql' | Should -Be $true
        Should -Invoke Show-Warning -ParameterFilter { $message -eq 'Please enter a valid positive number.'}
        Should -Invoke Show-Warning -ParameterFilter { $message -eq "Number must be between 0 and $($dllFiles.Length - 1)." }
    }

    It "Creates backup before modifying" {
        Disable-IniExtension -iniPath $script:testIniPath -extNames @('curl')
        Test-Path $script:testBackupPath | Should -Be $true
    }

    It "Returns -1 on error" {
        Mock Add-LogEntry { return 0 }
        Mock Get-MatchingPHPExtensionsStatus { throw 'Access denied' }
        $code = Disable-IniExtension -iniPath $script:testIniPath -extNames @('curl')
        $code | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
    }
}
