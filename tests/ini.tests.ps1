# INI Management Functions Tests

BeforeAll {
    # Mock global variables and functions that would be defined elsewhere
    $global:LOG_ERROR_PATH = "$PSScriptRoot\storage\logs\error.log"
    $global:PHP_CURRENT_ENV_NAME = "PHP"
    
    # Mock the Log-Data function
    function Log-Data {
        param($logPath, $message, $data)
        return $true
    }
    
    # Mock Get-EnvVar-ByName function
    function Get-EnvVar-ByName {
        param($name)
        return "$PSScriptRoot\storage\php\current"
    }
    
    # Setup test directory and files
    $script:TestDir = "TestDrive:\phptest"
    $script:TestIniPath = "$TestDir\php.ini"
    $script:TestBackupPath = "$TestIniPath.bak"
    
    New-Item -ItemType Directory -Path $TestDir -Force | Out-Null
    
    # Sample INI content for testing
    $script:SampleIniContent = @"
; PHP Configuration
memory_limit = 128M
max_execution_time = 30
;extension=curl
extension=openssl
; zend_extension=opcache
zend_extension=xdebug
post_max_size = 8M
upload_max_filesize = 2M
"@
    
    # Source the functions being tested (assuming they're in a separate file)
    # . "$PSScriptRoot\IniManagement.ps1"
}

Describe "Backup-IniFile Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        if (Test-Path $TestBackupPath) { Remove-Item $TestBackupPath }
    }
    
    It "Should create backup when backup doesn't exist" {
        Backup-IniFile -iniPath $TestIniPath
        
        Test-Path $TestBackupPath | Should -Be $true
        Get-Content $TestBackupPath | Should -Be (Get-Content $TestIniPath)
    }
    
    It "Should not overwrite existing backup" {
        "existing backup" | Set-Content $TestBackupPath
        
        Backup-IniFile -iniPath $TestIniPath
        
        Get-Content $TestBackupPath | Should -Be "existing backup"
    }
    
    It "Should return -1 on exception" {
        Mock Copy-Item { throw "Access denied" }
        
        $result = Backup-IniFile -iniPath $TestIniPath
        
        $result | Should -Be -1
    }
}

Describe "Restore-IniBackup Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        if (Test-Path $TestBackupPath) { Remove-Item $TestBackupPath }
        Mock Write-Host {}
    }
    
    It "Should restore from backup successfully" {
        "backup content" | Set-Content $TestBackupPath
        
        $result = Restore-IniBackup -iniPath $TestIniPath
        
        $result | Should -Be 0
        Get-Content $TestIniPath | Should -Be "backup content"
    }
    
    It "Should return -1 when backup file not found" {
        $result = Restore-IniBackup -iniPath $TestIniPath
        
        $result | Should -Be -1
    }
    
    It "Should return -1 on copy exception" {
        "backup content" | Set-Content $TestBackupPath
        Mock Copy-Item { throw "Access denied" }
        
        $result = Restore-IniBackup -iniPath $TestIniPath
        
        $result | Should -Be -1
    }
}

Describe "Get-IniSetting Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        Mock Write-Host {}
    }
    
    It "Should return -1 when key is missing" {
        $result = Get-IniSetting -iniPath $TestIniPath -key $null
        
        $result | Should -Be -1
    }
    
    It "Should return -1 when key is empty string" {
        $result = Get-IniSetting -iniPath $TestIniPath -key ""
        
        $result | Should -Be -1
    }
    
    It "Should find and return existing setting" {
        $result = Get-IniSetting -iniPath $TestIniPath -key "memory_limit"
        
        $result | Should -Be 0
    }
    
    It "Should return -1 for non-existent key" {
        $result = Get-IniSetting -iniPath $TestIniPath -key "nonexistent_setting"
        
        $result | Should -Be -1
    }
    
    It "Should handle keys with special regex characters" {
        $specialContent = "test.setting = value"
        Add-Content -Path $TestIniPath -Value $specialContent
        
        $result = Get-IniSetting -iniPath $TestIniPath -key "test.setting"
        
        $result | Should -Be 0
    }
    
    It "Should return -1 on file read exception" {
        Mock Get-Content { throw "File not found" }
        
        $result = Get-IniSetting -iniPath $TestIniPath -key "memory_limit"
        
        $result | Should -Be -1
    }
}

