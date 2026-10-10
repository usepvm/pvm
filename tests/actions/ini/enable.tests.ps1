
BeforeAll {
    if (-not $Global:CurrentTestDrive) {
        $currentFileName = Split-Path -Path $PSCommandPath -Leaf
        $msg = "`nTest Drive is not set for '$currentFileName'"
        $line = "`n$('=' * $msg.Length)"
        $errorMessage = $line + $msg + $line
        throw " `n$errorMessage"
    }

    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:phpPath = "$script:TEST_DRIVE\php"
    $script:testIniPath = "$script:phpPath\php.ini"
    $script:extDirectory = "$script:phpPath\ext"
    $script:testBackupPath = "$script:phpPath\$($Global:PVMConfig.constants.INI_BACKUP_DIR_NAME)"

    $null = New-Item -ItemType Directory -Path $Global:PVMConfig.paths.directories.cache -Force
    $null = New-Item -ItemType Directory -Path $script:phpPath -Force
    $null = New-Item -ItemType Directory -Path $script:extDirectory -Force

    Mock Show-Warning { }
    Mock Show-Info { }
    Mock Show-Message { }
    Mock Write-Color { }
    Mock Backup-IniFile { return 0 }

    function Reset-IniContent {
        @(
            'memory_limit = 128M'
            ';extension=php_xdebug.dll'
            'extension=php_curl.dll'
            'zend_extension=php_opcache.dll'
            'display_errors = On'
            'max_execution_time = 30'
            ';upload_max_filesize = 2M'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8
    }

    Reset-IniContent
}

Describe "Enable-IniExtension" {
    BeforeEach {
        Mock Test-DirectoryExists -ParameterFilter { $path -eq $script:extDirectory } -MockWith { return $true }
        Reset-IniContent
        Remove-Item -Path $script:testBackupPath -Force -Recurse -ErrorAction SilentlyContinue
    }

    It "Enables commented extension" {
        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$script:extDirectory\php_xdebug.dll" } )
        }
        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames @('xdebug')
        $code | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) -match '^extension=php_xdebug.dll' | Should -Be $true
    }

    It "Returns 0 for already enabled extension" {
        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_curl'; Name = 'php_curl.dll'; FullName = "$script:extDirectory\php_curl.dll" } )
        }

        $code =Enable-IniExtension -iniPath $script:testIniPath -extNames @('curl')
        $code | Should -Be 0
    }

    It "Returns 0 immediately when extension is already enabled" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'php_curl'; status = 'Enabled'; color = 'DarkGreen'; line = 'extension=php_curl.dll'; lineNumber = 1 }
            )
        }
        Mock Set-ContentWrapper { return 0 }

        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames @('curl')
        $code | Should -Be 0
        Should -Invoke Set-ContentWrapper -Times 0
    }

    It "Returns 0 when line does not match for modification (file already has correct state)" {
        # Test the branch where $modified remains false because line pattern doesn't match
        @(
            'extension=php_xdebug.dll'
            'extension=php_curl.dll'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8

        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$script:extDirectory\php_xdebug.dll" } )
        }
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'php_xdebug'; status = 'Disabled'; line = 'nonexistent_line'; lineNumber = 999 }
            )
        }

        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames @('xdebug')
        $code | Should -Be 0
        # File should remain unchanged since line didn't match
        (Get-ContentWrapper -path $script:testIniPath) | Should -Contain 'extension=php_xdebug.dll'
    }

    It "Returns -1 for non-existent extension" {
        Mock Get-ChildItemWrapper { return @() }
        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames @('nonexistent_ext')
        $code | Should -Be -1
    }

    It "Requires extension name" {
        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames ''
        $code | Should -Be -1
        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames $null
        $code | Should -Be -1
    }

    It "Handles zend_extension" {
        @(
            ';zend_extension=php_opcache.dll'
            'extension=php_curl.dll'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8
        Mock Get-ChildItemWrapper {
            param ($path)
            return @( @{ BaseName = 'php_opcache'; Name = 'php_opcache.dll'; FullName = "$script:extDirectory\php_opcache.dll" } )
        }
        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames @('opcache')
        $code | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) -match '^zend_extension=php_opcache.dll' | Should -Be $true
    }

    It "Prompts user to select extension if multiple matches found" {
        @(
            ';extension=pdo_mysql'
            'extension=pdo_pgsql'
            ';extension=pdo_sqlite'
            ';extension=pgsql'
            'extension=sqlite3'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8
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

        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames @('sql')
        $code | Should -Be 0

        (Get-ContentWrapper -path $script:testIniPath) -match '^extension\s*=\s*pdo_mysql' | Should -Be $true
    }

    It "Prints error message for non-valid number" {
        @(
            ';extension=pdo_mysql'
            'extension=pdo_pgsql'
            ';extension=pdo_sqlite'
            ';extension=pgsql'
            'extension=sqlite3'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8

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

        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames @('sql')
        $code | Should -Be 0

        (Get-ContentWrapper -path $script:testIniPath) -match '^extension\s*=\s*pgsql' | Should -Be $true
        Should -Invoke Show-Warning -ParameterFilter { $message -eq 'Please enter a valid positive number.'}
        Should -Invoke Show-Warning -ParameterFilter { $message -eq "Number must be between 0 and $($dllFiles.Length - 1)." }
    }

    It "Creates backup before modifying" {
        Enable-IniExtension -iniPath $script:testIniPath -extNames @('xdebug')
        Should -Invoke Backup-IniFile -ParameterFilter { $iniPath -like "*$script:testIniPath*" }
    }

    It "Returns -1 on error" {
        Mock Add-LogEntry { return 0 }
        Mock Get-MatchingPHPExtensionsStatus { throw 'Access denied' }
        $code = Enable-IniExtension -iniPath $script:testIniPath -extNames @('xdebug')
        $code | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
    }
}
