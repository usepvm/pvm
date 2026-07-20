
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    Import-Module PowerShellGet -ErrorAction SilentlyContinue
}

AfterAll {
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Invoke-Setup Tests" {
    BeforeEach {
        Mock Test-PVM-Setup { $true }
        Mock Initialize-PVM { @{ code = 0; message = 'Setup completed' } }
        Mock Optimize-SystemPath { 0 }
        Mock Initialize-Environment-Directories-And-Files { 0 }
        Mock New-Env-File { 0 }
        Mock Wait-ForEnvEdit { }
        Mock Show-Msg-By-ExitCode { }
        Mock Write-Host { }
    }

    It "Should return 0 when PVM is already setup" {
        Mock Test-PVM-Setup { $true }

        $result = Invoke-Setup
        $result | Should -Be 0

        Should -Invoke Test-PVM-Setup -Times 1
        Should -Invoke Initialize-PVM -Times 0
        Should -Invoke Initialize-Environment-Directories-And-Files -Times 0
        Should -Invoke New-Env-File -Times 0
        Should -Invoke Optimize-SystemPath -Times 1
        Should -Invoke Show-Msg-By-ExitCode -Times 1
    }

    It "Should setup PVM when not already setup" {
        Mock Test-PVM-Setup { $false }
        Mock Initialize-PVM { @{ code = 0; message = 'Setup completed successfully' } }

        $result = Invoke-Setup
        $result | Should -Be 0

        Should -Invoke Test-PVM-Setup -Times 1
        Should -Invoke Initialize-PVM -Times 1
        Should -Invoke Initialize-Environment-Directories-And-Files -Times 1
        Should -Invoke New-Env-File -Times 1
        Should -Invoke Optimize-SystemPath -Times 1
        Should -Invoke Show-Msg-By-ExitCode -Times 1
    }

    It "Should display warning when system path optimization fails" {
        Mock Optimize-SystemPath { -1 }

        $result = Invoke-Setup
        $result | Should -Be 0

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Failed to optimize system path*' -and $ForegroundColor -eq 'DarkYellow' }
    }

    It "Should pause for env edit after creating env file" {
        Mock Test-PVM-Setup { $false }
        Mock New-Env-File { return 0 }
        Mock Wait-ForEnvEdit { }
        Mock Initialize-PVM { @{ code = 0; message = 'Setup completed successfully' } }

        $result = Invoke-Setup
        $result | Should -Be 0

        Should -Invoke New-Env-File -Times 1
        Should -Invoke Wait-ForEnvEdit -Times 1
        Should -Invoke Initialize-PVM -Times 1
    }
}

Describe "Invoke-Repair Tests" {
    BeforeAll {
        Mock Wait-ForEnvEdit { }
    }

    It "Should return 0 when all actions succeed" {
        Mock New-Env-File { 0 }
        Mock Initialize-Environment-Directories-And-Files { 0 }

        $result = Invoke-Repair
        $result | Should -Be 0
        Should -Invoke Initialize-Environment-Directories-And-Files -Times 1
    }

    It "Should return -1 when Initialize-Environment-Directories-And-Files fails" {
        Mock Initialize-Environment-Directories-And-Files { -1 }
        Mock New-Env-File { 0 }

        $result = Invoke-Repair
        $result | Should -Be -1
        Should -Invoke Initialize-Environment-Directories-And-Files -Times 1
        Should -Invoke New-Env-File -Times 1
    }

    It "Should return -1 when New-Env-File fails" {
        Mock Initialize-Environment-Directories-And-Files { 0 }
        Mock New-Env-File { -1 }

        $result = Invoke-Repair
        $result | Should -Be -1
        Should -Invoke Initialize-Environment-Directories-And-Files -Times 1
        Should -Invoke New-Env-File -Times 1
    }

    It "Should pause for env edit after creating env file" {
        Mock Initialize-Environment-Directories-And-Files { 0 }
        Mock New-Env-File { 0 }
        Mock Wait-ForEnvEdit { }

        $result = Invoke-Repair
        $result | Should -Be 0
        Should -Invoke Initialize-Environment-Directories-And-Files -Times 1
        Should -Invoke New-Env-File -Times 1
        Should -Invoke Wait-ForEnvEdit -Times 1
    }
}

