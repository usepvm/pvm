
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    # Mock data and helper functions for testing
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\use-drive"
    $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$TEST_DRIVE\pvm\php"
    $PVMConfig.paths.logError = "$TEST_DRIVE\logs\error.log"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Force | Out-Null

    Mock Write-Host {}

    Mock Get-MatchingPHPVersions {
        param ($version)
        # Mock implementation
        if ($version -like '8.*') {
            return @(
                @{version='8.1'; path='C:\php\8.1'},
                @{version='8.2'; path='C:\php\8.2'}
            )
        }
        return @()
    }

    Mock Get-UserSelectedPHPVersion {
        param ($installedVersions)
        # If we're in the Auto-Select test and a specific version was detected
        if ($script:TestScenario -eq 'composer' -or $script:TestScenario -eq '.php-version' -and $installedVersions) {
            # Find the version that matches what we detected (8.2)
            $selected = $installedVersions | Where-Object { $_.version -eq '8.2' }
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

    Mock New-SymbolicLink {
        param ($link, $target)
        # Mock implementation
        return @{ code = 0 }
    }

    Mock Add-LogEntry {
        param ($logPath, $message, $data)
        # Mock implementation
        return $true
    }
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Find-PHPVersionFromProject" {
    It "Should detect PHP version from .php-version" {
        Mock Test-Path { return $true }
        Mock Get-Content { return '7.4' }
        $result = Find-PHPVersionFromProject
        $result | Should -Be '7.4'
    }

    It "Should not detect PHP version if does not exist in .php-version" {
        Mock Test-FileExists -ParameterFilter { $path -eq '.php-version'} -MockWith { return $true }
        Mock Test-FileExists -ParameterFilter { $path -eq 'composer.json'} -MockWith { return $false }
        Mock Get-Content { return '' }
        Mock Show-Error { }

        $result = Find-PHPVersionFromProject

        $result | Should -BeNullOrEmpty
    }

    It "Should detect PHP version from composer.json" {
        Mock Test-Path {
            param ($path)
            if ($path -eq 'composer.json') { return $true }
            return $false
        }
        Mock Get-Content { return '{"require": {"php": "^8.4"}}' }
        $result = Find-PHPVersionFromProject
        $result | Should -Be '8.4'
    }

    It "Handles parser exceptions gracefully" {
        Mock Test-Path {
            param ($path)
            if ($path -eq 'composer.json') { return $true }
            return $false
        }
        Mock Get-Content { throw 'Simulated parse error' }
        { Find-PHPVersionFromProject } | Should -Not -Throw
    }
}

Describe "Update-PHPVersion" {
    BeforeEach {
        $script:TestScenario = $null
    }

    It "Should successfully update to an exact version match" {
        $result = Update-PHPVersion -version '8.1'
        $result.code | Should -Be 0
        $result.message | Should -BeExactly 'Now using PHP 8.1'
    }

    It "Should handle version not found when exact path doesn't exist" {
        $result = Update-PHPVersion -version '7.4'
        $result.code | Should -Be -1
        $result.message | Should -BeExactly 'PHP version 7.4 was not found!'
    }

    It "Should handle when no matching versions are found" {
        $result = Update-PHPVersion -version '5.6'
        $result.code | Should -Be -1
        $result.message | Should -BeExactly 'PHP version 5.6 was not found!'
    }

    It "Should return when switching to same current version" {
        Mock Get-UserSelectedPHPVersion { return @{
            code=0; version='8.2.0'; arch = 'x64';
            buildType = 'TS'; path= "$TEST_DRIVE\php\8.2.0"
        }}
        Mock Get-CurrentPHPVersion { return @{
            version = '8.2.0';
            path = "$TEST_DRIVE\php\8.2.0"
            arch = 'x64'
            buildType = 'TS'
        }}
        $result = Update-PHPVersion -version '8.2.0'
        $result.code | Should -Be 0
        $result.message | Should -BeExactly 'Already using PHP 8.2.0'
    }

    It "Should handle when New-SymbolicLink fails" {
        Mock New-SymbolicLink { return @{ code = -1; message = 'Failed to create link'; color = 'DarkYellow' } }
        $result = Update-PHPVersion -version '8.1'
        $result.code | Should -Be -1
        $result.message | Should -BeExactly 'Failed to create link'
        $result.color | Should -Be 'DarkYellow'
    }

    It "Should handle exceptions gracefully" {
        # Force an exception by mocking Get-MatchingPHPVersions to throw
        Mock Get-MatchingPHPVersions { throw 'Test exception' }
        $result = Update-PHPVersion -version '8.1'
        $result.code | Should -Be -1
        $result.message | Should -Match 'No matching PHP versions found'
    }

    It "Should return error when pathVersionObject is null" {
        Mock Get-UserSelectedPHPVersion { return $null }
        $result = Update-PHPVersion -version '8.x'
        $result.code | Should -Be -1
        $result.message | Should -Match 'was not found'
    }

    It "Should return error when pathVersionObject has non-zero code" {
        Mock Get-UserSelectedPHPVersion { return @{code=-1; message='Test error'} }
        $result = Update-PHPVersion -version '8.x'
        $result.code | Should -Be -1
    }
}

Describe "Select-PHPVersionAutomatically" {
    BeforeEach {
        $script:TestScenario = $null
        Mock Find-PHPVersionFromProject {
            return '8.1'
        }
    }

    It "Should detect version from .php-version file" {
        $script:TestScenario = '.php-version'
        $result = Select-PHPVersionAutomatically
        $result.code | Should -Be 0
        $result.version | Should -Be '8.1'
    }

    It "Should detect version from composer.json" {
        $script:TestScenario = 'composer'
        $result = Select-PHPVersionAutomatically
        $result.code | Should -Be 0
        $result.version | Should -Be '8.1'
    }

    It "Should return error if no version can be detected and user enters invalid version format" {
        Mock Find-PHPVersionFromProject { return $null }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nCould not detect PHP version. Enter a version to use (e.g. 8.3 or 8.3.1)" } -MockWith { return 'abc' }

        $result = Select-PHPVersionAutomatically

        $result.code | Should -Be -1
        $result.message | Should -Match "Invalid version format: 'abc'. Expected e.g. 8, 8.3 or 8.3.1"
    }

    It "Should return valid version entered by user if no version can be detected" {
        Mock Find-PHPVersionFromProject { return $null }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nCould not detect PHP version. Enter a version to use (e.g. 8.3 or 8.3.1)" } -MockWith { return '8.5' }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSave as project default in .php-version? (y/n)" } -MockWith { return 'n' }
        Mock Set-Content-Wrapper { }
        Mock Get-MatchingPHPVersions {
            return @(
                @{version='8.5.1'; path='C:\php\8.5.1'},
                @{version='8.5.2'; path='C:\php\8.5.2'}
            )
        }

        $result = Select-PHPVersionAutomatically

        $result.code | Should -Be 0
        $result.version | Should -Be '8.5'
        Should -Invoke Set-Content-Wrapper -Exactly 0
    }

    It "Should return valid version entered by user and save to .php-version if no version can be detected" {
        Mock Find-PHPVersionFromProject { return $null }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nCould not detect PHP version. Enter a version to use (e.g. 8.3 or 8.3.1)" } -MockWith { return '8.5' }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSave as project default in .php-version? (y/n)" } -MockWith { return 'y' }
        Mock Set-Content-Wrapper { }
        Mock Get-MatchingPHPVersions {
            return @(
                @{version='8.5.1'; path='C:\php\8.5.1'},
                @{version='8.5.2'; path='C:\php\8.5.2'}
            )
        }

        $result = Select-PHPVersionAutomatically

        $result.code | Should -Be 0
        $result.version | Should -Be '8.5'
        Should -Invoke Set-Content-Wrapper -Exactly 1
    }

    It "Should return error when detected version is not installed" {
        $script:TestScenario = '.php-version'
        Mock Get-MatchingPHPVersions { return @() }
        $result = Select-PHPVersionAutomatically
        $result.code | Should -Be -1
        $result.message | Should -Match "PHP '8.1' is not installed"
    }
}
