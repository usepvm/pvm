
BeforeAll {
    $testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $testIniPath = "$testDrivePath\php.ini"
    $extDirectory = "$testDrivePath\ext"
    $testBackupPath = "$testIniPath.bak"

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
}

Describe "Backup-IniFile" {
    It "Creates a backup when none exists" {
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
        Backup-IniFile -iniPath $testIniPath
        Test-Path $testBackupPath | Should -Be $true
        (Get-Content $testBackupPath) | Should -Be (Get-Content $testIniPath)
    }

    It "Does not overwrite existing backup" {
        $originalContent = Get-Content $testIniPath
        Backup-IniFile -iniPath $testIniPath
        $newContent = 'modified content'
        $newContent | Set-Content $testIniPath
        Backup-IniFile -iniPath $testIniPath
        (Get-Content $testBackupPath) | Should -Be $originalContent
    }

    It "Returns -1 on error" {
        Mock Copy-Item { throw 'Access denied' }
        Backup-IniFile -iniPath 'invalidpath' | Should -Be -1
    }
}

Describe "Get-Matching-PHPExtensionsStatus" {
    BeforeEach {
        Reset-Ini-Content
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } -MockWith { return $true }
        Mock Get-Zend-Extensions-List { return @('xdebug', 'opcache') }
    }

    It "Returns empty when ext directory missing" {
        Remove-Item -Recurse -Force ("$testIniPath\..\ext") -ErrorAction SilentlyContinue
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'testext'
        $res | Should -Be @()
    }

    It "Finds extensions in ext directory and marks them Disabled when not in ini" {
        Mock Get-ChildItem {
            param ($Path)
            return @(
                @{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = 'pdo_pgsql'; Name = 'pdo_pgsql.dll'; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = 'pdo_sqlite'; Name = 'pdo_sqlite.dll'; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = 'pgsql'; Name = 'pgsql.dll'; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = 'sqlite3'; Name = 'sqlite3.dll'; FullName = "$extDirectory\sqlite3.dll" }
            )
        }
        # ensure ext exists and not configured in ini
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'sql'
        $res.Count | Should -BeGreaterThan 0
        $res[0].status | Should -Be 'Disabled'
    }

    It "Adds a disabled zend_extension entry when a zend extension exists in ext but not in ini" {
        @"
zend_extension=php_opcache.dll
extension=php_mbstring.dll
"@ | Set-Content $testIniPath
        Mock Get-ChildItem {
            param ($Path)
            return @(
                @{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$extDirectory\php_xdebug.dll" }
            )
        }
        Mock Get-Zend-Extensions-List { return @('xdebug') }

        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'xdebug'

        $res.Length | Should -Be 1
        $res.status | Should -Be 'Disabled'
        $res.line | Should -Be ';zend_extension=php_xdebug.dll'
        (Get-Content $testIniPath) | Should -Contain ';zend_extension=php_xdebug.dll'
    }

    It "Uses wildcard '*.dll' search when extName is empty" {
        Mock Get-ChildItem {
            param ($Path)
            return @(
                @{ BaseName = 'php_testext'; Name = 'php_testext.dll'; FullName = "$extDirectory\php_testext.dll" }
            )
        }
        Mock Is-Directory-Exists { return $true }

        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName ''
        $res.Length | Should -Be 1
        $res.name | Should -Be 'php_testext'
        $res.status | Should -Be 'Disabled'
    }

    It "Skips invalid ini extension names and increments line numbers" {
        Mock Get-ChildItem {
            param ($Path)
            return @(
                @{ BaseName = 'php_testext'; Name = 'php_testext.dll'; FullName = "$extDirectory\php_testext.dll" }
            )
        }
        Mock Is-Directory-Exists { return $true }
        @"
extension=.dll
;extension=.dll
"@ | Set-Content $testIniPath

        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName ''
        $res.Length | Should -Be 1
        $res.name | Should -Be 'php_testext'
    }

    It "Returns available status when ini write fails" {
        Mock Get-ChildItem {
            param ($Path)
            return @(
                @{ BaseName = 'php_testext'; Name = 'php_testext.dll'; FullName = "$extDirectory\php_testext.dll" }
            )
        }
        Mock Is-Directory-Exists { return $true }
        Mock Get-Zend-Extensions-List { return @() }
        Mock Set-Content { throw 'Disk full' }

        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'testext'
        $res.Length | Should -Be 1
        $res.status | Should -Be 'Available (not configured)'
        $res.line | Should -Be 'Found in ext directory: $($extMatch.fullPath)'
    }

    It "Detects extension configured as Enabled in ini file" {
        # configure extension as enabled in ini
        # Add-Content -Path $testIniPath -Value "extension=php_testext.dll"
        @"
extension=pdo_mysql
"@ | Set-Content $testIniPath
        Mock Get-ChildItem {
            param ($Path)
            return @(
                @{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = 'pdo_pgsql'; Name = 'pdo_pgsql.dll'; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = 'pdo_sqlite'; Name = 'pdo_sqlite.dll'; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = 'pgsql'; Name = 'pgsql.dll'; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = 'sqlite3'; Name = 'sqlite3.dll'; FullName = "$extDirectory\sqlite3.dll" }
            )
        }
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'sql'
        $res | Should -Not -Be @()
        $res[0].status | Should -Be 'Enabled'
    }
}
