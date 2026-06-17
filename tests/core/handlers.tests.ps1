
BeforeAll {
    Mock Write-Host {}
}

Describe "Invoke-Setup Tests" {
    BeforeEach {
        Mock Is-PVM-Setup { $true }
        Mock Setup-PVM { @{ code = 0; message = 'Setup completed' } }
        Mock Optimize-SystemPath { 0 }
        Mock Setup-Environment-Directories-And-Files { 0 }
        Mock Display-Msg-By-ExitCode { }
        Mock Write-Host { }
    }

    It "Should return 0 when PVM is already setup" {
        Mock Is-PVM-Setup { $true }

        $result = Invoke-Setup
        $result | Should -Be 0

        Assert-MockCalled Is-PVM-Setup -Times 1
        Assert-MockCalled Setup-PVM -Times 0
        Assert-MockCalled Optimize-SystemPath -Times 1
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }

    It "Should setup PVM when not already setup" {
        Mock Is-PVM-Setup { $false }
        Mock Setup-PVM { @{ code = 0; message = 'Setup completed successfully' } }

        $result = Invoke-Setup
        $result | Should -Be 0

        Assert-MockCalled Is-PVM-Setup -Times 1
        Assert-MockCalled Setup-PVM -Times 1
        Assert-MockCalled Optimize-SystemPath -Times 1
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }

    It "Should display warning when system path optimization fails" {
        Mock Optimize-SystemPath { -1 }

        $result = Invoke-Setup
        $result | Should -Be 0

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Failed to optimize system path*' -and $ForegroundColor -eq 'DarkYellow' }
    }
}

Describe "Invoke-Current Tests" {
    BeforeEach {
        Mock Get-Current-PHP-Version { @{
            version = '8.2.0'
            arch = 'x64'
            buildType = 'TS'
            path = 'C:\PHP\8.2.0'
            status = @{ "xdebug" = $true; "opcache" = $false }
        }}
        Mock Write-Host { }
    }

    It "Should display current PHP version and extensions when version is set" {
        $result = Invoke-Current
        $result | Should -Be 0

        Assert-MockCalled Get-Current-PHP-Version -Times 1
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Running version: PHP 8.2.0*' }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*xdebug is enabled*' -and $ForegroundColor -eq 'DarkGreen' }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*opcache is disabled*' -and $ForegroundColor -eq 'DarkYellow' }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Path: C:\PHP\8.2.0*' -and $ForegroundColor -eq 'Gray' }
    }

    It "Should return -1 when no PHP version is set" {
        Mock Get-Current-PHP-Version { @{ version = $null; status = $null; path = $null } }

        $result = Invoke-Current
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*No PHP version is currently set*' }
    }

    It "Should handle missing status information" {
        Mock Get-Current-PHP-Version { @{ version = '8.2.0'; status = $null; path = 'C:\PHP\8.2.0' } }

        $result = Invoke-Current
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*No status information available*' -and $ForegroundColor -eq 'Yellow' }
    }
}

