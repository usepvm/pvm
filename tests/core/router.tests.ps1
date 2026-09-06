
BeforeAll {
    Mock Show-Message { }
    Mock Show-Error { }
    Mock Write-Color { }
    Mock New-Line { }
}

Describe "Get-HelpAction" {
    It "Should return the help action" {
        Mock Invoke-Help { return 0 }

        $helpAction = Get-HelpAction

        $helpAction | Should -BeOfType [hashtable]
        $helpAction.Keys | Should -Contain 'command'
        $helpAction.Keys | Should -Contain 'description'
        $helpAction.Keys | Should -Contain 'usage'
        $helpAction.Keys | Should -Contain 'action'

        $code = & $helpAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Help -Times 1
    }
}

Describe "Get-VersionAction" {
    It "Should return the version action" {
        Mock Invoke-Version { return 0 }

        $versionAction = Get-VersionAction

        $versionAction | Should -BeOfType [hashtable]
        $versionAction.Keys | Should -Contain 'command'
        $versionAction.Keys | Should -Contain 'description'
        $versionAction.Keys | Should -Contain 'usage'
        $versionAction.Keys | Should -Contain 'action'

        $code = & $versionAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Version -Times 1
    }
}

Describe "Get-SetupAction" {
    It "Should return the setup action" {
        Mock Invoke-Setup { return 0 }

        $setupAction = Get-SetupAction

        $setupAction | Should -BeOfType [hashtable]
        $setupAction.Keys | Should -Contain 'command'
        $setupAction.Keys | Should -Contain 'description'
        $setupAction.Keys | Should -Contain 'usage'
        $setupAction.Keys | Should -Contain 'action'

        $code = & $setupAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Setup -Times 1
    }
}

Describe "Get-CurrentAction" {
    It "Should return the current action" {
        Mock Invoke-Current { return 0 }

        $currentAction = Get-CurrentAction

        $currentAction | Should -BeOfType [hashtable]
        $currentAction.Keys | Should -Contain 'command'
        $currentAction.Keys | Should -Contain 'description'
        $currentAction.Keys | Should -Contain 'usage'
        $currentAction.Keys | Should -Contain 'action'

        $code = & $currentAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Current -Times 1
    }
}

Describe "Get-ListAction" {
    It "Should return the list action" {
        Mock Invoke-List { return 0 }

        $listAction = Get-ListAction

        $listAction | Should -BeOfType [hashtable]
        $listAction.Keys | Should -Contain 'command'
        $listAction.Keys | Should -Contain 'description'
        $listAction.Keys | Should -Contain 'usage'
        $listAction.Keys | Should -Contain 'action'

        $code = & $listAction.action -arguments @('available')

        $code | Should -Be 0
        Should -Invoke Invoke-List -Times 1
    }
}

Describe "Get-InstallAction" {
    It "Should return the install action" {
        Mock Invoke-Install { return 0 }

        $installAction = Get-InstallAction

        $installAction | Should -BeOfType [hashtable]
        $installAction.Keys | Should -Contain 'command'
        $installAction.Keys | Should -Contain 'description'
        $installAction.Keys | Should -Contain 'usage'
        $installAction.Keys | Should -Contain 'action'

        $code = & $installAction.action -arguments @('8.2.0')

        $code | Should -Be 0
        Should -Invoke Invoke-Install -Times 1
    }
}

Describe "Get-UseAction" {
    It "Should return the use action" {
        Mock Invoke-Use { return 0 }

        $useAction = Get-UseAction

        $useAction | Should -BeOfType [hashtable]
        $useAction.Keys | Should -Contain 'command'
        $useAction.Keys | Should -Contain 'description'
        $useAction.Keys | Should -Contain 'usage'
        $useAction.Keys | Should -Contain 'action'

        $code = & $useAction.action -arguments @('8.2.0')

        $code | Should -Be 0
        Should -Invoke Invoke-Use -Times 1
    }
}

Describe "Get-UninstallAction" {
    It "Should return the uninstall action" {
        Mock Invoke-Uninstall { return 0 }

        $uninstallAction = Get-UninstallAction

        $uninstallAction | Should -BeOfType [hashtable]
        $uninstallAction.Keys | Should -Contain 'command'
        $uninstallAction.Keys | Should -Contain 'description'
        $uninstallAction.Keys | Should -Contain 'usage'
        $uninstallAction.Keys | Should -Contain 'action'

        $code = & $uninstallAction.action -arguments @('8.2.0')

        $code | Should -Be 0
        Should -Invoke Invoke-Uninstall -Times 1
    }
}

Describe "Get-IniAction" {
    It "Should return the ini action" {
        Mock Invoke-Ini { return 0 }

        $iniAction = Get-IniAction

        $iniAction | Should -BeOfType [hashtable]
        $iniAction.Keys | Should -Contain 'command'
        $iniAction.Keys | Should -Contain 'description'
        $iniAction.Keys | Should -Contain 'usage'
        $iniAction.Keys | Should -Contain 'action'

        $code = & $iniAction.action -arguments @('set', 'memory_limit=256M')

        $code | Should -Be 0
        Should -Invoke Invoke-Ini -Times 1
    }
}