Describe "Set-IniSetting Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        if (Test-Path $TestBackupPath) { Remove-Item $TestBackupPath }
        Mock Write-Host {}
    }
    
    It "Should return -1 for invalid key=value format" {
        $invalidFormats = @("invalidformat", "key=", "=value", "key==value=extra")
        
        foreach ($format in $invalidFormats) {
            $result = Set-IniSetting -iniPath $TestIniPath -keyValue $format
            $result | Should -Be -1
        }
    }
    
    It "Should successfully update existing setting" {
        $result = Set-IniSetting -iniPath $TestIniPath -keyValue "memory_limit=512M"
        
        $result | Should -Be 0
        Test-Path $TestBackupPath | Should -Be $true
        (Get-Content $TestIniPath) -match "memory_limit = 512M" | Should -Not -BeNullOrEmpty
    }
    
    It "Should return -1 for non-existent key" {
        $result = Set-IniSetting -iniPath $TestIniPath -keyValue "nonexistent_key=value"
        
        $result | Should -Be -1
    }
    
    It "Should handle keys with special characters" {
        # Add a setting with special characters first
        Add-Content -Path $TestIniPath -Value "test.setting = original"
        
        $result = Set-IniSetting -iniPath $TestIniPath -keyValue "test.setting=updated"
        
        $result | Should -Be 0
    }
    
    It "Should return -1 on file operation exception" {
        Mock Set-Content { throw "Access denied" }
        
        $result = Set-IniSetting -iniPath $TestIniPath -keyValue "memory_limit=512M"
        
        $result | Should -Be -1
    }
}

Describe "Enable-IniExtension Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        if (Test-Path $TestBackupPath) { Remove-Item $TestBackupPath }
        Mock Write-Host {}
    }
    
    It "Should return -1 when extension name is missing" {
        $result = Enable-IniExtension -iniPath $TestIniPath -extName $null
        
        $result | Should -Be -1
    }
    
    It "Should return -1 when extension name is empty" {
        $result = Enable-IniExtension -iniPath $TestIniPath -extName ""
        
        $result | Should -Be -1
    }
    
    It "Should successfully enable disabled extension" {
        $result = Enable-IniExtension -iniPath $TestIniPath -extName "curl"
        
        $result | Should -Be 0
        Test-Path $TestBackupPath | Should -Be $true
        (Get-Content $TestIniPath) -match "^extension=curl" | Should -Not -BeNullOrEmpty
    }
    
    It "Should successfully enable disabled zend_extension" {
        $result = Enable-IniExtension -iniPath $TestIniPath -extName "opcache"
        
        $result | Should -Be 0
        (Get-Content $TestIniPath) -match "^zend_extension=opcache" | Should -Not -BeNullOrEmpty
    }
    
    It "Should return -1 for already enabled extension" {
        $result = Enable-IniExtension -iniPath $TestIniPath -extName "openssl"
        
        $result | Should -Be -1
    }
    
    It "Should return -1 for non-existent extension" {
        $result = Enable-IniExtension -iniPath $TestIniPath -extName "nonexistent"
        
        $result | Should -Be -1
    }
    
    It "Should return -1 on file operation exception" {
        Mock Set-Content { throw "Access denied" }
        
        $result = Enable-IniExtension -iniPath $TestIniPath -extName "curl"
        
        $result | Should -Be -1
    }
}

