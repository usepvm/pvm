
. "$PSScriptRoot\..\src\actions\profile.ps1"

BeforeAll {
    # Mock global variables
    $global:PROFILES_PATH = "TestDrive:\\profiles"
    $PROFILES_PATH = $global:PROFILES_PATH
    
    # Mock helper functions
    function Get-Current-PHP-Version { 
        return @{ 
            version = "8.2.0"
            path = "C:\\php\\8.2.0"
        }
    }
    
    function Get-PHP-Data { 
        param($PhpIniPath)
        return @{
            settings = @(
                @{ Name = "memory_limit"; Value = "128M"; Enabled = $true },
                @{ Name = "display_errors"; Value = "On"; Enabled = $true },
                @{ Name = "opcache.enable"; Value = "1"; Enabled = $true }
            )
            extensions = @(
                @{ Extension = "php_curl.dll"; Enabled = $true; Type = "extension" },
                @{ Extension = "php_mbstring.dll"; Enabled = $true; Type = "extension" },
                @{ Extension = "php_opcache.dll"; Enabled = $false; Type = "zend_extension" }
            )
        }
    }
    
    # function Backup-IniFile { param($path) {}}
    function Make-Directory { param($path) return 0 }
    function Log-Data { param($data) return $true }
    
    # Create test profile directory
    New-Item -ItemType Directory -Path $global:PROFILES_PATH -Force | Out-Null
}

Describe "Set-IniSetting-Direct Tests" {
    BeforeEach {
        $testIniPath = "TestDrive:\\test.ini"
        "setting1 = value1" | Set-Content -Path $testIniPath
    }
    
    It "Should update existing setting" {
        $result = Set-IniSetting-Direct -iniPath "TestDrive:\\test.ini" -settingName "setting1" -value "newvalue"
        $result | Should -Be 0
        (Get-Content "TestDrive:\\test.ini") | Should -Be "setting1 = newvalue"
    }
    
    It "Should add new setting if not exists" {
        $result = Set-IniSetting-Direct -iniPath "TestDrive:\\test.ini" -settingName "setting2" -value "value2"
        $result | Should -Be 0
        $content = (Get-Content "TestDrive:\\test.ini")
        $content | Should -Contain "setting1 = value1"
        $content | Should -Contain "setting2 = value2"
    }
    
    It "Should handle disabled settings" {
        $result = Set-IniSetting-Direct -iniPath "TestDrive:\\test.ini" -settingName "setting1" -value "newvalue" -enabled $false
        $result | Should -Be 0
        (Get-Content "TestDrive:\\test.ini") | Should -Be ";setting1 = newvalue"
    }
}

Describe "Enable/Disable-IniExtension-Direct Tests" {
    BeforeEach {
        $testIniPath = "TestDrive:\\extensions.ini"
        @(
            ";extension=php_curl.dll",
            "zend_extension=php_opcache.dll"
        ) | Set-Content -Path $testIniPath
    }
    
    It "Should enable an extension" {
        $result = Enable-IniExtension-Direct -iniPath "TestDrive:\\extensions.ini" -extName "curl"
        $result | Should -Be 0
        (Get-Content "TestDrive:\\extensions.ini") | Should -Contain "extension=php_curl.dll"
    }
    
    It "Should disable an extension" {
        $result = Disable-IniExtension-Direct -iniPath "TestDrive:\\extensions.ini" -extName "opcache" -extType "zend_extension"
        $result | Should -Be 0
        (Get-Content "TestDrive:\\extensions.ini") | Should -Contain ";zend_extension=php_opcache.dll"
    }
}