Describe "Invoke-Current Tests" {
    It "Should display current PHP version and extensions when version is set" {
        Mock Get-Current-PHP-Version { @{
                version   = '8.2.0'
                arch      = 'x64'
                buildType = 'TS'
                path      = 'C:\PHP\8.2.0'
                status    = @(
                    @{ Name = 'xdebug'; Version = '3.2.0'; Copyright = 'Zend'; Enabled = $true }
                    @{ Name = 'opcache'; Version = '8.2.0'; Copyright = 'Zend'; Enabled = $false }
                )
            } }
        $result = Invoke-Current

        $result | Should -Be 0
        Should -Invoke Get-Current-PHP-Version -Times 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Running version: PHP 8.2.0*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*xdebug v3.2.0*' -and $ForegroundColor -eq 'DarkGreen' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*opcache v8.2.0*' -and $ForegroundColor -eq 'DarkYellow' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Path: C:\PHP\8.2.0*' }
    }

    It "Should display current PHP version and extensions when version is not set" {
        Mock Get-Current-PHP-Version { @{
                version   = '8.2.0'
                arch      = 'x64'
                buildType = 'TS'
                path      = 'C:\PHP\8.2.0'
                status    = @(
                    @{ Name = 'xdebug'; Version = $null; Enabled = $true }
                    @{ Name = 'opcache'; Version = $null; Enabled = $false }
                )
            } }

        $result = Invoke-Current

        $result | Should -Be 0
        Should -Invoke Get-Current-PHP-Version -Times 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Running version: PHP 8.2.0*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*xdebug*' -and $ForegroundColor -eq 'DarkGreen' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*opcache*' -and $ForegroundColor -eq 'DarkYellow' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Path: C:\PHP\8.2.0*' }
    }

    It "Should return -1 when no PHP version is set" {
        Mock Get-Current-PHP-Version { @{ version = $null; status = $null; path = $null } }

        $result = Invoke-Current
        $result | Should -Be -1

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No PHP version is currently set*' }
    }

    It "Should handle missing status information" {
        Mock Get-Current-PHP-Version { @{ version = '8.2.0'; status = $null; path = 'C:\PHP\8.2.0' } }

        $result = Invoke-Current
        $result | Should -Be -1

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No status information available*' -and $ForegroundColor -eq 'Yellow' }
    }
}

Describe "Invoke-List Tests" {
    BeforeEach {
        Mock Get-Available-PHP-Versions { return 0 }
        Mock Show-Installed-PHP-Versions { return 0 }
    }

    It "Should call Get-Available-PHP-Versions when 'available' argument is provided" {
        $arguments = @("available")

        $result = Invoke-List -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Get-Available-PHP-Versions -Times 1
        Should -Invoke Show-Installed-PHP-Versions -Times 0
    }

    It "Should call Show-Installed-PHP-Versions when no 'available' argument" {
        $arguments = @()

        $result = Invoke-List -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Show-Installed-PHP-Versions -Times 1
        Should -Invoke Get-Available-PHP-Versions -Times 0
    }
}

Describe "Invoke-Install Tests" {
    BeforeEach {
        Mock Install-PHP { 0 }
        Mock Write-Host { }
    }

    It "Should return -1 when no version is provided" {
        $arguments = @()

        $result = Invoke-Install -arguments $arguments
        $result | Should -Be -1

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Please provide a PHP version to install*' }
    }

    It "Should install PHP with basic parameters" {
        $arguments = @('8.2.0')

        $result = Invoke-Install -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Install-PHP -Times 1 -ParameterFilter {
            $version -eq '8.2.0'
        }
    }

    It "Should install detected PHP version from the project" {
        $arguments = @('auto')

        Mock Get-Matching-PHP-Versions { return @() }
        Mock Find-PHP-VersionFromProject { return '8.1' }
        $result = Invoke-Install -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Install-PHP -Times 1 -ParameterFilter {
            $version -eq '8.1'
        }
    }

    It "Should install latest PHP version when 'latest' argument is provided" {
        $arguments = @('latest')
        Mock Get-Latest-PHP-Version { return @{version = '8.6.0' } }

        $result = Invoke-Install -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Install-PHP -Times 1 -ParameterFilter {
            $version -eq '8.6.0'
        }
    }

    It "Should return -1 when no latest PHP version was found" {
        $arguments = @('latest')
        Mock Get-Latest-PHP-Version { return $null }

        $result = Invoke-Install -arguments $arguments

        $result | Should -Be -1
    }

    It "Should return -1 when detected PHP version is already installed" {
        $arguments = @('auto')
        Mock Select-PHP-Version-Automatically { return @{ code = 0; version = '8.2' } }

        $result = Invoke-Install -arguments $arguments

        $result | Should -Be -1
    }
}