Describe "Invoke-List Tests" {
    BeforeEach {
        Mock Get-Available-PHP-Versions { return 0 }
        Mock Display-Installed-PHP-Versions { return 0 }
    }

    It "Should call Get-Available-PHP-Versions when 'available' argument is provided" {
        $arguments = @("available")

        $result = Invoke-List -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Get-Available-PHP-Versions -Times 1
        Assert-MockCalled Display-Installed-PHP-Versions -Times 0
    }

    It "Should call Display-Installed-PHP-Versions when no 'available' argument" {
        $arguments = @()

        $result = Invoke-List -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Display-Installed-PHP-Versions -Times 1
        Assert-MockCalled Get-Available-PHP-Versions -Times 0
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

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Please provide a PHP version to install*' }
    }

    It "Should install PHP with basic parameters" {
        $arguments = @('8.2.0')

        $result = Invoke-Install -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter {
            $version -eq '8.2.0'
        }
    }

    It "Should install detected PHP version from the project" {
        $arguments = @('auto')

        Mock Get-Matching-PHP-Versions { return @() }
        Mock Detect-PHP-VersionFromProject { return '8.1' }
        $result = Invoke-Install -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter {
            $version -eq '8.1'
        }
    }

    It "Should install latest PHP version when 'latest' argument is provided" {
        $arguments = @('latest')
        Mock Get-Latest-PHP-Version { return @{version = '8.6.0'} }

        $result = Invoke-Install -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter {
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
        Mock Auto-Select-PHP-Version { return @{ code = 0; version = '8.2' } }

        $result = Invoke-Install -arguments $arguments

        $result | Should -Be -1
    }
}

Describe "Invoke-Uninstall Tests" {
    BeforeEach {
        Mock Get-Current-PHP-Version { @{ version = '8.1.0' } }
        Mock Uninstall-PHP { @{ code = 0; message = 'Uninstalled successfully' } }
        Mock Display-Msg-By-ExitCode { }
        Mock Write-Host { }
        Mock Read-Host { }
    }

    It "Should return -1 when no version is provided" {
        $arguments = @()

        $result = Invoke-Uninstall -arguments $arguments
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Please provide a PHP version to uninstall*' }
    }

    It "Should uninstall PHP version successfully" {
        $arguments = @('8.2.0')

        $result = Invoke-Uninstall -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Uninstall-PHP -Times 1 -ParameterFilter { $version -eq '8.2.0' }
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }

    It "Should not prompt when uninstalling different version than current" {
        Mock Get-Current-PHP-Version { @{ version = '8.1.0' } }
        $arguments = @('8.2.0')

        $result = Invoke-Uninstall -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Read-Host -Times 0
        Assert-MockCalled Uninstall-PHP -Times 1
    }
}

Describe "Invoke-Use Tests" {
    BeforeEach {
        Mock Auto-Select-PHP-Version { @{ code = 0; version = '8.2.0' } }
        Mock Update-PHP-Version { @{ code = 0; message = 'Version updated' } }
        Mock Display-Msg-By-ExitCode { }
        Mock Write-Host { }
    }

    It "Should return -1 when no version is provided" {
        $arguments = @()

        $result = Invoke-Use -arguments $arguments
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Please provide a PHP version to use*' }
    }

    It "Should use specific PHP version" {
        $arguments = @('8.2.0')

        $result = Invoke-Use -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Update-PHP-Version -Times 1 -ParameterFilter {
            $version -eq '8.2.0'
        }
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }

    It "Should handle 'auto' version selection successfully" {
        $arguments = @('auto')

        $result = Invoke-Use -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Auto-Select-PHP-Version -Times 1
        Assert-MockCalled Update-PHP-Version -Times 1 -ParameterFilter { $version -eq '8.2.0' }
    }

    It "Should return -1 when auto-selection fails" {
        Mock Auto-Select-PHP-Version { @{ code = 1; message = 'Auto selection failed' } }
        $arguments = @('auto')

        $result = Invoke-Use -arguments $arguments
        $result | Should -Be -1

        Assert-MockCalled Auto-Select-PHP-Version -Times 1
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
        Assert-MockCalled Update-PHP-Version -Times 0
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

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please specify an action for 'pvm ini'*" }
    }

    It "Should call Invoke-IniAction with correct parameters for single action" {
        $arguments = @('set')

        $result = Invoke-Ini -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Invoke-IniAction -Times 1 -ParameterFilter {
            $action -eq 'set' -and
            $params.Count -eq 0
        }
    }

    It "Should call Invoke-IniAction with remaining arguments" {
        $arguments = @('set', 'memory_limit', '256M')

        $result = Invoke-Ini -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Invoke-IniAction -Times 1 -ParameterFilter {
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

            Assert-MockCalled Invoke-IniAction -ParameterFilter { $action -eq $testAction }
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

        Assert-MockCalled Show-Log -Exactly 1 -ParameterFilter { $pageSize -eq '5' }
    }

    It "Calls Show-Log with default page size when no argument is given" {
        $arguments = @()
        Invoke-Log -arguments $arguments | Should -Be 0

        Assert-MockCalled Show-Log -Exactly 1 -ParameterFilter { $pageSize -eq 5 }
    }

    It "Passes return code from Show-Log back to caller" {
        Mock Show-Log { return 0 }
        (Invoke-Log -arguments @('--pageSize=2')) | Should -Be 0

        Mock Show-Log { return -1 }
        (Invoke-Log -arguments @('--pageSize=2')) | Should -Be -1
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
        Mock Prepare-Tests { 0 }
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
}

Describe "Invoke-Profile Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Save-PHP-Profile { 0 }
        Mock Load-PHP-Profile { 0 }
        Mock List-PHP-Profiles { 0 }
        Mock Show-PHP-Profile { 0 }
        Mock Delete-PHP-Profile { 0 }
        Mock Export-PHP-Profile { 0 }
        Mock Import-PHP-Profile { 0 }
    }

    Context "No action provided" {
        It "Should return -1 when no action is provided" {
            $arguments = @()

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Assert-MockCalled Write-Host -ParameterFilter {
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

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile save*'
            }
        }

        It "Should save profile with name only" {
            $arguments = @('save', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Save-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile' -and $description -eq $null
            }
        }

        It "Should save profile with name and description" {
            $arguments = @('save', 'myprofile', 'This', 'is', 'my', 'description')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Save-PHP-Profile -Times 1 -ParameterFilter {
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

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile load*'
            }
        }

        It "Should load profile with provided name" {
            $arguments = @('load', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Load-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('load', 'myprofile', 'to-be-ignored')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Load-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }
    }

    Context "List action" {
        It "Should list profiles without additional arguments" {
            $arguments = @('list')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled List-PHP-Profiles -Times 1
        }
    }

    Context "Show action" {
        It "Should return -1 when show action has no profile name" {
            $arguments = @('show')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile show*'
            }
        }

        It "Should show profile with provided name" {
            $arguments = @('show', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Show-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('show', 'myprofile', 'to-be-ignored')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Show-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }
    }

    Context "Delete action" {
        It "Should return -1 when delete action has no profile name" {
            $arguments = @('delete')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile delete*'
            }
        }

        It "Should delete profile with provided name" {
            $arguments = @('delete', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Delete-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('delete', 'myprofile', 'to-be-ignored')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Delete-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile'
            }
        }
    }

    Context "Export action" {
        It "Should return -1 when export action has no profile name" {
            $arguments = @('export')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like '*Please provide a profile name: pvm profile export*'
            }
        }

        It "Should export profile with name only" {
            $arguments = @('export', 'myprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Export-PHP-Profile -Times 1 -ParameterFilter {
                $profileName -eq 'myprofile' -and $exportPath -eq $null
            }
        }

        It "Should export profile with name and path" {
            $arguments = @('export', 'myprofile', 'C:\exports\profile.json')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Export-PHP-Profile -Times 1 -ParameterFilter {
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

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like '*Please provide a file path: pvm profile import*'
            }
        }

        It "Should import profile from file path only" {
            $arguments = @('import', 'C:\profiles\export.json')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Import-PHP-Profile -Times 1 -ParameterFilter {
                $importPath -eq 'C:\profiles\export.json' -and $profileName -eq $null
            }
        }

        It "Should import profile from file path with custom name" {
            $arguments = @('import', 'C:\profiles\export.json', 'myimported')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Import-PHP-Profile -Times 1 -ParameterFilter {
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

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like "*Unknown action 'unknown'*" -and
                $ForegroundColor -eq "Yellow"
            }
        }

        It "Should handle case-insensitive action names" {
            $arguments = @('SAVE', 'testprofile')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Save-PHP-Profile -Times 1
        }
    }

    Context "Action success and failure returns" {
        It "Should return 0 when Save-PHP-Profile succeeds" {
            Mock Save-PHP-Profile { return 0 }
            $arguments = @('save', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0
        }

        It "Should return -1 when Load-PHP-Profile fails" {
            Mock Load-PHP-Profile { return -1 }
            $arguments = @('load', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1
        }

        It "Should return action result code from any profile action" {
            Mock Delete-PHP-Profile { return 5 }
            $arguments = @('delete', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 5
        }
    }
}

Describe "Invoke-Cache Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock List-Cache-Files { 0 }
        Mock Show-Cache-Data { 0 }
        Mock Delete-Cache-File { 0 }
        Mock Clear-Cache-Files { 0 }
    }

    Context "No action provided" {
        It "Should return -1 when no action is provided" {
            $arguments = @()

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be -1

            Assert-MockCalled Write-Host -ParameterFilter {
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

            Assert-MockCalled List-Cache-Files -Times 1
        }
    }

    Context "Show action" {
        It "Should return -1 when show action has no cache name" {
            $arguments = @('show')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be -1

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like '*Please provide a cache name: pvm cache show*'
            }
        }

        It "Should show cache with provided name" {
            $arguments = @('show', 'available_versions')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Show-Cache-Data -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('show', 'available_versions', 'to-be-ignored')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Show-Cache-Data -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions'
            }
        }
    }

    Context "Delete action" {
        It "Should return -1 when delete action has no cache name" {
            $arguments = @('delete')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be -1

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like '*Please provide a cache name: pvm cache delete*'
            }
        }

        It "Should delete cache with provided name" {
            $arguments = @('delete', 'available_versions')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Delete-Cache-File -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions'
            }
        }

        It "Should take first and ignore extra arguments" {
            $arguments = @('delete', 'available_versions', 'to-be-ignored')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled Delete-Cache-File -Times 1 -ParameterFilter {
                $cacheName -eq 'available_versions'
            }
        }
    }

    Context "Clear action" {
        It "Should clear all cache files" {
            $arguments = @('clear')

            $result = Invoke-Cache -arguments $arguments

            $result | Should -Be 0
            Assert-MockCalled Clear-Cache-Files -Times 1
        }
    }

    Context "Unknown action" {
        It "Should return -1 for unknown action" {
            $arguments = @('unknown')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be -1

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -like "*Unknown action 'unknown'*" -and
                $ForegroundColor -eq "Yellow"
            }
        }

        It "Should handle case-insensitive action names" {
            $arguments = @('LIST', 'testcache')

            $result = Invoke-Cache -arguments $arguments
            $result | Should -Be 0

            Assert-MockCalled List-Cache-Files -Times 1
        }
    }

    Context "Action success and failure returns" {
        It "Should return 0 when Save-PHP-Profile succeeds" {
            Mock Save-PHP-Profile { return 0 }
            $arguments = @('save', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be 0
        }

        It "Should return -1 when Load-PHP-Profile fails" {
            Mock Load-PHP-Profile { return -1 }
            $arguments = @('load', 'test')

            $result = Invoke-Profile -arguments $arguments
            $result | Should -Be -1
        }

        It "Should return action result code from any profile action" {
            Mock Delete-PHP-Profile { return 5 }
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
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*No aliases found.*' -and $ForegroundColor -eq 'DarkYellow' }
    }

    It "Should return 0 when aliases are found" {
        Mock Get-Aliases { return @{ 'alias1' = 'command1'; 'alias2' = 'command2' } }

        $result = Invoke-Aliases

        $result | Should -Be 0
        Assert-MockCalled Write-Host -Times 2
    }
}
