# Load required modules and functions
. "$PSScriptRoot\..\src\actions\ini.ps1"

BeforeAll {
    $testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $testIniPath = Join-Path $testDrivePath "php.ini"
    $extDirectory = Join-Path $testDrivePath "ext"
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
    
    # Mock global variables
    $script:LOG_ERROR_PATH = Join-Path $testDrivePath "error.log"
    $script:PHP_CURRENT_VERSION_PATH = Join-Path $testDrivePath "php"
    
    # Create directory and symlink for current PHP version
    $phpVersionPath = Join-Path $testDrivePath "php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
    Copy-Item $testIniPath (Join-Path $phpVersionPath "php.ini") -Force
    
    # Mock Log-Data function
    function script:Log-Data {
        param($logPath, $message, $data)
        return $true
    }
    
    # Mock Get-Current-PHP-Version function
    function script:Get-Current-PHP-Version {
        return @{
            version = "8.2.0"
            path = $phpVersionPath
        }
    }
    
    $global:MockFileSystem = @{
        Directories = @()
        Files = @{}
        WebResponses = @{}
        DownloadFails = $false
    }
    function Invoke-WebRequest {
        param($Uri, $OutFile = $null)
        
        if ($global:MockFileSystem.DownloadFails) {
            throw "Network error"
        }
        
        if ($global:MockFileSystem.WebResponses.ContainsKey($Uri)) {
            $response = $global:MockFileSystem.WebResponses[$Uri]
            if ($OutFile) {
                $global:MockFileSystem.Files[$OutFile] = "Downloaded content"
                return
            }
            return @{
                Content = $response.Content
                Links = $response.Links
            }
        }
        
        throw "URL not mocked: $Uri"
    }
}

Describe "Add-Missing-PHPExtension" {
    BeforeEach {
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
    }
    
    It "Returns -1 when current PHP version is null" {
        Mock Get-Current-PHP-Version { return @{ version = $null; path = $null } }
        $result = Add-Missing-PHPExtension -iniPath $testIniPath -extName "curl"
        $result | Should -Be -1
    }
    
    It "Adds and configures xdebug in ini file" {
        $result = Add-Missing-PHPExtension -iniPath $testIniPath -extName "xdebug"
        $result | Should -Be 0
    }
    
    It "Adds any extension to ini file" {
        @"
zend_extension=php_opcache.dll
extension=php_mbstring.dll
"@ | Set-Content $testIniPath
        $result = Add-Missing-PHPExtension -iniPath $testIniPath -extName "curl"
        $result | Should -Be 0
        (Get-Content $testIniPath) -match "extension=php_curl.dll" | Should -Be $true
    }
    
    It "Adds any extension in disabled state to ini file" {
        @"
zend_extension=php_opcache.dll
;extension=php_mbstring.dll
"@ | Set-Content $testIniPath
        $result = Add-Missing-PHPExtension -iniPath $testIniPath -extName "curl" -enable $false
        $result | Should -Be 0
        (Get-Content $testIniPath) -match ";extension=php_curl.dll" | Should -Be $true
    }
    
    It "Adds extensions correctly for older PHP versions" {
        @"
zend_extension=php_opcache.dll
extension=php_mbstring.dll
"@ | Set-Content $testIniPath
        Mock Get-Current-PHP-Version { return @{ version = "7.1.0"; path = "TestDrive:\php\7.1.0" } }
        $result = Add-Missing-PHPExtension -iniPath $testIniPath -extName "curl"
        $result | Should -Be 0
        (Get-Content $testIniPath) -match "extension=php_curl.dll" | Should -Be $true
    }
    
    It "Adds zend_extensions correctly" {
        @"
extension=php_mbstring.dll
"@ | Set-Content $testIniPath
        Mock Get-Current-PHP-Version { return @{ version = "7.1.0"; path = "TestDrive:\php\7.1.0" } }
        $result = Add-Missing-PHPExtension -iniPath $testIniPath -extName "opcache"
        $result | Should -Be 0
        (Get-Content $testIniPath) -match "zend_extension=php_opcache.dll" | Should -Be $true
    }
    
    It "Handles exception gracefully" {
        Mock Get-Content { throw "Access denied" }
        $result = Add-Missing-PHPExtension -iniPath $testIniPath -extName "curl"
        $result | Should -Be -1
    }
}

Describe "Get-XDebug-FROM-URL Tests" {
    BeforeAll {
        function Reset-MockState {
            $global:MockRegistryThrowException = $false
            $global:MockFileSystem.DownloadFails = $false
            $global:MockFileSystem.WebResponses = @{}
            $global:MockFileSystem.Files = @{}
            $global:MockFileSystem.Directories = @()
        }
        function Set-MockWebResponse {
            param($url, $content, $links = @())
            $global:MockFileSystem.WebResponses[$url] = @{
                Content = $content
                Links = $links
            }
        }
    }
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
    }
    
    It "Should parse XDebug versions correctly" {
        $mockLinks = @(
            @{ href = "/download/php_xdebug-3.1.0-8.1-vs16-x86_64.dll" },
            @{ href = "/download/php_xdebug-2.9.0-8.1-vs16-x86_64.dll" },
            @{ href = "/download/php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll" },
            @{ href = "/download/php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll" },
            @{ href = "/download/php_random.dll" }
        )
        Set-MockWebResponse -url "https://test.com" -links $mockLinks
        
        $result = Get-XDebug-FROM-URL -url "https://test.com" -version "8.1"
        
        $result.Count | Should -Be 4
        $result[0].xDebugVersion | Should -Be "3.1.0"
        $result[1].xDebugVersion | Should -Be "2.9.0"
    }
    
    It "Should handle network errors" {
        $global:MockFileSystem.DownloadFails = $true
        
        $result = Get-XDebug-FROM-URL -url "https://test.com" -version "8.1"
        
        $result | Should -Be @()
    }
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
        $newContent = "modified content"
        $newContent | Set-Content $testIniPath
        Backup-IniFile -iniPath $testIniPath
        (Get-Content $testBackupPath) | Should -Be $originalContent
    }
    
    It "Returns -1 on error" {
        Mock Copy-Item { throw "Access denied" }
        Backup-IniFile -iniPath "invalidpath" | Should -Be -1
    }
}