Describe "Invoke-Uninstall Tests" {
    BeforeEach {
        Mock Uninstall-PHP { @{ code = 0; message = 'Uninstalled successfully' } }
        Mock Show-Msg-By-ExitCode { }
        Mock Write-Host { }
    }

    It "Should return -1 when no version is provided" {
        $result = Invoke-Uninstall -arguments @()
        $result | Should -Be -1

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Please provide a PHP version to uninstall*' }
    }

    It "Should uninstall PHP version without skipConfirmation by default" {
        $result = Invoke-Uninstall -arguments @('8.2.0')
        $result | Should -Be 0

        Should -Invoke Uninstall-PHP -Exactly 1 -ParameterFilter {
            $version -eq '8.2.0' -and $skipConfirmation -eq $false
        }
        Should -Invoke Show-Msg-By-ExitCode -Exactly 1
    }

    It "Should pass skipConfirmation true when -y flag is provided" {
        $result = Invoke-Uninstall -arguments @('8.2.0', '-y')
        $result | Should -Be 0

        Should -Invoke Uninstall-PHP -Exactly 1 -ParameterFilter {
            $version -eq '8.2.0' -and $skipConfirmation -eq $true
        }
    }

    It "Should pass skipConfirmation true when --yes flag is provided" {
        $result = Invoke-Uninstall -arguments @('8.2.0', '--yes')
        $result | Should -Be 0

        Should -Invoke Uninstall-PHP -Exactly 1 -ParameterFilter {
            $version -eq '8.2.0' -and $skipConfirmation -eq $true
        }
    }

    It "Should pass skipConfirmation false when no flag is provided" {
        $result = Invoke-Uninstall -arguments @('8.2.0')
        $result | Should -Be 0

        Should -Invoke Uninstall-PHP -Exactly 1 -ParameterFilter {
            $version -eq '8.2.0' -and $skipConfirmation -eq $false
        }
    }

    It "Should ignore unrecognized flags and not set skipConfirmation" {
        $result = Invoke-Uninstall -arguments @('8.2.0', '--force')
        $result | Should -Be 0

        Should -Invoke Uninstall-PHP -Exactly 1 -ParameterFilter {
            $version -eq '8.2.0' -and $skipConfirmation -eq $false
        }
    }
}

Describe "Invoke-Use Tests" {
    BeforeEach {
        Mock Select-PHP-Version-Automatically { @{ code = 0; version = '8.2.0' } }
        Mock Update-PHP-Version { @{ code = 0; message = 'Version updated' } }
        Mock Show-Msg-By-ExitCode { }
        Mock Write-Host { }
    }

    It "Should return -1 when no version is provided" {
        $arguments = @()

        $result = Invoke-Use -arguments $arguments
        $result | Should -Be -1

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Please provide a PHP version to use*' }
    }

    It "Should use specific PHP version" {
        $arguments = @('8.2.0')

        $result = Invoke-Use -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Update-PHP-Version -Times 1 -ParameterFilter {
            $version -eq '8.2.0'
        }
        Should -Invoke Show-Msg-By-ExitCode -Times 1
    }

    It "Should handle 'auto' version selection successfully" {
        $arguments = @('auto')

        $result = Invoke-Use -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Select-PHP-Version-Automatically -Times 1
        Should -Invoke Update-PHP-Version -Times 1 -ParameterFilter { $version -eq '8.2.0' }
    }

    It "Should return -1 when auto-selection fails" {
        Mock Select-PHP-Version-Automatically { @{ code = 1; message = 'Auto selection failed' } }
        $arguments = @('auto')

        $result = Invoke-Use -arguments $arguments
        $result | Should -Be -1

        Should -Invoke Select-PHP-Version-Automatically -Times 1
        Should -Invoke Show-Msg-By-ExitCode -Times 1
        Should -Invoke Update-PHP-Version -Times 0
    }
}

Describe "Invoke-Ini Tests" {
    BeforeEach {
        Mock Invoke-IniAction { 0 }
        Mock Write-Host { }
    }

    It "Should return -1 when no action is provided" {
        $arguments = @()

        $result = Invoke-Ini -arguments $arguments
        $result | Should -Be -1

        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Please specify an action for 'pvm ini'*" }
    }

    It "Should call Invoke-IniAction with correct parameters for single action" {
        $arguments = @('set')

        $result = Invoke-Ini -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Invoke-IniAction -Times 1 -ParameterFilter {
            $action -eq 'set' -and
            $params.Count -eq 0
        }
    }

    It "Should call Invoke-IniAction with remaining arguments" {
        $arguments = @('set', 'memory_limit', '256M')

        $result = Invoke-Ini -arguments $arguments
        $result | Should -Be 0

        Should -Invoke Invoke-IniAction -Times 1 -ParameterFilter {
            $action -eq 'set' -and
            $params.Count -eq 2 -and
            $params[0] -eq 'memory_limit' -and
            $params[1] -eq '256M'
        }
    }

    It "Should handle different actions correctly" {
        $testActions = @('get', 'enable', 'disable', 'restore')

        foreach ($testAction in $testActions) {
            $arguments = @($testAction, 'param1', 'param2')

            $result = Invoke-Ini -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Invoke-IniAction -ParameterFilter { $action -eq $testAction }
        }
    }
}