Describe "Disable-IniExtension Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        if (Test-Path $TestBackupPath) { Remove-Item $TestBackupPath }
        Mock Write-Host {}
    }
    
    It "Should return -1 when extension name is missing" {
        $result = Disable-IniExtension -iniPath $TestIniPath -extName $null
        
        $result | Should -Be -1
    }
    
    It "Should return -1 when extension name is empty" {
        $result = Disable-IniExtension -iniPath $TestIniPath -extName ""
        
        $result | Should -Be -1
    }
    
    It "Should successfully disable enabled extension" {
        $result = Disable-IniExtension -iniPath $TestIniPath -extName "openssl"
        
        $result | Should -Be 0
        Test-Path $TestBackupPath | Should -Be $true
        (Get-Content $TestIniPath) -match "^;extension=openssl" | Should -Not -BeNullOrEmpty
    }
    
    It "Should successfully disable enabled zend_extension" {
        $result = Disable-IniExtension -iniPath $TestIniPath -extName "xdebug"
        
        $result | Should -Be 0
        (Get-Content $TestIniPath) -match "^;zend_extension=xdebug" | Should -Not -BeNullOrEmpty
    }
    
    It "Should return -1 for already disabled extension" {
        $result = Disable-IniExtension -iniPath $TestIniPath -extName "curl"
        
        $result | Should -Be -1
    }
    
    It "Should return -1 for non-existent extension" {
        $result = Disable-IniExtension -iniPath $TestIniPath -extName "nonexistent"
        
        $result | Should -Be -1
    }
    
    It "Should return -1 on file operation exception" {
        Mock Set-Content { throw "Access denied" }
        
        $result = Disable-IniExtension -iniPath $TestIniPath -extName "openssl"
        
        $result | Should -Be -1
    }
}

Describe "Get-IniExtensionStatus Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        Mock Write-Host {}
    }
    
    It "Should return -1 when extension name is missing" {
        $result = Get-IniExtensionStatus -iniPath $TestIniPath -extName $null
        
        $result | Should -Be -1
    }
    
    It "Should return -1 when extension name is empty" {
        $result = Get-IniExtensionStatus -iniPath $TestIniPath -extName ""
        
        $result | Should -Be -1
    }
    
    It "Should return 0 for enabled extension" {
        $result = Get-IniExtensionStatus -iniPath $TestIniPath -extName "openssl"
        
        $result | Should -Be 0
    }
    
    It "Should return 0 for enabled zend_extension" {
        $result = Get-IniExtensionStatus -iniPath $TestIniPath -extName "xdebug"
        
        $result | Should -Be 0
    }
    
    It "Should return 0 for disabled extension" {
        $result = Get-IniExtensionStatus -iniPath $TestIniPath -extName "curl"
        
        $result | Should -Be 0
    }
    
    It "Should return 0 for disabled zend_extension" {
        $result = Get-IniExtensionStatus -iniPath $TestIniPath -extName "opcache"
        
        $result | Should -Be 0
    }
    
    It "Should return -1 for non-existent extension" {
        $result = Get-IniExtensionStatus -iniPath $TestIniPath -extName "nonexistent"
        
        $result | Should -Be -1
    }
    
    It "Should return -1 on file read exception" {
        Mock Get-Content { throw "File not found" }
        
        $result = Get-IniExtensionStatus -iniPath $TestIniPath -extName "openssl"
        
        $result | Should -Be -1
    }
}

