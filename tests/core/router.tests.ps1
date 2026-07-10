
BeforeAll {
    Mock Write-Host {}
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
        $arguments = @('test', 'arg')
        $actions = Get-Actions -arguments $arguments

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

    It "Should set script-level arguments variable" {
        $testArgs = @('arg1', 'arg2')
        Get-Actions -arguments $testArgs

        $script:arguments | Should -Be $testArgs
    }

    Context "Action Execution Tests" {
        It "Should execute help action correctly" {
            $actions = Get-Actions -arguments @()
            $actions['help'].action.Invoke()

            Should -Invoke Invoke-Help -Times 1
        }

        It "Should execute version action correctly" {
            $actions = Get-Actions -arguments @()
            $actions['version'].action.Invoke()

            Should -Invoke Invoke-Version -Times 1
        }

        It "Should execute setup action correctly" {
            $actions = Get-Actions -arguments @()
            $actions['setup'].action.Invoke()

            Should -Invoke Invoke-Setup -Times 1
        }

        It "Should execute repair action correctly" {
            $actions = Get-Actions -arguments @()
            $actions['repair'].action.Invoke()

            Should -Invoke Invoke-Repair -Times 1
        }

        It "Should execute current action correctly" {
            $actions = Get-Actions -arguments @()
            $actions['current'].action.Invoke()

            Should -Invoke Invoke-Current -Times 1
        }

        It "Should execute list action with arguments" {
            $testArgs = @('available')
            $actions = Get-Actions -arguments $testArgs
            $actions['list'].action.Invoke()

            Should -Invoke Invoke-List -Times 1
        }

        It "Should execute install action correctly" {
            $actions = Get-Actions -arguments @('8.2.0')
            $actions['install'].action.Invoke()

            Should -Invoke Invoke-Install -Times 1
        }

        It "Should execute uninstall action correctly" {
            $actions = Get-Actions -arguments @('8.2.0')
            $actions['uninstall'].action.Invoke()

            Should -Invoke Invoke-Uninstall -Times 1
        }

        It "Should execute use action correctly" {
            $actions = Get-Actions -arguments @('8.2.0')
            $actions['use'].action.Invoke()

            Should -Invoke Invoke-Use -Times 1
        }

        It "Should execute ini action correctly" {
            $actions = Get-Actions -arguments @('set', 'memory_limit=256M')
            $actions['ini'].action.Invoke()

            Should -Invoke Invoke-Ini -Times 1
        }

        It "Should execute info action" {
            $actions = Get-Actions -arguments @()
            $actions['info'].action.Invoke()

            Should -Invoke Invoke-Info -Times 1
        }

        It "Should execute log action" {
            $actions = Get-Actions -arguments @("--pageSize=10")
            $actions['log'].action.Invoke()

            Should -Invoke Invoke-Log -Times 1
        }

        It "Should execute test action with verbosity" {
            $testArgs = @('TestFile.ps1', 'Detailed', "--tag=unit")
            $actions = Get-Actions -arguments $testArgs
            $actions['test'].action.Invoke()

            Should -Invoke Invoke-Test -Times 1
        }

        It "Should execute profile action" {
            $actions = Get-Actions -arguments @('save')
            $actions['profile'].action.Invoke()

            Should -Invoke Invoke-Profile -Times 1
        }

        It "Should execute cache action" {
            $actions = Get-Actions -arguments @('list')
            $actions['cache'].action.Invoke()

            Should -Invoke Invoke-Cache -Times 1
        }

        It "Should execute aliases action" {
            $actions = Get-Actions -arguments @()
            $actions['aliases'].action.Invoke()

            Should -Invoke Invoke-Aliases -Times 1
        }

        It "Should execute update action" {
            $actions = Get-Actions -arguments @()
            $actions['update'].action.Invoke()

            Should -Invoke Invoke-Update -Times 1
        }

        It "Should execute run action" {
            $actions = Get-Actions -arguments @()
            $actions['run'].action.Invoke()

            Should -Invoke Invoke-Run -Times 1
        }
    }
}

Describe "Integration Tests" {
    Context "Command Flow Integration" {
        BeforeEach {
            # Setup comprehensive mocks for integration testing
            Mock Is-PVM-Setup { $true }
            Mock Setup-Environment-Directories-And-Files { 0 }
            Mock Create-Env-File { 0 }
            Mock Setup-PVM { @{ code = 0; message = 'Setup completed' } }
            Mock Optimize-SystemPath { 0 }
            Mock Display-Msg-By-ExitCode { }
            Mock Get-Current-PHP-Version { @{ version = '8.2.0'; status = @{ 'xdebug' = $true }; path = 'C:\PHP\8.2.0' } }
            Mock Install-PHP { 0 }
            Mock Update-PHP-Version { @{ code = 0; message = 'Version updated' } }
            Mock Write-Host { }
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
            Should -Invoke Is-PVM-Setup -Times 1
            Should -Invoke Install-PHP -Times 1
            Should -Invoke Update-PHP-Version -Times 1
            Should -Invoke Get-Current-PHP-Version -Times 1
        }
    }

    Context "Error Handling Integration" {
        It "Should handle cascading failures gracefully" {
            Mock Is-PVM-Setup { $false }
            Mock Setup-Environment-Directories-And-Files { -1 }
            Mock Create-Env-File { -1 }
            Mock Setup-PVM { @{ code = 1; message = 'Setup failed' } }
            Mock Optimize-SystemPath { -1 }
            Mock Display-Msg-By-ExitCode { }
            Mock Write-Host { }

            $result = Invoke-Setup
            $result | Should -Be 0

            Should -Invoke Setup-PVM -Times 1
            Should -Invoke Write-Host -ParameterFilter { $Object -like '*Failed to optimize system path*' }
            Should -Invoke Display-Msg-By-ExitCode -Times 1
        }
    }
}
