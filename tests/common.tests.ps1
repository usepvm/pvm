# Load required modules and functions
. "$PSScriptRoot\..\src\actions\common.ps1"


Describe "Get-Source-Urls" {
    It "Should return correct URL structure" {
        $result = Get-Source-Urls
        
        $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $result.Keys.Count | Should -Be 2
        $result.Keys -contains "Archives" | Should -Be $true
        $result.Keys -contains "Releases" | Should -Be $true
    }
    
    It "Should return correct Archive URL" {
        $result = Get-Source-Urls
        $result["Archives"] | Should -Be "https://windows.php.net/downloads/releases/archives"
    }
    
    It "Should return correct Releases URL" {
        $result = Get-Source-Urls
        $result["Releases"] | Should -Be "https://windows.php.net/downloads/releases"
    }
}

Describe "Is-PVM-Setup" {
    BeforeAll {
        $global:PHP_CURRENT_VERSION_PATH = "C:\php\8.1"
        $global:PVMRoot = "C:\PVM"
    }
    
    Context "When PVM is properly set up" {
        It "Should return true when all environment variables are correctly configured" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq "Path" } -MockWith { 
                return "C:\pvm;C:\php\8.1;C:\other\paths"
            }
            Mock Test-Path { return $true}
            
            $result = Is-PVM-Setup
            $result | Should -Be $true
        }
        
        It "Should return true when pvm is in path with different casing" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq "Path" } -MockWith { 
                return "C:\PVM;C:\php\8.1;C:\other\paths"
            }
            Mock Test-Path { return $true}
            
            $result = Is-PVM-Setup
            $result | Should -Be $true
        }
    }
    
    Context "When PVM is not properly set up" {
        It "Should return false when pvm is not in PATH" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq "Path" } -MockWith { 
                return "C:\php\8.1;C:\other\paths"
            }
            
            $result = Is-PVM-Setup
            $result | Should -Be $false
        }
        
        It "Should return false when PHP value is not in PATH" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq "Path" } -MockWith { 
                return "C:\pvm;C:\other\paths"
            }
            
            $result = Is-PVM-Setup
            $result | Should -Be $false
        }
    }
    
    Context "When exceptions occur" {
        It "Should return false and log error when Get-EnvVar-ByName throws exception" {
            Mock Get-EnvVar-ByName { throw "Test exception" }
            Mock Log-Data { return $true }
            
            $result = Is-PVM-Setup
            $result | Should -Be $false
            
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq "Is-PVM-Setup - Failed to check if PVM is set up"
            }
        }
    }
}

Describe "Get-Installed-PHP-Versions" {
    Context "When environment variables contain PHP versions" {
        It "Should return sorted PHP versions" {
            $script:STORAGE_PATH = "C:\mock\path"
            $script:LOG_ERROR_PATH = "C:\mock\error"
            Mock Cache-Data { return 0 }
            Mock Can-Use-Cache { return $false }
            Mock Get-Installed-PHP-Versions-From-Directory {
                return @(
                    @{version = "5.6"; arch = "x64"; buildType = "nts"}
                    @{version = "7.4"; arch = "x64"; buildType = "nts"}
                    @{version = "8.0"; arch = "x64"; buildType = "nts"}
                    @{version = "8.1"; arch = "x64"; buildType = "nts"}
                    @{version = "8.2"; arch = "x64"; buildType = "nts"}
                )
            }
            
            $result = Get-Installed-PHP-Versions
            $expected = @("5.6", "7.4", "8.0", "8.1", "8.2")
            
            $result.Count | Should -Be $expected.Count
            for ($i = 0; $i -lt $result.Count; $i++) {
                $result[$i].version | Should -Be $expected[$i]
            }
        }
        
        It "Should return empty array when no PHP versions are found" {
            Mock Get-All-EnvVars {
                return @{
                    "PATH" = "C:\Windows"
                    "OTHER_VAR" = "some value"
                }
            }
            Mock Log-Data { return $true }
            
            $result = Get-Installed-PHP-Versions
            $result.Count | Should -Be 0
        }
        
        It "Should handle single digit versions" {
            Mock Cache-Data { return 0 }
            Mock Can-Use-Cache { return $false }
            Mock Get-Installed-PHP-Versions-From-Directory {
                return @(
                    @{version = "7.4"; arch = "x64"; buildType = "nts"}
                    @{version = "8.1"; arch = "x64"; buildType = "nts"}
                )
            }
            
            $result = Get-Installed-PHP-Versions
            $result.Count | Should -Be 2
            $result[0].version | Should -Be "7.4"
            $result[1].version | Should -Be "8.1"
        }
    }
    
    Context "When exceptions occur" {
        It "Should return empty array and log error when Get-All-EnvVars throws exception" {
            Mock Get-All-Subdirectories { throw "Test exception" }
            Mock Log-Data { return $true }
            
            $result = Get-Installed-PHP-Versions
            $result.Count | Should -Be 0
            
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq "Get-Installed-PHP-Versions - Failed to retrieve installed PHP versions"
            }
        }
    }
}

