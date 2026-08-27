
BeforeAll {
    Mock Show-Message {}
    Mock Show-Error {}
    Mock Write-Color {}
    Mock New-Line {}
}

Describe "Get-Actions Tests" {
    BeforeEach {
        Mock Invoke-Version { }
        Mock Invoke-Help { }
        Mock Invoke-Setup { }
        Mock Invoke-Repair { }
        Mock Invoke-Current { }
        Mock Invoke-List { }
        Mock Invoke-Install { }
        Mock Invoke-Uninstall { }
        Mock Invoke-Use { }
        Mock Invoke-Info { }
        Mock Invoke-Ini { }
        Mock Invoke-Log { }
        Mock Invoke-Test { }
        Mock Invoke-Profile { }
        Mock Invoke-Cache { }
        Mock Invoke-Aliases { }
        Mock Invoke-Update { }
        Mock Invoke-Run { }
    }

    It "Should return ordered hashtable with all actions" {
        $actions = Get-Actions

        $actions | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $actions.Keys | Should -Contain 'help'
        $actions.Keys | Should -Contain 'version'
        $actions.Keys | Should -Contain 'setup'
        $actions.Keys | Should -Contain 'current'
        $actions.Keys | Should -Contain 'list'
        $actions.Keys | Should -Contain 'install'
        $actions.Keys | Should -Contain 'uninstall'
        $actions.Keys | Should -Contain 'use'
        $actions.Keys | Should -Contain 'info'
        $actions.Keys | Should -Contain 'ini'
        $actions.Keys | Should -Contain 'profile'
        $actions.Keys | Should -Contain 'cache'
        $actions.Keys | Should -Contain 'test'
        $actions.Keys | Should -Contain 'log'
        $actions.Keys | Should -Contain 'update'
        $actions.Keys | Should -Contain 'run'
    }

    Context "Action Execution Tests" {
        It "Should execute help action correctly" {
            $actions = Get-Actions
            $actions['help'].data.action.Invoke()

            Should -Invoke Invoke-Help -Times 1
        }

        It "Should execute version action correctly" {
            $actions = Get-Actions
            $actions['version'].data.action.Invoke()

            Should -Invoke Invoke-Version -Times 1
        }

        It "Should execute setup action correctly" {
            $actions = Get-Actions
            $actions['setup'].data.action.Invoke()

            Should -Invoke Invoke-Setup -Times 1
        }

        It "Should execute repair action correctly" {
            $actions = Get-Actions
            $actions['repair'].data.action.Invoke()

            Should -Invoke Invoke-Repair -Times 1
        }

        It "Should execute current action correctly" {
            $actions = Get-Actions
            $actions['current'].data.action.Invoke()

            Should -Invoke Invoke-Current -Times 1
        }

        It "Should execute list action with arguments" {
            $testArgs = @('available')
            $actions = Get-Actions
            & $actions['list'].data.action -arguments $testArgs

            Should -Invoke Invoke-List -Times 1
        }

        It "Should execute install action correctly" {
            $actions = Get-Actions
            & $actions['install'].data.action -arguments @('8.2.0')

            Should -Invoke Invoke-Install -Times 1
        }

        It "Should execute uninstall action correctly" {
            $actions = Get-Actions
            & $actions['uninstall'].data.action -arguments @('8.2.0')

            Should -Invoke Invoke-Uninstall -Times 1
        }

        It "Should execute use action correctly" {
            $actions = Get-Actions
            & $actions['use'].data.action -arguments @('8.2.0')

            Should -Invoke Invoke-Use -Times 1
        }

        It "Should execute ini action correctly" {
            $actions = Get-Actions
            & $actions['ini'].data.action -arguments @('set', 'memory_limit=256M')

            Should -Invoke Invoke-Ini -Times 1
        }

        It "Should execute info action" {
            $actions = Get-Actions
            $actions['info'].data.action.Invoke()

            Should -Invoke Invoke-Info -Times 1
        }

        It "Should execute log action" {
            $actions = Get-Actions
            & $actions['log'].data.action -arguments @("--pageSize=10")

            Should -Invoke Invoke-Log -Times 1
        }

        It "Should execute test action with verbosity" {
            $testArgs = @('TestFile.ps1', 'Detailed', "--tag=unit")
            $actions = Get-Actions
            & $actions['test'].data.action -arguments $testArgs

            Should -Invoke Invoke-Test -Times 1
        }

        It "Should execute profile action" {
            $actions = Get-Actions
            & $actions['profile'].data.action -arguments @('save')

            Should -Invoke Invoke-Profile -Times 1
        }

        It "Should execute cache action" {
            $actions = Get-Actions
            & $actions['cache'].data.action -arguments @('list')

            Should -Invoke Invoke-Cache -Times 1
        }

        It "Should execute aliases action" {
            $actions = Get-Actions
            $actions['aliases'].data.action.Invoke()

            Should -Invoke Invoke-Aliases -Times 1
        }

        It "Should execute update action" {
            $actions = Get-Actions
            $actions['update'].data.action.Invoke()

            Should -Invoke Invoke-Update -Times 1
        }

        It "Should execute run action" {
            $actions = Get-Actions
            $actions['run'].data.action.Invoke()

            Should -Invoke Invoke-Run -Times 1
        }
    }
}