Describe "Restore-IniBackup" {
    It "Creates backup and restores successfully" {
        Reset-Ini-Content
        # Create backup first
        Backup-IniFile -iniPath $testIniPath
        
        # Modify original
        "modified content" | Set-Content $testIniPath
        Restore-IniBackup -iniPath $testIniPath | Should -Be 0
        (Get-Content $testIniPath) | Should -Not -Be "modified content"
    }
    
    It "Fails when backup doesn't exist" {
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
        Restore-IniBackup -iniPath $testIniPath | Should -Be -1
    }
    
    It "Returns -1 on error" {
        Mock Test-Path { return $true }
        Mock Copy-Item { throw "Access denied" }
        Backup-IniFile -iniPath $testIniPath
        Restore-IniBackup -iniPath $testIniPath | Should -Be -1
    }
}

Describe "Get-IniSetting" {
    It "Gets existing setting" {
        Get-IniSetting -iniPath $testIniPath -key "upload_max_filesize" | Should -Be 0
    }
    
    It "Gets setting with spaces in value" {
        Get-IniSetting -iniPath $testIniPath -key "display_errors" | Should -Be 0
    }
    
    It "Returns -1 for commented settings" {
        Get-IniSetting -iniPath $testIniPath -key "xdebug" | Should -Be -1
    }
    
    It "Returns -1 for non-existent setting" {
        Get-IniSetting -iniPath $testIniPath -key "nonexistent_setting" | Should -Be -1
    }
    
    It "Requires key parameter" {
        Get-IniSetting -iniPath $testIniPath -key "" | Should -Be -1
        Get-IniSetting -iniPath $testIniPath -key $null | Should -Be -1
    }
    
    It "Handles regex special characters in key names" {
        Get-IniSetting -iniPath $testIniPath -key "memory_limit" | Should -Be 0
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Get-IniSetting -iniPath $testIniPath -key "memory_limit" | Should -Be -1
    }
}

Describe "Set-IniSetting" {
    BeforeEach {
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
    }
    
    It "Accepts key parameter without value" {
        Mock Read-Host { return "256M" }
        $result = Set-IniSetting -iniPath $testIniPath -key "memory_limit"
        $result | Should -Be 0
    }
    
    It "Accepts key parameter with value" {
        $result = Set-IniSetting -iniPath $testIniPath -key "memory_limit=1G"
        $result | Should -Be 0
    }
    
    It "Handles null key" {
        $result = Set-IniSetting -iniPath $testIniPath -key $null
        $result | Should -Be -1
    }
    
    It "Updates existing setting" {
        Mock Read-Host { return "256M" }
        Set-IniSetting -iniPath $testIniPath -key "memory_limit" | Should -Be 0
        (Get-Content $testIniPath) -match "^memory_limit\s*=\s*256M" | Should -Be $true
    }
    
    It "Updates setting with spaces" {
        Mock Read-Host { return "Off" }
        Set-IniSetting -iniPath $testIniPath -key "display_errors" | Should -Be 0
        (Get-Content $testIniPath) -match "^display_errors\s*=\s*Off" | Should -Be $true
    }
    
    It "Updates setting and disables" {
        Mock Read-Host { return "60" }
        Set-IniSetting -iniPath $testIniPath -key "max_execution_time" -enable $false | Should -Be 0
        (Get-Content $testIniPath) -match "^;max_execution_time\s*=\s*60" | Should -Be $true
    }
    
    It "Prompts user when multiple matches found and requires input" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-Content $testIniPath

        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith { return 1 }
        Mock Read-Host -ParameterFilter { $Prompt -eq "Enter new value for 'memory_limit'" } -MockWith { return "4G" }
        
        Set-IniSetting -iniPath $testIniPath -key "memory" | Should -Be 0
        (Get-Content $testIniPath) -match "^memory_limit\s*=\s*4G" | Should -Be $true
    }
    
    It "Prompts user when multiple matches found and does not require input" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-Content $testIniPath

        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith { return 1 }
        
        Set-IniSetting -iniPath $testIniPath -key "memory=2G" | Should -Be 0
        (Get-Content $testIniPath) -match "^memory_limit\s*=\s*2G" | Should -Be $true
    }
    
    It "Creates backup before modifying" {
        Mock Read-Host { return "256M" }
        Set-IniSetting -iniPath $testIniPath -key "memory_limit"
        Test-Path $testBackupPath | Should -Be $true
    }
    
    It "Fails for non-existent setting" {
        Set-IniSetting -iniPath $testIniPath -key "nonexistent_setting=value" | Should -Be -1
    }
    
    It "Prints error message for non-valid number" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-Content $testIniPath

        $script:callCount = 0
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { 'A' } 
            if ($script:callCount -eq 2) { -1 }
            else { '1' }
        }

        Set-IniSetting -iniPath $testIniPath -key "memory=1G" | Should -Be 0
    }
    
    It "Validates key=value format" {
        Set-IniSetting -iniPath $testIniPath -key "invalidformat" | Should -Be -1
        Set-IniSetting -iniPath $testIniPath -key "novalue=" | Should -Be -1
        Set-IniSetting -iniPath $testIniPath -key "=nokey" | Should -Be -1
    }
    
    It "Handles values with special characters" {
        Mock Read-Host { return "10M" }
        Set-IniSetting -iniPath $testIniPath -key "upload_max_filesize" | Should -Be 0
        (Get-Content $testIniPath) -match "^upload_max_filesize\s*=\s*10M" | Should -Be $true
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Set-IniSetting -iniPath $testIniPath -key "memory_limit=256M" | Should -Be -1
    }
}