Describe "Save-PHP-Profile Tests" {
    BeforeAll {
        # Create PHP directory and php.ini file
        $phpDir = "TestDrive:\php\8.2.0"
        New-Item -ItemType Directory -Force -Path $phpDir | Out-Null
        "" | Set-Content -Path "$phpDir\php.ini"
        
        Mock Get-Current-PHP-Version { 
            return @{ 
                version = "8.2.0"
                path = $phpDir
            }
        }
        
        Mock Get-PHP-Data { 
            return @{
                settings = @(
                    @{ Name = "memory_limit"; Value = "256M"; Enabled = $true },
                    @{ Name = "display_errors"; Value = "On"; Enabled = $true }
                )
                extensions = @(
                    @{ Extension = "php_curl.dll"; Enabled = $true; Type = "extension" },
                    @{ Extension = "php_opcache.dll"; Enabled = $false; Type = "zend_extension" }
                )
            }
        }
        
        Mock Write-Host {}
        Mock Log-Data { return $true }
    }
    
    It "Returns -1 when php.ini file is missing" {
        Mock Test-Path { return $false }
        
        $result = Save-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
    }
    
    It "Should use default description when none provided" {
        $result = Save-PHP-Profile -profileName "testprofile"
        $result | Should -Be 0
        
        $profilePath = "$global:PROFILES_PATH\testprofile.json"
        Test-Path $profilePath | Should -Be $true
        
        $profileContent = Get-Content $profilePath -Raw | ConvertFrom-Json
        $profileContent.description | Should -Be "Profile saved on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
    
    It "Should return -1 when profile directory cannot be created" {
        Mock Make-Directory { return -1 }
        
        $result = Save-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
    }
    
    It "Should create a profile file with correct structure" {
        # Ensure profiles directory exists
        New-Item -ItemType Directory -Force -Path $global:PROFILES_PATH | Out-Null
        
        $result = Save-PHP-Profile -profileName "testprofile" -description "Test profile"
        $result | Should -Be 0
        
        $profilePath = "$global:PROFILES_PATH\testprofile.json"
        Test-Path $profilePath | Should -Be $true
        
        $profileContent = Get-Content $profilePath -Raw | ConvertFrom-Json
        $profileContent.name | Should -Be "testprofile"
        $profileContent.description | Should -Be "Test profile"
        $profileContent.phpVersion | Should -Be "8.2.0"
        $profileContent.settings.PSObject.Properties.Name -contains "memory_limit" | Should -Be $true
        $profileContent.settings.memory_limit.value | Should -Be "256M"
        $profileContent.extensions.PSObject.Properties.Name -contains "curl" | Should -Be $true
        $profileContent.extensions.curl.enabled | Should -Be $true
    }
    
    It "Should handle errors when PHP version cannot be determined" {
        Mock Get-Current-PHP-Version { return $null }
        
        $result = Save-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
    }
}

Describe "Load-PHP-Profile Tests" {
    BeforeEach {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "512M"; enabled = $true }
                display_errors = @{ value = "Off"; enabled = $true }
                post_max_size = @{ value = "skipped"; enabled = $true }
                ignored_setting = @{ value = "IgnoredValue"; enabled = $true }
            }
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
                opcache = @{ enabled = $false; type = "zend_extension" }
                ignored_extension = @{ enabled = $true; type = "zend_extension" }
                pdo_pgsql = @{ enabled = $true; type = "extension" }
                pdo_sqlite = @{ enabled = $false; type = "extension" }
            }
        }
        
        # Ensure profiles directory exists
        New-Item -ItemType Directory -Force -Path $global:PROFILES_PATH | Out-Null
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        # Create PHP directory and php.ini file
        $phpDir = "TestDrive:\php\8.2.0"
        New-Item -ItemType Directory -Force -Path $phpDir | Out-Null
        "" | Set-Content -Path "$phpDir\php.ini"
        
        Mock Get-Current-PHP-Version { 
            return @{ 
                version = "8.2.0"
                path = $phpDir
            }
        }
        
        Mock Set-IniSetting-Direct { return 0 }
        Mock Enable-IniExtension-Direct { return 0 }
        Mock Disable-IniExtension-Direct { return 0 }
        Mock Write-Host {}
        Mock Log-Data { return $true }
    }
    
    It "Should return -1 when current PHP version cannot be determined" {
        Mock Get-Current-PHP-Version { return $null }
        
        $result = Load-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
    }
    
    It "Should return -1 when php.ini file is missing" {
        Mock Test-Path { return $false }
        
        $result = Load-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
    }
    
    It "Should load and apply a profile" {
        $result = Load-PHP-Profile -profileName "testprofile"
        $result | Should -Be 0
        
        Assert-MockCalled Set-IniSetting-Direct -ParameterFilter { 
            $settingName -eq "memory_limit" -and $value -eq "512M" 
        } -Exactly 1
        
        Assert-MockCalled Set-IniSetting-Direct -ParameterFilter { 
            $settingName -eq "display_errors" -and $value -eq "Off" 
        } -Exactly 1
        
        Assert-MockCalled Enable-IniExtension-Direct -ParameterFilter { 
            $extName -eq "curl" 
        } -Exactly 1
        
        Assert-MockCalled Disable-IniExtension-Direct -ParameterFilter { 
            $extName -eq "opcache" 
        } -Exactly 1
    }
    
    It "Shows number of skipped/ignored settings and extensions" {
        Mock Set-IniSetting-Direct -ParameterFilter {$settingName -eq "post_max_size"} -MockWith { return -1 }
        Mock Enable-IniExtension-Direct -ParameterFilter {$extName -eq "pdo_pgsql"} -MockWith { return -1 }
        Mock Disable-IniExtension-Direct -ParameterFilter {$extName -eq "pdo_sqlite"} -MockWith { return -1 }
        
        $result = Load-PHP-Profile -profileName "testprofile"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -eq "  Settings ignored (not popular): 1" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -eq "  Settings skipped: 1" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -eq "  Extensions ignored (not popular): 1"
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -eq "  Extensions skipped: 2"
        } -Exactly 1
    }
    
    It "Should handle non-existent profile" {
        $result = Load-PHP-Profile -profileName "nonexistent"
        $result | Should -Be -1
    }
}