Describe "Invoke-Log Tests" {
    BeforeAll {
        # Default log page size value for tests
        $PVMConfig.env.DEFAULT_LOG_PAGE_SIZE = 5
        Mock Show-Log { 0 }
    }

    It "Calls Show-Log with provided --pageSize argument" {
        $arguments = @('--pageSize=5')
        Invoke-Log -arguments $arguments | Should -Be 0

        Should -Invoke Show-Log -Exactly 1 -ParameterFilter { $pageSize -eq '5' }
    }

    It "Calls Show-Log with default page size when no argument is given" {
        $arguments = @()
        Invoke-Log -arguments $arguments | Should -Be 0

        Should -Invoke Show-Log -Exactly 1 -ParameterFilter { $pageSize -eq 5 }
    }

    It "Passes return code from Show-Log back to caller" {
        Mock Show-Log { return 0 }
        (Invoke-Log -arguments @('--pageSize=2')) | Should -Be 0

        Mock Show-Log { return -1 }
        (Invoke-Log -arguments @('--pageSize=2')) | Should -Be -1
    }
}

Describe "Invoke-Version Tests" {
    It "Should show version and return 0" {
        Mock Show-PVM-Version { }
        $result = Invoke-Version

        $result | Should -Be 0
        Should -Invoke Show-PVM-Version -Times 1
    }
}

Describe "Invoke-Help Tests" {
    It "Should display help for setup command" {
        $result = Invoke-Help -arguments @('setup')
        $result | Should -Be 0
    }

    It "Should return -1 for non-existent usage" {
        $result = Invoke-Help -arguments @('nonexistent')
        $result | Should -Be -1
    }

    It "Should display general help when no command is provided" {
        $result = Invoke-Help -arguments @()
        $result | Should -Be 0
    }
}

