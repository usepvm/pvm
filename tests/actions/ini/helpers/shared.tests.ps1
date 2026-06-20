
BeforeAll {
    $script:testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $script:testIniPath = "$testDrivePath\php.ini"
    $script:extDirectory = "$testDrivePath\ext"
    $script:testBackupPath = "$testIniPath.bak"

    Mock Write-Host {}

    function Reset-Ini-Content {
        # Create a test php.ini file
        @"
memory_limit = 128M
;zend_extension=php_xdebug.dll
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
        Remove-Item -Path $testBackupPath -ErrorAction SilentlyContinue
        Backup-IniFile -iniPath $testIniPath
        Test-Path $testBackupPath | Should -Be $true
        (Get-Content -Path $testBackupPath) | Should -Be (Get-Content -Path $testIniPath)
    }

    It "Does not overwrite existing backup" {
        $originalContent = Get-Content -Path $testIniPath
        Backup-IniFile -iniPath $testIniPath
        $newContent = 'modified content'
        $newContent | Set-Content -Path $testIniPath
        Backup-IniFile -iniPath $testIniPath
        (Get-Content -Path $testBackupPath) | Should -Be $originalContent
    }

    It "Returns -1 on error" {
        Mock Copy-Item { throw 'Access denied' }
        Backup-IniFile -iniPath 'invalidpath' | Should -Be -1
    }
}

Describe "Get-All-PHPExtensionsStatus" {
    BeforeEach {
        Reset-Ini-Content
        Mock Backup-IniFile {}
        Mock Is-Directory-Exists { return $true }
        Mock Get-Zend-Extensions-List { return @('xdebug', 'opcache') }
    }

    It "Returns empty when ext directory does not exist" {
        Mock Is-Directory-Exists { return $false }
        $res = Get-All-PHPExtensionsStatus -iniPath $testIniPath
        $res | Should -Be @()
    }

    It "Returns empty when ext directory has no dlls and ini has no extensions" {
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } { return @() }
        $res = Get-All-PHPExtensionsStatus -iniPath $testIniPath
        $res | Should -Be @()
    }

    It "Returns Disabled for dll in ext not configured in ini" {
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        $res.Length        | Should -Be 1
        $res[0]['name']    | Should -Be 'pdo_mysql'
        $res[0]['status']  | Should -Be 'Disabled'
        $res[0]['source']  | Should -Be 'ext,ini'
        (Get-Content -Path $testIniPath) | Should -Contain ';extension=pdo_mysql.dll'
    }

    It "Writes zend_extension prefix for known zend extensions" {
        '' | Set-Content -Path $testIniPath  # override whatever Reset-Ini-Content wrote
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{
                    BaseName = 'php_xdebug'
                    Name     = 'php_xdebug.dll'
                    FullName = "$extDirectory\php_xdebug.dll"
                }
            )
        }
        Mock Get-Zend-Extensions-List {
            'xdebug'
            'opcache'
        }

        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        $res.Length        | Should -Be 1
        $res[0]['line']    | Should -Be ';zend_extension=php_xdebug.dll'
        $res[0]['enabled'] | Should -Be $false
        (Get-Content -Path $testIniPath) | Should -Contain ';zend_extension=php_xdebug.dll'
    }

    It "Returns Available when ini write fails for ext-only extension" {
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'php_testext'; Name = 'php_testext.dll'; FullName = "$extDirectory\php_testext.dll" }
            )
        }
        Mock Set-Content { throw 'Disk full' }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        $res[0]['status'] | Should -Be 'Disabled'
        $res[0]['comment'] | Should -Be 'Available (not configured)'
        $res[0]['source'] | Should -Be 'ext'
    }

    It "Returns Enabled for extension configured as enabled in ini" {
        'extension=pdo_mysql' | Set-Content -Path $testIniPath
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        $res.Length          | Should -Be 1
        $res[0]['status']    | Should -Be 'Enabled'
        $res[0]['enabled']   | Should -Be $true
        $res[0]['source']    | Should -Be 'ext,ini'
    }

    It "Returns Disabled for extension configured as disabled in ini" {
        ';extension=pdo_mysql' | Set-Content -Path $testIniPath
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        $res[0]['status']  | Should -Be 'Disabled'
        $res[0]['enabled'] | Should -Be $false
    }

    It "Includes ini-only entry when no matching dll exists" {
        ';extension=oci8_12c  ; Use with Oracle Database 12c Instant Client' | Set-Content -Path $testIniPath
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } { return @() }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath -includeIniOnly $true)
        $res.Length          | Should -Be 1
        $res[0]['name']      | Should -Be 'oci8_12c'
        $res[0]['source']    | Should -Be 'ini'
        $res[0]['enabled']   | Should -Be $false
        $res[0]['fullPath']  | Should -Be $null
    }

    It "Returns both ext+ini and ini-only entries together" {
        @'
extension=pdo_mysql
;extension=oci8_12c
'@ | Set-Content -Path $testIniPath
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath -includeIniOnly $true)
        $res.Length | Should -Be 2
        ($res | Where-Object { $_['name'] -eq 'pdo_mysql' })['source'] | Should -Be 'ext,ini'
        ($res | Where-Object { $_['name'] -eq 'oci8_12c' })['source']  | Should -Be 'ini'
    }

    It "Skips dll with empty basename after normalization" {
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'php_'; Name = 'php_.dll'; FullName = "$extDirectory\php_.dll" }
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        # php_ normalizes to '' and is skipped, only pdo_mysql survives
        $res.Length       | Should -Be 1
        $res[0]['name']   | Should -Be 'pdo_mysql'
    }

    It "Skips ini lines whose extension name normalizes to empty" {
        @'
extension=php_
extension=pdo_mysql
'@ | Set-Content -Path $testIniPath
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        $res.Length      | Should -Be 1
        $res[0]['name']  | Should -Be 'pdo_mysql'
    }

    It "Skips disabled ini lines whose extension name normalizes to empty" {
        @'
;extension=php_
;extension=pdo_mysql
'@ | Set-Content -Path $testIniPath
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'pdo_mysql'
    }

    It "Skips dll with null or empty BaseName" {
        Mock Get-ChildItem -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = ''; Name = '.dll'; FullName = "$extDirectory\.dll" }
                [PSCustomObject]@{ BaseName = $null; Name = '.dll'; FullName = "$extDirectory\.dll" }
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        '' | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPExtensionsStatus -iniPath $testIniPath)
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'pdo_mysql'
    }
}