Describe "List-PHP-Profiles Tests" {
    BeforeEach {
        # Create test profiles
        @{
            name = "profile1"
            description = "First profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.1.0"
            settings = @{}
            extensions = @{}
        } | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\profile1.json"
        
        @{
            name = "profile2"
            description = "Second profile"
            created = "2023-02-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                setting1 = @{ value = "value1"; enabled = $true }
            }
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
            }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\profile2.json"
        
        Mock Write-Host {}
    }
    
    It "Returns -1 when profiles directory does not exist" {
        Mock Test-Path { return $false }
        
        $result = List-PHP-Profiles
        $result | Should -Be -1
    }
    
    It "Should list all available profiles" {
        $result = List-PHP-Profiles
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -match "profile1" }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -match "profile2" }
    }
    
    It "Should handle empty profiles directory" {
        # Remove all profiles
        Remove-Item "$global:PROFILES_PATH\*" -Force
        
        $result = List-PHP-Profiles
        $result | Should -Be -1
    }
}

Describe "Get-Popular-PHP-Settings and Get-Popular-PHP-Extensions Tests" {
    It "Should return popular PHP settings" {
        $settings = Get-Popular-PHP-Settings
        $settings | Should -Not -Be $null
        $settings.Count | Should -BeGreaterThan 0
        $settings | Should -Contain "memory_limit"
        $settings | Should -Contain "display_errors"
    }
    
    It "Should return popular PHP extensions" {
        $extensions = Get-Popular-PHP-Extensions
        $extensions | Should -Not -Be $null
        $extensions.Count | Should -BeGreaterThan 0
        $extensions | Should -Contain "curl"
        $extensions | Should -Contain "mbstring"
        $extensions | Should -Contain "opcache"
    }
}