Describe "Invoke-Test Tests" {
    BeforeAll {
        Mock Initialize-Tests { 0 }
    }

    It "Installs Pester module when not already installed" {
        Mock Get-Module -ParameterFilter { $ListAvailable -and $Name -eq 'Pester' } -MockWith { return $null }
        Mock Install-Module -ParameterFilter { $Name -eq 'Pester' } -MockWith { }

        $result = Invoke-Test -arguments @()
        $result | Should -Be 0
    }

    It "Should call Run-Tests with no arguments" {
        $result = Invoke-Test -arguments @()
        $result | Should -Be 0
    }

    It "Should call Run-Tests with provided arguments" {
        $result = Invoke-Test -arguments @(
            'TestFile.ps1', 'TestFile2.ps1',
            '--coverage=80', '--verbosity=detailed', '--tag=unit', '--sort=coverage', '--exclude=TestFile3.ps1'
        )
        $result | Should -Be 0
    }

    It "Should keep grouping disabled by default" {
        Mock Initialize-Tests { param($testsNames, $options, $exclude) return $options }

        $result = Invoke-Test -arguments @()

        $result.groupBy | Should -BeNullOrEmpty
    }

    It "Should pass coverage grouping option to Initialize-Tests" {
        Mock Initialize-Tests { param($testsNames, $options, $exclude) return $options }

        $result = Invoke-Test -arguments @('--group=coverage')

        $result.groupBy | Should -Be 'coverage'
    }

    It "Should group summary entries by folder when requested" {
        Mock Write-Host { }

        $testSummary = @(
            [pscustomobject]@{
                code = 0
                relativeFilePath = 'core/handlers.tests.ps1'
                Message = 'Passed'
                testResultData = [pscustomobject]@{
                    failedCount = 0
                    duration = 0.2
                    coverageRaw = 100
                }
            },
            [pscustomobject]@{
                code = 0
                relativeFilePath = 'actions/install.tests.ps1'
                Message = 'Passed'
                testResultData = [pscustomobject]@{
                    failedCount = 0
                    duration = 0.1
                    coverageRaw = 90
                }
            }
        )

        $result = Write-Tests-Summary -testSummary $testSummary -options @{ sortBy = $null; groupBy = 'folder'; target = 75 } -maxLineLength 40

        $result | Should -Be 0
        Should -Invoke Write-Host -ParameterFilter { $Object -eq "`n  [core]" }
        Should -Invoke Write-Host -ParameterFilter { $Object -eq "`n  [actions]" }
    }

    Context "Handle invalid coverage target values" {
        It "Should return -1 for over 100 coverage target" {
            $result = Invoke-Test -arguments @('TestFile.ps1', '--coverage=150')
            $result | Should -Be -1
        }

        It "Should return -1 for negative coverage value" {
            $result = Invoke-Test -arguments @('TestFile.ps1', '--coverage=-10')
            $result | Should -Be -1
        }
    }

    It "Should handle unknown flags gracefully" {
        $result = Invoke-Test -arguments @('-i', '--unknown')
        $result | Should -Be 0
    }

    Context "Pester version parsing" {
        It "Should parse --pester argument correctly" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude, $pesterVersion) return $pesterVersion }

            $result = Invoke-Test -arguments @('--pester=5.5')

            $result | Should -Be '5.5'
        }

        It "Should pass null when no --pester argument" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude, $pesterVersion) return $pesterVersion }

            $result = Invoke-Test -arguments @()

            $result | Should -Be $null
        }

        It "Should pass 'latest' when --pester=latest is specified" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude, $pesterVersion) return $pesterVersion }

            $result = Invoke-Test -arguments @('--pester=latest')

            $result | Should -Be 'latest'
        }

        It "Should pass pesterVersion to Initialize-Tests" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude, $pesterVersion) return $pesterVersion }

            $result = Invoke-Test -arguments @('--pester=5.6.0')

            Should -Invoke Initialize-Tests -ParameterFilter {
                $pesterVersion -eq '5.6.0'
            } -Times 1
        }

        It "Should pass null pesterVersion when no --pester argument" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude, $pesterVersion) return $pesterVersion }

            $result = Invoke-Test -arguments @()

            Should -Invoke Initialize-Tests -ParameterFilter {
                $pesterVersion -eq $null
            } -Times 1
        }
    }

    Context "Test argument parsing" {
        It "Should filter out --pester argument from test names" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $testsNames }

            $result = Invoke-Test -arguments @('TestFile.ps1', '--pester=5.5')

            $result | Should -Not -Contain '--pester=5.5'
        }

        It "Should parse --exclude argument correctly" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $exclude }

            $result = Invoke-Test -arguments @('--exclude=TestFile1.ps1,TestFile2.ps1')

            $result | Should -Be @('TestFile1.ps1', 'TestFile2.ps1')
        }

        It "Should parse --sort argument correctly" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $options }

            $result = Invoke-Test -arguments @('--sort=coverage')

            $result.sortBy | Should -Be 'coverage'
        }

        It "Should parse --group argument correctly" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $options }

            $result = Invoke-Test -arguments @('--group=folder')

            $result.groupBy | Should -Be 'folder'
        }

        It "Should parse --tag argument correctly" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $options }

            $result = Invoke-Test -arguments @('--tag=unit')

            $result.tag | Should -Be 'unit'
        }

        It "Should parse --coverage argument with custom target" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $options }

            $result = Invoke-Test -arguments @('--coverage=85')

            $result.coverage | Should -Be $true
            $result.target | Should -Be 85
        }

        It "Should parse --coverage argument without target (default 75)" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $options }

            $result = Invoke-Test -arguments @('--coverage')

            $result.coverage | Should -Be $true
            $result.target | Should -Be 75
        }

        It "Should parse --verbosity argument correctly" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $options }

            $result = Invoke-Test -arguments @('--verbosity=detailed')

            $result.verbosity | Should -Be 'detailed'
        }

        It "Should filter out flag arguments from test names" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $testsNames }

            $result = Invoke-Test -arguments @('TestFile.ps1', '--unknown', '-x')

            $result | Should -Be @('TestFile.ps1')
        }

        It "Should pass non-flag arguments as test names" {
            Mock Initialize-Tests { param($testsNames, $options, $exclude) return $testsNames }

            $result = Invoke-Test -arguments @('TestFile1.ps1', 'TestFile2.ps1')

            $result | Should -Be @('TestFile1.ps1', 'TestFile2.ps1')
        }
    }

    Context "Coverage validation" {
        It "Should return -1 when coverage target is over 100" {
            $result = Invoke-Test -arguments @('--coverage=150')

            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Invalid coverage value*' -and $ForegroundColor -eq 'Yellow'
            }
        }

        It "Should return -1 when coverage target is negative" {
            $result = Invoke-Test -arguments @('--coverage=-10')

            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Invalid coverage value*' -and $ForegroundColor -eq 'Yellow'
            }
        }

        It "Should accept coverage target of 0" {
            Mock Initialize-Tests { 0 }

            $result = Invoke-Test -arguments @('--coverage=0')

            $result | Should -Be 0
        }

        It "Should accept coverage target of 100" {
            Mock Initialize-Tests { 0 }

            $result = Invoke-Test -arguments @('--coverage=100')

            $result | Should -Be 0
        }
    }
}

