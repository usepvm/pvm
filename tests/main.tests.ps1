BeforeAll {
    # Mock global variables that would be loaded from config
    $global:PVM_VERSION = "1.0.0"
    $global:LOG_ERROR_PATH = "TestDrive:\logs\error.log"
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
        $global:PVM_VERSION = "2.0"
        Show-Usage
        
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like "*Running version : 2.0*" }
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


Describe "Show-PVM-Version Function Tests" {
    BeforeEach {
        Mock Write-Host { }
        $global:PVM_VERSION = "1.2.3"
    }

    It "Should display version with proper formatting" {
        Show-PVM-Version
        
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPVM version 1.2.3" 
        }
    }

    It "Should display version when PVM_VERSION is null" {
        $global:PVM_VERSION = $null
        Show-PVM-Version
        
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPVM version " 
        }
    }

    It "Should display version when PVM_VERSION is empty string" {
        $global:PVM_VERSION = ""
        Show-PVM-Version
        
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPVM version " 
        }
    }

    It "Should display version with different version formats" {
        $testVersions = @("1.0.0", "2.5.1-beta", "3.0.0-alpha.1", "v1.0.0", "1.0.0.0")
        
        foreach ($version in $testVersions) {
            $global:PVM_VERSION = $version
            Show-PVM-Version
            
            Assert-MockCalled Write-Host -ParameterFilter { 
                $Object -eq "`nPVM version $version" 
            }
        }
    }

    It "Should handle special characters in version" {
        $global:PVM_VERSION = "1.0.0-RC1+build.123"
        Show-PVM-Version
        
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPVM version 1.0.0-RC1+build.123" 
        }
    }
}

Describe "Alias-Handler Tests" {
    $testCases = @(
        @{ Operation = "ls"; Expected = "list" }
        @{ Operation = "rm"; Expected = "uninstall" }
        @{ Operation = "i"; Expected = "install" }
        @{ Operation = "LS"; Expected = "list" }
        @{ Operation = "RM"; Expected = "uninstall" }
        @{ Operation = "I"; Expected = "install" }
        @{ Operation = "install"; Expected = "install" }
        @{ Operation = "list"; Expected = "list" }
        @{ Operation = "uninstall"; Expected = "uninstall" }
        @{ Operation = "unknown"; Expected = "unknown" }
        @{ Operation = ""; Expected = $null }
        @{ Operation = "    "; Expected = $null }
        @{ Operation = $null; Expected = $null }
    )
    
    It "Returns '<Expected>' when '<Operation>' is passed" -TestCases $testCases {
        param($Operation, $Expected)
        $result = Alias-Handler $Operation
        $result | Should -Be $Expected
    }
}

