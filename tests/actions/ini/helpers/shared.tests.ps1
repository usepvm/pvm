
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\shared-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    function Reset-IniContent {
        # Create a test php.ini file
        @"
memory_limit = 128M
;zend_extension=php_xdebug.dll
extension=php_curl.dll
zend_extension=php_opcache.dll
display_errors = On
max_execution_time = 30
;upload_max_filesize = 2M
"@ | Set-ContentWrapper -path $testIniPath
    }

    # Create initial ini content first
    Reset-IniContent
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "ConvertTo-ExtensionId" {
    It "Returns empty string for null input" {
        $res = ConvertTo-ExtensionId -name $null
        $res | Should -BeNullOrEmpty
    }

    It "Returns empty string for whitespaced input" {
        $res = ConvertTo-ExtensionId -name '    '
        $res | Should -BeNullOrEmpty
    }

    It "returns an empty string for an empty string" {
        $res = ConvertTo-ExtensionId -name ''
        $res | Should -Be ''
    }

    It 'trims surrounding double quotes' {
        $res = ConvertTo-ExtensionId -name '"xdebug"'
        $res | Should -Be 'xdebug'
    }

    It 'trims surrounding single quotes' {
        $res = ConvertTo-ExtensionId -name "'xdebug'"
        $res | Should -Be 'xdebug'
    }

    It 'extracts filename from a full path' {
        $res = ConvertTo-ExtensionId -name 'C:\php\ext\php_xdebug.dll'
        $res | Should -Be 'xdebug'
    }

    It 'extracts filename from a unix-style path' {
        $res = ConvertTo-ExtensionId -name '/usr/lib/php/extensions/php_redis.dll'
        $res | Should -Be 'redis'
    }

    It 'strips the php_ prefix' {
        $res = ConvertTo-ExtensionId -name 'php_mbstring.dll'
        $res | Should -Be 'mbstring'
    }

    It 'strips the .dll extension' {
        $res = ConvertTo-ExtensionId -name 'opcache.dll'
        $res | Should -Be 'opcache'
    }

    It 'strips a trailing version suffix' {
        $res = ConvertTo-ExtensionId -name 'php_xdebug-3.2.1.dll'
        $res | Should -Be 'xdebug'
    }

    It 'strips a trailing version suffix with extra text' {
        $res = ConvertTo-ExtensionId -name 'php_xdebug-3.2.1-8.2-vs16-x86_64.dll'
        $res | Should -Be 'xdebug'
    }

    It 'lowercases the result' {
        $res = ConvertTo-ExtensionId -name 'PHP_XDEBUG.DLL'
        $res | Should -Be 'xdebug'
    }

    It 'handles a bare extension name with no prefix, suffix, or path' {
        $res = ConvertTo-ExtensionId -name 'redis'
        $res | Should -Be 'redis'
    }

    It 'handles combined quotes, path, prefix, version, and case' {
        $res = ConvertTo-ExtensionId -name '"C:\ext\PHP_Imagick-3.7.0-8.2-nts-vs16-x64.dll"'
        $res | Should -Be 'imagick'
    }
}

Describe "Backup-IniFile" {
    It "Creates a backup when none exists" {
        Remove-ItemWrapper -path $testBackupPath -ErrorAction SilentlyContinue
        $result = Backup-IniFile -iniPath $testIniPath
        $result | Should -Be 0
        Test-Path $testBackupPath | Should -Be $true
        (Get-ContentWrapper -path $testBackupPath) | Should -Be (Get-ContentWrapper -path $testIniPath)
    }

    It "Does not overwrite existing backup" {
        $originalContent = Get-ContentWrapper -path $testIniPath
        $result = Backup-IniFile -iniPath $testIniPath
        $result | Should -Be 0
        $newContent = 'modified content'
        $newContent | Set-ContentWrapper -path $testIniPath
        $result = Backup-IniFile -iniPath $testIniPath
        $result | Should -Be 0
        (Get-ContentWrapper -path $testBackupPath) | Should -Be $originalContent
    }

    It "Returns -1 on error" {
        Mock Copy-ItemWrapper { throw 'Access denied' }
        $result = Backup-IniFile -iniPath 'invalidpath'
        $result | Should -Be -1
    }
}

