# Comprehensive Tests for PVM Actions

# Load required modules and functions
. "$PSScriptRoot\..\src\core\router.ps1"


BeforeAll {
    Mock Write-Host {}
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
        }
        Process = @{}
        User = @{}
    }
    
    # Mock file system for logging tests
    $global:MockFileSystem = @{
        Directories = @()
        Files = @{}
    }
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
        # Mock Write-Host { }
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

    It "Should return -1 when no PHP version is set" {
        Mock Get-Current-PHP-Version { @{ version = $null; status = $null; path = $null } }
        
        $result = Invoke-PVMCurrent
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*No PHP version is currently set*" }
    }

    It "Should handle missing status information" {
        Mock Get-Current-PHP-Version { @{ version = "8.2.0"; status = $null; path = "C:\PHP\8.2.0" } }
        
        $result = Invoke-PVMCurrent
        $result | Should -Be -1
        
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
        
        Assert-MockCalled Get-Available-PHP-Versions -Times 1
        Assert-MockCalled Display-Installed-PHP-Versions -Times 0
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
        # Mock Write-Host { }
    }

    It "Should return -1 when no version is provided" {
        $arguments = @()
        
        $result = Invoke-PVMInstall -arguments $arguments
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please provide a PHP version to install*" }
    }

    It "Should install PHP with basic parameters" {
        $arguments = @("8.2.0")
        
        $result = Invoke-PVMInstall -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter { 
            $version -eq "8.2.0"
        }
    }

    It "Should install detected PHP version from the project" {
        $arguments = @("auto")

        Mock Detect-PHP-VersionFromProject { return "8.1" }
        $result = Invoke-PVMInstall -arguments $arguments
        $result | Should -Be 0

        Assert-MockCalled Install-PHP -Times 1 -ParameterFilter { 
            $version -eq "8.1"
        }
    }
}

Describe "Invoke-PVMUninstall Tests" {
    BeforeEach {
        Mock Get-Current-PHP-Version { @{ version = "8.1.0" } }
        Mock Uninstall-PHP { @{ code = 0; message = "Uninstalled successfully" } }
        Mock Display-Msg-By-ExitCode { }
        # Mock Write-Host { }
        Mock Read-Host { }
    }

    It "Should return -1 when no version is provided" {
        $arguments = @()
        
        $result = Invoke-PVMUninstall -arguments $arguments
        $result | Should -Be -1
        
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
        # Mock Write-Host { }
    }

    It "Should return -1 when no version is provided" {
        $arguments = @()
        
        $result = Invoke-PVMUse -arguments $arguments
        $result | Should -Be -1
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Please provide a PHP version to use*" }
    }

    It "Should use specific PHP version" {
        $arguments = @("8.2.0")
        
        $result = Invoke-PVMUse -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Update-PHP-Version -Times 1 -ParameterFilter { 
            $version -eq "8.2.0" 
        }
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
    }

    It "Should handle 'auto' version selection successfully" {
        $arguments = @("auto")
        
        $result = Invoke-PVMUse -arguments $arguments
        $result | Should -Be 0
        
        Assert-MockCalled Auto-Select-PHP-Version -Times 1
        Assert-MockCalled Update-PHP-Version -Times 1 -ParameterFilter { $version -eq "8.2.0" }
    }

    It "Should return -1 when auto-selection fails" {
        Mock Auto-Select-PHP-Version { @{ code = 1; message = "Auto selection failed" } }
        $arguments = @("auto")
        
        $result = Invoke-PVMUse -arguments $arguments
        $result | Should -Be -1
        
        Assert-MockCalled Auto-Select-PHP-Version -Times 1
        Assert-MockCalled Display-Msg-By-ExitCode -Times 1
        Assert-MockCalled Update-PHP-Version -Times 0
    }
}