Describe "Invoke-Profile Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Save-PHP-Profile { 0 }
        Mock Use-PHP-Profile { 0 }
        Mock Show-PHP-Profiles { 0 }
        Mock Show-PHP-Profile { 0 }
        Mock Remove-PHP-Profile { 0 }
        Mock Clear-PHP-Profiles { 0 }
        Mock Export-PHP-Profile { 0 }
        Mock Import-PHP-Profile { 0 }
    }

    Context "No action provided" {
        It "Should return -1 when no action is provided" {
            $arguments = @()

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like "*Please specify an action for 'pvm profile'*" -and
                $ForegroundColor -eq 'Yellow'
            }
        }
    }

    Context "Save action" {
        It "Should return -1 when save action has no profile name" {
            $arguments = @("save")

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile save*'
            }
        }

        It "Should save profile with name only" {
            $arguments = @('save', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Save-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile' -and $description -eq $null
            }
        }

        It "Should save profile with name and description" {
            $arguments = @('save', 'myprofile', 'This', 'is', 'my', 'description')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Save-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile' -and
                $description -eq 'This is my description'
            }
        }
    }

    Context "Load action" {
        It "Should return -1 when load action has no profile name" {
            $arguments = @('load')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile load*'
            }
        }

        It "Should load profile with provided name" {
            $arguments = @('load', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Use-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('load', 'myprofile', 'to-be-ignored')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Use-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }
    }

    Context "List action" {
        It "Should list profiles without additional arguments" {
            $arguments = @('list')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Show-PHP-Profiles -Times 1
        }
    }

    Context "Show action" {
        It "Should return -1 when show action has no profile name" {
            $arguments = @('show')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile show*'
            }
        }

        It "Should show profile with provided name" {
            $arguments = @('show', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Show-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('show', 'myprofile', 'to-be-ignored')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Show-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }
    }

    Context "Delete action" {
        It "Should return -1 when delete action has no profile name" {
            $arguments = @('delete')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile delete*'
            }
        }

        It "Should delete profile with provided name" {
            $arguments = @('delete', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Remove-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('delete', 'myprofile', 'to-be-ignored')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Remove-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }

        It "Should delete profile with provided name and skip confirmation" {
            $arguments = @('delete', 'myprofile', '-y')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Remove-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile' -and $skipConfirmation -eq $true
            }
        }
    }

    Context "Clear action" {
        It "Should clear all profiles files" {
            $arguments = @('clear')

            $result = Invoke-Profile -arguments $arguments

            $result | Should -Be 0
            Should -Invoke Clear-PHP-Profiles -Times 1
        }

        It "Should clear all profiles files and skip confirmation" {
            $arguments = @('clear', '-y')

            $result = Invoke-Profile -arguments $arguments

            $result | Should -Be 0
            Should -Invoke Clear-PHP-Profiles -Times 1
        }

        It "Should clear all profiles files and skip confirmation using --yes" {
            $arguments = @('clear', '--yes')

            $result = Invoke-Profile -arguments $arguments

            $result | Should -Be 0
            Should -Invoke Clear-PHP-Profiles -Times 1
        }
    }

    Context "Export action" {
        It "Should return -1 when export action has no profile name" {
            $arguments = @('export')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile export*'
            }
        }

        It "Should export profile with name only" {
            $arguments = @('export', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Export-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile' -and $exportPath -eq $null
            }
        }

        It "Should export profile with name and path" {
            $arguments = @('export', 'myprofile', 'C:\exports\profile.json')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Export-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile' -and
                $exportPath -eq 'C:\exports\profile.json'
            }
        }
    }

    Context "Import action" {
        It "Should return -1 when import action has no file path" {
            $arguments = @('import')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Please provide a file path: pvm profile import*'
            }
        }

        It "Should import profile from file path only" {
            $arguments = @('import', 'C:\profiles\export.json')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Import-PHP-Profile -Times 1 -ParameterFilter {
                $importPath -eq 'C:\profiles\export.json' -and $profileName -eq $null
            }
        }

        It "Should import profile from file path with custom name" {
            $arguments = @('import', 'C:\profiles\export.json', 'myimported')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Import-PHP-Profile -Times 1 -ParameterFilter {
                $importPath -eq 'C:\profiles\export.json' -and
                $profileName -eq 'myimported'
            }
        }
    }

    Context "Unknown action" {
        It "Should return -1 for unknown action" {
            $arguments = @('unknown')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like "*Unknown action 'unknown'*" -and
                $ForegroundColor -eq "DarkYellow"
            }
        }

        It "Should handle case-insensitive action names" {
            $arguments = @('SAVE', 'testprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Save-PHP-Profile -Times 1
        }
    }

    Context "Action success and failure returns" {
        It "Should return 0 when Save-PHP-Profile succeeds" {
            Mock Save-PHP-Profile { return 0 }
            $arguments = @('save', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0
        }

        It "Should return -1 when Use-PHP-Profile fails" {
            Mock Use-PHP-Profile { return -1 }
            $arguments = @('load', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1
        }

        It "Should return action result code from any profile action" {
            Mock Remove-PHP-Profile { return 5 }
            $arguments = @('delete', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 5
        }
    }
}

Describe "Invoke-Cache Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Cache-Files { 0 }
        Mock Show-Cached-Data { 0 }
        Mock Remove-Cache-File { 0 }
        Mock Clear-Cache-Files { 0 }
    }

    Context "No action provided" {
        It "Should return -1 when no action is provided" {
            $arguments = @()

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like "*Please specify an action for 'pvm cache'*" -and
                $ForegroundColor -eq 'Yellow'
            }
        }
    }

    Context "List action" {
        It "Should list cache names without additional arguments" {
            $arguments = @('list')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Show-Cache-Files -Times 1
        }
    }

    Context "Show action" {
        It "Should return -1 when show action has no cache name" {
            $arguments = @('show')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Please provide a cache name: pvm cache show*'
            }
        }

        It "Should show cache with provided name" {
            $arguments = @('show', 'available_versions')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Show-Cached-Data -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('show', 'available_versions', 'to-be-ignored')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Show-Cached-Data -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions'
            }
        }
    }

    Context "Delete action" {
        It "Should return -1 when delete action has no cache name" {
            $arguments = @('delete')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*Please provide a cache name: pvm cache delete*'
            }
        }

        It "Should delete cache with provided name" {
            $arguments = @('delete', 'available_versions')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Remove-Cache-File -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('delete', 'available_versions', 'to-be-ignored')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Remove-Cache-File -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions'
            }
        }

        It "Should delete profile with provided name and skip confirmation" {
            $arguments = @('delete', 'available_versions', '-y')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Remove-Cache-File -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions' -and $skipConfirmation -eq $true
            }
        }
    }

    Context "Clear action" {
        It "Should clear all cache files" {
            $arguments = @('clear')

            $result = Invoke-Cache -arguments $arguments

            $result | Should -Be 0
            Should -Invoke Clear-Cache-Files -Times 1
        }

        It "Should clear all cache files and skip confirmation" {
            $arguments = @('clear', '-y')

            $result = Invoke-Cache -arguments $arguments

            $result | Should -Be 0
            Should -Invoke Clear-Cache-Files -Times 1
        }

        It "Should clear all cache files and skip confirmation using --yes" {
            $arguments = @('clear', '--yes')

            $result = Invoke-Cache -arguments $arguments

            $result | Should -Be 0
            Should -Invoke Clear-Cache-Files -Times 1
        }
    }

    Context "Unknown action" {
        It "Should return -1 for unknown action" {
            $arguments = @('unknown')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be -1

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like "*Unknown action 'unknown'*" -and
                $ForegroundColor -eq "DarkYellow"
            }
        }

        It "Should handle case-insensitive action names" {
            $arguments = @('LIST', 'testcache')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Should -Invoke Show-Cache-Files -Times 1
        }
    }

    Context "Action success and failure returns" {
        It "Should return 0 when Save-PHP-Profile succeeds" {
            Mock Save-PHP-Profile { return 0 }
            $arguments = @('save', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0
        }

        It "Should return -1 when Use-PHP-Profile fails" {
            Mock Use-PHP-Profile { return -1 }
            $arguments = @('load', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1
        }

        It "Should return action result code from any profile action" {
            Mock Remove-PHP-Profile { return 5 }
            $arguments = @('delete', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 5
        }
    }
}

Describe "Invoke-Aliases Tests" {
    BeforeEach {
        Mock Write-Host { }
    }

    It "Should return -1 when no aliases are found" {
        Mock Get-Aliases { return @{} }

        $result = Invoke-Aliases

        $result | Should -Be -1
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No aliases found.*' -and $ForegroundColor -eq 'DarkYellow' }
    }

    It "Should return 0 when aliases are found" {
        Mock Get-Aliases { return @{ 'alias1' = 'command1'; 'alias2' = 'command2' } }

        $result = Invoke-Aliases

        $result | Should -Be 0
        Should -Invoke Write-Host -Times 2
    }
}

Describe "Invoke-Info Tests" {
    BeforeEach {
        Mock Write-Host { }
        $Global:PVMRoot = 'C:\pvm'
        $PVMConfig.version = '2.6'
        $PVMConfig.paths = @{
            storage = 'C:\pvm\storage'
            data    = 'C:\pvm\storage\data'
        }
        $PVMConfig.env = @{
            CACHE_MAX_HOURS      = 168
            MIN_PAD_RIGHT_LENGTH = 2
            PHP_CURRENT_VERSION_PATH = 'C:\pvm'
        }
        Mock Get-Profile-Files {
            @('profile1.json', 'profile2.json')
        }
        Mock Get-Cache-Files {
            @('cache1.json')
        }
        Mock Get-Installed-PHP-Versions-From-Disk {
            @(
                @{ version = '8.2' }
                @{ version = '8.3' }
            )
        }
    }

    Context "Default output" {
        BeforeEach {
            Mock Get-Current-PHP-Version {
                @{
                    version   = '8.3.28'
                    arch      = 'x64'
                    buildType = 'TS'
                    path      = 'C:\pvm\storage\php\8.3.28'
                }
            }
        }

        It "Returns 0" {
            Invoke-Info -arguments @() | Should -Be 0
        }

        It "Displays status section" {
            Invoke-Info -arguments @()

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*PVM status*'
            }
        }

        It "Does not display verbose sections" {
            Invoke-Info -arguments @()

            Should -Not -Invoke Write-Host -ParameterFilter {
                $Object -like '*PVM paths*'
            }
        }
    }

    Context "When no PHP version is active" {
        BeforeEach {
            Mock Get-Current-PHP-Version { $null }
        }

        It "Returns 0" {
            Invoke-Info -arguments @() | Should -Be 0
        }

        It "Completes successfully" {
            { Invoke-Info -arguments @() } | Should -Not -Throw
        }
    }

    Context "Verbose output" {
        BeforeEach {
            Mock Get-Current-PHP-Version {
                @{
                    version   = '8.3.28'
                    arch      = 'x64'
                    buildType = 'TS'
                    path      = 'C:\pvm\storage\php\8.3.28'
                }
            }
        }

        It "Displays environment paths section" {
            Invoke-Info -arguments @('--verbose')

            Should -Invoke Write-Host -ParameterFilter {
                $Object -like '*PVM paths*'
            }
        }

        It "Returns 0" {
            Invoke-Info -arguments @('--verbose') | Should -Be 0
        }
    }
}

Describe "Invoke-Update Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Update-PVM { @{ code = 0; message = 'Updated' } }
    }

    It "Should call Update-PVM and return 0" {
        $result = Invoke-Update -arguments @()
        $result | Should -Be 0

        Should -Invoke Update-PVM -Times 1
    }
}