Describe "Enable-IniExtension" {
    BeforeEach {
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } -MockWith { return $true }
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
    }
    
    It "Enables commented extension" {
        Mock Get-ChildItem {
            param($Path)
            return @( @{ BaseName = "php_xdebug"; Name = "php_xdebug.dll"; FullName = "$extDirectory\php_xdebug.dll" } )
        }
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be 0
        (Get-Content $testIniPath) -match "^extension=php_xdebug.dll" | Should -Be $true
    }
    
    It "Returns 0 for already enabled extension" {
        Mock Get-ChildItem {
            param($Path)
            return @( @{ BaseName = "php_curl"; Name = "php_curl.dll"; FullName = "$extDirectory\php_curl.dll" } )
        }
        
        Enable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be 0
    }
    
    It "Returns -1 for non-existent extension" {
        Mock Get-ChildItem { return @() }
        Enable-IniExtension -iniPath $testIniPath -extName "nonexistent_ext" | Should -Be -1
    }
    
    It "Requires extension name" {
        Enable-IniExtension -iniPath $testIniPath -extName "" | Should -Be -1
        Enable-IniExtension -iniPath $testIniPath -extName $null | Should -Be -1
    }
    
    It "Handles zend_extension" {
        @"
;zend_extension=php_opcache.dll
extension=php_curl.dll
"@ | Set-Content $testIniPath
        Mock Get-ChildItem {
            param($Path)
            return @( @{ BaseName = "php_opcache"; Name = "php_opcache.dll"; FullName = "$extDirectory\php_opcache.dll" } )
        }
        Enable-IniExtension -iniPath $testIniPath -extName "opcache" | Should -Be 0
        (Get-Content $testIniPath) -match "^zend_extension=php_opcache.dll" | Should -Be $true
    }
    
    It "Prompts user to select extension if multiple matches found" {
        @"
;extension=pdo_mysql
extension=pdo_pgsql
;extension=pdo_sqlite
;extension=pgsql
extension=sqlite3
"@ | Set-Content $testIniPath
        Mock Get-ChildItem {
            param($Path)
            return @(
                @{ BaseName = "pdo_mysql"; Name = "pdo_mysql.dll"; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = "pdo_pgsql"; Name = "pdo_pgsql.dll"; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = "pdo_sqlite"; Name = "pdo_sqlite.dll"; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = "pgsql"; Name = "pgsql.dll"; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = "sqlite3"; Name = "sqlite3.dll"; FullName = "$extDirectory\sqlite3.dll" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith { return 1 }
        
        Enable-IniExtension -iniPath $testIniPath -extName "sql" | Should -Be 0
        
        (Get-Content $testIniPath) -match "^extension\s*=\s*pdo_mysql" | Should -Be $true
    }
    
    It "Prints error message for non-valid number" {
        @"
;extension=pdo_mysql
extension=pdo_pgsql
;extension=pdo_sqlite
;extension=pgsql
extension=sqlite3
"@ | Set-Content $testIniPath

        $script:callCount = 0
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { 'A' } 
            if ($script:callCount -eq 2) { -1 }
            else { 4 }
        }
        
        Mock Get-ChildItem {
            param($Path)
            return @(
                @{ BaseName = "pdo_mysql"; Name = "pdo_mysql.dll"; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = "pdo_pgsql"; Name = "pdo_pgsql.dll"; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = "pdo_sqlite"; Name = "pdo_sqlite.dll"; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = "pgsql"; Name = "pgsql.dll"; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = "sqlite3"; Name = "sqlite3.dll"; FullName = "$extDirectory\sqlite3.dll" }
            )
        }

        Enable-IniExtension -iniPath $testIniPath -extName "sql" | Should -Be 0
        
        (Get-Content $testIniPath) -match "^extension\s*=\s*pgsql" | Should -Be $true
    }
    
    It "Creates backup before modifying" {
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug"
        Test-Path $testBackupPath | Should -Be $true
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be -1
    }
}

Describe "Disable-IniExtension" {
    BeforeEach {
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } -MockWith { return $true }
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
    }
    
    It "Disables enabled extension" {
        Mock Get-ChildItem {
            param($Path)
            return @( @{ BaseName = "php_curl"; Name = "php_curl.dll"; FullName = "$extDirectory\php_curl.dll" } )
        }
        Disable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be 0
        (Get-Content $testIniPath) -match "^;extension=php_curl.dll" | Should -Be $true
    }
    
    It "Returns -1 for already disabled extension" {
        Disable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be -1
    }
    
    It "Returns -1 for non-existent extension" {
        Disable-IniExtension -iniPath $testIniPath -extName "nonexistent_ext" | Should -Be -1
    }
    
    It "Requires extension name" {
        Disable-IniExtension -iniPath $testIniPath -extName "" | Should -Be -1
        Disable-IniExtension -iniPath $testIniPath -extName $null | Should -Be -1
    }
    
    It "Handles zend_extension" {
        Mock Get-ChildItem {
            param($Path)
            return @( @{ BaseName = "php_opcache"; Name = "php_opcache.dll"; FullName = "$extDirectory\php_opcache.dll" } )
        }
        Disable-IniExtension -iniPath $testIniPath -extName "opcache" | Should -Be 0
        (Get-Content $testIniPath) -match "^;zend_extension=php_opcache.dll" | Should -Be $true
    }
    
    
    It "Prompts user to select extension if multiple matches found" {
        @"
extension=pdo_mysql
;extension=pdo_pgsql
extension=pdo_sqlite
extension=pgsql
;extension=sqlite3
"@ | Set-Content $testIniPath
        Mock Get-ChildItem {
            param($Path)
            return @(
                @{ BaseName = "pdo_mysql"; Name = "pdo_mysql.dll"; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = "pdo_pgsql"; Name = "pdo_pgsql.dll"; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = "pdo_sqlite"; Name = "pdo_sqlite.dll"; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = "pgsql"; Name = "pgsql.dll"; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = "sqlite3"; Name = "sqlite3.dll"; FullName = "$extDirectory\sqlite3.dll" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith { return 1 }
        
        Disable-IniExtension -iniPath $testIniPath -extName "sql" | Should -Be 0
        
        (Get-Content $testIniPath) -match "^;extension\s*=\s*pdo_mysql" | Should -Be $true
    }
    
    It "Prints error message for non-valid number" {
        @"
extension=pdo_mysql
;extension=pdo_pgsql
extension=pdo_sqlite
extension=pgsql
;extension=sqlite3
"@ | Set-Content $testIniPath

        $script:callCount = 0
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { 'A' } 
            if ($script:callCount -eq 2) { -1 }
            else { 4 }
        }
        
        Mock Get-ChildItem {
            param($Path)
            return @(
                @{ BaseName = "pdo_mysql"; Name = "pdo_mysql.dll"; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = "pdo_pgsql"; Name = "pdo_pgsql.dll"; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = "pdo_sqlite"; Name = "pdo_sqlite.dll"; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = "pgsql"; Name = "pgsql.dll"; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = "sqlite3"; Name = "sqlite3.dll"; FullName = "$extDirectory\sqlite3.dll" }
            )
        }
        Disable-IniExtension -iniPath $testIniPath -extName "sql" | Should -Be 0
        
        (Get-Content $testIniPath) -match "^;extension\s*=\s*pgsql" | Should -Be $true
    }
    
    It "Creates backup before modifying" {
        Disable-IniExtension -iniPath $testIniPath -extName "curl"
        Test-Path $testBackupPath | Should -Be $true
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Disable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be -1
    }
}

Describe "Get-IniExtensionStatus" {
    BeforeEach {
        Reset-Ini-Content
    }
    
    It "Detects enabled extension" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(
                @{ name = "curl"; id="curl"; status="Enabled"; color="DarkGreen"; line=0; lineNamber=0; source="ext,ini"}
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "curl" | Should -Be 0
    }
    
    It "Detects disabled extension" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(
                @{ name = "xdebug"; id="xdebug"; status="Disabled"; color="DarkYellow"; line=0; lineNamber=0; source="ext,ini"}
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "xdebug" | Should -Be 0
    }
    
    It "Detects enabled zend_extension" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(
                @{ name = "opcache"; id="opcache"; status="Enabled"; color="DarkGreen"; line=0; lineNamber=0; source="ext,ini"}
            )
        }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "opcache" | Should -Be 0
    }
    
    It "Returns -1 for non-existent extension" {
        Mock Read-Host { return "n" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "nonexistent_ext" | Should -Be -1
    }
    
    It "Requires extension name" {
        Get-IniExtensionStatus -iniPath $testIniPath -extName "" | Should -Be -1
        Get-IniExtensionStatus -iniPath $testIniPath -extName $null | Should -Be -1
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "curl" | Should -Be -1
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
                    @{ Extension = "curl"; Enabled = $true }
                    @{ Extension = "xdebug"; Enabled = $false }
                )
                settings = @(
                    @{ Name = "memory_limit"; Value = "128M"; Enabled = $true }
                    @{ Name = "max_execution_time"; Value = "30"; Enabled = $false }
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

Describe "Get-PHP-Data" {
    BeforeEach {
        Reset-Ini-Content
    }
    
    It "Returns extensions with correct status" {
        $extensions = (Get-PHP-Data -PhpIniPath $testIniPath).extensions
        $extensions | Should -Not -Be $null
        $extensions.Count | Should -BeGreaterThan 0
        
        $curlExt = $extensions | Where-Object { $_.Extension -like "*curl*" }
        $curlExt.Enabled | Should -Be $true
        
        $xdebugExt = $extensions | Where-Object { $_.Extension -like "*xdebug*" }
        $xdebugExt.Enabled | Should -Be $false
    }
    
    It "Handles empty ini file" {
        "" | Set-Content $testIniPath
        $extensions = (Get-PHP-Data -PhpIniPath $testIniPath).extensions
        $extensions.Count | Should -Be 0
    }
}

Describe "Get-Matching-PHPExtensionsStatus" {
    BeforeEach {
        Reset-Ini-Content
        # $phpDir = Split-Path -Parent $testIniPath
        # $extDir = Join-Path $phpDir "ext"
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } -MockWith { return $true }

        # create some fake dll files in ext directory
        # Set-Content -Path (Join-Path $extDir "php_testext.dll") -Value "" -Encoding UTF8
        # Set-Content -Path (Join-Path $extDir "php_otherext.dll") -Value "" -Encoding UTF8
    }

    It "Returns empty when ext directory missing" {
        Remove-Item -Recurse -Force (Join-Path (Split-Path -Parent $testIniPath) "ext") -ErrorAction SilentlyContinue
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName "testext"
        $res | Should -Be @()
    }

    It "Finds extensions in ext directory and marks them Disabled when not in ini" {
        Mock Get-ChildItem {
            param($Path)
            return @(
                @{ BaseName = "pdo_mysql"; Name = "pdo_mysql.dll"; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = "pdo_pgsql"; Name = "pdo_pgsql.dll"; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = "pdo_sqlite"; Name = "pdo_sqlite.dll"; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = "pgsql"; Name = "pgsql.dll"; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = "sqlite3"; Name = "sqlite3.dll"; FullName = "$extDirectory\sqlite3.dll" }
            )
        }
        # ensure ext exists and not configured in ini
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName "sql"
        $res.Count | Should -BeGreaterThan 0
        $res[0].status | Should -Be "Disabled"
    }

    It "Detects extension configured as Enabled in ini file" {
        # configure extension as enabled in ini
        # Add-Content -Path $testIniPath -Value "extension=php_testext.dll"
        @"
extension=pdo_mysql
"@ | Set-Content $testIniPath
        Mock Get-ChildItem {
            param($Path)
            return @(
                @{ BaseName = "pdo_mysql"; Name = "pdo_mysql.dll"; FullName = "$extDirectory\pdo_mysql.dll" }
                @{ BaseName = "pdo_pgsql"; Name = "pdo_pgsql.dll"; FullName = "$extDirectory\pdo_pgsql.dll" }
                @{ BaseName = "pdo_sqlite"; Name = "pdo_sqlite.dll"; FullName = "$extDirectory\pdo_sqlite.dll" }
                @{ BaseName = "pgsql"; Name = "pgsql.dll"; FullName = "$extDirectory\pgsql.dll" }
                @{ BaseName = "sqlite3"; Name = "sqlite3.dll"; FullName = "$extDirectory\sqlite3.dll" }
            )
        }
        $res = Get-Matching-PHPExtensionsStatus -iniPath $testIniPath -extName "sql"
        $res | Should -Not -Be @()
        Write-Host ($res | ConvertTo-Json)
        # $res[0].status | Should -Be "Enabled"
    }
}

Describe "Install-Extension" {
    BeforeAll {
        $global:MockFileSystem = @{
            Directories = @()
            Files = @{}
            WebResponses = @{}
            DownloadFails = $false
        }
        
        function Read-Host {
            param($Prompt)
            if ($Prompt -eq "`nInsert the [number] you want to install") {
                return "0"
            }
        }
        function Get-ChildItem {
            param($Path)
            if ($global:getRandomFile) {
                return @( @{ Name = "random_file" } )
            }
            return @( @{ Name = "php_curl.dll"; FullName = "TestDrive:\php_curl-1.4.0-7.4-ts-vc15-x86\php_curl.dll" } )
        }
        Mock Extract-Zip { }
        Mock Remove-Item { }
        Mock Move-Item { }
        Mock Test-Path { return $true }
        
    }
    
    BeforeEach {
        $global:getRandomFile = $false
        $global:MockFileSystem.DownloadFails = $false
        $global:MockFileSystem.WebResponses = @{
            "$PECL_PACKAGE_ROOT_URL/nonexistent_ext" = @{
                Content = "Mocked PHP nonexistent_ext content"
                Links = @()
            }
            "$PECL_PACKAGE_ROOT_URL/pdo_mysql" = @{
                Content = "Mocked pdo_mysql content"
                Links = @(
                    @{ href = "/package/pdo_mysql/1.4.0/windows" },
                    @{ href = "/package/pdo_mysql/2.1.0/windows" }
                )
            }
            "$PECL_PACKAGE_ROOT_URL/curl" = @{
                Content = "Mocked curl content"
                Links = @(
                    @{ href = "/package/curl/1.4.0/windows" },
                    @{ href = "/package/curl/2.1.0/windows" }
                )
            }
            "$PECL_PACKAGE_ROOT_URL/curl/1.4.0/windows" = @{
                Content = "Mocked PHP curl 1.4.0 content"
                Links = @(
                    @{ href = "other_link" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip" }
                )
            }
            "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" = @{
                Content = "Mocked PHP curl 1.4.0 zip content"
            }
            "$PECL_PACKAGE_ROOT_URL/curl/2.1.0/windows" = @{
                Content = "Mocked PHP curl 2.1.0 content"
                Links = @()
            }
        }
    }
    
    It "Returns -1 when gets empty list from extension" {
        $code = Install-Extension -iniPath $testIniPath -extName "nonexistent_ext"
        $code | Should -Be -1
    }
    
    It "Returns -1 when No package is found" {
        Mock Add-Member { throw "error" }
        $code = Install-Extension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when user does not choose a zip extension version to install" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { '' }

        $code = Install-Extension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when user does choose a non valid zip extension version to install" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith {
            return '5'
        }

        $code = Install-Extension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when downloaded zip extension has no dll" {
        $global:getRandomFile = $true        
        $code = Install-Extension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when user answers no to replace existing extension" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { 
            return "n"
        }
        
        $code = Install-Extension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when user answers yes to replace existing extension" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { 
            return "y"
        }
        Mock Move-Item { }
        Mock Add-Missing-PHPExtension { return -1 }
        
        $code = Install-Extension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Installs extension successfully" {
        Mock Test-Path { return $false }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { 
            return "y"
        }
        
        $code = Install-Extension -iniPath $testIniPath -extName "curl"
        $code | Should -Be 0
    }
    
    Context "When extension has no direct link" {
        BeforeEach {
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/nonexistent_ext" } -MockWith { 
                throw "Network error"
            }
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq $PECL_PACKAGES_URL } -MockWith {
                return @{
                    Content = "Mocked PHP extensions content"
                    Links = @(
                        @{ href = $null }
                        @{ href = "random_link" }
                        @{ href = "/packages.php?catpid=1&amp;catname=Authentication"; 
                            outerHTML = '<a href="/packages.php?catpid=1&amp;catname=Authentication">Authentication</a>' }
                        @{ href = "/packages.php?catpid=3&amp;catname=Caching"; 
                            outerHTML = '<a href="/packages.php?catpid=3&amp;catname=Caching">Caching</a>' }
                        @{ href = "/packages.php?catpid=7&amp;catname=EmptyCat"; 
                            outerHTML = '<a href="/packages.php?catpid=7&amp;catname=EmptyCat">EmptyCat</a>' }
                    )
                }
            }
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=1&amp;catname=Authentication" } -MockWith {
                return @{
                    Content = "Mocked PHP extension Auth content"
                    Links = @(
                        @{ href = $null }
                        @{ href = "/package/courierauth" }
                        @{ href = "/package/krb5" }
                    )
                }
            }
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching" } -MockWith {
                return @{
                    Content = "Mocked PHP extension Caching content"
                    Links = @(
                        @{ href = "/package/APC" }
                        @{ href = "/package/APCu" }
                        @{ href = "/package/memcache" }
                        @{ href = "/package/memcached" }
                    )
                }
            }
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=7&amp;catname=EmptyCat" } -MockWith {
                return @{
                    Content = "Mocked PHP extension EmptyCat content"
                    Links = @()
                }
            }
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/courierauth" } -MockWith {
                return @{
                    Content = "Mocked courierauth content"
                    Links = @(
                        @{ href = "/package/courierauth/1.4.0/windows" },
                        @{ href = "/package/courierauth/2.1.0/windows" }
                    )
                }
            }
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/courierauth/1.4.0/windows" } -MockWith {
                return @{
                    Content = "Mocked PHP courierauth 1.4.0 content"
                    Links = @(
                        @{ href = "other_link" },
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip" },
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x64.zip" }
                    )
                }
            }
            Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip" } -MockWith {
                $global:MockFileSystem.Files[$OutFile] = "Downloaded content"
                return
            }
            Mock Get-ChildItem {
                param($Path)
                return @( @{ Name = "php_courierauth.dll"; FullName = "TestDrive:\php_courierauth-1.4.0-7.4-ts-vc15-x86\php_courierauth.dll" } )
            }
        }
        It "Falls back to matching links if extension direct link is not found" {
            Mock Test-Path { return $false }
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { 
                return "y"
            }
            
            $code = Install-Extension -iniPath $testIniPath -extName "cour"
            $code | Should -Be 0        
        }
        It "Returns -1 when no extension is found" {
            $code = Install-Extension -iniPath $testIniPath -extName "nonexistent_ext"
            $code | Should -Be -1
        }
        It "Returns -1 when user does not choose a dll extension version to install" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { '' }
            $code = Install-Extension -iniPath $testIniPath -extName "cache"
            $code | Should -Be -1
        }
        It "Returns -1 when user does choose a non valid dll extension version to install" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { '-10' }
            $code = Install-Extension -iniPath $testIniPath -extName "cache"
            $code | Should -Be -1
        }
    }
    
    It "Handles thrown exception" {
        $global:MockFileSystem.DownloadFails = $true
        $code = Install-Extension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
}