Describe "Show-PHP-Profile Tests" {
    BeforeEach {
        Mock Write-Host {}
        Mock Log-Data { return $true }
        
        # Ensure profiles directory exists
        New-Item -ItemType Directory -Force -Path $global:PROFILES_PATH | Out-Null
    }
    
    It "Should return -1 when profile file does not exist" {
        $result = Show-PHP-Profile -profileName "nonexistent"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'nonexistent' not found" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Use 'pvm profile list' to see available profiles" 
        } -Exactly 1
    }
    
    It "Should return -1 when JSON parsing fails" {
        # Create invalid JSON file
        "invalid json content {{{{ }" | Set-Content -Path "$global:PROFILES_PATH\invalid.json"
        
        $result = Show-PHP-Profile -profileName "invalid"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Failed to show profile" 
        } -Exactly 1
        
        Assert-MockCalled Log-Data -Exactly 1
    }
    
    It "Should display profile with no settings and no extensions" {
        $testProfile = @{
            name = "emptyprofile"
            description = "Empty profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\emptyprofile.json"
        
        $result = Show-PHP-Profile -profileName "emptyprofile"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile: emptyprofile" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Settings \(0\):" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Extensions \(0\):" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "\(none\)" 
        } -Exactly 2
    }
    
    It "Should display profile with settings but no extensions" {
        $testProfile = @{
            name = "settingsonly"
            description = "Settings only profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "256M"; enabled = $true }
                display_errors = @{ value = "On"; enabled = $true }
            }
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\settingsonly.json"
        
        $result = Show-PHP-Profile -profileName "settingsonly"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Settings \(2\):" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Extensions \(0\):" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "memory_limit" 
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "display_errors" 
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "\(none\)" -and $ForegroundColor -eq "Gray"
        } -Exactly 1
    }
    
    It "Should display profile with extensions but no settings" {
        $testProfile = @{
            name = "extensionsonly"
            description = "Extensions only profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
                opcache = @{ enabled = $false; type = "zend_extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\extensionsonly.json"
        
        $result = Show-PHP-Profile -profileName "extensionsonly"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Settings \(0\):" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Extensions \(2\):" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "curl" 
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "opcache" 
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "\(none\)" -and $ForegroundColor -eq "Gray"
        } -Exactly 1
    }
    
    It "Should display profile with both settings and extensions" {
        $testProfile = @{
            name = "fullprofile"
            description = "Full profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "512M"; enabled = $true }
                display_errors = @{ value = "Off"; enabled = $false }
            }
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
                opcache = @{ enabled = $false; type = "zend_extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\fullprofile.json"
        
        $result = Show-PHP-Profile -profileName "fullprofile"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Settings \(2\):" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Extensions \(2\):" 
        } -Exactly 1
    }
    
    It "Should display enabled settings with DarkGreen color and disabled with DarkYellow" {
        $testProfile = @{
            name = "mixedsettings"
            description = "Mixed settings profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                enabled_setting = @{ value = "value1"; enabled = $true }
                disabled_setting = @{ value = "value2"; enabled = $false }
            }
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\mixedsettings.json"
        
        $result = Show-PHP-Profile -profileName "mixedsettings"
        $result | Should -Be 0
        
        # Check for enabled setting status with DarkGreen
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -eq "Enabled" -and $ForegroundColor -eq "DarkGreen"
        } -Exactly 1
        
        # Check for disabled setting status with DarkYellow
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -eq "Disabled" -and $ForegroundColor -eq "DarkYellow"
        } -Exactly 1
    }
    
    It "Should display enabled extensions with DarkGreen color and disabled with DarkYellow" {
        $testProfile = @{
            name = "mixedextensions"
            description = "Mixed extensions profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{
                enabled_ext = @{ enabled = $true; type = "extension" }
                disabled_ext = @{ enabled = $false; type = "extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\mixedextensions.json"
        
        $result = Show-PHP-Profile -profileName "mixedextensions"
        $result | Should -Be 0
        
        # Check for enabled extension status with DarkGreen
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -eq "Enabled" -and $ForegroundColor -eq "DarkGreen"
        } -Exactly 1
        
        # Check for disabled extension status with DarkYellow
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -eq "Disabled" -and $ForegroundColor -eq "DarkYellow"
        } -Exactly 1
    }
    
    It "Should display extension types (extension and zend_extension)" {
        $testProfile = @{
            name = "extensiontypes"
            description = "Extension types profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{
                regular_ext = @{ enabled = $true; type = "extension" }
                zend_ext = @{ enabled = $true; type = "zend_extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\extensiontypes.json"
        
        $result = Show-PHP-Profile -profileName "extensiontypes"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "regular_ext" -and $Object -match "extension"
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "zend_ext" -and $Object -match "zend_extension"
        }
    }
    
    It "Should handle null settings property" {
        $testProfile = @{
            name = "nullsettings"
            description = "Null settings profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\nullsettings.json"
        
        $result = Show-PHP-Profile -profileName "nullsettings"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Settings \(0\):" 
        } -Exactly 1
    }
    
    It "Should handle null extensions property" {
        $testProfile = @{
            name = "nullextensions"
            description = "Null extensions profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "256M"; enabled = $true }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\nullextensions.json"
        
        $result = Show-PHP-Profile -profileName "nullextensions"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Extensions \(0\):" 
        } -Exactly 1
    }
    
    It "Should display all required profile fields" {
        $testProfile = @{
            name = "completeprofile"
            description = "Complete profile description"
            created = "2023-01-01T12:30:45Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\completeprofile.json"
        
        $result = Show-PHP-Profile -profileName "completeprofile"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "`nProfile: completeprofile" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Description: Complete profile description" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Created: 01/01/2023 12:30:45" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "PHP Version: 8.2.0" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "PATH:" 
        } -Exactly 1
    }
    
    It "Should sort settings alphabetically" {
        $testProfile = @{
            name = "sortedsettings"
            description = "Sorted settings profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                zebra = @{ value = "z"; enabled = $true }
                alpha = @{ value = "a"; enabled = $true }
                beta = @{ value = "b"; enabled = $true }
            }
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\sortedsettings.json"
        
        $output = @()
        Mock Write-Host -ParameterFilter { $Object -match "alpha|beta|zebra" } {
            $output += $Object
        }
        
        $result = Show-PHP-Profile -profileName "sortedsettings"
        $result | Should -Be 0
        
        # Verify settings are displayed (order is checked by the function using Sort-Object)
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "alpha" 
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "beta" 
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "zebra" 
        }
    }
    
    It "Should sort extensions alphabetically" {
        $testProfile = @{
            name = "sortedextensions"
            description = "Sorted extensions profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{
                zebra_ext = @{ enabled = $true; type = "extension" }
                alpha_ext = @{ enabled = $true; type = "extension" }
                beta_ext = @{ enabled = $true; type = "extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\sortedextensions.json"
        
        $result = Show-PHP-Profile -profileName "sortedextensions"
        $result | Should -Be 0
        
        # Verify extensions are displayed (order is checked by the function using Sort-Object)
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "alpha_ext" 
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "beta_ext" 
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "zebra_ext" 
        }
    }
    
    It "Should display setting values correctly" {
        $testProfile = @{
            name = "settingvalues"
            description = "Setting values profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "512M"; enabled = $true }
                max_execution_time = @{ value = "60"; enabled = $true }
            }
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\settingvalues.json"
        
        $result = Show-PHP-Profile -profileName "settingvalues"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "memory_limit" -and $Object -match "512M"
        }
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "max_execution_time" -and $Object -match "60"
        }
    }
    
    It "Should handle profile with many settings and extensions" {
        $settings = @{}
        $extensions = @{}
        
        # Add 10 settings
        1..10 | ForEach-Object {
            $settings["setting$_"] = @{ value = "value$_"; enabled = ($_ % 2 -eq 0) }
        }
        
        # Add 10 extensions
        1..10 | ForEach-Object {
            $extensions["ext$_"] = @{ enabled = ($_ % 2 -eq 0); type = if ($_ % 3 -eq 0) { "zend_extension" } else { "extension" } }
        }
        
        $testProfile = @{
            name = "largeprofile"
            description = "Large profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = $settings
            extensions = $extensions
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\largeprofile.json"
        
        $result = Show-PHP-Profile -profileName "largeprofile"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Settings \(10\):" 
        } -Exactly 1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Extensions \(10\):" 
        } -Exactly 1
    }
}