Describe "Start-PVM Function Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Show-PVM-Version { }
        Mock Get-Actions { 
            [ordered]@{
                "setup" = [PSCustomObject]@{ action = { return 0 } }
                "install" = [PSCustomObject]@{ action = { return 0 } }
                "use" = [PSCustomObject]@{ action = { return 0 } }
                "list" = [PSCustomObject]@{ action = { return 0 } }
            }
        }
        Mock Is-PVM-Setup { $true }
        Mock Log-Data { $true }
        Mock Alias-Handler {
            param($alias)


            if ([string]::IsNullOrWhiteSpace($alias)) {
                return $null
            }

            $alias = $alias.ToLower().Trim()
            switch ($alias) {
                "ls" { return "list" }
                "rm" { return "uninstall" }
                "i"  { return "install" }
                Default { return $alias }
            }
        }
        
        $global:PVM_VERSION = "1.2.3"
    }

    Context "Version Display Path Tests" {
        It "Should show version and return 0 with --version argument" {
            $result = Start-PVM -operation "install" -arguments @("--version")
            
            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should show version and return 0 with -v argument" {
            $result = Start-PVM -operation "install" -arguments @("-v")
            
            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should show version and return 0 with version operation" {
            $result = Start-PVM -operation "version" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should show version when both version flag and version operation are present" {
            $result = Start-PVM -operation "version" -arguments @("--version")
            
            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
        }

        It "Should show version with --version in mixed arguments" {
            $result = Start-PVM -operation "install" -arguments @("8.2.0", "--version", "extra")
            
            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
        }

        It "Should show version with -v in mixed arguments" {
            $result = Start-PVM -operation "use" -arguments @("8.1.0", "-v", "--force")
            
            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
        }

        It "Should not show version with partial matches" {
            $result = Start-PVM -operation "install" -arguments @("--verbose", "-version")
            
            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 0
            Assert-MockCalled Get-Actions -Times 1
        }
    }

    Context "Operation Validation Path Tests" {
        It "Should show usage and return 0 when operation is null" {
            $result = Start-PVM -operation $null -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Alias-Handler -Times 1
        }

        It "Should show usage and return 0 when operation is empty string" {
            $result = Start-PVM -operation "" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Alias-Handler -Times 1
        }

        It "Should show usage and return 0 when operation is whitespace" {
            $result = Start-PVM -operation "   " -arguments @()
            
            $result = Start-PVM -operation "   " -arguments @()
            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
        }

        It "Should show usage and return 0 when operation not in actions" {
            $result = Start-PVM -operation "invalid-operation" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Alias-Handler -Times 1
        }

        It "Should proceed when operation exists in actions" {
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 0
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Alias-Handler -Times 1
        }

        It "Should handle alias conversion correctly" {
            
            $result = Start-PVM -operation "i" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Alias-Handler -Times 1 -ParameterFilter { $alias -eq "i" }
            Assert-MockCalled Show-Usage -Times 0
        }

        # It "Should handle case where Get-Actions returns null" {
        #     Mock Get-Actions { $null }
            
        #     $result = Start-PVM -operation "install" -arguments @()
            
        #     $result | Should -Be 0
        #     Assert-MockCalled Show-Usage -Times 1
        # }

        It "Should handle case where Get-Actions returns empty hashtable" {
            Mock Get-Actions { @{} }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
        }
    }

    Context "Setup Validation Path Tests" {
        It "Should skip setup check for setup operation" {
            Mock Is-PVM-Setup { $false }
            
            $result = Start-PVM -operation "setup" -arguments @()
            
            $result | Should -Be 0
            # The setup check condition should not evaluate Is-PVM-Setup for setup operation
            Assert-MockCalled Is-PVM-Setup -Times 0
        }

        It "Should require setup when PVM is not setup for non-setup operation" {
            Mock Is-PVM-Setup { $false }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be -1
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
                $Object -eq "`nPVM is not setup. Please run 'pvm setup' first." 
            }
        }

        It "Should proceed when PVM is setup for non-setup operation" {
            Mock Is-PVM-Setup { $true }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Write-Host -Times 0 -ParameterFilter { 
                $Object -like "*PVM is not setup*" 
            }
        }

        It "Should handle different operations requiring setup check" {
            $operationsRequiringSetup = @("install", "use", "list", "current", "remove")
            Mock Is-PVM-Setup { $false }
            
            foreach ($op in $operationsRequiringSetup) {
                Mock Get-Actions { 
                    [ordered]@{
                        $op = [PSCustomObject]@{ action = { return 0 } }
                    }
                }
                
                $result = Start-PVM -operation $op -arguments @()
                
                $result | Should -Be -1
                Assert-MockCalled Write-Host -ParameterFilter { 
                    $Object -eq "`nPVM is not setup. Please run 'pvm setup' first." 
                }
            }
        }
    }

    Context "Action Execution Path Tests" {
        It "Should execute action and return 0" {
            Mock Get-Actions {
                [ordered]@{
                    "install" = [PSCustomObject]@{ action = { return 0 } }
                }
            }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be 0
        }

        It "Should execute action and return non-zero exit code" {
            Mock Get-Actions {
                [ordered]@{
                    "install" = [PSCustomObject]@{ action = { return 1 } }
                }
            }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be 1
        }

        It "Should execute action and return custom exit code" {
            Mock Get-Actions {
                [ordered]@{
                    "use" = [PSCustomObject]@{ action = { return 42 } }
                }
            }
            
            $result = Start-PVM -operation "use" -arguments @()
            
            $result | Should -Be 42
        }

        # It "Should handle action that returns null" {
        #     Mock Get-Actions {
        #         [ordered]@{
        #             "test" = [PSCustomObject]@{ action = { return $null } }
        #         }
        #     }
            
        #     $result = Start-PVM -operation "test" -arguments @()
            
        #     # $null should be treated as 0 in PowerShell context
        #     $result | Should -Be 0
        # }

        It "Should execute complex action logic" {
            Mock Test-Path { $true }
            Mock Get-Actions {
                [ordered]@{
                    "test" = [PSCustomObject]@{ 
                        action = { 
                            if (Test-Path "C:\Test") { return 0 } else { return 1 }
                        } 
                    }
                }
            }
            
            $result = Start-PVM -operation "test" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Test-Path -Times 1
        }
    }

    Context "Error Handling Path Tests" {
        It "Should catch exception and return 1" {
            Mock Get-Actions {
                [ordered]@{
                    "install" = [PSCustomObject]@{ 
                        action = { throw "Test exception" }
                    }
                }
            }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $Object -eq "`nOperation canceled or failed to elevate privileges." -and
                $ForegroundColor -eq "DarkYellow"
            }
        }

        It "Should handle exception with proper logging data" {
            Mock Get-Actions {
                [ordered]@{
                    "install" = [PSCustomObject]@{ 
                        action = { throw "Detailed test exception" }
                    }
                }
            }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.header -eq "Start-PVM - An error occurred during operation 'install'" -and
                $data.exception.Exception.Message -like "*Detailed test exception*"
            }
        }

        It "Should handle different exception types" {
            $exceptions = @(
                [System.UnauthorizedAccessException]::new("Access denied"),
                [System.IO.FileNotFoundException]::new("File not found"),
                [System.ArgumentException]::new("Invalid argument"),
                [System.InvalidOperationException]::new("Invalid operation state")
            )
            
            foreach ($exception in $exceptions) {
                Mock Get-Actions {
                    [ordered]@{
                        "test" = [PSCustomObject]@{ 
                            action = { throw $exception }
                        }
                    }
                }
                
                $result = Start-PVM -operation "test" -arguments @()
                
                $result | Should -Be -1
                Assert-MockCalled Log-Data -ParameterFilter {
                    $data.exception.Exception.Message -like "*$($exception.Message)*"
                }
            }
        }

        It "Should handle exception during Get-Actions call" {
            Mock Get-Actions { throw "Get-Actions failed" }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.exception.Exception.Message -like "*Get-Actions failed*"
            }
        }

        It "Should handle exception during Alias-Handler call" {
            Mock Alias-Handler { throw "Alias handler failed" }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.exception.Exception.Message -like "*Alias handler failed*"
            }
        }

        It "Should handle exception during Is-PVM-Setup call" {
            Mock Is-PVM-Setup { throw "Setup check failed" }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.exception.Exception.Message -like "*Setup check failed*"
            }
        }

        It "Should handle exception when Log-Data fails" {
            Mock Log-Data { $false }
            Mock Get-Actions {
                [ordered]@{
                    "install" = [PSCustomObject]@{ 
                        action = { throw "Test exception" }
                    }
                }
            }
            
            $result = Start-PVM -operation "install" -arguments @()
            
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $ForegroundColor -eq "DarkYellow"
            }
        }

        It "Should handle null operation in exception logging" {
            Mock Get-Actions { throw "Early exception" }
            
            $result = Start-PVM -operation $null -arguments @()
            
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.header -eq "Start-PVM - An error occurred during operation ''"
            }
        }
    }

    Context "Edge Cases and Boundary Tests" {
        It "Should handle null arguments parameter" {
            $result = Start-PVM -operation "setup" -arguments $null
            
            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1 -ParameterFilter { $arguments -eq $null }
        }

        It "Should handle empty arguments array" {
            $result = Start-PVM -operation "setup" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1 -ParameterFilter { $arguments.Count -eq 0 }
        }

        It "Should handle large arguments array" {
            $largeArgs = 1..100 | ForEach-Object { "arg$_" }
            
            $result = Start-PVM -operation "setup" -arguments $largeArgs
            
            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1 -ParameterFilter { $arguments.Count -eq 100 }
        }

        It "Should handle version flag with other parameters" {
            $result = Start-PVM -operation "install" -arguments @("8.2.0", "--version", "--force", "extra")
            
            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            # Should short-circuit before other calls
            Assert-MockCalled Get-Actions -Times 0
        }

        It "Should handle multiple operations through alias handler" {
            Mock Alias-Handler { param($alias) 
                switch ($alias) {
                    "i" { return "install" }
                    "u" { return "use" }
                    "l" { return "list" }
                    default { return $alias }
                }
            }
            
            $testCases = @(
                @{ input = "i"; expected = "install" },
                @{ input = "u"; expected = "use" },
                @{ input = "l"; expected = "list" },
                @{ input = "unknown"; expected = "unknown" }
            )
            
            foreach ($case in $testCases) {
                Mock Get-Actions {
                    [ordered]@{
                        "install" = [PSCustomObject]@{ action = { return 10 } }
                        "use" = [PSCustomObject]@{ action = { return 20 } }
                        "list" = [PSCustomObject]@{ action = { return 30 } }
                    }
                }
                
                $result = Start-PVM -operation $case.input -arguments @()
                
                Assert-MockCalled Alias-Handler -ParameterFilter { $alias -eq $case.input }
                
                if ($case.expected -in @("install", "use", "list")) {
                    $result | Should -BeGreaterThan 0
                    Assert-MockCalled Show-Usage -Times 0
                } else {
                    $result | Should -Be 0
                    Assert-MockCalled Show-Usage -Times 1
                }
            }
        }

        It "Should preserve argument order and content" {
            $testArgs = @("arg1", "--flag", "value with spaces", "123")
            
            Start-PVM -operation "setup" -arguments $testArgs
            
            Assert-MockCalled Get-Actions -Times 1 -ParameterFilter { 
                $arguments.Count -eq 4 -and
                $arguments[0] -eq "arg1" -and
                $arguments[1] -eq "--flag" -and
                $arguments[2] -eq "value with spaces" -and
                $arguments[3] -eq "123"
            }
        }
    }

    Context "Integration Path Tests" {
        It "Should execute complete happy path" {
            Mock Get-Actions {
                [ordered]@{
                    "install" = [PSCustomObject]@{ action = { return 0 } }
                }
            }
            Mock Is-PVM-Setup { $true }
            
            $result = Start-PVM -operation "install" -arguments @("8.2.0")
            
            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Alias-Handler -Times 1
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Show-Usage -Times 0
            Assert-MockCalled Show-PVM-Version -Times 0
            Assert-MockCalled Log-Data -Times 0
        }

        It "Should handle complete setup workflow" {
            Mock Get-Actions {
                [ordered]@{
                    "setup" = [PSCustomObject]@{ action = { return 0 } }
                }
            }
            Mock Alias-Handler { param($alias) return $alias }
            # Is-PVM-Setup should not be called for setup operation
            
            $result = Start-PVM -operation "setup" -arguments @()
            
            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Alias-Handler -Times 1
            Assert-MockCalled Is-PVM-Setup -Times 0
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should handle complete error workflow" {
            Mock Get-Actions {
                [ordered]@{
                    "install" = [PSCustomObject]@{ 
                        action = { throw [System.UnauthorizedAccessException]::new("Access denied") }
                    }
                }
            }
            Mock Alias-Handler { param($alias) return $alias }
            Mock Is-PVM-Setup { $true }
            Mock Log-Data { $true }
            
            $result = Start-PVM -operation "install" -arguments @("8.2.0")
            
            $result | Should -Be -1
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Alias-Handler -Times 1
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Log-Data -Times 1
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $ForegroundColor -eq "DarkYellow"
            }
        }
    }
}