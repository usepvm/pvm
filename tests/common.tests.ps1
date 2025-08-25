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
    Context "When PVM is properly set up" {
        It "Should return true when all environment variables are correctly configured" {
            Mock Get-EnvVar-ByName {
                param($name)
                switch ($name) {
                    "Path" { return "C:\pvm;C:\php8.1;C:\other\paths" }
                    "php" { return "C:\php8.1" }
                    "pvm" { return "C:\pvm" }
                }
            }
            
            $result = Is-PVM-Setup
            $result | Should -Be $true
        }
        
        It "Should return true when pvm is in path with different casing" {
            Mock Get-EnvVar-ByName {
                param($name)
                switch ($name) {
                    "Path" { return "C:\PVM;C:\php8.1;C:\other\paths" }
                    "PHP" { return "C:\php8.1" }
                    "pvm" { return "C:\pvm" }
                }
            }
            
            $result = Is-PVM-Setup
            $result | Should -Be $true
        }
    }
    
    Context "When PVM is not properly set up" {
        It "Should return false when pvm environment variable is null" {
            Mock Get-EnvVar-ByName {
                param($name)
                switch ($name) {
                    "Path" { return "C:\php8.1;C:\other\paths" }
                    "PHP" { return "C:\php8.1" }
                    "pvm" { return $null }
                }
            }
            
            $result = Is-PVM-Setup
            $result | Should -Be $false
        }
        
        It "Should return false when pvm is not in PATH" {
            Mock Get-EnvVar-ByName {
                param($name)
                switch ($name) {
                    "Path" { return "C:\php8.1;C:\other\paths" }
                    "PHP" { return "C:\php8.1" }
                    "pvm" { return "C:\pvm" }
                }
            }
            
            $result = Is-PVM-Setup
            $result | Should -Be $false
        }
        
        It "Should return false when PHP environment variable is null" {
            Mock Get-EnvVar-ByName {
                param($name)
                switch ($name) {
                    "Path" { return "C:\pvm;C:\other\paths" }
                    "PHP" { return $null }
                    "pvm" { return "C:\pvm" }
                }
            }
            
            $result = Is-PVM-Setup
            $result | Should -Be $false
        }
        
        It "Should return false when PHP value is not in PATH" {
            Mock Get-EnvVar-ByName {
                param($name)
                switch ($name) {
                    "Path" { return "C:\pvm;C:\other\paths" }
                    "PHP" { return "C:\php8.1" }
                    "pvm" { return "C:\pvm" }
                }
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
            Mock Get-All-Subdirectories {
                param ($path)
                return @(
                    @{ Name = "8.1"; FullName = "path\php\8.1" }
                    @{ Name = "7.4"; FullName = "path\php\7.4" }
                    @{ Name = "8.2"; FullName = "path\php\8.2" }
                    @{ Name = "8.0"; FullName = "path\php\8.0" }
                    @{ Name = "5.6"; FullName = "path\php\5.6" }
                )
            }
            Mock Log-Data { return $true }
            
            $result = Get-Installed-PHP-Versions
            $expected = @("5.6", "7.4", "8.0", "8.1", "8.2")
            
            $result.Count | Should -Be $expected.Count
            for ($i = 0; $i -lt $result.Count; $i++) {
                $result[$i] | Should -Be $expected[$i]
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
            Mock Get-All-Subdirectories {
                param ($path)
                return @(
                    @{ Name = "8.1"; FullName = "path\php\8.1" }
                    @{ Name = "7.4"; FullName = "path\php\7.4" }
                )
            }
            Mock Log-Data { return $true }
            
            $result = Get-Installed-PHP-Versions
            $result.Count | Should -Be 2
            $result[0] | Should -Be "7.4"
            $result[1] | Should -Be "8.1"
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

Describe "Get-Matching-PHP-Versions" {
    Context "When matching versions exist" {
        It "Should return matching versions for partial version number" {
            Mock Get-Installed-PHP-Versions {
                return @("7.4", "8.0", "8.1", "8.2")
            }
            Mock Log-Data { return $true }
            
            $result = Get-Matching-PHP-Versions -version "8"
            $expected = @("8.0", "8.1", "8.2")
            
            $result.Count | Should -Be $expected.Count
            $result -contains "8.0" | Should -Be $true
            $result -contains "8.1" | Should -Be $true
            $result -contains "8.2" | Should -Be $true
        }
        
        It "Should return exact match for pattern version number" {
            Mock Get-Installed-PHP-Versions {
                return @("7.4", "8.0", "8.1", "8.1.9", "8.2")
            }
            Mock Log-Data { return $true }
            
            $result = Get-Matching-PHP-Versions -version "8.1"
            $result.Count | Should -Be 2
            $result[0] | Should -Be "8.1"
        }
        
         It "Should return exact match for full version number" {
            Mock Get-Installed-PHP-Versions {
                return @("7.4", "8.0", "8.1", "8.1.9", "8.2")
            }
            Mock Log-Data { return $true }
            
            $result = Get-Matching-PHP-Versions -version "8.1.9"
            $result.Count | Should -Be 1
            $result | Should -Be "8.1.9"
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
                if ($version -eq "8.1") {
                    return @("8.1", "8.1.1", "8.1.2")
                }
                return @()
            }
            Mock Log-Data { return $true }
            
            $result = Is-PHP-Version-Installed -version "8.1"
            $result | Should -Be $true
        }
        
        It "Should return false for non-installed version" {
            Mock Get-Matching-PHP-Versions {
                param($version)
                if ($version -eq "8.1") {
                    return @("8.1.1", "8.1.2")  # 8.1 exact match not included
                }
                return @()
            }
            Mock Log-Data { return $true }
            
            $result = Is-PHP-Version-Installed -version "8.1"
            $result | Should -Be $false
        }
        
        It "Should return false when no matching versions found" {
            Mock Get-Matching-PHP-Versions {
                return @()
            }
            Mock Log-Data { return $true }
            
            $result = Is-PHP-Version-Installed -version "9.0"
            $result | Should -Be $false
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

Describe "Integration Tests" {
    Context "When testing function interactions" {
        It "Should work together for a complete workflow" {
            # Mock the environment to simulate a working PVM setup
            Mock Get-EnvVar-ByName {
                param($name)
                switch ($name) {
                    "Path" { return "C:\pvm;C:\php8.1;C:\other\paths" }
                    "PHP" { return "C:\php8.1" }
                    "pvm" { return "C:\pvm" }
                }
            }
            
            Mock Get-Installed-PHP-Versions {
                return @("7.4", "8.0", "8.1", "8.1.9", "8.2")
            }
            
            Mock Log-Data { return $true }
            
            # Test the complete workflow
            $pvmSetup = Is-PVM-Setup
            $installedVersions = Get-Installed-PHP-Versions
            $matchingVersions = Get-Matching-PHP-Versions -version "8"
            $isInstalled = Is-PHP-Version-Installed -version "8.1"
            
            $pvmSetup | Should -Be $true
            $installedVersions -contains "8.1" | Should -Be $true
            $matchingVersions -contains "8.1" | Should -Be $true
            $isInstalled | Should -Be $true
        }
    }
}