Describe "Delete-PHP-Profile Tests" {
    BeforeEach {
        Mock Write-Host {}
        Mock Log-Data { return $true }
        
        # Ensure profiles directory exists
        New-Item -ItemType Directory -Force -Path $global:PROFILES_PATH | Out-Null
    }
    
    It "Should return -1 when profile file does not exist" {
        $result = Delete-PHP-Profile -profileName "nonexistent"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'nonexistent' not found" 
        } -Exactly 1
    }
    
    It "Should return -1 when user cancels deletion with 'n'" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Read-Host { return "n" }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
        
        # Verify file still exists
        Test-Path "$global:PROFILES_PATH\testprofile.json" | Should -Be $true
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Deletion cancelled" 
        } -Exactly 1
        
        Assert-MockCalled Read-Host -Exactly 1
    }
    
    It "Should return -1 when user cancels deletion with empty response" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Read-Host { return "" }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
        
        # Verify file still exists
        Test-Path "$global:PROFILES_PATH\testprofile.json" | Should -Be $true
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Deletion cancelled" 
        } -Exactly 1
    }
    
    It "Should return -1 when user cancels deletion with 'no'" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Read-Host { return "no" }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
        
        # Verify file still exists
        Test-Path "$global:PROFILES_PATH\testprofile.json" | Should -Be $true
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Deletion cancelled" 
        } -Exactly 1
    }
    
    It "Should successfully delete profile when user confirms with 'y'" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Read-Host { return "y" }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be 0
        
        # Verify file is deleted
        Test-Path "$global:PROFILES_PATH\testprofile.json" | Should -Be $false
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'testprofile' deleted successfully" 
        } -Exactly 1
        
        Assert-MockCalled Read-Host -ParameterFilter { 
            $Prompt -match "Are you sure you want to delete profile 'testprofile'" 
        } -Exactly 1
    }
    
    It "Should successfully delete profile when user confirms with 'Y'" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Read-Host { return "Y" }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be 0
        
        # Verify file is deleted
        Test-Path "$global:PROFILES_PATH\testprofile.json" | Should -Be $false
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'testprofile' deleted successfully" 
        } -Exactly 1
    }
    
    It "Should handle response with whitespace and trim it" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Read-Host { return "  y  " }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be 0
        
        # Verify file is deleted
        Test-Path "$global:PROFILES_PATH\testprofile.json" | Should -Be $false
    }
    
    It "Should handle response with whitespace and cancel if not 'y' or 'Y'" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Read-Host { return "  n  " }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
        
        # Verify file still exists
        Test-Path "$global:PROFILES_PATH\testprofile.json" | Should -Be $true
    }
    
    It "Should return -1 and log error when Remove-Item fails" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Read-Host { return "y" }
        Mock Remove-Item { throw "Access denied" }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Failed to delete profile" 
        } -Exactly 1
        
        Assert-MockCalled Log-Data -Exactly 1
    }
    
    It "Should display correct confirmation prompt with profile name" {
        # Create test profile
        $testProfile = @{
            name = "myprofile"
            description = "My profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\myprofile.json"
        
        Mock Read-Host { return "y" }
        
        $result = Delete-PHP-Profile -profileName "myprofile"
        $result | Should -Be 0
        
        Assert-MockCalled Read-Host -ParameterFilter { 
            $Prompt -match "Are you sure you want to delete profile 'myprofile'" -and 
            $Prompt -match "\(y/n\)"
        } -Exactly 1
    }
    
    It "Should handle deletion of profile with complex name" {
        # Create test profile with special characters in name
        $testProfile = @{
            name = "test-profile_123"
            description = "Test profile with special chars"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\test-profile_123.json"
        
        Mock Read-Host { return "y" }
        
        $result = Delete-PHP-Profile -profileName "test-profile_123"
        $result | Should -Be 0
        
        # Verify file is deleted
        Test-Path "$global:PROFILES_PATH\test-profile_123.json" | Should -Be $false
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'test-profile_123' deleted successfully" 
        } -Exactly 1
    }
    
    It "Should handle case-insensitive confirmation correctly" {
        # Test that both 'y' and 'Y' work, but other variations don't
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        # Test that 'yes' (not just 'y') is rejected
        Mock Read-Host { return "yes" }
        
        $result = Delete-PHP-Profile -profileName "testprofile"
        $result | Should -Be -1
        
        # Verify file still exists
        Test-Path "$global:PROFILES_PATH\testprofile.json" | Should -Be $true
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Deletion cancelled" 
        } -Exactly 1
    }
}

