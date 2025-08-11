# Load required modules and functions
. "$PSScriptRoot\..\src\actions\use.ps1"

BeforeAll {
    
    # Mock data and helper functions for testing
    $PHP_CURRENT_VERSION_PATH = "C:\pvm\php"
    $LOG_ERROR_PATH = "C:\logs\error.log"

    Mock Write-Host {}
    function Get-PHP-Path-By-Version {
        param($version)
        # Mock implementation
        if ($version -eq "8.1") { return "C:\php\8.1" }
        if ($version -eq "8.2") { return "C:\php\8.2" }
        return $null
    }

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

    function Get-UserSelected-PHP-Version {
        param($installedVersions)
        # If we're in the Auto-Select test and a specific version was detected
        if ($global:TestScenario -eq "composer" -and $installedVersions) {
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
        return 0
    }

    function Log-Data {
        param($logPath, $message, $data)
        # Mock implementation
        return $true
    }

    function Detect-PHP-VersionFromProject {
        # Mock implementation
        if ($global:TestScenario -eq "phpversion") { return "8.1" }
        if ($global:TestScenario -eq "composer") { return "8.2" }
        return $null
    }
}

# Test Cases for Update-PHP-Version
Describe "Update-PHP-Version" {
    BeforeEach {
        $global:TestScenario = $null
    }

    It "Should successfully update to an exact version match" {
        $result = Update-PHP-Version -variableName "PHP_VERSION" -variableValue "8.1"
        Write-Host ($result | ConvertTo-Json)
        $result.code | Should -Be 0
        $result.message | Should -BeExactly "Now using PHP 8.1"
    }

    It "Should handle version not found when exact path doesn't exist" {
        $result = Update-PHP-Version -variableName "PHP_VERSION" -variableValue "7.4"
        $result.code | Should -Be -1
        $result.message | Should -BeExactly "PHP version 7.4 was not found!"
    }

    It "Should handle when Get-PHP-Path-By-Version returns null but matching versions exist" {
        $result = Update-PHP-Version -variableName "PHP_VERSION" -variableValue "8.x"
        $result.code | Should -Be 0
        $result.message | Should -BeExactly "Now using PHP 8.1"  # Assuming it selects the first match
    }

    It "Should handle when no matching versions are found" {
        $result = Update-PHP-Version -variableName "PHP_VERSION" -variableValue "5.6"
        $result.code | Should -Be -1
        $result.message | Should -BeExactly "PHP version 5.6 was not found!"
    }

    It "Should handle exceptions gracefully" {
        # Force an exception by mocking Get-PHP-Path-By-Version to throw
        Mock Get-PHP-Path-By-Version { throw "Test exception" }
        $result = Update-PHP-Version -variableName "PHP_VERSION" -variableValue "8.1"
        $result.code | Should -Be -1
        $result.message | Should -Match "No matching PHP versions found"
    }

    It "Should return error when pathVersionObject is null" {
        Mock Get-UserSelected-PHP-Version { return $null }
        $result = Update-PHP-Version -variableName "PHP_VERSION" -variableValue "8.x"
        $result.code | Should -Be -1
        $result.message | Should -Match "was not found"
    }

    It "Should return error when pathVersionObject has non-zero code" {
        Mock Get-UserSelected-PHP-Version { return @{code=-1; message="Test error"} }
        $result = Update-PHP-Version -variableName "PHP_VERSION" -variableValue "8.x"
        $result.code | Should -Be -1
    }

    It "Should return error when path is missing in pathVersionObject" {
        Mock Get-UserSelected-PHP-Version { return @{code=0; version="8.1"; path=$null} }
        $result = Update-PHP-Version -variableName "PHP_VERSION" -variableValue "8.x"
        $result.code | Should -Be -1
        $result.message | Should -Match "was not found"
    }
}

# Test Cases for Auto-Select-PHP-Version
Describe "Auto-Select-PHP-Version" {
    BeforeEach {
        $global:TestScenario = $null
    }

    It "Should detect version from .php-version file" {
        $global:TestScenario = "phpversion"
        $result = Auto-Select-PHP-Version
        $result.code | Should -Be 0
        $result.version | Should -Be "8.1"
    }

    It "Should detect version from composer.json" {
        $global:TestScenario = "composer"
        $result = Auto-Select-PHP-Version
        $result.code | Should -Be 0
        $result.version | Should -Be "8.2"
    }

    It "Should return error when no version can be detected" {
        $result = Auto-Select-PHP-Version
        $result.code | Should -Be -1
        $result.message | Should -Match "Could not detect PHP version"
    }

    It "Should return error when detected version is not installed" {
        $global:TestScenario = "phpversion"
        Mock Get-Matching-PHP-Versions { return @() }
        $result = Auto-Select-PHP-Version
        $result.code | Should -Be -1
        $result.message | Should -Match "PHP '8.1' is not installed"
    }
}