Describe "Get-Matching-PHPExtensionsStatus" {
    It "Returns empty when extName is empty" {
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName ''
        $res | Should -Be @()
    }

    It "Returns empty when extName is whitespace" {
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName '   '
        $res | Should -Be @()
    }

    It "Returns empty when extName is null" {
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName $null
        $res | Should -Be @()
    }

    It "Returns empty when no extensions match the term" {
        Mock Get-All-PHPExtensionsStatus {
            return @(
                @{ name = 'pdo_mysql'; id = 'pdo_mysql'; status = 'Enabled'; enabled = $true }
                @{ name = 'mbstring'; id = 'mbstring'; status = 'Disabled'; enabled = $false }
            )
        }
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'xdebug'
        $res | Should -Be @()
    }

    It "Returns matched extensions by name" {
        Mock Get-All-PHPExtensionsStatus {
            return @(
                @{ name = 'pdo_mysql'; id = 'pdo_mysql'; status = 'Enabled'; enabled = $true }
                @{ name = 'pdo_pgsql'; id = 'pdo_pgsql'; status = 'Disabled'; enabled = $false }
                @{ name = 'pdo_sqlite'; id = 'pdo_sqlite'; status = 'Disabled'; enabled = $false }
                @{ name = 'mbstring'; id = 'mbstring'; status = 'Enabled'; enabled = $true }
            )
        }
        $res = @(Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'pdo')
        $res.Length       | Should -Be 3
        $res.name         | Should -Contain 'pdo_mysql'
        $res.name         | Should -Contain 'pdo_pgsql'
        $res.name         | Should -Contain 'pdo_sqlite'
    }

    It "Returns matched extensions by id (normalized)" {
        Mock Get-All-PHPExtensionsStatus {
            return @(
                @{ name = 'php_xdebug'; id = 'xdebug'; status = 'Disabled'; enabled = $false }
                @{ name = 'mbstring'; id = 'mbstring'; status = 'Enabled'; enabled = $true }
            )
        }
        $res = @(Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'xdebug')
        $res.Length        | Should -Be 1
        $res[0]['name']    | Should -Be 'php_xdebug'
    }

    It "Returns single match with correct status" {
        Mock Get-All-PHPExtensionsStatus {
            return @(
                @{ name = 'pdo_mysql'; id = 'pdo_mysql'; status = 'Enabled'; enabled = $true }
                @{ name = 'mbstring'; id = 'mbstring'; status = 'Enabled'; enabled = $true }
            )
        }
        $res = @(Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName 'pdo_mysql')
        $res.Length          | Should -Be 1
        $res[0]['status']    | Should -Be 'Enabled'
        $res[0]['enabled']   | Should -Be $true
    }
}

