
BeforeAll {
    
    # Mock data and helper functions for testing
    $PHP_CURRENT_VERSION_PATH = "C:\pvm\php"
    $LOG_ERROR_PATH = "C:\logs\error.log"

    Mock Write-Host {}

    function Get-Matching-PHP-Versions {
        param($version)
        # Mock implementation
        if ($version -like "8.*") {
            return @(
                @{version="8.1"; path="C:\php\8.1"},
                @{version="8.2"; path="C:\php\8.2"}
            )
        }
        return @()
    }

    Mock Get-UserSelected-PHP-Version {
        param($installedVersions)
        # If we're in the Auto-Select test and a specific version was detected
        if ($global:TestScenario -eq "composer" -or $global:TestScenario -eq ".php-version" -and $installedVersions) {
            # Find the version that matches what we detected (8.2)
            $selected = $installedVersions | Where-Object { $_.version -eq "8.2" }
            if ($selected) {
                return @{code=0; version=$selected.version; path=$selected.path}
            }
        }
        
        # Default behavior - select first version
        if ($installedVersions -and $installedVersions.Count -gt 0) {
            return @{code=0; version=$installedVersions[0].version; path=$installedVersions[0].path}
        }
        return $null
    }

    function Make-Symbolic-Link {
        param($link, $target)
        # Mock implementation
        return @{ code = 0 }
    }

    function Log-Data {
        param($logPath, $message, $data)
        # Mock implementation
        return $true
    }

}

Describe "Detect-PHP-VersionFromProject" {
    It "Should detect PHP version from .php-version" {
        Mock Test-Path { return $true }
        Mock Get-Content { return "7.4" }
        $result = Detect-PHP-VersionFromProject
        $result | Should -Be "7.4"
    }
    
    It "Should detect PHP version from composer.json" {
        Mock Test-Path {
            param($path)
            if ($path -eq "composer.json") { return $true }
            return $false
        }
        Mock Get-Content { return '{"require": {"php": "^8.4"}}' }
        $result = Detect-PHP-VersionFromProject
        $result | Should -Be "8.4"
    }
    
    It "Handles parser exceptions gracefully" {
        Mock Test-Path {
            param($path)
            if ($path -eq "composer.json") { return $true }
            return $false
        }
        Mock Get-Content { throw "Simulated parse error" }
        { Detect-PHP-VersionFromProject } | Should -Not -Throw
    }

}


# Test Cases for Update-PHP-Version
Describe "Update-PHP-Version" {
    BeforeEach {
        $global:TestScenario = $null
    }

    It "Should successfully update to an exact version match" {
        $result = Update-PHP-Version -version "8.1"
        $result.code | Should -Be 0
        $result.message | Should -BeExactly "Now using PHP 8.1"
    }

    It "Should handle version not found when exact path doesn't exist" {
        $result = Update-PHP-Version -version "7.4"
        $result.code | Should -Be -1
        $result.message | Should -BeExactly "PHP version 7.4 was not found!"
    }

    It "Should handle when no matching versions are found" {
        $result = Update-PHP-Version -version "5.6"
        $result.code | Should -Be -1
        $result.message | Should -BeExactly "PHP version 5.6 was not found!"
    }
    
    It "Should return when switching to same current version" {
        Mock Get-UserSelected-PHP-Version { return @{
            code=0; version="8.2.0"; arch = 'x64';
            buildType = 'TS'; path="TestDrive:\php\8.2.0"
        }}
        Mock Get-Current-PHP-Version { return @{
            version = "8.2.0";
            path = "TestDrive:\php\8.2.0" 
            arch = 'x64'
            buildType = 'TS'
        }}
        $result = Update-PHP-Version -version "8.2.0"
        $result.code | Should -Be 0
        $result.message | Should -BeExactly "Already using PHP 8.2.0"
    }
    
    It "Should handle when Make-Symbolic-Link fails" {
        Mock Make-Symbolic-Link { return @{ code = -1; message = "Failed to create link"; color = "DarkYellow" } }
        $result = Update-PHP-Version -version "8.1"
        $result.code | Should -Be -1
        $result.message | Should -BeExactly "Failed to create link"
        $result.color | Should -Be "DarkYellow"
    }

    It "Should handle exceptions gracefully" {
        # Force an exception by mocking Get-Matching-PHP-Versions to throw
        Mock Get-Matching-PHP-Versions { throw "Test exception" }
        $result = Update-PHP-Version -version "8.1"
        $result.code | Should -Be -1
        $result.message | Should -Match "No matching PHP versions found"
    }

    It "Should return error when pathVersionObject is null" {
        Mock Get-UserSelected-PHP-Version { return $null }
        $result = Update-PHP-Version -version "8.x"
        $result.code | Should -Be -1
        $result.message | Should -Match "was not found"
    }

    It "Should return error when pathVersionObject has non-zero code" {
        Mock Get-UserSelected-PHP-Version { return @{code=-1; message="Test error"} }
        $result = Update-PHP-Version -version "8.x"
        $result.code | Should -Be -1
    }
}

# Test Cases for Auto-Select-PHP-Version
Describe "Auto-Select-PHP-Version" {
    BeforeEach {
        $global:TestScenario = $null
        Mock Detect-PHP-VersionFromProject {
            return "8.1"
        }
    }

    It "Should detect version from .php-version file" {
        $global:TestScenario = ".php-version"
        $result = Auto-Select-PHP-Version
        $result.code | Should -Be 0
        $result.version | Should -Be "8.1"
    }

    It "Should detect version from composer.json" {
        $global:TestScenario = "composer"
        $result = Auto-Select-PHP-Version
        $result.code | Should -Be 0
        $result.version | Should -Be "8.1"
    }

    It "Should return error when no version can be detected" {
        Mock Detect-PHP-VersionFromProject { return $null }
        $result = Auto-Select-PHP-Version
        $result.code | Should -Be -1
        $result.message | Should -Match "Could not detect PHP version"
    }

    It "Should return error when detected version is not installed" {
        $global:TestScenario = ".php-version"
        Mock Get-Matching-PHP-Versions { return @() }
        $result = Auto-Select-PHP-Version
        $result.code | Should -Be -1
        $result.message | Should -Match "PHP '8.1' is not installed"
    }
}