Describe "Invoke-Run Tests" {
    BeforeAll {
        Mock Get-Actions {
            [ordered]@{
                'install' = @{ action = { return 0 } }
                'list' = @{ action = { return 0 } }
                'ini' = @{ action = { return 0 } }
                'cache' = @{ action = { return 0 } }
                'test' = @{ action = { return 0 } }
            }
        }
    }

    It "Should return -1 when no arguments are provided" {
        $result = Invoke-Run -arguments @()
        $result | Should -Be -1
    }

    It "Should return -1 when an unknown script is provided" {
        Mock Get-Scripts { return @{ 'script1' = 'command1'; 'script2' = 'command2' } }

        $result = Invoke-Run -arguments @('unknown')
        $result | Should -Be -1
    }

    It "Should return -1 when an unknown command is provided" {
        Mock Get-Scripts { return @{ 'cmd1:arg1' = 'command1'; 'cmd2:arg2' = 'command2' } }

        $result = Invoke-Run -arguments @('cmd1:arg1')
        $result | Should -Be -1
    }

    It "Should return 0 when a valid script is provided" {
        Mock Get-Scripts { return @{ 'test:cov' = 'test --coverage'; 'test:quiet' = 'test --verbosity=None' } }

        $result = Invoke-Run -arguments @('test:cov')
        $result | Should -Be 0
    }
}
