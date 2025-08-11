# Comprehensive Tests for PVM Actions

# Load required modules and functions
. "$PSScriptRoot\..\src\core\router.ps1"


BeforeAll {
    # Global mock registry for environment variables
    $global:MockRegistry = @{
        Machine = @{
            "Path" = "C:\Windows\System32;C:\Program Files\Git\bin;C:\CustomApp;C:\Program Files\Java\bin"
            "JAVA_HOME" = "C:\Program Files\Java"
            "GIT_HOME" = "C:\Program Files\Git\bin"
            "CUSTOM_APP" = "C:\CustomApp"
            "WINDOWS_DIR" = "C:\Windows"
            "SYSTEM32_DIR" = "C:\Windows\System32"
            "REGULAR_VAR" = "SomeValue"
            "PHP_CURRENT_ENV_NAME" = "8.2.0"
        }
        Process = @{}
        User = @{}
    }
    
    # Mock file system for logging tests
    $global:MockFileSystem = @{
        Directories = @()
        Files = @{}
    }

    # Mock variables
    $global:PHP_CURRENT_ENV_NAME = "PHP"
}


Describe "Invoke-PVMSetup Tests" {
    BeforeEach {
        Mock Is-PVM-Setup { $true }
        Mock Setup-PVM { @{ code = 0; message = "Setup completed" } }
        Mock Optimize-SystemPath { 0 }
        Mock Display-Msg-By-ExitCode { }
        Mock Write-Host { }
    }

    It "Should return 0 when PVM is already setup" {
        Mock Is-PVM-Setup { $true }
        
        $result = Invoke-PVMSetup
        $result | Should -Be 0
        
        Assert-MockCalled Is-PVM-Setup -Times 1
        Assert-MockCalled Setup-PVM -Times 0
        Assert-MockCalled Optimize-SystemPath -Times 1
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }

    It "Should setup PVM when not already setup" {
        Mock Is-PVM-Setup { $false }
        Mock Setup-PVM { @{ code = 0; message = "Setup completed successfully" } }
        
        $result = Invoke-PVMSetup
        $result | Should -Be 0
        
        Assert-MockCalled Is-PVM-Setup -Times 1
        Assert-MockCalled Setup-PVM -Times 1
        Assert-MockCalled Optimize-SystemPath -Times 1
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }

    It "Should display warning when system path optimization fails" {
        Mock Optimize-SystemPath { 1 }
        
        $result = Invoke-PVMSetup
        $result | Should -Be 0
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Failed to optimize system path*" -and $ForegroundColor -eq "DarkYellow" }
    }
}

Describe "Invoke-PVMCurrent Tests" {
    BeforeEach {
        Mock Get-Current-PHP-Version { @{ version = "8.2.0"; status = @{ "xdebug" = $true; "opcache" = $false }; path = "C:\PHP\8.2.0" } }
        Mock Write-Host { }
    }

    It "Should display current PHP version and extensions when version is set" {
        $result = Invoke-PVMCurrent
        $result | Should -Be 0
        
        Assert-MockCalled Get-Current-PHP-Version -Times 1
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Running version: PHP 8.2.0*" }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*xdebug is enabled*" -and $ForegroundColor -eq "DarkGreen" }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*opcache is disabled*" -and $ForegroundColor -eq "DarkYellow" }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Path: C:\PHP\8.2.0*" -and $ForegroundColor -eq "Gray" }
    }

    It "Should return 1 when no PHP version is set" {
        Mock Get-Current-PHP-Version { @{ version = $null; status = $null; path = $null } }
        
        $result = Invoke-PVMCurrent
        $result | Should -Be 1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*No PHP version is currently set*" }
    }

    It "Should handle missing status information" {
        Mock Get-Current-PHP-Version { @{ version = "8.2.0"; status = $null; path = "C:\PHP\8.2.0" } }
        
        $result = Invoke-PVMCurrent
        $result | Should -Be 1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*No status information available*" -and $ForegroundColor -eq "Yellow" }
    }
}

