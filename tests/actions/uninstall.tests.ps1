
BeforeAll {
    # Create a test directory for PHP installations
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\uninstall-drive"
    $script:CACHE_PATH = $PVMConfig.paths.cache = "$TEST_DRIVE\cache"
    $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$TEST_DRIVE\php\current"
    $PVMConfig.paths.logError = "$TEST_DRIVE\Logs\error.log"
    $script:testPhpPath = "$TEST_DRIVE\PHP"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -Path "$testPhpPath\7.4" -ItemType Directory -Force
    New-Item -Path "$testPhpPath\8.0" -ItemType Directory -Force

    Mock Add-LogEntry -MockWith {
        param ($logPath, $message, $data)
        return 0
    }

    New-Item -ItemType Directory -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Force | Out-Null
    Mock Write-Host { }
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Uninstall-PHP" {
    Context "When PHP version is found directly" {
        BeforeEach {
            Mock Get-MatchingPHPVersions -MockWith { }
            Mock Get-UserSelectedPHPVersion -MockWith { }
            Mock Remove-Item -MockWith { }
            Mock Add-LogEntry -MockWith { 0 }
            Mock Get-CurrentPHPVersion { @{ version = $null } }
        }

        It "Should successfully uninstall when version is found directly (skipConfirmation)" {
            Mock Get-UserSelectedPHPVersion -MockWith {
                return @{ code = 0; version = '7.4'; arch = 'x86'; buildType = 'nts'; path = "$testPhpPath\7.4" }
            }
            $result = Uninstall-PHP -version '7.4' -skipConfirmation $true

            $result.code | Should -Be 0
            $result.message | Should -BeLike '*PHP version 7.4 has been uninstalled successfully*'
            $result.color | Should -Be 'DarkGreen'

            Should -Invoke Remove-Item -Exactly 1 -ParameterFilter {
                $Path -eq "$testPhpPath\7.4" -and $Recurse -eq $true -and $Force -eq $true
            }
        }

        It "Should ask general confirmation when skipConfirmation is false and cancel on 'n'" {
            Mock Get-UserSelectedPHPVersion -MockWith {
                return @{ code = 0; version = '7.4'; arch = 'x86'; buildType = 'nts'; path = "$testPhpPath\7.4" }
            }
            Mock Read-Host { 'n' }

            $result = Uninstall-PHP -version '7.4' -skipConfirmation $false

            $result.code | Should -Be -1
            $result.message | Should -Be 'Uninstallation cancelled'

            Should -Invoke Read-Host -Exactly 1 -ParameterFilter {
                $Prompt -like "*Are you sure you want to delete PHP version*"
            }
            Should -Invoke Remove-Item -Exactly 0
        }

        It "Should proceed after general confirmation 'y' when not current version" {
            Mock Get-UserSelectedPHPVersion -MockWith {
                return @{ code = 0; version = '7.4'; arch = 'x86'; buildType = 'nts'; path = "$testPhpPath\7.4" }
            }
            Mock Read-Host { 'y' }

            $result = Uninstall-PHP -version '7.4' -skipConfirmation $false

            $result.code | Should -Be 0
            $result.message | Should -BeLike '*PHP version 7.4 has been uninstalled successfully*'

            # Only 1 Read-Host call (general confirm), no current-version prompt
            Should -Invoke Read-Host -Exactly 1
            Should -Invoke Remove-Item -Exactly 1
        }

        It "Should prompt current-version warning after general confirm when uninstalling active version" {
            Mock Get-UserSelectedPHPVersion -MockWith {
                return @{ code = 0; version = '7.4'; arch = 'x64'; buildType = 'nts'; path = "$testPhpPath\7.4" }
            }
            Mock Get-CurrentPHPVersion { @{ version = '7.4'; arch = 'x64'; buildType = 'nts' } }
            Mock Test-TwoPHPVersionsEqual { $true }
            # First call: general confirm 'y', second call: current-version prompt returns nothing (cancel)
            $script:readHostCalls = 0
            Mock Read-Host {
                $script:readHostCalls++
                if ($script:readHostCalls -eq 1) { return 'y' }
                return ''
            }

            $result = Uninstall-PHP -version '7.4' -skipConfirmation $false

            $result.code | Should -Be -1
            Should -Invoke Read-Host -Exactly 2
            Should -Invoke Remove-Item -Exactly 0
        }

        It "Should prompt current-version warning and cancel on 'n'" {
            Mock Get-UserSelectedPHPVersion -MockWith {
                return @{ code = 0; version = '7.4'; arch = 'x64'; buildType = 'nts'; path = "$testPhpPath\7.4" }
            }
            Mock Get-CurrentPHPVersion { @{ version = '7.4'; arch = 'x64'; buildType = 'nts' } }
            Mock Test-TwoPHPVersionsEqual { $true }
            $script:readHostCalls = 0
            Mock Read-Host {
                $script:readHostCalls++
                if ($script:readHostCalls -eq 1) { return 'y' }
                return 'n'
            }

            $result = Uninstall-PHP -version '7.4' -skipConfirmation $false

            $result.code | Should -Be -1
            $result.message | Should -Be 'Uninstallation cancelled'
            Should -Invoke Read-Host -Exactly 2
            Should -Invoke Remove-Item -Exactly 0
        }

        It "Should uninstall current version after both confirmations answered 'y'" {
            Mock Get-UserSelectedPHPVersion -MockWith {
                return @{ code = 0; version = '8.0'; arch = 'x64'; buildType = 'nts'; path = "$testPhpPath\8.0" }
            }
            Mock Get-CurrentPHPVersion { @{ version = '8.0'; arch = 'x64'; buildType = 'nts' } }
            Mock Test-TwoPHPVersionsEqual { $true }
            Mock Read-Host { 'y' }

            $result = Uninstall-PHP -version '8.0' -skipConfirmation $false

            $result.code | Should -Be 0
            Should -Invoke Read-Host -Exactly 2
            Should -Invoke Remove-Item -Exactly 1
        }

        It "Should skip all prompts and uninstall current version when skipConfirmation is true" {
            Mock Get-UserSelectedPHPVersion -MockWith {
                return @{ code = 0; version = '8.0'; arch = 'x64'; buildType = 'nts'; path = "$testPhpPath\8.0" }
            }
            Mock Get-CurrentPHPVersion { @{ version = '8.0'; arch = 'x64'; buildType = 'nts' } }
            Mock Read-Host { }

            $result = Uninstall-PHP -version '8.0' -skipConfirmation $true

            $result.code | Should -Be 0
            Should -Invoke Read-Host -Exactly 0
            Should -Invoke Remove-Item -Exactly 1
        }
    }

    Context "When PHP version is not found directly but matches exist" {
        BeforeEach {
            Mock Get-MatchingPHPVersions -ParameterFilter { $version -eq '8.*' } -MockWith {
                @('8.0', '8.1')
            }
            Mock Get-UserSelectedPHPVersion -MockWith {
                @{ code = 0; version = '8.0'; path = "$testPhpPath\8.0" }
            }
            Mock Remove-Item -MockWith { }
            Mock Add-LogEntry -MockWith { 0 }
            Mock Get-CurrentPHPVersion { @{ version = $null } }
        }

        It "Should successfully uninstall after user selection (skipConfirmation)" {
            $result = Uninstall-PHP -version '8.*' -skipConfirmation $true

            $result.code | Should -Be 0
            $result.message | Should -BeLike '*PHP version 8.0 has been uninstalled successfully*'
            $result.color | Should -Be 'DarkGreen'

            Should -Invoke Get-MatchingPHPVersions -Exactly 1
            Should -Invoke Get-UserSelectedPHPVersion -Exactly 1
            Should -Invoke Remove-Item -Exactly 1 -ParameterFilter {
                $Path -eq "$testPhpPath\8.0"
            }
        }
    }

    Context "When PHP version is not found at all" {
        BeforeEach {
            Mock Get-MatchingPHPVersions -ParameterFilter { $version -eq '5.6' } -MockWith {
                @()
            }
            Mock Get-UserSelectedPHPVersion -MockWith { }
            Mock Remove-Item -MockWith { }
            Mock Add-LogEntry -MockWith { 0 }
        }

        It "Should return version not found message" {
            $result = Uninstall-PHP -version '5.6' -skipConfirmation $true

            $result.code | Should -Be -1
            $result.message | Should -BeExactly 'PHP version 5.6 was not found!'
            $result.color | Should -Be 'DarkYellow'

            Should -Invoke Get-MatchingPHPVersions -Exactly 1
            Should -Invoke Remove-Item -Exactly 0
        }
    }

    Context "When user selection returns an error" {
        BeforeEach {
            Mock Get-MatchingPHPVersions -ParameterFilter { $version -eq '8.*' } -MockWith {
                @('8.0', '8.1')
            }
            Mock Get-UserSelectedPHPVersion -MockWith {
                @{ code = -1; message = 'User cancelled the selection'; color = 'DarkYellow' }
            }
            Mock Remove-Item -MockWith { }
            Mock Add-LogEntry -MockWith { 0 }
        }

        It "Should return the user selection error" {
            $result = Uninstall-PHP -version '8.*' -skipConfirmation $true

            $result.code | Should -Be -1
            $result.message | Should -Be 'User cancelled the selection'
            $result.color | Should -Be 'DarkYellow'

            Should -Invoke Get-MatchingPHPVersions -Exactly 1
            Should -Invoke Get-UserSelectedPHPVersion -Exactly 1
            Should -Invoke Remove-Item -Exactly 0
        }
    }

    Context "When user selection returns a version but no path" {
        BeforeEach {
            Mock Get-MatchingPHPVersions -MockWith { return $null }
            Mock Get-UserSelectedPHPVersion -MockWith { return $null }
            Mock Remove-Item -MockWith { }
            Mock Add-LogEntry -MockWith { 0 }
        }

        It "Should return version not found message" {
            $result = Uninstall-PHP -version '8.2' -skipConfirmation $true

            $result.code | Should -Be -1
            $result.message | Should -BeExactly 'PHP version 8.2 was not found!'
            $result.color | Should -Be 'DarkYellow'

            Should -Invoke Get-MatchingPHPVersions -Exactly 1
            Should -Invoke Get-UserSelectedPHPVersion -Exactly 1
            Should -Invoke Remove-Item -Exactly 0
        }
    }

    Context "When uninstallation fails with an exception" {
        BeforeEach {
            Mock Get-CurrentPHPVersion { @{ version = $null } }
            Mock Get-MatchingPHPVersions -MockWith { }
            Mock Get-UserSelectedPHPVersion -MockWith { }
            Mock Remove-Item -MockWith { throw 'Access denied' }
        }

        It "Should catch the exception and return error message" {
            Mock Get-UserSelectedPHPVersion -MockWith {
                return @{ code = 0; version = '7.4'; arch = 'x64'; buildType = 'nts'; path = "$testPhpPath\7.4" }
            }
            Mock Update-InstalledPHPVersionsCache { throw 'Error' }

            $result = Uninstall-PHP -version '7.4' -skipConfirmation $true

            $result.code | Should -Be -1
            $result.message | Should -Be "Failed to uninstall PHP version '7.4'"
            $result.color | Should -Be 'DarkYellow'

            Should -Invoke Remove-Item -Exactly 1
            Should -Invoke Add-LogEntry -Exactly 1
        }
    }

    AfterAll {
        Remove-Item -Path $testPhpPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}