Describe "Get-All-PHPSettings" {
    BeforeEach {
        Reset-Ini-Content
        Mock Backup-IniFile {}
    }

    It "Returns empty when ini has no key=value lines" {
        "; this is a comment`n[PHP]" | Set-Content -Path $testIniPath
        $res = Get-All-PHPSettings -iniPath $testIniPath
        $res | Should -Be @()
    }

    It "Returns all settings" {
        "memory_limit = 128M`nupload_max_filesize = 64M`n;max_execution_time = 30" | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res.Length | Should -Be 3
    }

    It "Sets enabled=true and status=Enabled for uncommented setting" {
        'memory_limit = 256M' | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res[0]['enabled'] | Should -Be $true
        $res[0]['status']  | Should -Be 'Enabled'
        $res[0]['color']   | Should -Be 'DarkGreen'
    }

    It "Sets enabled=false and status=Disabled for commented setting" {
        ';memory_limit = 256M' | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res[0]['enabled'] | Should -Be $false
        $res[0]['status']  | Should -Be 'Disabled'
        $res[0]['color']   | Should -Be 'DarkYellow'
    }

    It "Captures name correctly" {
        'memory_limit = 512M' | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res[0]['name'] | Should -Be 'memory_limit'
    }

    It "Captures value correctly" {
        'memory_limit = 512M' | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res[0]['value'] | Should -Be '512M'
    }

    It "Captures empty value correctly" {
        'session.save_path =' | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res[0]['value'] | Should -Be ''
    }

    It "Returns correct lineNo for each entry" {
        "memory_limit = 128M`nupload_max_filesize = 64M`nmax_execution_time = 30" | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res[0]['lineNo'] | Should -Be 0
        $res[1]['lineNo'] | Should -Be 1
        $res[2]['lineNo'] | Should -Be 2
    }

    It "Ignores section headers and comments" {
        "[PHP]`n; a comment`nmemory_limit = 128M" | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'memory_limit'
    }

    It "Returns both enabled and disabled entries" {
        "memory_limit = 128M`n;memory_limit = 256M" | Set-Content -Path $testIniPath
        $res = @(Get-All-PHPSettings -iniPath $testIniPath)
        $res.Length | Should -Be 2
        ($res | Where-Object { $_['enabled'] })['value']      | Should -Be '128M'
        ($res | Where-Object { -not $_['enabled'] })['value'] | Should -Be '256M'
    }
}

Describe "Get-Matching-PHPSettings" {
    BeforeEach {
        Reset-Ini-Content
    }

    It "Returns empty when searchKey is empty" {
        $res = Get-Matching-PHPSettings -iniPath $testIniPath -searchKey ''
        $res | Should -Be @()
    }

    It "Returns empty when searchKey is not provided" {
        $res = Get-Matching-PHPSettings -iniPath $testIniPath
        $res | Should -Be @()
    }

    It "Returns empty when no settings match the searchKey" {
        Mock Get-All-PHPSettings {
            return @(
                @{ name = 'memory_limit'; value = '128M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'upload_max_filesize'; value = '64M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
            )
        }
        $res = Get-Matching-PHPSettings -iniPath $testIniPath -searchKey 'xdebug'
        $res | Should -Be @()
    }

    It "Returns only matching settings when searchKey provided" {
        Mock Get-All-PHPSettings {
            return @(
                @{ name = 'memory_limit'; value = '128M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'upload_max_filesize'; value = '64M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'max_execution_time'; value = '30'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
            )
        }
        $res = @(Get-Matching-PHPSettings -iniPath $testIniPath -searchKey 'memory')
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'memory_limit'
    }

    It "Returns multiple matches for partial searchKey" {
        Mock Get-All-PHPSettings {
            return @(
                @{ name = 'pdo_mysql.default_socket'; value = ''; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'pdo_pgsql.default_socket'; value = ''; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'memory_limit'; value = '128M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
            )
        }
        $res = @(Get-Matching-PHPSettings -iniPath $testIniPath -searchKey 'pdo')
        $res.Length | Should -Be 2
        $res.name   | Should -Contain 'pdo_mysql.default_socket'
        $res.name   | Should -Contain 'pdo_pgsql.default_socket'
    }

    It "Returns enabled and disabled matches for same searchKey" {
        Mock Get-All-PHPSettings {
            return @(
                @{ name = 'memory_limit'; value = '128M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'memory_limit'; value = '256M'; enabled = $false; status = 'Disabled'; color = 'DarkYellow' }
            )
        }
        $res = @(Get-Matching-PHPSettings -iniPath $testIniPath -searchKey 'memory_limit')
        $res.Length | Should -Be 2
        ($res | Where-Object { $_['enabled'] })['value']      | Should -Be '128M'
        ($res | Where-Object { -not $_['enabled'] })['value'] | Should -Be '256M'
    }
}