Describe "Invoke-PVMList Tests" {
    BeforeEach {
        Mock Get-Available-PHP-Versions { return 0 }
        Mock Display-Installed-PHP-Versions { return 0 }
    }

    It "Should call Get-Available-PHP-Versions when 'available' argument is provided" {
        $arguments = @("available")
        
        $result = Invoke-PVMList -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Get-Available-PHP-Versions -Times 1 -ParameterFilter { $getFromSource -eq $false }
        Assert-MockCalled Display-Installed-PHP-Versions -Times 0
    }

    It "Should call Get-Available-PHP-Versions with force when '-f' flag is provided" {
        $arguments = @("available", "-f")
        
        $result = Invoke-PVMList -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Get-Available-PHP-Versions -Times 1 -ParameterFilter { $getFromSource -eq $true }
    }

    It "Should call Get-Available-PHP-Versions with force when '--force' flag is provided" {
        $arguments = @("available", "--force")
        
        $result = Invoke-PVMList -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Get-Available-PHP-Versions -Times 1 -ParameterFilter { $getFromSource -eq $true }
    }

    It "Should call Display-Installed-PHP-Versions when no 'available' argument" {
        $arguments = @()
        
        $result = Invoke-PVMList -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Display-Installed-PHP-Versions -Times 1
        Assert-MockCalled Get-Available-PHP-Versions -Times 0
    }
}

Describe "Invoke-PVMInstall Tests" {
    BeforeEach {
        Mock Install-PHP { 0 }
        Mock Write-Host { }
    }

    It "Should return 1 when no version is provided" {
        $arguments = @()
        
        $result = Invoke-PVMInstall -arguments $arguments
        $result | Should -Be 1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please provide a PHP version to install*" }
    }

    It "Should install PHP with basic parameters" {
        $arguments = @("8.2.0")
        
        $result = Invoke-PVMInstall -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter { 
            $version -eq "8.2.0" -and 
            $includeXDebug -eq $false -and 
            $enableOpcache -eq $false 
        }
    }


    It "Should handle --xdebug flag" {
        $arguments = @("8.2.0", "--xdebug")
        
        $result = Invoke-PVMInstall -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter { $includeXDebug -eq $true }
    }

    It "Should handle --opcache flag" {
        $arguments = @("8.2.0", "--opcache")
        
        $result = Invoke-PVMInstall -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter { $enableOpcache -eq $true }
    }

    It "Should handle multiple flags together" {
        $arguments = @("8.2.0", "--xdebug", "--opcache")
        
        $result = Invoke-PVMInstall -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter { 
            $version -eq "8.2.0" -and 
            $includeXDebug -eq $true -and 
            $enableOpcache -eq $true 
        }
    }
}

Describe "Invoke-PVMUninstall Tests" {
    BeforeEach {
        Mock Get-Current-PHP-Version { @{ version = "8.1.0" } }
        Mock Uninstall-PHP { @{ code = 0; message = "Uninstalled successfully" } }
        Mock Display-Msg-By-ExitCode { }
        Mock Write-Host { }
        Mock Read-Host { }
    }

    It "Should return 1 when no version is provided" {
        $arguments = @()
        
        $result = Invoke-PVMUninstall -arguments $arguments
        $result | Should -Be 1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please provide a PHP version to uninstall*" }
    }

    It "Should uninstall PHP version successfully" {
        $arguments = @("8.2.0")
        
        $result = Invoke-PVMUninstall -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Uninstall-PHP -Times 1 -ParameterFilter { $version -eq "8.2.0" }
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }


    It "Should not prompt when uninstalling different version than current" {
        Mock Get-Current-PHP-Version { @{ version = "8.1.0" } }
        $arguments = @("8.2.0")
        
        $result = Invoke-PVMUninstall -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Read-Host -Times 0
        Assert-MockCalled Uninstall-PHP -Times 1
    }
}

Describe "Invoke-PVMUse Tests" {
    BeforeEach {
        Mock Auto-Select-PHP-Version { @{ code = 0; version = "8.2.0" } }
        Mock Update-PHP-Version { @{ code = 0; message = "Version updated" } }
        Mock Display-Msg-By-ExitCode { }
        Mock Write-Host { }
    }

    It "Should return 1 when no version is provided" {
        $arguments = @()
        
        $result = Invoke-PVMUse -arguments $arguments
        $result | Should -Be 1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please provide a PHP version to use*" }
    }

    It "Should use specific PHP version" {
        $arguments = @("8.2.0")
        
        $result = Invoke-PVMUse -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Update-PHP-Version -Times 1 -ParameterFilter { 
            $variableName -eq $PHP_CURRENT_ENV_NAME -and 
            $variableValue -eq "8.2.0" 
        }
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }

    It "Should handle 'auto' version selection successfully" {
        $arguments = @("auto")
        
        $result = Invoke-PVMUse -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Auto-Select-PHP-Version -Times 1
        Assert-MockCalled Update-PHP-Version -Times 1 -ParameterFilter { $variableValue -eq "8.2.0" }
    }

    It "Should return 1 when auto-selection fails" {
        Mock Auto-Select-PHP-Version { @{ code = 1; message = "Auto selection failed" } }
        $arguments = @("auto")
        
        $result = Invoke-PVMUse -arguments $arguments
        $result | Should -Be 1
        
        Assert-MockCalled Auto-Select-PHP-Version -Times 1
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
        Assert-MockCalled Update-PHP-Version -Times 0
    }
}

