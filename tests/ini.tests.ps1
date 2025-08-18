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
        return
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
}

Describe "Disable-IniExtension" {
    BeforeEach {
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
}

Describe "Get-IniExtensionStatus" {
    BeforeEach {
        Reset-Ini-Content
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
        Mock Get-Current-PHP-Version { return @{ version = $null; path = $null } }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "xdebug" | Should -Be -1
    }
    
    It "Handles non-xdebug extension with 'n' input for adding to list" {
        Mock Read-Host { return "n" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "nonexistent_ext" | Should -Be -1
    }
    
    It "Handles non-xdebug extension with 'y' input for adding to list" {
        Mock Read-Host { return "y" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "newext" | Should -Be 0
        (Get-Content $testIniPath) -match "^extension=newext" | Should -Be $true
    }
    
    It "Handles zend_extension addition for opcache" {
            @"
;extension=php_xdebug.dll
extension=php_curl.dll
"@ | Set-Content -Path $testIniPath -Encoding UTF8
        Mock Read-Host { return "y" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "opcache" | Should -Be 0
        (Get-Content $testIniPath) -match "^zend_extension=opcache" | Should -Be $true
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
    
    It "Throws error for non-existent ini file" {
        { Get-PHPExtensionsStatus -PhpIniPath "nonexistent.ini" } | Should -Throw
    }
    
    It "Handles empty ini file" {
        "" | Set-Content $testIniPath
        $extensions = Get-PHPExtensionsStatus -PhpIniPath $testIniPath
        $extensions | Should -Be $null
    }
}

Describe "Invoke-PVMIniAction" {
    BeforeEach {
        Reset-Ini-Content
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
        Mock Get-Item {
            return @{ Target = $phpVersionPath }
        }
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
    
    Context "error handling" {
        It "Handles invalid action" {
            $result = Invoke-PVMIniAction -action "invalid" -params @()
            $result | Should -Be 1
        }
        
        It "Handles missing PHP current version" {
            Mock Get-Item { return $null }
            $result = Invoke-PVMIniAction -action "info" -params @()
            $result | Should -Be -1
        }
        
        It "Handles missing php.ini file" {
            Remove-Item (Join-Path $phpVersionPath "php.ini") -Force
            $result = Invoke-PVMIniAction -action "info" -params @()
            $result | Should -Be -1
        }
        
        It "Returns -1 on unexpected error" {
            Mock Get-Item { throw "Unexpected error" }
            $result = Invoke-PVMIniAction -action "info" -params @()
            $result | Should -Be -1
        }
    }
}