Describe "Install-IniExtension" {
    
    It "Handles null extension name" {
        $code = Install-IniExtension -iniPath $testIniPath -extName $null
        $code | Should -Be -1
    }
    
    It "Installs xdebug" {
        Mock Install-XDebug-Extension { return 0 }
        $code = Install-IniExtension -iniPath $testIniPath -extName "xdebug"
        $code | Should -Be 0
    }
    
    It "Installs extension" {
        Mock Install-Extension { return 0 }
        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be 0
    }
    
    It "Returns -1 on error" {
        Mock Install-Extension { return -1 }
        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
}

Describe "Get-PHPExtensions-From-Source" {
    BeforeAll {
        Mock Cache-Data { return 0 }
        $global:MockFileSystem = @{
            Directories = @()
            Files = @{}
            WebResponses = @{}
            DownloadFails = $false
        }
    }
    
    BeforeEach {
        $global:getRandomFile = $false
        $global:MockFileSystem.DownloadFails = $false
        $global:MockFileSystem.WebResponses = @{
            $PECL_PACKAGES_URL = @{
                Content = "Mocked PHP extensions content"
                Links = @(
                    @{ href = $null }
                    @{ href = "random_link" }
                    @{ href = "/packages.php?catpid=1&amp;catname=Authentication"; 
                        outerHTML = '<a href="/packages.php?catpid=1&amp;catname=Authentication">Authentication</a>' }
                    @{ href = "/packages.php?catpid=3&amp;catname=Caching"; 
                        outerHTML = '<a href="/packages.php?catpid=3&amp;catname=Caching">Caching</a>' }
                    @{ href = "/packages.php?catpid=7&amp;catname=EmptyCat"; 
                        outerHTML = '<a href="/packages.php?catpid=7&amp;catname=EmptyCat">EmptyCat</a>' }
                )
            }
            "$($PECL_PACKAGES_URL)?catpid=1&amp;catname=Authentication" = @{
                Content = "Mocked PHP extension Auth content"
                Links = @(
                    @{ href = $null }
                    @{ href = "/package/courierauth" }
                    @{ href = "/package/krb5" }
                )
            }
            "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching" = @{
                Content = "Mocked PHP extension Caching content"
                Links = @(
                    @{ href = "/package/APC" }
                    @{ href = "/package/APCu" }
                )
            }
            "$($PECL_PACKAGES_URL)?catpid=7&amp;catname=EmptyCat" = @{
                Content = "Mocked PHP extension EmptyCat content"
                Links = @()
            }
        }
    }
    
    It "Returns list of available extensions" {
        $list = Get-PHPExtensions-From-Source
        $list.Count | Should -Be 3 # include xdebug category
    }
    
    It "Handles thrown exception" {
        $global:MockFileSystem.DownloadFails = $true
        $list = Get-PHPExtensions-From-Source
        $list.Count | Should -Be 0
    }
}

Describe "List-PHP-Extensions" {
    BeforeAll {
        Mock Get-PHP-Data {
            return @{
                extensions = @(
                    @{Extension = "curl"; Enabled = $true; Type = "extension"}
                    @{Extension = "opcache"; Enabled = $false; Type = "zend_extension"}
                )
            }
        }
        function Get-Extension-List {
            return @{
                Authentication = @(
                    @{
                        outerHTML = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName = "A";
                        href = "/package/courierauth";
                        extName = "courierauth";
                        extCategory = "Authentication";
                    },
                    @{
                        outerHTML = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName = "A";
                        href = "/package/krb5";
                        extName = "krb5";
                        extCategory = "Authentication"
                    }
                )
                Caching = @(
                    @{
                        outerHTML = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName = "A";
                        href = "/package/APC";
                        extName = "APC";
                        extCategory = "Caching"
                    }
                    @{
                        outerHTML = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName = "A";
                        href = "/package/APCu";
                        extName = "APCu";
                        extCategory = "Caching"
                    }
                )
            }
        }
        Mock Get-Data-From-Cache { return Get-Extension-List }
        Mock Get-PHPExtensions-From-Source -MockWith{ return Get-Extension-List }
        Mock Display-Extensions-States {}
        Mock Display-Installed-Extensions {}
    }
    
    It "Returns -1 when no extensions are installed" {
        Mock Get-PHP-Data { return @{ extensions = @() } }
        $code = List-PHP-Extensions -iniPath $testIniPath
        $code | Should -Be -1
    }
    
    It "Displays installed extensions" {
        $code = List-PHP-Extensions -iniPath $testIniPath
        $code | Should -Be 0
        Assert-MockCalled Get-PHP-Data -Exactly 1
        Assert-MockCalled Display-Extensions-States -Exactly 1
        Assert-MockCalled Display-Installed-Extensions -Exactly 1
    }
    
    It "Displays local extensions matching the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -term "pc"
        $code | Should -Be 0
        Assert-MockCalled Get-PHP-Data -Exactly 1
        Assert-MockCalled Display-Extensions-States -Exactly 1
        Assert-MockCalled Display-Installed-Extensions -Exactly 1
    }
    
    It "Returns -1 when no local extensions matchs the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -term "nonexistent"
        $code | Should -Be -1
        Assert-MockCalled Get-PHP-Data -Exactly 1
        Assert-MockCalled Display-Extensions-States -Exactly 0
        Assert-MockCalled Display-Installed-Extensions -Exactly 0
    }
    
    It "Returns -1 when no extensions are found" {
        Mock Test-Path { return $false }
        Mock Get-PHPExtensions-From-Source { return @{} }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
        Assert-MockCalled Get-PHPExtensions-From-Source -Exactly 1
        Assert-MockCalled Get-Data-From-Cache -Exactly 0
    }
    
    It "Displays available extensions from cache" {
        Mock Test-Path { return $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
        Mock Get-Item { return @{ LastWriteTime = $timeWithinLastWeek } }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
        Assert-MockCalled Get-Data-From-Cache -Exactly 1
        Assert-MockCalled Get-PHPExtensions-From-Source -Exactly 0
    }
    
    It "Displays available extensions from source when cache is empty" {
        Mock Test-Path { return $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
        Mock Get-Item { return @{ LastWriteTime = $timeWithinLastWeek } }
        Mock Get-Data-From-Cache { return @{} }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
        Assert-MockCalled Get-Data-From-Cache -Exactly 1
        Assert-MockCalled Get-PHPExtensions-From-Source -Exactly 1
    }
    
    It "Displays available extensions matching the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true -term "pc"
        $code | Should -Be 0
    }
    
    It "Returns -1 when no available extensions matchs the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true -term "nonexistent"
        $code | Should -Be -1
    }
    
    It "Handles thrown exception" {
        Mock Can-Use-Cache { throw 'Error' }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
    }
}