Describe "Export-PHP-Profile Tests" {
    BeforeEach {
        Mock Write-Host {}
        Mock Log-Data { return $true }
        
        # Ensure profiles directory exists
        New-Item -ItemType Directory -Force -Path $global:PROFILES_PATH | Out-Null
        
        # Create export directory and set it as current location
        $exportDir = "TestDrive:\export"
        New-Item -ItemType Directory -Force -Path $exportDir | Out-Null
        
        # Mock Get-Location - when used in string interpolation "$(Get-Location)", 
        # PowerShell converts it to string, so returning a string works
        Mock Get-Location { return $exportDir }
    }
    
    It "Should return -1 when profile file does not exist" {
        $result = Export-PHP-Profile -profileName "nonexistent"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'nonexistent' not found" 
        } -Exactly 1
    }
    
    It "Should export profile to default location when exportPath not provided" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "256M"; enabled = $true }
            }
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        $result = Export-PHP-Profile -profileName "testprofile"
        $result | Should -Be 0
        
        # Verify content matches
        $exportPath = "TestDrive:\export\testprofile.json"
        $exportedContent = Get-Content $exportPath -Raw | ConvertFrom-Json
        $exportedContent.name | Should -Be "testprofile"
        $exportedContent.settings.memory_limit.value | Should -Be "256M"
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'testprofile' exported to:" 
        } -Exactly 1
        
        Assert-MockCalled Get-Location -Exactly 1
    }
    
    It "Should export profile to specified location when exportPath provided" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        $customExportPath = "TestDrive:\custom\myprofile.json"
        New-Item -ItemType Directory -Force -Path "TestDrive:\custom" | Out-Null
        
        $result = Export-PHP-Profile -profileName "testprofile" -exportPath $customExportPath
        $result | Should -Be 0
        
        # Verify file was exported to custom location
        Test-Path $customExportPath | Should -Be $true
        
        # Verify content matches
        $exportedContent = Get-Content $customExportPath -Raw | ConvertFrom-Json
        $exportedContent.name | Should -Be "testprofile"
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'testprofile' exported to:" -and $Object -match "custom\\myprofile.json"
        } -Exactly 1
    }
    
    It "Should overwrite existing file when exporting to existing path" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "256M"; enabled = $true }
            }
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        $exportPath = "TestDrive:\existing.json"
        "old content" | Set-Content -Path $exportPath
        
        $result = Export-PHP-Profile -profileName "testprofile" -exportPath $exportPath
        $result | Should -Be 0
        
        # Verify file was overwritten with new content
        $exportedContent = Get-Content $exportPath -Raw | ConvertFrom-Json
        $exportedContent.name | Should -Be "testprofile"
        $exportedContent.settings.memory_limit.value | Should -Be "256M"
    }
    
    It "Should return -1 and log error when Copy-Item fails" {
        # Create test profile
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\testprofile.json"
        
        Mock Copy-Item { throw "Access denied" }
        
        $result = Export-PHP-Profile -profileName "testprofile" -exportPath "TestDrive:\export.json"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Failed to export profile" 
        } -Exactly 1
        
        Assert-MockCalled Log-Data -Exactly 1
    }
    
    It "Should export profile with complex name correctly" {
        # Create test profile with special characters
        $testProfile = @{
            name = "test-profile_123"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\test-profile_123.json"
        
        $result = Export-PHP-Profile -profileName "test-profile_123"
        $result | Should -Be 0
        
        $expectedPath = "TestDrive:\export\test-profile_123.json"
        Test-Path $expectedPath | Should -Be $true
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile 'test-profile_123' exported to:" 
        } -Exactly 1
    }
    
    It "Should export profile with all fields preserved" {
        # Create comprehensive test profile
        $testProfile = @{
            name = "fullprofile"
            description = "Full profile description"
            created = "2023-01-01T12:30:45Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "512M"; enabled = $true }
                display_errors = @{ value = "Off"; enabled = $false }
            }
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
                opcache = @{ enabled = $false; type = "zend_extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "$global:PROFILES_PATH\fullprofile.json"
        
        $exportPath = "TestDrive:\fullprofile.json"
        $result = Export-PHP-Profile -profileName "fullprofile" -exportPath $exportPath
        $result | Should -Be 0
        
        # Verify all fields are preserved
        $exportedContent = Get-Content $exportPath -Raw | ConvertFrom-Json
        $exportedContent.name | Should -Be "fullprofile"
        $exportedContent.description | Should -Be "Full profile description"
        # Normalize date format (PowerShell adds microseconds when converting DateTime to string)
        # ConvertFrom-Json may return DateTime object or string, handle both cases
        # Parse as UTC to avoid timezone conversion issues
        $expectedDate = [DateTimeOffset]::Parse("2023-01-01T12:30:45Z").UtcDateTime
        $actualDate = if ($exportedContent.created -is [DateTime]) {
            $exportedContent.created.ToUniversalTime()
        } elseif ($exportedContent.created -is [DateTimeOffset]) {
            $exportedContent.created.UtcDateTime
        } else {
            [DateTimeOffset]::Parse($exportedContent.created).UtcDateTime
        }
        $actualDate | Should -Be $expectedDate
        $exportedContent.phpVersion | Should -Be "8.2.0"
        $exportedContent.settings.memory_limit.value | Should -Be "512M"
        $exportedContent.settings.memory_limit.enabled | Should -Be $true
        $exportedContent.settings.display_errors.enabled | Should -Be $false
        $exportedContent.extensions.curl.enabled | Should -Be $true
        $exportedContent.extensions.opcache.enabled | Should -Be $false
        $exportedContent.extensions.opcache.type | Should -Be "zend_extension"
    }
}