Describe "Integration Tests" {
    Context "Command Flow Integration" {
        BeforeEach {
            # Setup comprehensive mocks for integration testing
            Mock Test-PVMSetup { $true }
            Mock Initialize-EnvironmentDirectoriesAndFiles { 0 }
            Mock New-EnvFile { 0 }
            Mock Initialize-PVM { @{ code = 0; message = 'Setup completed' } }
            Mock Optimize-SystemPath { 0 }
            Mock Show-MsgByExitCode { }
            Mock Get-CurrentPHPVersion { @{ version = '8.2.0'; path = 'C:\PHP\8.2.0' } }
            Mock Get-PHPStatus {
                return @(
                    @{ name = 'Xdebug'; version = '3.2.0'; copyright = 'Xdebug'; color = 'DarkGreen'; status = 'Enabled' },
                    @{ name = 'Zend Opcache'; version = '8.2.0'; copyright = 'Zend'; color = 'DarkYellow'; status = 'Disabled' }
                )
            }
            Mock Install-PHP { 0 }
            Mock Update-PHPVersion { 0 }
        }

        It "Should handle complete workflow: setup -> install -> use -> current" {
            # Setup
            $result = Invoke-Setup
            $result | Should -Be 0

            # Install
            $result = Invoke-Install -arguments @('8.2.0')
            $result | Should -Be 0

            # Use
            $result = Invoke-Use -arguments @('8.2.0')
            $result | Should -Be 0

            # Current
            $result = Invoke-Current
            $result | Should -Be 0

            # Verify all functions were called
            Should -Invoke Test-PVMSetup -Times 1
            Should -Invoke Install-PHP -Times 1
            Should -Invoke Update-PHPVersion -Times 1
            Should -Invoke Get-CurrentPHPVersion -Times 1
        }
    }

    Context "Error Handling Integration" {
        It "Should handle cascading failures gracefully" {
            Mock Test-PVMSetup { $false }
            Mock Initialize-EnvironmentDirectoriesAndFiles { -1 }
            Mock New-EnvFile { -1 }
            Mock Initialize-PVM { @{ code = 1; message = 'Setup failed' } }
            Mock Optimize-SystemPath { -1 }
            Mock Show-MsgByExitCode { }

            $result = Invoke-Setup
            $result | Should -Be 0

            Should -Invoke Initialize-PVM -Times 1
            Should -Invoke Show-Error -ParameterFilter { $message -like '*Failed to optimize system path*' }
            Should -Invoke Show-MsgByExitCode -Times 1
        }
    }
}