Describe "Invoke-PVMIni Tests" {
    BeforeEach {
        Mock Invoke-PVMIniAction { 0 }
        # Mock Write-Host { }
    }

    It "Should return -1 when no action is provided" {
        $arguments = @()
        
        $result = Invoke-PVMIni -arguments $arguments
        $result | Should -Be -1
        
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

Describe "Invoke-PVMLog Tests" {
    BeforeAll {
        # Default log page size value for tests
        $global:DefaultLogPageSize = 5
        Mock Show-Log { 0 }
    }
    
    It "Calls Show-Log with provided --pageSize argument" {
        $arguments = @("--pageSize=5")
        Invoke-PVMLog -arguments $arguments | Should -Be 0

        Assert-MockCalled Show-Log -Exactly 1 -ParameterFilter { $pageSize -eq "5" }
    }
    
    It "Calls Show-Log with default page size when no argument is given" {
        $arguments = @()
        Invoke-PVMLog -arguments $arguments | Should -Be 0

        Assert-MockCalled Show-Log -Exactly 1 -ParameterFilter { $pageSize -eq 5 }
    }
    
    It "Passes return code from Show-Log back to caller" {
        Mock Show-Log { return 0 }
        (Invoke-PVMLog -arguments @("--pageSize=2")) | Should -Be 0

        Mock Show-Log { return -1 }
        (Invoke-PVMLog -arguments @("--pageSize=2")) | Should -Be -1
    }
}

Describe "Invoke-PVMHelp Tests" {
    
    It "Should display help for setup command" {
        $result = Invoke-PVMHelp -arguments @("setup")
        $result | Should -Be 0
    }
    
    It "Should return -1 for non-existent usage" {
        $result = Invoke-PVMHelp -arguments @("nonexistent")
        $result | Should -Be -1
    }
    
    It "Should display general help when no command is provided" {
        $result = Invoke-PVMHelp -arguments @()
        $result | Should -Be 0
    }
}

Describe "Invoke-PVMTest Tests" {
    BeforeAll {
        Mock Run-Tests { @{ code = 0; message = "Tests passed" } }
    }
    
    It "Should call Run-Tests with no arguments" {
        $result = Invoke-PVMTest -arguments @()
        $result | Should -Be 0
    }
    
    It "Should call Run-Tests with provided arguments" {
        $result = Invoke-PVMTest -arguments @("TestFile.ps1", "TestFile2.ps1", "--coverage", "--verbosity=detailed", "--tag=unit", "--target=75")
        $result | Should -Be 0
    }
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
    }

    It "Should return ordered hashtable with all actions" {
        $arguments = @("test", "arg")
        $actions = Get-Actions -arguments $arguments
        
        $actions | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $actions.Keys | Should -Contain "help"
        $actions.Keys | Should -Contain "setup"
        $actions.Keys | Should -Contain "current"
        $actions.Keys | Should -Contain "list"
        $actions.Keys | Should -Contain "install"
        $actions.Keys | Should -Contain "uninstall"
        $actions.Keys | Should -Contain "use"
        $actions.Keys | Should -Contain "info"
        $actions.Keys | Should -Contain "ini"
        $actions.Keys | Should -Contain "test"
        $actions.Keys | Should -Contain "log"
    }

    It "Should set script-level arguments variable" {
        $testArgs = @("arg1", "arg2")
        Get-Actions -arguments $testArgs
        
        $script:arguments | Should -Be $testArgs
    }

    Context "Action Execution Tests" {
        It "Should execute help action correctly" {
            $actions = Get-Actions -arguments @()
            $actions["help"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMHelp -Times 1
        }
        
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
            $testArgs = @("available")
            $actions = Get-Actions -arguments $testArgs
            $actions["list"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMList -Times 1
        }
        
        It "Should execute install action correctly" {
            $actions = Get-Actions -arguments @("8.2.0")
            $actions["install"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMInstall -Times 1
        }
        
        It "Should execute uninstall action correctly" {
            $actions = Get-Actions -arguments @("8.2.0")
            $actions["uninstall"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMUninstall -Times 1
        }
        
        It "Should execute use action correctly" {
            $actions = Get-Actions -arguments @("8.2.0")
            $actions["use"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMUse -Times 1
        }
        
        It "Should execute ini action correctly" {
            $actions = Get-Actions -arguments @("set", "memory_limit=256M")
            $actions["ini"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMIni -Times 1
        }
        
        It "Should execute info action" {
            $actions = Get-Actions -arguments @()
            $actions["info"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMIni -Times 1
        }
        
        It "Should execute log action" {
            $actions = Get-Actions -arguments @("--pageSize=10")
            $actions["log"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMLog -Times 1
        }
        
        It "Should execute test action with verbosity" {
            $testArgs = @("TestFile.ps1", "Detailed", "--tag=unit")
            $actions = Get-Actions -arguments $testArgs
            $actions["test"].action.Invoke()
            
            Assert-MockCalled Invoke-PVMTest -Times 1
        }
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
            # Mock Write-Host { }
        }

        It "Should handle complete workflow: setup -> install -> use -> current" {
            # Setup
            $result = Invoke-PVMSetup
            $result | Should -Be 0
            
            # Install
            $result = Invoke-PVMInstall -arguments @("8.2.0")
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
            # Mock Write-Host { }
            
            $result = Invoke-PVMSetup
            $result | Should -Be 0
            
            Assert-MockCalled Setup-PVM -Times 1
            Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Failed to optimize system path*" }
            Assert-MockCalled Display-Msg-By-ExitCode -Times 1
        }
    }
}