Describe "Get-ProfileAction" {
    It "Should return the profile action" {
        Mock Invoke-Profile { return 0 }

        $profileAction = Get-ProfileAction

        $profileAction | Should -BeOfType [hashtable]
        $profileAction.Keys | Should -Contain 'command'
        $profileAction.Keys | Should -Contain 'description'
        $profileAction.Keys | Should -Contain 'usage'
        $profileAction.Keys | Should -Contain 'action'

        $code = & $profileAction.action -arguments @('8.2.0')

        $code | Should -Be 0
        Should -Invoke Invoke-Profile -Times 1
    }
}

Describe "Get-InfoAction" {
    It "Should return the info action" {
        Mock Invoke-Info { return 0 }

        $infoAction = Get-InfoAction

        $infoAction | Should -BeOfType [hashtable]
        $infoAction.Keys | Should -Contain 'command'
        $infoAction.Keys | Should -Contain 'description'
        $infoAction.Keys | Should -Contain 'usage'
        $infoAction.Keys | Should -Contain 'action'

        $code = & $infoAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Info -Times 1
    }
}

Describe "Get-AliasesAction" {
    It "Should return the aliases action" {
        Mock Invoke-Aliases { return 0 }

        $aliasesAction = Get-AliasesAction

        $aliasesAction | Should -BeOfType [hashtable]
        $aliasesAction.Keys | Should -Contain 'command'
        $aliasesAction.Keys | Should -Contain 'description'
        $aliasesAction.Keys | Should -Contain 'usage'
        $aliasesAction.Keys | Should -Contain 'action'

        $code = & $aliasesAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Aliases -Times 1
    }
}

Describe "Get-LogAction" {
    It "Should return the log action" {
        Mock Invoke-Log { return 0 }

        $logAction = Get-LogAction

        $logAction | Should -BeOfType [hashtable]
        $logAction.Keys | Should -Contain 'command'
        $logAction.Keys | Should -Contain 'description'
        $logAction.Keys | Should -Contain 'usage'
        $logAction.Keys | Should -Contain 'action'

        $code = & $logAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Log -Times 1
    }
}

Describe "Get-RepairAction" {
    It "Should return the repair action" {
        Mock Invoke-Repair { return 0 }

        $repairAction = Get-RepairAction

        $repairAction | Should -BeOfType [hashtable]
        $repairAction.Keys | Should -Contain 'command'
        $repairAction.Keys | Should -Contain 'description'
        $repairAction.Keys | Should -Contain 'usage'
        $repairAction.Keys | Should -Contain 'action'

        $code = & $repairAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Repair -Times 1
    }
}

Describe "Get-CacheAction" {
    It "Should return the cache action" {
        Mock Invoke-Cache { return 0 }

        $cacheAction = Get-CacheAction

        $cacheAction | Should -BeOfType [hashtable]
        $cacheAction.Keys | Should -Contain 'command'
        $cacheAction.Keys | Should -Contain 'description'
        $cacheAction.Keys | Should -Contain 'usage'
        $cacheAction.Keys | Should -Contain 'action'

        $code = & $cacheAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Cache -Times 1
    }
}

Describe "Get-UpdateAction" {
    It "Should return the update action" {
        Mock Invoke-Update { return 0 }

        $updateAction = Get-UpdateAction

        $updateAction | Should -BeOfType [hashtable]
        $updateAction.Keys | Should -Contain 'command'
        $updateAction.Keys | Should -Contain 'description'
        $updateAction.Keys | Should -Contain 'usage'
        $updateAction.Keys | Should -Contain 'action'

        $code = & $updateAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Update -Times 1
    }
}

Describe "Get-TestAction" {
    It "Should return the test action" {
        Mock Invoke-Test { return 0 }

        $testAction = Get-TestAction

        $testAction | Should -BeOfType [hashtable]
        $testAction.Keys | Should -Contain 'command'
        $testAction.Keys | Should -Contain 'description'
        $testAction.Keys | Should -Contain 'usage'
        $testAction.Keys | Should -Contain 'action'

        $code = & $testAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Test -Times 1
    }
}

Describe "Get-RunAction" {
    It "Should return the run action" {
        Mock Invoke-Run { return 0 }

        $runAction = Get-RunAction

        $runAction | Should -BeOfType [hashtable]
        $runAction.Keys | Should -Contain 'command'
        $runAction.Keys | Should -Contain 'description'
        $runAction.Keys | Should -Contain 'usage'
        $runAction.Keys | Should -Contain 'action'

        $code = & $runAction.action -arguments @()

        $code | Should -Be 0
        Should -Invoke Invoke-Run -Times 1
    }
}

Describe "Get-Actions" {
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
            Mock Test-PVMSetup { $true }
            Mock Initialize-EnvironmentDirectoriesAndFiles { 0 }
            Mock New-EnvFile { 0 }
            Mock Initialize-PVM { 0 }
            Mock Optimize-SystemPath { 0 }
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
            Mock Initialize-PVM { -1 }
            Mock Optimize-SystemPath { -1 }

            $result = Invoke-Setup
            $result | Should -Be -1

            Should -Invoke Initialize-PVM -Times 1
            Should -Invoke Show-Error -ParameterFilter { $message -like '*Failed to optimize system path*' }
        }
    }
}