Describe "Get-AllPHPExtensionsStatus" {
    BeforeEach {
        Reset-IniContent
        Mock Backup-IniFile {}
        Mock Test-DirectoryExists { return $true }
        Mock Get-ZendExtensionsList { return @('xdebug', 'opcache') }
    }

    It "Returns empty when ext directory does not exist" {
        Mock Test-DirectoryExists { return $false }
        $res = Get-AllPHPExtensionsStatus -iniPath $testIniPath
        $res | Should -Be @()
    }

    It "Returns empty when ext directory has no dlls and ini has no extensions" {
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } { return @() }
        $res = Get-AllPHPExtensionsStatus -iniPath $testIniPath
        $res | Should -Be @()
    }

    It "Returns Disabled for dll in ext not configured in ini" {
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        $res.Length        | Should -Be 1
        $res[0]['name']    | Should -Be 'pdo_mysql'
        $res[0]['status']  | Should -Be 'Disabled'
        $res[0]['source']  | Should -Be 'ext,ini'
        (Get-ContentWrapper -path $testIniPath) | Should -Contain ';extension=pdo_mysql.dll'
    }

    It "Writes zend_extension prefix for known zend extensions" {
        '' | Set-ContentWrapper -path $testIniPath  # override whatever Reset-IniContent wrote
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{
                    BaseName = 'php_xdebug'
                    Name     = 'php_xdebug.dll'
                    FullName = "$extDirectory\php_xdebug.dll"
                }
            )
        }
        Mock Get-ZendExtensionsList {
            'xdebug'
            'opcache'
        }

        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        $res.Length        | Should -Be 1
        $res[0]['line']    | Should -Be ';zend_extension=php_xdebug.dll'
        $res[0]['enabled'] | Should -Be $false
        (Get-ContentWrapper -path $testIniPath) | Should -Contain ';zend_extension=php_xdebug.dll'
    }

    It "Returns Available when ini write fails for ext-only extension" {
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'php_testext'; Name = 'php_testext.dll'; FullName = "$extDirectory\php_testext.dll" }
            )
        }
        Mock Set-ContentWrapper { throw 'Disk full' }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        $res[0]['status'] | Should -Be 'Disabled'
        $res[0]['comment'] | Should -Be 'Available (not configured)'
        $res[0]['source'] | Should -Be 'ext'
    }

    It "Returns Enabled for extension configured as enabled in ini" {
        'extension=pdo_mysql' | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        $res.Length          | Should -Be 1
        $res[0]['status']    | Should -Be 'Enabled'
        $res[0]['enabled']   | Should -Be $true
        $res[0]['source']    | Should -Be 'ext,ini'
    }

    It "Returns Disabled for extension configured as disabled in ini" {
        ';extension=pdo_mysql' | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        $res[0]['status']  | Should -Be 'Disabled'
        $res[0]['enabled'] | Should -Be $false
    }

    It "Includes ini-only entry when no matching dll exists" {
        ';extension=oci8_12c  ; Use with Oracle Database 12c Instant Client' | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } { return @() }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath -includeIniOnly $true)
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
'@ | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath -includeIniOnly $true)
        $res.Length | Should -Be 2
        ($res | Where-Object -FilterScript { $_['name'] -eq 'pdo_mysql' })['source'] | Should -Be 'ext,ini'
        ($res | Where-Object -FilterScript { $_['name'] -eq 'oci8_12c' })['source']  | Should -Be 'ini'
    }

    It "Skips dll with empty basename after normalization" {
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'php_'; Name = 'php_.dll'; FullName = "$extDirectory\php_.dll" }
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        # php_ normalizes to '' and is skipped, only pdo_mysql survives
        $res.Length       | Should -Be 1
        $res[0]['name']   | Should -Be 'pdo_mysql'
    }

    It "Skips ini lines whose extension name normalizes to empty" {
        @'
extension=php_
extension=pdo_mysql
'@ | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        $res.Length      | Should -Be 1
        $res[0]['name']  | Should -Be 'pdo_mysql'
    }

    It "Skips disabled ini lines whose extension name normalizes to empty" {
        @'
;extension=php_
;extension=pdo_mysql
'@ | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'pdo_mysql'
    }

    It "Skips dll with null or empty BaseName" {
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = ''; Name = '.dll'; FullName = "$extDirectory\.dll" }
                [PSCustomObject]@{ BaseName = $null; Name = '.dll'; FullName = "$extDirectory\.dll" }
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        '' | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath)
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'pdo_mysql'
    }

    It "Skips adding extension with dll found to ini file" {
        '' | Set-ContentWrapper -path $testIniPath
        Mock Get-ChildItemWrapper -ParameterFilter { $Path -like '*ext*' } {
            return @(
                [PSCustomObject]@{ BaseName = 'pdo_mysql'; Name = 'pdo_mysql.dll'; FullName = "$extDirectory\pdo_mysql.dll" }
            )
        }
        $res = @(Get-AllPHPExtensionsStatus -iniPath $testIniPath -addToIniFileIfMissing $false)
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'pdo_mysql'
        $res[0]['line'] | Should -BeLike '*Found in ext directory*'
        Get-ContentWrapper -path $testIniPath | Should -Not -Contain ';extension=pdo_mysql.dll'
    }
}

