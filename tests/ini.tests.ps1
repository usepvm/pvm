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
}

Describe "Backup-IniFile" {
    It "Creates a backup when none exists" {
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
        Mock Test-Path { throw "Access denied" }
        Backup-IniFile -iniPath "invalidpath" | Should -Be -1
    }
}

Describe "Restore-IniBackup" {
    It "Restores from backup successfully" {
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
    
    It "Handles commented settings" {
        Get-IniSetting -iniPath $testIniPath -key "xdebug" | Should -Be -1
    }
    
    It "Returns -1 for non-existent setting" {
        Get-IniSetting -iniPath $testIniPath -key "nonexistent" | Should -Be -1
    }
    
    It "Requires key parameter" {
        Get-IniSetting -iniPath $testIniPath -key "" | Should -Be -1
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Get-IniSetting -iniPath $testIniPath -key "memory_limit" | Should -Be -1
    }
}

Describe "Set-IniSetting" {
    It "Updates existing setting" {
        Set-IniSetting -iniPath $testIniPath -keyValue "memory_limit=256M" | Should -Be 0
        (Get-Content $testIniPath) -match "^memory_limit\s*=\s*256M" | Should -Be $true
    }
    
    It "Creates backup before modifying" {
        Remove-Item $testBackupPath -ErrorAction SilentlyContinue
        Set-IniSetting -iniPath $testIniPath -keyValue "memory_limit=256M"
        Test-Path $testBackupPath | Should -Be $true
    }
    
    It "Fails for non-existent setting" {
        Set-IniSetting -iniPath $testIniPath -keyValue "nonexistent=value" | Should -Be -1
    }
    
    It "Validates key=value format" {
        Set-IniSetting -iniPath $testIniPath -keyValue "invalidformat" | Should -Be -1
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Set-IniSetting -iniPath $testIniPath -keyValue "memory_limit=256M" | Should -Be -1
    }
}

Describe "Enable-IniExtension" {
    It "Enables commented extension" {
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be 0
        (Get-Content $testIniPath) -match "^extension=php_xdebug.dll" | Should -Be $true
    }
    
    It "Does nothing for already enabled extension" {
        Enable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be -1
    }
    
    It "Fails for non-existent extension" {
        Enable-IniExtension -iniPath $testIniPath -extName "nonexistent" | Should -Be -1
    }
    
    It "Requires extension name" {
        Enable-IniExtension -iniPath $testIniPath -extName "" | Should -Be -1
    }
    
    It "Handles zend_extension" {
        @"
;zend_extension=php_opcache.dll
"@ | Set-Content $testIniPath
        Enable-IniExtension -iniPath $testIniPath -extName "opcache" | Should -Be 0
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Enable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be -1
    }
}

Describe "Disable-IniExtension" {
    It "Disables enabled extension" {
        Reset-Ini-Content
        Disable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be 0
        (Get-Content $testIniPath) -match "^;extension=php_curl.dll" | Should -Be $true
    }
    
    It "Does nothing for already disabled extension" {
        Disable-IniExtension -iniPath $testIniPath -extName "xdebug" | Should -Be -1
    }
    
    It "Fails for non-existent extension" {
        Disable-IniExtension -iniPath $testIniPath -extName "nonexistent" | Should -Be -1
    }
    
    It "Requires extension name" {
        Disable-IniExtension -iniPath $testIniPath -extName "" | Should -Be -1
    }
    
    It "Handles zend_extension" {
        Disable-IniExtension -iniPath $testIniPath -extName "opcache" | Should -Be 0
        (Get-Content $testIniPath) -match "^;zend_extension=php_opcache.dll" | Should -Be $true
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Disable-IniExtension -iniPath $testIniPath -extName "curl" | Should -Be -1
    }
}

Describe "Get-IniExtensionStatus" {
    It "Detects enabled extension" {
        Get-IniExtensionStatus -iniPath $testIniPath -extName "curl" | Should -Be 0
    }
    
    It "Detects disabled extension" {
        Get-IniExtensionStatus -iniPath $testIniPath -extName "xdebug" | Should -Be 0
    }
    
    It "Detects non-existent extension" {
        Get-IniExtensionStatus -iniPath $testIniPath -extName "nonexistent" | Should -Be -1
    }
    
    It "Requires extension name" {
        Get-IniExtensionStatus -iniPath $testIniPath -extName "" | Should -Be -1
    }
    
    It "Returns -1 on error" {
        Mock Get-Content { throw "Access denied" }
        Get-IniExtensionStatus -iniPath $testIniPath -extName "curl" | Should -Be -1
    }
}