Describe "Invoke-PVMIni Tests" {
    BeforeEach {
        Mock Invoke-PVMIniAction { 0 }
        Mock Write-Host { }
    }

    It "Should return 1 when no action is provided" {
        $arguments = @()
        
        $result = Invoke-PVMIni -arguments $arguments
        $result | Should -Be 1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please specify an action for 'pvm ini'*" }
    }

    It "Should call Invoke-PVMIniAction with correct parameters for single action" {
        $arguments = @("set")
        
        $result = Invoke-PVMIni -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Invoke-PVMIniAction -Times 1 -ParameterFilter { 
            $action -eq "set" -and 
            $params.Count -eq 0 
        }
    }

    It "Should call Invoke-PVMIniAction with remaining arguments" {
        $arguments = @("set", "memory_limit", "256M")
        
        $result = Invoke-PVMIni -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Invoke-PVMIniAction -Times 1 -ParameterFilter { 
            $action -eq "set" -and 
            $params.Count -eq 2 -and 
            $params[0] -eq "memory_limit" -and 
            $params[1] -eq "256M" 
        }
    }

    It "Should handle different actions correctly" {
        $testActions = @("get", "enable", "disable", "restore")
        
        foreach ($testAction in $testActions) {
            $arguments = @($testAction, "param1", "param2")
            
            $result = Invoke-PVMIni -arguments $arguments
            $result | Should -Be 0
            
            Assert-MockCalled Invoke-PVMIniAction -ParameterFilter { $action -eq $testAction }
        }
    }
}

Describe "Invoke-PVMSet Tests" {
    BeforeEach {
        Mock Set-PHP-Env { @{ code = 0; message = "Environment variable set" } }
        Mock Display-Msg-By-ExitCode { }
        Mock Write-Host { }
    }

    It "Should return 1 when no variable name is provided" {
        $arguments = @()
        
        $result = Invoke-PVMSet -arguments $arguments
        $result | Should -Be 1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please provide an environment variable name*" }
    }

    It "Should return 1 when no variable value is provided" {
        $arguments = @("MY_VAR")
        
        $result = Invoke-PVMSet -arguments $arguments
        $result | Should -Be 1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please provide an environment variable value*" }
    }

    It "Should set environment variable successfully" {
        $arguments = @("MY_VAR", "MY_VALUE")
        
        $result = Invoke-PVMSet -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Set-PHP-Env -Times 1 -ParameterFilter { 
            $name -eq "MY_VAR" -and 
            $value -eq "MY_VALUE" 
        }
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }
}

