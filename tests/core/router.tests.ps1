
BeforeAll {
    Mock Write-Host {}
}

Describe "Get-Actions Tests" {
    BeforeEach {
        Mock Invoke-PVMHelp { }
        Mock Invoke-PVMSetup { }
        Mock Invoke-PVMCurrent { }
        Mock Invoke-PVMList { }
        Mock Invoke-PVMInstall { }
        Mock Invoke-PVMUninstall { }
        Mock Invoke-PVMUse { }
        Mock Invoke-PVMIni { }
        Mock Invoke-PVMLog { }
        Mock Invoke-PVMTest { }
        Mock Invoke-PVMProfile { }
    }

    It "Should return ordered hashtable with all actions" {
        $arguments = @('test', 'arg')
        $actions = Get-Actions -arguments $arguments

        $actions | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $actions.Keys | Should -Contain 'help'
        $actions.Keys | Should -Contain 'setup'
        $actions.Keys | Should -Contain 'current'
        $actions.Keys | Should -Contain 'list'
        $actions.Keys | Should -Contain 'install'
        $actions.Keys | Should -Contain 'uninstall'
        $actions.Keys | Should -Contain 'use'
        $actions.Keys | Should -Contain 'info'
        $actions.Keys | Should -Contain 'ini'
        $actions.Keys | Should -Contain 'test'
        $actions.Keys | Should -Contain 'log'
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

            Assert-MockCalled Invoke-PVMHelp -Times 1
        }

        It "Should execute setup action correctly" {
            $actions = Get-Actions -arguments @()
            $actions['setup'].action.Invoke()

            Assert-MockCalled Invoke-PVMSetup -Times 1
        }

        It "Should execute current action correctly" {
            $actions = Get-Actions -arguments @()
            $actions['current'].action.Invoke()

            Assert-MockCalled Invoke-PVMCurrent -Times 1
        }

        It "Should execute list action with arguments" {
            $testArgs = @('available')
            $actions = Get-Actions -arguments $testArgs
            $actions['list'].action.Invoke()

            Assert-MockCalled Invoke-PVMList -Times 1
        }

        It "Should execute install action correctly" {
            $actions = Get-Actions -arguments @('8.2.0')
            $actions['install'].action.Invoke()

            Assert-MockCalled Invoke-PVMInstall -Times 1
        }

        It "Should execute uninstall action correctly" {
            $actions = Get-Actions -arguments @('8.2.0')
            $actions['uninstall'].action.Invoke()

            Assert-MockCalled Invoke-PVMUninstall -Times 1
        }

        It "Should execute use action correctly" {
            $actions = Get-Actions -arguments @('8.2.0')
            $actions['use'].action.Invoke()

            Assert-MockCalled Invoke-PVMUse -Times 1
        }

        It "Should execute ini action correctly" {
            $actions = Get-Actions -arguments @('set', 'memory_limit=256M')
            $actions['ini'].action.Invoke()

            Assert-MockCalled Invoke-PVMIni -Times 1
        }

        It "Should execute info action" {
            $actions = Get-Actions -arguments @()
            $actions['info'].action.Invoke()

            Assert-MockCalled Invoke-PVMIni -Times 1
        }

        It "Should execute log action" {
            $actions = Get-Actions -arguments @("--pageSize=10")
            $actions['log'].action.Invoke()

            Assert-MockCalled Invoke-PVMLog -Times 1
        }

        It "Should execute test action with verbosity" {
            $testArgs = @('TestFile.ps1', 'Detailed', "--tag=unit")
            $actions = Get-Actions -arguments $testArgs
            $actions['test'].action.Invoke()

            Assert-MockCalled Invoke-PVMTest -Times 1
        }

        It "Should execute profile action" {
            $actions = Get-Actions -arguments @('save')
            $actions['profile'].action.Invoke()

            Assert-MockCalled Invoke-PVMProfile -Times 1
        }
    }
}

Describe "Integration Tests" {
    Context "Command Flow Integration" {
        BeforeEach {
            # Setup comprehensive mocks for integration testing
            Mock Is-PVM-Setup { $true }
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
            $result = Invoke-PVMSetup
            $result | Should -Be 0

            # Install
            $result = Invoke-PVMInstall -arguments @('8.2.0')
            $result | Should -Be 0

            # Use
            $result = Invoke-PVMUse -arguments @('8.2.0')
            $result | Should -Be 0

            # Current
            $result = Invoke-PVMCurrent
            $result | Should -Be 0

            # Verify all functions were called
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Install-PHP -Times 1
            Assert-MockCalled Update-PHP-Version -Times 1
            Assert-MockCalled Get-Current-PHP-Version -Times 1
        }
    }

    Context "Error Handling Integration" {
        It "Should handle cascading failures gracefully" {
            Mock Is-PVM-Setup { $false }
            Mock Setup-PVM { @{ code = 1; message = 'Setup failed' } }
            Mock Optimize-SystemPath { 1 }
            Mock Display-Msg-By-ExitCode { }
            Mock Write-Host { }

            $result = Invoke-PVMSetup
            $result | Should -Be 0

            Assert-MockCalled Setup-PVM -Times 1
            Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Failed to optimize system path*' }
            Assert-MockCalled Display-Msg-By-ExitCode -Times 1
        }
    }
}