Describe "Get-MatchingPHPExtensionsStatus" {
    It "Returns empty when extName is empty" {
        $res = Get-MatchingPHPExtensionsStatus -iniPath $testIniPath -extName ''
        $res | Should -Be @()
    }

    It "Returns empty when extName is whitespace" {
        $res = Get-MatchingPHPExtensionsStatus -iniPath $testIniPath -extName '   '
        $res | Should -Be @()
    }

    It "Returns empty when extName is null" {
        $res = Get-MatchingPHPExtensionsStatus -iniPath $testIniPath -extName $null
        $res | Should -Be @()
    }

    It "Returns empty when no extensions match the term" {
        Mock Get-AllPHPExtensionsStatus {
            return @(
                @{ name = 'pdo_mysql'; id = 'pdo_mysql'; status = 'Enabled'; enabled = $true }
                @{ name = 'mbstring'; id = 'mbstring'; status = 'Disabled'; enabled = $false }
            )
        }
        $res = Get-MatchingPHPExtensionsStatus -iniPath $testIniPath -extName 'xdebug'
        $res | Should -Be @()
    }

    It "Returns matched extensions by name" {
        Mock Get-AllPHPExtensionsStatus {
            return @(
                @{ name = 'pdo_mysql'; id = 'pdo_mysql'; status = 'Enabled'; enabled = $true }
                @{ name = 'pdo_pgsql'; id = 'pdo_pgsql'; status = 'Disabled'; enabled = $false }
                @{ name = 'pdo_sqlite'; id = 'pdo_sqlite'; status = 'Disabled'; enabled = $false }
                @{ name = 'mbstring'; id = 'mbstring'; status = 'Enabled'; enabled = $true }
            )
        }
        $res = @(Get-MatchingPHPExtensionsStatus -iniPath $testIniPath -extName 'pdo')
        $res.Length       | Should -Be 3
        $res.name         | Should -Contain 'pdo_mysql'
        $res.name         | Should -Contain 'pdo_pgsql'
        $res.name         | Should -Contain 'pdo_sqlite'
    }

    It "Returns matched extensions by id (normalized)" {
        Mock Get-AllPHPExtensionsStatus {
            return @(
                @{ name = 'php_xdebug'; id = 'xdebug'; status = 'Disabled'; enabled = $false }
                @{ name = 'mbstring'; id = 'mbstring'; status = 'Enabled'; enabled = $true }
            )
        }
        $res = @(Get-MatchingPHPExtensionsStatus -iniPath $testIniPath -extName 'xdebug')
        $res.Length        | Should -Be 1
        $res[0]['name']    | Should -Be 'php_xdebug'
    }

    It "Returns single match with correct status" {
        Mock Get-AllPHPExtensionsStatus {
            return @(
                @{ name = 'pdo_mysql'; id = 'pdo_mysql'; status = 'Enabled'; enabled = $true }
                @{ name = 'mbstring'; id = 'mbstring'; status = 'Enabled'; enabled = $true }
            )
        }
        $res = @(Get-MatchingPHPExtensionsStatus -iniPath $testIniPath -extName 'pdo_mysql')
        $res.Length          | Should -Be 1
        $res[0]['status']    | Should -Be 'Enabled'
        $res[0]['enabled']   | Should -Be $true
    }
}

