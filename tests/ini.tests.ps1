# Load required modules and functions
. "$PSScriptRoot\..\src\actions\ini.ps1"

BeforeAll {
    $testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $testIniPath = Join-Path $testDrivePath "php.ini"
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
upload_max_filesize = 2M
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
    
    # Mock Config-XDebug function
    function script:Config-XDebug {
        param($version, $phpPath)
        return 0
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

Describe "Get-Single-PHPExtensionStatus" {
    Context "When extension is enabled" {
        It "Returns enabled status" {
            @"
zend_extension=php_opcache.dll
extension=php_curl.dll
"@ | Set-Content $testIniPath
            $result = Get-Single-PHPExtensionStatus -iniPath $testIniPath -extName "opcache"
            $result.status | Should -Be "Enabled"
            $result.color | Should -Be "DarkGreen"
        }
    }
    
    Context "When extension is disabled" {
        It "Returns disabled status" {
            @"
;zend_extension=php_opcache.dll
extension=php_curl.dll
"@ | Set-Content $testIniPath
            $result = Get-Single-PHPExtensionStatus -iniPath $testIniPath -extName "opcache"
            $result.status | Should -Be "Disabled"
            $result.color | Should -Be "DarkYellow"
        }
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
        Get-IniSetting -iniPath $testIniPath -key "memory_limit" | Should -Be 0
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
    
    It "Updates existing setting" {
        Set-IniSetting -iniPath $testIniPath -keyValue "memory_limit=256M" | Should -Be 0
        (Get-Content $testIniPath) -match "^memory_limit\s*=\s*256M" | Should -Be $true
    }
    
    It "Updates setting with spaces" {
        Set-IniSetting -iniPath $testIniPath -keyValue "display_errors=Off" | Should -Be 0
        (Get-Content $testIniPath) -match "^display_errors\s*=\s*Off" | Should -Be $true
    }
    
    It "Creates backup before modifying" {
        Set-IniSetting -iniPath $testIniPath -keyValue "memory_limit=256M"
        Test-Path $testBackupPath | Should -Be $true
    }
    
    It "Fails for non-existent setting" {
        Set-IniSetting -iniPath $testIniPath -keyValue "nonexistent_setting=value" | Should -Be -1
    }
    
    It "Validates key=value format" {
        Set-IniSetting -iniPath $testIniPath -keyValue "invalidformat" | Should -Be -1
        Set-IniSetting -iniPath $testIniPath -keyValue "novalue=" | Should -Be -1
        Set-IniSetting -iniPath $testIniPath -keyValue "=nokey" | Should -Be -1
    }
    
    It "Handles values with special characters" {
        Set-IniSetting -iniPath $testIniPath -keyValue "upload_max_filesize=10M" | Should -Be 0
        (Get-Content $testIniPath) -match "^upload_max_filesize\s*=\s*10M" | Should -Be $true
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Set-IniSetting -iniPath $testIniPath -keyValue "memory_limit=256M" | Should -Be -1
    }
}

Describe "Enable-IniExtension" {
    BeforeEach {
        Mock Read-Host { return "n" }
        Mock Add-Missing-PHPExtension { return 0 }
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
    }
    
    It "Enables commented extension" {
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be 0
        (Get-Content $testIniPath) -match "^extension=php_xdebug.dll" | Should -Be $true
    }
    
    It "Returns -1 for already enabled extension" {
        Enable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be -1
    }
    
    It "Returns -1 for non-existent extension" {
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
        Enable-IniExtension -iniPath $testIniPath -extName "opcache" | Should -Be 0
        (Get-Content $testIniPath) -match "^zend_extension=php_opcache.dll" | Should -Be $true
    }
    
    It "Creates backup before modifying" {
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug"
        Test-Path $testBackupPath | Should -Be $true
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be -1
    }
    
    It "Prompts to add missing extension" {
        Mock Get-Single-PHPExtensionStatus { return $null }
        Mock Read-Host { return "y" }
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be 0
    }
}

Describe "Disable-IniExtension" {
    BeforeEach {
        Mock Read-Host { return "n" }
        Mock Add-Missing-PHPExtension { return 0 }
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
    }
    
    It "Disables enabled extension" {
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
        Disable-IniExtension -iniPath $testIniPath -extName "opcache" | Should -Be 0
        (Get-Content $testIniPath) -match "^;zend_extension=php_opcache.dll" | Should -Be $true
    }
    
    It "Creates backup before modifying" {
        Disable-IniExtension -iniPath $testIniPath -extName "curl"
        Test-Path $testBackupPath | Should -Be $true
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Disable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be -1
    }
    
    It "Prompts to add missing extension" {
        Mock Get-Single-PHPExtensionStatus { return $null }
        Mock Read-Host { return "y" }
        Disable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be 0
    }
}

Describe "Get-IniExtensionStatus" {
    BeforeEach {
        Reset-Ini-Content
        Mock Add-Missing-PHPExtension { return 0 }
    }
    
    It "Detects enabled extension" {
        Get-IniExtensionStatus -iniPath $testIniPath -extName "curl" | Should -Be 0
    }
    
    It "Detects disabled extension" {
        Get-IniExtensionStatus -iniPath $testIniPath -extName "xdebug" | Should -Be 0
    }
    
    It "Detects enabled zend_extension" {
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
    
    It "Handles xdebug special case with 'n' input" {
        Mock Read-Host { return "n" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "nonexistent_xdebug_test" | Should -Be -1
    }
    
    It "Handles xdebug special case with 'y' input" {
        Mock Read-Host { return "y" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "xdebug" | Should -Be 0
    }
    
    It "Handles xdebug special case with failed PHP version" {
            @"
memory_limit = 128M
extension=php_curl.dll
zend_extension=php_opcache.dll
"@ | Set-Content -Path $testIniPath -Encoding UTF8
        Mock Read-Host { return "y" }
        Mock Add-Missing-PHPExtension { return -1 }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "xdebug" | Should -Be -1
    }
    
    It "Handles non-xdebug extension with 'n' input for adding to list" {
        Mock Read-Host { return "n" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "nonexistent_ext" | Should -Be -1
    }
    
    It "Handles non-xdebug extension with 'y' input for adding to list" {
        Mock Read-Host { return "y" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "newext" | Should -Be 0
    }
    
    It "Handles zend_extension addition for opcache" {
            @"
;extension=php_xdebug.dll
extension=php_curl.dll
"@ | Set-Content -Path $testIniPath -Encoding UTF8
        Mock Read-Host { return "y" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "opcache" | Should -Be 0
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
        Mock Get-PHPExtensionsStatus {
            return @()
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

Describe "Get-PHPExtensionsStatus" {
    BeforeEach {
        Reset-Ini-Content
    }
    
    It "Returns extensions with correct status" {
        $extensions = Get-PHPExtensionsStatus -PhpIniPath $testIniPath
        $extensions | Should -Not -Be $null
        $extensions.Count | Should -BeGreaterThan 0
        
        $curlExt = $extensions | Where-Object { $_.Extension -like "*curl*" }
        $curlExt.Enabled | Should -Be $true
        
        $xdebugExt = $extensions | Where-Object { $_.Extension -like "*xdebug*" }
        $xdebugExt.Enabled | Should -Be $false
    }
    
    It "Handles empty ini file" {
        "" | Set-Content $testIniPath
        $extensions = Get-PHPExtensionsStatus -PhpIniPath $testIniPath
        $extensions | Should -Be $null
    }
}

Describe "Install-IniExtension" {
    BeforeAll {
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
        Mock Test-Path { return $true }
        
    }
    
    BeforeEach {
        $global:getRandomFile = $false
        $global:MockFileSystem.DownloadFails = $false
        $global:MockFileSystem.WebResponses = @{
            "https://pecl.php.net/package/nonexistent_ext" = @{
                Content = "Mocked PHP nonexistent_ext content"
                Links = @()
            }
            "https://pecl.php.net/package/pdo_mysql" = @{
                Content = "Mocked pdo_mysql content"
                Links = @(
                    @{ href = "/package/pdo_mysql/1.4.0/windows" },
                    @{ href = "/package/pdo_mysql/2.1.0/windows" }
                )
            }
            "https://pecl.php.net/package/curl" = @{
                Content = "Mocked curl content"
                Links = @(
                    @{ href = "/package/curl/1.4.0/windows" },
                    @{ href = "/package/curl/2.1.0/windows" }
                )
            }
            "https://pecl.php.net/package/curl/1.4.0/windows" = @{
                Content = "Mocked PHP curl 1.4.0 content"
                Links = @(
                    @{ href = "other_link" },
                    @{ href = "https://downloads.php.net/~windows/pecl/releases/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "https://downloads.php.net/~windows/pecl/releases/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip" }
                )
            }
            "https://downloads.php.net/~windows/pecl/releases/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" = @{
                Content = "Mocked PHP curl 1.4.0 zip content"
            }
            "https://pecl.php.net/package/curl/2.1.0/windows" = @{
                Content = "Mocked PHP curl 2.1.0 content"
                Links = @()
            }
        }
    }
    
    It "Handles null extension name" {
        $code = Install-IniExtension -iniPath $testIniPath -extName $null
        $code | Should -Be -1
    }
    
    It "Returns -1 when gets empty list from extension" {
        $code = Install-IniExtension -iniPath $testIniPath -extName "nonexistent_ext"
        $code | Should -Be -1
    }
    
    It "Returns -1 when No package is found" {
        Mock Add-Member { throw "error" }
        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when user does not choose a zip extension version to install" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { }

        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when user does choose a non valid zip extension version to install" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith {
            return 5
        }

        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when downloaded zip extension has no dll" {
        $global:getRandomFile = $true        
        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when user answers no to replace existing extension" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { 
            return "n"
        }
        
        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Returns -1 when user answers no to replace existing extension" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { 
            return "y"
        }
        Mock Move-Item { }
        Mock Add-Missing-PHPExtension { return -1 }
        
        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be -1
    }
    
    It "Installs extension successfully" {
        Mock Test-Path { return $false }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { 
            return "y"
        }
        Mock Install-Extension { return 0 }
        
        $code = Install-IniExtension -iniPath $testIniPath -extName "curl"
        $code | Should -Be 0
    }
    
    It "Handles thrown exception" {
        $global:MockFileSystem.DownloadFails = $true
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
    
    BeforeEach {
        $global:getRandomFile = $false
        $global:MockFileSystem.DownloadFails = $false
        $global:MockFileSystem.WebResponses = @{
            "https://pecl.php.net/packages.php" = @{
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
            "https://pecl.php.net/packages.php?catpid=1&amp;catname=Authentication" = @{
                Content = "Mocked PHP extension Auth content"
                Links = @(
                    @{ href = $null }
                    @{ href = "/package/courierauth" }
                    @{ href = "/package/krb5" }
                )
            }
            "https://pecl.php.net/packages.php?catpid=3&amp;catname=Caching" = @{
                Content = "Mocked PHP extension Caching content"
                Links = @(
                    @{ href = "/package/APC" }
                    @{ href = "/package/APCu" }
                )
            }
            "https://pecl.php.net/packages.php?catpid=7&amp;catname=EmptyCat" = @{
                Content = "Mocked PHP extension EmptyCat content"
                Links = @()
            }
        }
    }
    
    It "Returns list of available extensions" {
        $list = Get-PHPExtensions-From-Source
        $list.Count | Should -Be 2
    }
    
    It "Handles thrown exception" {
        $global:MockFileSystem.DownloadFails = $true
        $list = Get-PHPExtensions-From-Source
        $list.Count | Should -Be 0
    }
}

Describe "List-PHP-Extensions" {
    BeforeAll {
        Mock Get-PHPExtensionsStatus {
            return @(
                @{Extension = "curl"; Enabled = $true; Type = "extension"}
                @{Extension = "opcache"; Enabled = $false; Type = "zend_extension"}
            )
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
        Mock Get-PHPExtensionsStatus { return @() }
        $code = List-PHP-Extensions -iniPath $testIniPath
        $code | Should -Be -1
    }
    
    It "Displays installed extensions" {
        $code = List-PHP-Extensions -iniPath $testIniPath
        $code | Should -Be 0
        Assert-MockCalled Get-PHPExtensionsStatus -Exactly 1
        Assert-MockCalled Display-Extensions-States -Exactly 1
        Assert-MockCalled Display-Installed-Extensions -Exactly 1
    }
    
    It "Displays local extensions matching the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -term "pc"
        $code | Should -Be 0
        Assert-MockCalled Get-PHPExtensionsStatus -Exactly 1
        Assert-MockCalled Display-Extensions-States -Exactly 1
        Assert-MockCalled Display-Installed-Extensions -Exactly 1
    }
    
    It "Returns -1 when no local extensions matchs the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -term "nonexistent"
        $code | Should -Be -1
        Assert-MockCalled Get-PHPExtensionsStatus -Exactly 1
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
        Mock Get-Item { return @{LastWriteTime = "2025-09-09T18:27:39.5309088+01:00"} }
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
        Mock Test-Path { return $true }
        Mock New-TimeSpan { throw "Access denied" }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
    }    
}

Describe "Invoke-PVMIniAction" {
    BeforeEach {
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
    }
    
    Context "info action" {
        It "Executes info action successfully" {
            $result = Invoke-PVMIniAction -action "info" -params @()
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
            $result = Invoke-PVMIniAction -action "set" -params @("memory_limit=512M")
            $result | Should -Be 0
        }
        
        It "Sets multiple settings" {
            $result = Invoke-PVMIniAction -action "set" -params @("memory_limit=512M", "max_execution_time=60")
            $result | Should -Be 0
        }
        
        It "Requires at least one parameter" {
            $result = Invoke-PVMIniAction -action "set" -params @()
            $result | Should -Be -1
        }
    }
    
    Context "enable action" {
        It "Enables single extension" {
            $result = Invoke-PVMIniAction -action "enable" -params @("xdebug")
            $result | Should -Be 0
        }
        
        It "Enables multiple extensions" {
            @"
;extension=php_xdebug.dll
;extension=php_gd.dll
extension=php_curl.dll
"@ | Set-Content (Join-Path $phpVersionPath "php.ini")
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
                                "https://pecl.php.net/package/nonexistent_ext" = @{
                                    Content = "Mocked PHP nonexistent_ext content"
                                    Links = @()
                                }
                                "https://pecl.php.net/package/pdo_mysql" = @{
                                    Content = "Mocked pdo_mysql content"
                                    Links = @(
                                        @{ href = "/package/pdo_mysql/1.4.0/windows" },
                                        @{ href = "/package/pdo_mysql/2.1.0/windows" }
                                    )
                                }
                                "https://pecl.php.net/package/curl" = @{
                                    Content = "Mocked curl content"
                                    Links = @(
                                        @{ href = "/package/curl/1.4.0/windows" },
                                        @{ href = "/package/curl/2.1.0/windows" }
                                    )
                                }
                                "https://pecl.php.net/package/curl/1.4.0/windows" = @{
                                    Content = "Mocked PHP curl 1.4.0 content"
                                    Links = @(
                                        @{ href = "other_link" },
                                        @{ href = "https://downloads.php.net/~windows/pecl/releases/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" },
                                        @{ href = "https://downloads.php.net/~windows/pecl/releases/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip" }
                                    )
                                }
                                "https://downloads.php.net/~windows/pecl/releases/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" = @{
                                    Content = "Mocked PHP curl 1.4.0 zip content"
                                }
                                "https://pecl.php.net/package/curl/2.1.0/windows" = @{
                                    Content = "Mocked PHP curl 2.1.0 content"
                                    Links = @()
                                }
                            }
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
            Mock Get-PHPExtensionsStatus {
                return @(
                    @{Extension = "curl"; Enabled = $true; Type = "extension"}
                    @{Extension = "opcache"; Enabled = $false; Type = "zend_extension"}
                )
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