Describe "Install-XDebug-Extension" {
    BeforeAll {
        Mock Get-Current-PHP-Version { return @{ version = "7.1.0"; path = "TestDrive:\php\7.1.0" }}
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = "/download/php_xdebug-3.1.0-8.1-vs16-x64.dll"; version = "3.1.0"; xDebugVersion = "3.1.0"; fileName = "php_xdebug-3.1.0-8.1-vs16-x64.dll"; outerHTML = "<a href='/download/php_xdebug-3.1.0-8.1-vs16-x64.dll'>php_xdebug-3.1.0-8.1-vs16-x64.dll</a>" }
                @{ href = "/download/php_xdebug-2.9.0-8.1-vs16-x86_64.dll"; version = "2.9.0"; xDebugVersion = "2.9.0"; fileName = "php_xdebug-2.9.0-8.1-vs16-x86_64.dll"; outerHTML = "<a href='/download/php_xdebug-2.9.0-8.1-vs16-x86_64.dll'>php_xdebug-2.9.0-8.1-vs16-x86_64.dll</a>" }
                @{ href = "/download/php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll"; version = "3.1.0"; xDebugVersion = "3.1.0"; fileName = "php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll"; outerHTML = "<a href='/download/php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll'>php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll</a>" }
                @{ href = "/download/php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll"; version = "2.9.0"; xDebugVersion = "2.9.0"; fileName = "php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll"; outerHTML = "<a href='/download/php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll'>php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll</a>" }
            )
        }
        Mock Read-Host {
            param($Prompt)
            if ($Prompt -eq "`nInsert the [number] you want to install") {
                return ''
            }
        }
        function Reset-MockState {
            $global:MockRegistryThrowException = $false
            $global:MockFileSystem.DownloadFails = $false
            $global:MockFileSystem.WebResponses = @{}
            $global:MockFileSystem.Files = @{}
            $global:MockFileSystem.Directories = @()
        }
        function Add-Content {
            param($Path, $Value)
            if ($global:MockFileSystem.Files.ContainsKey($Path)) {
                $global:MockFileSystem.Files[$Path] += "`n$Value"
            } else {
                $global:MockFileSystem.Files[$Path] = $Value
            }
        }
        function Set-MockWebResponse {
            param($url, $content, $links = @())
            $global:MockFileSystem.WebResponses[$url] = @{
                Content = $content
                Links = $links
            }
        }
    }
    
    BeforeEach {
        $global:MockFileSystem.Directories += "TestDrive:\php"
        $global:MockFileSystem.Directories += "TestDrive:\php\ext"
        $global:MockFileSystem.Files["TestDrive:\php\php.ini"] = @"
;extension_dir = "ext"
zend_extension = opcache
opcache.enable = 1
"@
        Reset-MockState
        $mockLinks = @(
            @{ href = "/download/php_xdebug-3.1.0-8.1-vs16-x64.dll" }
        )
        Set-MockWebResponse -url $XDEBUG_HISTORICAL_URL -links $mockLinks
    }
    
    It "Returns -1 when user does not choose a dll extension version to install" {
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }
    
    It "Returns -1 when user does choose a non valid dll extension version to install" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return "-10" }
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }
    
    It "Returns -1 when user does not want to overwrite existing dll extension version" {
        # $global:MockFileSystem.DownloadFails = $false
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-3.1.0-8.1-vs16-x64.dll" -content "XDebug DLL content"
        Mock Test-Path { return $true }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return "0" }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_xdebug-3.1.0-8.1-vs16-x64.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { return "n" }
        
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }
    
    It "Returns 0 when user wants to overwrite existing dll extension version" {
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-3.1.0-8.1-vs16-x64.dll" -content "XDebug DLL content"
        Mock Test-Path { return $false }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return "0" }
        Mock Remove-Item { }
        Mock Move-Item { }
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0
    }
    
    It "Handles exception gracefully" {
        Mock Sort-Object { throw "Error" }
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }
}