Describe "Get-Actions Tests" {
    BeforeEach {
        Mock Invoke-PVMSetup { }
        Mock Invoke-PVMCurrent { }
        Mock Invoke-PVMList { }
        Mock Invoke-PVMInstall { }
        Mock Invoke-PVMUninstall { }
        Mock Invoke-PVMUse { }
        Mock Invoke-PVMIni { }
        Mock Invoke-PVMSet { }
        Mock Run-Tests { }
    }

    It "Should return ordered hashtable with all actions" {
        $arguments = @("test", "arg")
        $actions = Get-Actions -arguments $arguments
        
        $actions | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $actions.Keys | Should -Contain "setup"
        $actions.Keys | Should -Contain "current"
        $actions.Keys | Should -Contain "list"
        $actions.Keys | Should -Contain "install"
        $actions.Keys | Should -Contain "uninstall"
        $actions.Keys | Should -Contain "use"
        $actions.Keys | Should -Contain "ini"
        $actions.Keys | Should -Contain "set"
        $actions.Keys | Should -Contain "test"
    }

    It "Should set script-level arguments variable" {
        $testArgs = @("arg1", "arg2")
        Get-Actions -arguments $testArgs
        
        $script:arguments | Should -Be $testArgs
    }

    Context "Action Execution Tests" {
        It "Should execute setup action correctly" {
            $actions = Get-Actions -arguments @()
            $actions["setup"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMSetup -Times 1
        }

        It "Should execute current action correctly" {
            $actions = Get-Actions -arguments @()
            $actions["current"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMCurrent -Times 1
        }

        It "Should execute list action with arguments" {
            $testArgs = @("available", "-f")
            $actions = Get-Actions -arguments $testArgs
            $actions["list"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMList -Times 1
        }

        It "Should execute test action with basic arguments" {
            Mock Run-Tests { }
            $testArgs = @("TestFile.ps1")
            $actions = Get-Actions -arguments $testArgs
            $actions["test"].action.Invoke()
            
            Assert-MockCalled Run-Tests -Times 1 -ParameterFilter { 
                $verbosity -eq "Normal" -and 
                $tests -contains "TestFile.ps1" 
            }
        }

        It "Should execute test action with verbosity" {
            Mock Run-Tests { }
            $testArgs = @("TestFile.ps1", "Detailed")
            $actions = Get-Actions -arguments $testArgs
            $actions["test"].action.Invoke()
            
            Assert-MockCalled Run-Tests -Times 1 -ParameterFilter { 
                $verbosity -eq "Detailed" -and 
                $tests -contains "TestFile.ps1" 
            }
        }

        It "Should execute test action with tag filtering" {
            Mock Run-Tests { }
            $testArgs = @("--tag=unit", "TestFile.ps1")
            $actions = Get-Actions -arguments $testArgs
            $actions["test"].action.Invoke()
            
            # Note: The tag variable should be set from the regex match
            Assert-MockCalled Run-Tests -Times 1 -ParameterFilter { 
                $tests -contains "TestFile.ps1" 
            }
        }

        It "Should execute test action with only verbosity (no files)" {
            Mock Run-Tests { }
            $testArgs = @("Diagnostic")
            $actions = Get-Actions -arguments $testArgs
            $actions["test"].action.Invoke()
            
            Assert-MockCalled Run-Tests -Times 1 -ParameterFilter { 
                $verbosity -eq "Diagnostic" -and 
                ($tests -eq $null -or $tests.Count -eq 0)
            }
        }
    }
}

Describe "Show-Usage Tests" {
    BeforeEach {
        Mock Get-Current-PHP-Version { @{ version = "8.2.0" } }
        Mock Write-Host { }
        
        # Mock the Get-Actions function to return a predictable set
        Mock Get-Actions { 
            [ordered]@{
                "setup" = [PSCustomObject]@{
                    command = "pvm setup"
                    description = "Setup the environment variables and paths for PHP."
                }
                "current" = [PSCustomObject]@{
                    command = "pvm current"
                    description = "Display active version."
                }
            }
        }
        
        # Set the $actions variable that Show-Usage expects
        $script:actions = Get-Actions
    }

    It "Should display current version when available" {
        Show-Usage
        
        Assert-MockCalled Get-Current-PHP-Version -Times 1
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Running version : 8.2.0*" }
    }

    It "Should not display version when none is set" {
        Mock Get-Current-PHP-Version { @{ version = $null } }
        
        Show-Usage
        
        Assert-MockCalled Get-Current-PHP-Version -Times 1
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Running version*" } -Times 0
    }

    It "Should display usage header" {
        Show-Usage
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Usage:*" }
    }

    It "Should display all available commands with descriptions" {
        Show-Usage
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*pvm setup*Setup the environment*" }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*pvm current*Display active version*" }
    }
}

Describe "Integration Tests" {
    Context "Command Flow Integration" {
        BeforeEach {
            # Setup comprehensive mocks for integration testing
            Mock Is-PVM-Setup { $true }
            Mock Setup-PVM { @{ code = 0; message = "Setup completed" } }
            Mock Optimize-SystemPath { 0 }
            Mock Display-Msg-By-ExitCode { }
            Mock Get-Current-PHP-Version { @{ version = "8.2.0"; status = @{ "xdebug" = $true }; path = "C:\PHP\8.2.0" } }
            Mock Install-PHP { 0 }
            Mock Update-PHP-Version { @{ code = 0; message = "Version updated" } }
            Mock Write-Host { }
        }

        It "Should handle complete workflow: setup -> install -> use -> current" {
            # Setup
            $result = Invoke-PVMSetup
            $result | Should -Be 0
            
            # Install
            $result = Invoke-PVMInstall -arguments @("8.2.0", "--xdebug")
            $result | Should -Be 0
            
            # Use
            $result = Invoke-PVMUse -arguments @("8.2.0")
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
            Mock Setup-PVM { @{ code = 1; message = "Setup failed" } }
            Mock Optimize-SystemPath { 1 }
            Mock Display-Msg-By-ExitCode { }
            Mock Write-Host { }
            
            $result = Invoke-PVMSetup
            $result | Should -Be 0
            
            Assert-MockCalled Setup-PVM -Times 1
            Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Failed to optimize system path*" }
            Assert-MockCalled Display-Msg-By-ExitCode -Times 1
        }
    }
}