Describe "Invoke-PVMIniAction Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        if (Test-Path $TestBackupPath) { Remove-Item $TestBackupPath }
        Mock Get-EnvVar-ByName { return $TestDir }
        Mock Write-Host {}
    }
    
    Context "INI file validation" {
        It "Should return -1 when php.ini not found" {
            Mock Get-EnvVar-ByName { return "C:\nonexistent" }
            
            $result = Invoke-PVMIniAction -action "get" -params @("memory_limit")
            
            $result | Should -Be -1
        }
    }
    
    Context "Get action tests" {
        It "Should return -1 when no parameters provided" {
            $result = Invoke-PVMIniAction -action "get" -params @()
            
            $result | Should -Be -1
        }
        
        It "Should process multiple get parameters" {
            $result = Invoke-PVMIniAction -action "get" -params @("memory_limit", "max_execution_time")
            
            $result | Should -Be 0
        }
    }
    
    Context "Set action tests" {
        It "Should return -1 when no parameters provided" {
            $result = Invoke-PVMIniAction -action "set" -params @()
            
            $result | Should -Be -1
        }
        
        It "Should process multiple set parameters" {
            $result = Invoke-PVMIniAction -action "set" -params @("memory_limit=512M", "max_execution_time=60")
            
            $result | Should -Be 0
        }
    }
    
    Context "Enable action tests" {
        It "Should return -1 when no parameters provided" {
            $result = Invoke-PVMIniAction -action "enable" -params @()
            
            $result | Should -Be -1
        }
        
        It "Should process multiple enable parameters" {
            $result = Invoke-PVMIniAction -action "enable" -params @("curl", "opcache")
            
            $result | Should -Be 0
        }
    }
    
    Context "Disable action tests" {
        It "Should return -1 when no parameters provided" {
            $result = Invoke-PVMIniAction -action "disable" -params @()
            
            $result | Should -Be -1
        }
        
        It "Should process multiple disable parameters" {
            $result = Invoke-PVMIniAction -action "disable" -params @("openssl", "xdebug")
            
            $result | Should -Be 0
        }
    }
    
    Context "Status action tests" {
        It "Should return -1 when no parameters provided" {
            $result = Invoke-PVMIniAction -action "status" -params @()
            
            $result | Should -Be -1
        }
        
        It "Should process multiple status parameters" {
            $result = Invoke-PVMIniAction -action "status" -params @("openssl", "curl")
            
            $result | Should -Be 0
        }
    }
    
    Context "Restore action tests" {
        It "Should call restore function" {
            "backup content" | Set-Content $TestBackupPath
            
            $result = Invoke-PVMIniAction -action "restore" -params @()
            
            $result | Should -Be 0
        }
    }
    
    Context "Unknown action tests" {
        It "Should handle unknown action gracefully" {
            $result = Invoke-PVMIniAction -action "unknown" -params @()
            
            $result | Should -Be 1  # Default exit code
        }
    }
    
    Context "Exception handling" {
        It "Should return -1 on exception during action processing" {
            Mock Get-Content { throw "Unexpected error" }
            
            $result = Invoke-PVMIniAction -action "get" -params @("memory_limit")
            
            $result | Should -Be -1
        }
    }
}

# Integration tests for complete workflows
Describe "Integration Tests" {
    BeforeEach {
        Set-Content -Path $TestIniPath -Value $SampleIniContent
        if (Test-Path $TestBackupPath) { Remove-Item $TestBackupPath }
        Mock Get-EnvVar-ByName { return $TestDir }
        Mock Write-Host {}
    }
    
    It "Should complete full enable -> disable -> restore workflow" {
        # Enable a disabled extension
        $result1 = Invoke-PVMIniAction -action "enable" -params @("curl")
        $result1 | Should -Be 0
        
        # Verify it's enabled
        $result2 = Invoke-PVMIniAction -action "status" -params @("curl")
        $result2 | Should -Be 0
        
        # Disable it
        $result3 = Invoke-PVMIniAction -action "disable" -params @("curl")
        $result3 | Should -Be 0
        
        # Restore from backup
        $result4 = Invoke-PVMIniAction -action "restore" -params @()
        $result4 | Should -Be 0
    }
    
    It "Should complete full set -> get -> restore workflow" {
        # Set a value
        $result1 = Invoke-PVMIniAction -action "set" -params @("memory_limit=1024M")
        $result1 | Should -Be 0
        
        # Get the value to verify
        $result2 = Invoke-PVMIniAction -action "get" -params @("memory_limit")
        $result2 | Should -Be 0
        
        # Restore original
        $result3 = Invoke-PVMIniAction -action "restore" -params @()
        $result3 | Should -Be 0
        
        # Verify restoration
        $content = Get-Content $TestIniPath
        $content -match "memory_limit = 128M" | Should -Not -BeNullOrEmpty
    }
}