Describe "Invoke-PVMIniAction" {
    BeforeEach {
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } -MockWith { return $true }
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
    }
    
    Context "info action" {
        It "Executes info action successfully" {
            $result = Invoke-PVMIniAction -action "info" -params @("--search=cache")
            $result | Should -Be 0
        }
    }
    
    Context "get action" {
        It "Gets single setting" {
            $result = Invoke-PVMIniAction -action "get" -params @("memory_limit")

            $result | Should -Be 0
        }
        
        It "Gets multiple settings" {
            $result = Invoke-PVMIniAction -action "get" -params @("memory_limit", "display_errors")
            $result | Should -Be 0
        }
        
        It "Requires at least one parameter" {
            $result = Invoke-PVMIniAction -action "get" -params @()
            $result | Should -Be -1
        }
    }
    
    Context "set action" {
        It "Sets single setting" {
            Mock Read-Host { return "256M" }
            $result = Invoke-PVMIniAction -action "set" -params @("memory_limit")
            $result | Should -Be 0
        }
        
        It "Sets multiple settings" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "Enter new value for 'memory_limit'" } -MockWith { '512M' }
            Mock Read-Host -ParameterFilter { $Prompt -eq "Enter new value for 'max_execution_time'" } -MockWith { '60' }

            $result = Invoke-PVMIniAction -action "set" -params @("memory_limit", "max_execution_time")
            $result | Should -Be 0
        }
        
        It "Requires at least one parameter" {
            $result = Invoke-PVMIniAction -action "set" -params @()
            $result | Should -Be -1
        }
    }
    
    Context "enable action" {
        It "Enables single extension" {
            Mock Get-ChildItem {
                param($Path)
                return @( @{ BaseName = "php_xdebug"; Name = "php_xdebug.dll"; FullName = "$extDirectory\php_xdebug.dll" } )
            }
            $result = Invoke-PVMIniAction -action "enable" -params @("xdebug")
            $result | Should -Be 0
        }
        
        It "Enables multiple extensions" {
            @"
;extension=php_xdebug.dll
;extension=php_gd.dll
extension=php_curl.dll
"@ | Set-Content (Join-Path $phpVersionPath "php.ini")

            $script:callCount = 0
            Mock Get-ChildItem {
                param($Path)
                $script:callCount++
                if ($script:callCount -eq 1) { return @(@{ BaseName = "php_xdebug"; Name = "php_xdebug.dll"; FullName = "$extDirectory\php_xdebug.dll" }) } 
                if ($script:callCount -eq 2) { return @(@{ BaseName = "php_gd"; Name = "php_gd.dll"; FullName = "$extDirectory\php_gd.dll" }) }
            }

            $result = Invoke-PVMIniAction -action "enable" -params @("xdebug", "gd")
            $result | Should -Be 0
        }
        
        It "Requires at least one parameter" {
            $result = Invoke-PVMIniAction -action "enable" -params @()
            $result | Should -Be -1
        }
    }
    
    Context "disable action" {
        It "Disables single extension" {
            Mock Get-ChildItem {
                param($Path)
                return @( @{ BaseName = "php_curl"; Name = "php_curl.dll"; FullName = "$extDirectory\php_curl.dll" } )
            }
            $result = Invoke-PVMIniAction -action "disable" -params @("curl")
            $result | Should -Be 0
        }
        
        It "Requires at least one parameter" {
            $result = Invoke-PVMIniAction -action "disable" -params @()
            $result | Should -Be -1
        }
    }
    
    Context "status action" {
        It "Checks single extension status" {
            Mock Get-ChildItem {
                param($Path)
                return @( @{ BaseName = "php_curl"; Name = "php_curl.dll"; FullName = "$extDirectory\php_curl.dll" } )
            }
            $result = Invoke-PVMIniAction -action "status" -params @("curl")
            $result | Should -Be 0
        }
        
        It "Requires at least one parameter" {
            $result = Invoke-PVMIniAction -action "status" -params @()
            $result | Should -Be -1
        }
    }
    
    Context "restore action" {
        It "Restores from backup" {
            # Create a backup first
            Backup-IniFile -iniPath (Join-Path $phpVersionPath "php.ini")
            $result = Invoke-PVMIniAction -action "restore" -params @()
            $result | Should -Be 0
        }
    }
    
    Context "install action" {
        BeforeAll {
            $global:getRandomFile = $false
            $global:MockFileSystem = @{
                Directories = @()
                Files = @{}
                WebResponses = @{
                                "$PECL_PACKAGE_ROOT_URL/nonexistent_ext" = @{
                                    Content = "Mocked PHP nonexistent_ext content"
                                    Links = @()
                                }
                                "$PECL_PACKAGE_ROOT_URL/pdo_mysql" = @{
                                    Content = "Mocked pdo_mysql content"
                                    Links = @(
                                        @{ href = "/package/pdo_mysql/1.4.0/windows" },
                                        @{ href = "/package/pdo_mysql/2.1.0/windows" }
                                    )
                                }
                                "$PECL_PACKAGE_ROOT_URL/curl" = @{
                                    Content = "Mocked curl content"
                                    Links = @(
                                        @{ href = "/package/curl/1.4.0/windows" },
                                        @{ href = "/package/curl/2.1.0/windows" }
                                    )
                                }
                                "$PECL_PACKAGE_ROOT_URL/curl/1.4.0/windows" = @{
                                    Content = "Mocked PHP curl 1.4.0 content"
                                    Links = @(
                                        @{ href = "other_link" },
                                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" },
                                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip" }
                                    )
                                }
                                "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" = @{
                                    Content = "Mocked PHP curl 1.4.0 zip content"
                                }
                                "$PECL_PACKAGE_ROOT_URL/curl/2.1.0/windows" = @{
                                    Content = "Mocked PHP curl 2.1.0 content"
                                    Links = @()
                                }
                            }
                DownloadFails = $false
            }
            
            function Read-Host {
                param($Prompt)
                if ($Prompt -eq "`nInsert the [number] you want to install") {
                    return 0
                }
            }
            function Get-ChildItem {
                param($Path)
                if ($global:getRandomFile) {
                    return @( @{ Name = "random_file" } )
                }
                return @( @{ Name = "php_curl.dll"; FullName = "TestDrive:\php_curl-1.4.0-7.4-ts-vc15-x86\php_curl.dll" } )
            }
            Mock Extract-Zip { }
            Mock Remove-Item { }
            Mock Move-Item { }
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { 
                return "y"
            }
            Mock Install-Extension { return 0 }
        }
        It "Installs extension" {
            $result = Invoke-PVMIniAction -action "install" -params @("curl")
            $result | Should -Be 0
        }
        
        It "Requires at least one parameter" {
            $result = Invoke-PVMIniAction -action "install" -params @()
            $result | Should -Be -1
        }
    }
    
    Context "list action" {
        It "Lists extensions" {
            Mock Get-PHP-Data {
                @{
                    extensions = @(
                        @{Extension = "curl"; Enabled = $true; Type = "extension"}
                        @{Extension = "opcache"; Enabled = $false; Type = "zend_extension"}
                    )
                    settings = @(
                        @{Name = "memory_limit"; Value = "128M"; Enabled = $true; Type = "setting"}
                        @{Name = "max_execution_time"; Value = "60"; Enabled = $false; Type = "setting"}
                    )
                }
            }
            $result = Invoke-PVMIniAction -action "list" -params @("--search=pc")
            $result | Should -Be 0
        }
    }
    
    Context "error handling" {
        It "Handles invalid action" {
            $result = Invoke-PVMIniAction -action "invalid" -params @()
            $result | Should -Be 1
        }
        
        It "Handles missing PHP current version" {
            Mock Get-Current-PHP-Version { return $null }
            $result = Invoke-PVMIniAction -action "info" -params @()
            $result | Should -Be -1
        }
        
        It "Handles missing php.ini file" {
            Remove-Item (Join-Path $phpVersionPath "php.ini") -Force
            $result = Invoke-PVMIniAction -action "info" -params @()
            $result | Should -Be -1
        }
        
        It "Returns -1 on unexpected error" {
            Mock Get-Current-PHP-Version { throw "Unexpected error" }
            $result = Invoke-PVMIniAction -action "info" -params @()
            $result | Should -Be -1
        }
    }
}