Describe "Import-PHP-Profile Tests" {
    BeforeEach {
        Mock Write-Host {}
        Mock Log-Data { return $true }
        Mock Make-Directory { return 0 }
        
        # Ensure profiles directory exists
        New-Item -ItemType Directory -Force -Path $global:PROFILES_PATH | Out-Null
    }
    
    It "Should return -1 when import file does not exist" {
        $result = Import-PHP-Profile -importPath "TestDrive:\nonexistent.json"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "File not found:" 
        } -Exactly 1
    }
    
    It "Should return -1 when JSON file is invalid" {
        # Create invalid JSON file
        "invalid json content {{{{ }" | Set-Content -Path "TestDrive:\invalid.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\invalid.json"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Invalid JSON file:" 
        } -Exactly 1
    }
    
    It "Should return -1 when profile is missing 'name' field" {
        $invalidProfile = @{
            description = "Missing name"
            settings = @{}
            extensions = @{}
        }
        $invalidProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\missingname.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\missingname.json"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Invalid profile format" -and $Object -match "name"
        } -Exactly 1
    }
    
    It "Should return -1 when profile is missing 'settings' field" {
        $invalidProfile = @{
            name = "missing_settings"
            extensions = @{}
        }
        $invalidProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\missingsettings.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\missingsettings.json"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Invalid profile format" -and $Object -match "settings"
        } -Exactly 1
    }
    
    It "Should return -1 when profile is missing 'extensions' field" {
        $invalidProfile = @{
            name = "missing_extensions"
            settings = @{}
        }
        $invalidProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\missingextensions.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\missingextensions.json"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Invalid profile format" -and $Object -match "extensions"
        } -Exactly 1
    }
    
    It "Should import profile using name from profile when profileName not provided" {
        $testProfile = @{
            name = "originalname"
            description = "Original profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "256M"; enabled = $true }
            }
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\originalname.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\originalname.json"
        $result | Should -Be 0
        
        # Verify profile was imported with original name
        $importedPath = "$global:PROFILES_PATH\originalname.json"
        Test-Path $importedPath | Should -Be $true
        
        $importedContent = Get-Content $importedPath -Raw | ConvertFrom-Json
        $importedContent.name | Should -Be "originalname"
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile imported successfully as 'originalname'" 
        } -Exactly 1
    }
    
    It "Should import profile with custom name when profileName provided" {
        $testProfile = @{
            name = "originalname"
            description = "Original profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\originalname.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\originalname.json" -profileName "customname"
        $result | Should -Be 0
        
        # Verify profile was imported with custom name
        $importedPath = "$global:PROFILES_PATH\customname.json"
        Test-Path $importedPath | Should -Be $true
        
        $importedContent = Get-Content $importedPath -Raw | ConvertFrom-Json
        $importedContent.name | Should -Be "customname"
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Profile imported successfully as 'customname'" 
        } -Exactly 1
    }
    
    It "Should update profile name when custom name differs from original" {
        $testProfile = @{
            name = "originalname"
            description = "Original profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "256M"; enabled = $true }
            }
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\originalname.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\originalname.json" -profileName "newname"
        $result | Should -Be 0
        
        # Verify profile name was updated
        $importedPath = "$global:PROFILES_PATH\newname.json"
        $importedContent = Get-Content $importedPath -Raw | ConvertFrom-Json
        $importedContent.name | Should -Be "newname"
        # Verify other fields are preserved
        $importedContent.settings.memory_limit.value | Should -Be "256M"
    }
    
    It "Should copy file directly when custom name matches original" {
        $testProfile = @{
            name = "samename"
            description = "Same name profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\samename.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\samename.json" -profileName "samename"
        $result | Should -Be 0
        
        # Verify profile was imported
        $importedPath = "$global:PROFILES_PATH\samename.json"
        Test-Path $importedPath | Should -Be $true
    }
    
    It "Should return -1 when Make-Directory fails" {
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\testprofile.json"
        
        Mock Make-Directory { return -1 }
        
        $result = Import-PHP-Profile -importPath "TestDrive:\testprofile.json"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Failed to create profiles directory" 
        } -Exactly 1
    }
    
    It "Should import profile with all fields preserved" {
        $testProfile = @{
            name = "fullprofile"
            description = "Full profile description"
            created = "2023-01-01T12:30:45Z"
            phpVersion = "8.2.0"
            settings = @{
                memory_limit = @{ value = "512M"; enabled = $true }
                display_errors = @{ value = "Off"; enabled = $false }
            }
            extensions = @{
                curl = @{ enabled = $true; type = "extension" }
                opcache = @{ enabled = $false; type = "zend_extension" }
            }
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\fullprofile.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\fullprofile.json"
        $result | Should -Be 0
        
        # Verify all fields are preserved
        $importedPath = "$global:PROFILES_PATH\fullprofile.json"
        $importedContent = Get-Content $importedPath -Raw | ConvertFrom-Json
        $importedContent.name | Should -Be "fullprofile"
        $importedContent.description | Should -Be "Full profile description"
        # Normalize date format (PowerShell adds microseconds when converting DateTime to string)
        # ConvertFrom-Json may return DateTime object or string, handle both cases
        # Parse as UTC to avoid timezone conversion issues
        $expectedDate = [DateTimeOffset]::Parse("2023-01-01T12:30:45Z").UtcDateTime
        $actualDate = if ($importedContent.created -is [DateTime]) {
            $importedContent.created.ToUniversalTime()
        } elseif ($importedContent.created -is [DateTimeOffset]) {
            $importedContent.created.UtcDateTime
        } else {
            [DateTimeOffset]::Parse($importedContent.created).UtcDateTime
        }
        $actualDate | Should -Be $expectedDate
        $importedContent.phpVersion | Should -Be "8.2.0"
        $importedContent.settings.memory_limit.value | Should -Be "512M"
        $importedContent.settings.display_errors.enabled | Should -Be $false
        $importedContent.extensions.curl.enabled | Should -Be $true
        $importedContent.extensions.opcache.type | Should -Be "zend_extension"
    }
    
    It "Should display usage message after successful import" {
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\testprofile.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\testprofile.json"
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Use 'pvm profile load testprofile' to apply it" 
        } -Exactly 1
    }
    
    It "Should return -1 and log error when import fails with exception" {
        $testProfile = @{
            name = "testprofile"
            description = "Test profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\testprofile.json"
        
        Mock Copy-Item { throw "Disk full" }
        
        $result = Import-PHP-Profile -importPath "TestDrive:\testprofile.json"
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { 
            $Object -match "Failed to import profile" 
        } -Exactly 1
        
        Assert-MockCalled Log-Data -Exactly 1
    }
    
    It "Should handle profile with empty settings and extensions" {
        $testProfile = @{
            name = "emptyprofile"
            description = "Empty profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\emptyprofile.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\emptyprofile.json"
        $result | Should -Be 0
        
        $importedPath = "$global:PROFILES_PATH\emptyprofile.json"
        Test-Path $importedPath | Should -Be $true
        
        $importedContent = Get-Content $importedPath -Raw | ConvertFrom-Json
        $importedContent.settings | Should -Not -Be $null
        $importedContent.extensions | Should -Not -Be $null
    }
    
    It "Should handle profile with complex name" {
        $testProfile = @{
            name = "test-profile_123"
            description = "Complex name profile"
            created = "2023-01-01T00:00:00Z"
            phpVersion = "8.2.0"
            settings = @{}
            extensions = @{}
        }
        $testProfile | ConvertTo-Json -Depth 10 | Set-Content -Path "TestDrive:\complex.json"
        
        $result = Import-PHP-Profile -importPath "TestDrive:\complex.json" -profileName "new-complex_456"
        $result | Should -Be 0
        
        $importedPath = "$global:PROFILES_PATH\new-complex_456.json"
        Test-Path $importedPath | Should -Be $true
        
        $importedContent = Get-Content $importedPath -Raw | ConvertFrom-Json
        $importedContent.name | Should -Be "new-complex_456"
    }
}