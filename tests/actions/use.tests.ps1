
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $null = New-Directory -path $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH

    Mock Write-Color { }
    Mock Show-Info { }
    Mock Show-Success { }
    Mock Show-Error { }
    Mock Show-Message { }

    Mock Get-MatchingPHPVersions {
        param ($version)

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

        if ($script:TestScenario -eq 'composer' -or $script:TestScenario -eq '.php-version' -and $installedVersions) {
            $selected = $installedVersions | Where-Object -FilterScript { $_.version -eq '8.2' }
            if ($selected) {
                return @{code=0; version=$selected.version; path=$selected.path}
            }
        }

        if ($installedVersions -and $installedVersions.Count -gt 0) {
            return @{code=0; version=$installedVersions[0].version; path=$installedVersions[0].path}
        }
        return $null
    }

    Mock New-SymbolicLink { return @{ code = 0 } }

    Mock Add-LogEntry { return 0 }
}

Describe "Update-PHPVersion" {
    BeforeEach {
        $script:TestScenario = $null
    }

    It "Should successfully update to an exact version match" {
        $result = Update-PHPVersion -version '8.1'
        $result | Should -Be 0
        Should -Invoke Show-Success -Exactly 1 -ParameterFilter { $message -like '*Now using PHP 8.1*' }
    }

    It "Should handle version not found when exact path doesn't exist" {
        $result = Update-PHPVersion -version '7.4'
        $result | Should -Be -1
        Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -like '*PHP version 7.4 was not found!*' }
    }

    It "Should handle when no matching versions are found" {
        $result = Update-PHPVersion -version '5.6'
        $result | Should -Be -1
        Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -like '*PHP version 5.6 was not found!*' }
    }

    It "Should return when switching to same current version" {
        Mock Get-UserSelectedPHPVersion { return @{
            code=0; version='8.2.0'; arch = 'x64';
            buildType = 'TS'; path= "$script:TEST_DRIVE\php\8.2.0"
        }}
        Mock Get-CurrentPHPVersion { return @{
            version = '8.2.0';
            path = "$script:TEST_DRIVE\php\8.2.0"
            arch = 'x64'
            buildType = 'TS'
        }}
        $result = Update-PHPVersion -version '8.2.0'
        $result | Should -Be 0
        Should -Invoke Show-Info -Exactly 1 -ParameterFilter { $message -like '*Already using PHP 8.2.0*' }
    }

    It "Should handle when New-SymbolicLink fails" {
        Mock New-SymbolicLink { return @{ code = -1; message = 'Failed to create link'; color = 'DarkYellow' } }
        $result = Update-PHPVersion -version '8.1'
        $result | Should -Be -1
        Should -Invoke Write-Color -Exactly 1 -ParameterFilter { $message -eq 'Failed to create link' }
    }

    It "Should handle exceptions gracefully" {
        Mock Get-MatchingPHPVersions { throw 'Test exception' }
        $result = Update-PHPVersion -version '8.1'
        $result | Should -Be -1
        Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'No matching PHP versions found' }
    }

    It "Should return error when pathVersionObject is null" {
        Mock Get-UserSelectedPHPVersion { return $null }
        $result = Update-PHPVersion -version '8.x'
        $result | Should -Be -1
        Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'was not found' }
    }

    It "Should return error when pathVersionObject has non-zero code" {
        Mock Get-UserSelectedPHPVersion { return @{code=-1; message='Test error'} }
        $result = Update-PHPVersion -version '8.x'
        $result | Should -Be -1
    }
}