Describe "Get-AllPHPSettings" {
    BeforeEach {
        Reset-IniContent
        Mock Backup-IniFile {}
    }

    It "Returns empty when ini has no key=value lines" {
        "; this is a comment`n[PHP]" | Set-ContentWrapper -path $testIniPath
        $res = Get-AllPHPSettings -iniPath $testIniPath
        $res | Should -Be @()
    }

    It "Returns all settings" {
        "memory_limit = 128M`nupload_max_filesize = 64M`n;max_execution_time = 30" | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res.Length | Should -Be 3
    }

    It "Sets enabled=true and status=Enabled for uncommented setting" {
        'memory_limit = 256M' | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res[0]['enabled'] | Should -Be $true
        $res[0]['status']  | Should -Be 'Enabled'
        $res[0]['color']   | Should -Be 'DarkGreen'
    }

    It "Sets enabled=false and status=Disabled for commented setting" {
        ';memory_limit = 256M' | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res[0]['enabled'] | Should -Be $false
        $res[0]['status']  | Should -Be 'Disabled'
        $res[0]['color']   | Should -Be 'DarkYellow'
    }

    It "Captures name correctly" {
        'memory_limit = 512M' | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res[0]['name'] | Should -Be 'memory_limit'
    }

    It "Captures value correctly" {
        'memory_limit = 512M' | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res[0]['value'] | Should -Be '512M'
    }

    It "Captures empty value correctly" {
        'session.save_path =' | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res[0]['value'] | Should -Be ''
    }

    It "Returns correct lineNo for each entry" {
        "memory_limit = 128M`nupload_max_filesize = 64M`nmax_execution_time = 30" | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res[0]['lineNo'] | Should -Be 0
        $res[1]['lineNo'] | Should -Be 1
        $res[2]['lineNo'] | Should -Be 2
    }

    It "Ignores section headers and comments" {
        "[PHP]`n; a comment`nmemory_limit = 128M" | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'memory_limit'
    }

    It "Returns both enabled and disabled entries" {
        "memory_limit = 128M`n;memory_limit = 256M" | Set-ContentWrapper -path $testIniPath
        $res = @(Get-AllPHPSettings -iniPath $testIniPath)
        $res.Length | Should -Be 2
        ($res | Where-Object -FilterScript { $_['enabled'] })['value']      | Should -Be '128M'
        ($res | Where-Object -FilterScript { -not $_['enabled'] })['value'] | Should -Be '256M'
    }
}

Describe "Get-MatchingPHPSettings" {
    BeforeEach {
        Reset-IniContent
    }

    It "Returns empty when searchKey is empty" {
        $res = Get-MatchingPHPSettings -iniPath $testIniPath -searchKey ''
        $res | Should -Be @()
    }

    It "Returns empty when searchKey is not provided" {
        $res = Get-MatchingPHPSettings -iniPath $testIniPath
        $res | Should -Be @()
    }

    It "Returns empty when no settings match the searchKey" {
        Mock Get-AllPHPSettings {
            return @(
                @{ name = 'memory_limit'; value = '128M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'upload_max_filesize'; value = '64M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
            )
        }
        $res = Get-MatchingPHPSettings -iniPath $testIniPath -searchKey 'xdebug'
        $res | Should -Be @()
    }

    It "Returns only matching settings when searchKey provided" {
        Mock Get-AllPHPSettings {
            return @(
                @{ name = 'memory_limit'; value = '128M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'upload_max_filesize'; value = '64M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'max_execution_time'; value = '30'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
            )
        }
        $res = @(Get-MatchingPHPSettings -iniPath $testIniPath -searchKey 'memory')
        $res.Length     | Should -Be 1
        $res[0]['name'] | Should -Be 'memory_limit'
    }

    It "Returns multiple matches for partial searchKey" {
        Mock Get-AllPHPSettings {
            return @(
                @{ name = 'pdo_mysql.default_socket'; value = ''; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'pdo_pgsql.default_socket'; value = ''; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'memory_limit'; value = '128M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
            )
        }
        $res = @(Get-MatchingPHPSettings -iniPath $testIniPath -searchKey 'pdo')
        $res.Length | Should -Be 2
        $res.name   | Should -Contain 'pdo_mysql.default_socket'
        $res.name   | Should -Contain 'pdo_pgsql.default_socket'
    }

    It "Returns enabled and disabled matches for same searchKey" {
        Mock Get-AllPHPSettings {
            return @(
                @{ name = 'memory_limit'; value = '128M'; enabled = $true; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'memory_limit'; value = '256M'; enabled = $false; status = 'Disabled'; color = 'DarkYellow' }
            )
        }
        $res = @(Get-MatchingPHPSettings -iniPath $testIniPath -searchKey 'memory_limit')
        $res.Length | Should -Be 2
        ($res | Where-Object -FilterScript { $_['enabled'] })['value']      | Should -Be '128M'
        ($res | Where-Object -FilterScript { -not $_['enabled'] })['value'] | Should -Be '256M'
    }
}