Describe "Get-UserSelected-PHP-Version" {
    It "Should return null when no installed versions are provided" {
        $result = Get-UserSelected-PHP-Version -installedVersions @()
        $result | Should -Be $null
    }
    
    It "Should return first version when only one is provided" {
        $result = Get-UserSelected-PHP-Version -installedVersions @(@{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'})
        $result.version | Should -Be "8.1"
    }
    
    It "Should return null when no version is selected" {
        Mock Read-Host { return "" }
        Mock Write-Host { }
        
        $result = Get-UserSelected-PHP-Version -installedVersions @(
            @{ version = '7.4'; Arch = 'x64'; BuildType = 'ts'}
            @{ version = '8.0'; Arch = 'x64'; BuildType = 'ts'}
            @{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'}
        )
        $result.code | Should -Be -1
    }
    
    It "Should prompt user and return selected version when multiple are provided" {
        Mock Read-Host { return "2" }
        Mock Write-Host { }
        
        $result = Get-UserSelected-PHP-Version -installedVersions @(
            @{ version = '7.4'; Arch = 'x64'; BuildType = 'ts'; InstallPath = "C:\php\7.4"}
            @{ version = '8.0'; Arch = 'x64'; BuildType = 'ts'; InstallPath = "C:\php\8.0"}
            @{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'; InstallPath = "C:\php\8.1"}
        )
        $result.version | Should -Be "8.1"
        $result.code | Should -Be 0
        $result.path | Should -Be "C:\php\8.1"
    }
}

Describe "Get-Matching-PHP-Versions" {
    Context "When matching versions exist" {
        It "Should return matching versions for partial version number" {
            Mock Get-Installed-PHP-Versions { return @(
                @{Version = "8.2"; Arch = "x64"; BuildType = 'NTS'}
                @{Version = "8.1"; Arch = "x64"; BuildType = 'NTS'}
                @{Version = "8.0"; Arch = "x64"; BuildType = 'NTS'}
                @{Version = "7.4"; Arch = "x64"; BuildType = 'NTS'}
            )}
            
            $result = Get-Matching-PHP-Versions -version "8"
            $expected = @("8.0", "8.1", "8.2")
            
            $result.Count | Should -Be $expected.Count
            $result | Where-Object { $_.version -eq '8.2' } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.version -eq '8.1' } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.version -eq '8.0' } | Should -Not -BeNullOrEmpty
        }
        
        It "Should return exact match for pattern version number" {
            Mock Get-Installed-PHP-Versions {
                return @(
                    @{Version = "8.2"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.1.9"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.1"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.0"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "7.4"; Arch = "x64"; BuildType = 'NTS'}
                )
            }
            
            $result = Get-Matching-PHP-Versions -version "8.1"
            $result.Count | Should -Be 2
            $result[0].version | Should -Be "8.1.9"
        }
        
        It "Should return exact match for full version number" {
            Mock Get-Installed-PHP-Versions {
                return @(
                    @{Version = "7.4"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.0"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.1"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.1.9"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.2"; Arch = "x64"; BuildType = 'NTS'}
                )
            }
            
            $result = Get-Matching-PHP-Versions -version "8.1.9"
            $result.Length | Should -Be 1
            $result.version | Should -Be "8.1.9"
        }
        
        It "Should return empty array when no matches found" {
            Mock Get-Installed-PHP-Versions {
                return @("php7.4", "php8.0", "php8.1")
            }
            Mock Log-Data { return $true }
            
            $result = Get-Matching-PHP-Versions -version "9"
            $result.Count | Should -Be 0
        }
    }
    
    Context "When exceptions occur" {
        It "Should return null and log error when Get-Installed-PHP-Versions throws exception" {
            Mock Get-Installed-PHP-Versions { throw "Test exception" }
            Mock Log-Data { return $true }
            
            $result = Get-Matching-PHP-Versions -version "8.1"
            $result | Should -Be $null
            
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq "Get-Matching-PHP-Versions - Failed to check if PHP version 8.1 is installed"
            }
        }
    }
}

Describe "Is-PHP-Version-Installed" {
    Context "When version exists" {
        It "Should return true for installed version" {
            Mock Get-Matching-PHP-Versions {
                param($version)
                return @(
                    @{Version = "8.1"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.1.1"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.1.2"; Arch = "x64"; BuildType = 'NTS'}
                )
            }
            
            $result = Is-PHP-Version-Installed -version @{version = "8.1"; Arch = "x64"; BuildType = 'NTS'}
            $result | Should -Be $true
        }
        
        It "Should return false for non-installed version" {
            Mock Get-Matching-PHP-Versions {
                param($version)
                return @(
                    @{Version = "8.1.1"; Arch = "x64"; BuildType = 'NTS'}
                    @{Version = "8.1.2"; Arch = "x64"; BuildType = 'NTS'}
                )
            }
            
            $result = Is-PHP-Version-Installed -version @{version = "8.1"; Arch = "x64"; BuildType = 'NTS'}
            $result | Should -Be $null
        }
        
        It "Should return false when no matching versions found" {
            Mock Get-Matching-PHP-Versions {
                return @()
            }
            
            $result = Is-PHP-Version-Installed -version "9.0"
            $result | Should -Be $null
        }
    }
    
    Context "When exceptions occur" {
        It "Should return false and log error when Get-Matching-PHP-Versions throws exception" {
            Mock Get-Matching-PHP-Versions { throw "Test exception" }
            Mock Log-Data { return $true }
            
            $result = Is-PHP-Version-Installed -version "8.1"
            $result | Should -Be $false
            
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq "Is-PHP-Version-Installed - Failed to check if PHP version 8.1 is installed"
            }
        }
    }
}
