# Tests for Setup-PVM function

Describe "Setup-PVM" {
    BeforeAll {
        Mock Write-Host {}
        # Mock global variables that the function depends on
        $global:PHP_CURRENT_ENV_NAME = "PHP"
        $global:PVMRoot = "C:\PVM"
        $global:LOG_ERROR_PATH = "TestDrive:\logs\error.log"
        
        # Initialize mock registry
        $global:MockRegistry = @{
            Machine = @{
                "Path" = "C:\Windows\System32"
                "PHP" = $null
                "pvm" = $null
            }
            Process = @{}
            User = @{}
        }
        
        # Mock Log-Data function
        Mock Log-Data { return $true }
        
        # Mock the System.Environment methods
        
        function Get-EnvironmentVariableWrapper {
            param($name, $target)
            
            if ($global:MockRegistryThrowException) {
                throw $global:MockRegistryException
            }
            
            switch ($target) {
                ([System.EnvironmentVariableTarget]::Machine) { return $global:MockRegistry.Machine[$name] }
                ([System.EnvironmentVariableTarget]::Process) { return $global:MockRegistry.Process[$name] }
                ([System.EnvironmentVariableTarget]::User) { return $global:MockRegistry.User[$name] }
                default { return $null }
            }
        }

        function Get-EnvVar-ByName {
            param ($name)
            try {
                if ([string]::IsNullOrWhiteSpace($name)) {
                    return $null
                }
                $name = $name.Trim()
                return Get-EnvironmentVariableWrapper -name $name -target ([System.EnvironmentVariableTarget]::Machine)
            } catch {
                $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-EnvVar-ByName: Failed to get environment variable '$name'" -data $_.Exception.Message
                return $null
            }
        }
        
        function Set-EnvironmentVariableWrapper {
            param($name, $value, $target)
            
            if ($global:MockRegistryThrowException) {
                throw $global:MockRegistryException
            }
            
            switch ($target) {
                ([System.EnvironmentVariableTarget]::Machine) { 
                    if ($value -eq $null) {
                        $global:MockRegistry.Machine.Remove($name)
                    } else {
                        $global:MockRegistry.Machine[$name] = $value
                    }
                }
                ([System.EnvironmentVariableTarget]::Process) { 
                    if ($value -eq $null) {
                        $global:MockRegistry.Process.Remove($name)
                    } else {
                        $global:MockRegistry.Process[$name] = $value
                    }
                }
                ([System.EnvironmentVariableTarget]::User) { 
                    if ($value -eq $null) {
                        $global:MockRegistry.User.Remove($name)
                    } else {
                        $global:MockRegistry.User[$name] = $value
                    }
                }
            }
        }
        
        function Set-EnvVar {
            param ($name, $value)
            try {
                if ([string]::IsNullOrWhiteSpace($name)) {
                    return -1
                }
                $name = $name.Trim()
                Set-EnvironmentVariableWrapper -name $name -value $value -target ([System.EnvironmentVariableTarget]::Machine)
                return 0
            } catch {
                $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-EnvVar: Failed to set environment variable '$name'" -data $_.Exception.Message
                return -1
            }
        }
        
    }

    BeforeEach {
        # Reset mock registry before each test
        $global:MockRegistry = @{
            Machine = @{
                "Path" = "C:\Windows\System32"
                "PHP" = $null
                "pvm" = $null
            }
            Process = @{}
            User = @{}
        }
    }

    Context "When environment is not set up" {
        It "Should add PHP to PATH when it doesn't exist" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;%pvm%"
            $global:MockRegistry.Machine["PHP"] = $null
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["PHP"] | Should -Be 'null'
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;%pvm%;%PHP%"
            $result.code | Should -Be 0
        }

        It "Should add PVM path to PATH when it doesn't exist" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;%PHP%"
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = $null

        
            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["pvm"] | Should -Be "C:\PVM"
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;%PHP%;%pvm%"
            $result.code | Should -Be 0
        }

        It "Should set up both PHP and pvm when neither exists" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32"
            $global:MockRegistry.Machine["PHP"] = $null
            $global:MockRegistry.Machine["pvm"] = $null

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["PHP"] | Should -Be 'null'
            $global:MockRegistry.Machine["pvm"] | Should -Be "C:\PVM"
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;%PHP%;%pvm%"
            $result.code | Should -Be 0
        }

        It "Should add both variables to PATH when PATH doesn't contain them" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;C:\SomeOtherPath"
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;C:\SomeOtherPath;%PHP%;%pvm%"
            $result.code | Should -Be 0
        }
    }

    Context "When environment is already set up" {
        It "Should return 1 when PATH already contains PHP and pvm paths" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;C:\PHP\8.1;C:\PVM"
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;C:\PHP\8.1;C:\PVM"
            $result.code | Should -Be 1
        }

        It "Should return 1 when PATH contains environment variable references" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;%PHP%;%pvm%"
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;%PHP%;%pvm%"
            $result.code | Should -Be 1
        }

        It "Should return 1 when PATH already contains pvm reference but PHP is null" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;%PHP%;%pvm%"
            $global:MockRegistry.Machine["PHP"] = $null
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;%PHP%;%pvm%"
            $result.code | Should -Be 1
        }
    }

    Context "When PHP exists but not in PATH" {
        It "Should add PHP to PATH but not set the variable" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;%pvm%"
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["PHP"] | Should -Be "C:\PHP\8.1"
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;%pvm%;%PHP%"
            $result.code | Should -Be 0
        }
    }

    Context "When pvm exists but not in PATH" {
        It "Should add pvm to PATH but not set the variable" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;C:\PHP\8.1"
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["pvm"] | Should -Be "C:\PVM"
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;C:\PHP\8.1;%pvm%"
            $result.code | Should -Be 0
        }
    }

    Context "Error handling" {
        It "Should return -1 and log error when environment variable access fails" {
            # Arrange - Mock System.Environment to throw exception
            function Get-EnvVar-ByName { throw "Access denied" }

            # Act
            $result = Setup-PVM

            # Assert
            Should -Invoke Log-Data -Times 1 -Exactly
            Should -Invoke Log-Data -ParameterFilter { 
                $logPath -eq "TestDrive:\logs\error.log" -and 
                $message -eq "Setup-PVM: Failed to set up PVM environment"
            }
            $result.code | Should -Be -1
        }

        It "Should return -1 and log error when Set-EnvVar fails" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32"
            $global:MockRegistry.Machine["PHP"] = $null
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"
            
            # Mock SetEnvironmentVariable to throw exception
            function Set-EnvVar { throw "Registry write access denied" }

            # Act
            $result = Setup-PVM

            # Assert
            Should -Invoke Log-Data -Times 1 -Exactly
            Should -Invoke Log-Data -ParameterFilter { 
                $logPath -eq "TestDrive:\logs\error.log" -and 
                $message -eq "Setup-PVM: Failed to set up PVM environment"
            }
            $result.code | Should -Be -1
        }
    }

    Context "Edge cases" {
        It "Should handle empty PATH variable" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = ""
            $global:MockRegistry.Machine["PHP"] = $null
            $global:MockRegistry.Machine["pvm"] = $null

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["Path"] | Should -Be ";%PHP%;%pvm%"
            $result.code | Should -Be 0
        }

        It "Should handle null PATH variable" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = $null
            $global:MockRegistry.Machine["PHP"] = $null
            $global:MockRegistry.Machine["pvm"] = $null

            # Act
            $result = Setup-PVM
            
            # Assert
            $global:MockRegistry.Machine["Path"] | Should -Be ";%PHP%;%pvm%"
            $result.code | Should -Be 0
        }

        It "Should be case-insensitive when checking PATH contents" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\windows\system32;c:\pvm;%PHP%"  # lowercase pvm
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = "C:\PVM"  # uppercase PVM

            # Act
            $result = Setup-PVM

            # Assert - Should recognize that c:\pvm matches C:\PVM
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\windows\system32;c:\pvm;%PHP%"
            $result.code | Should -Be 1
        }

        It "Should handle whitespace in environment variable names" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32"
            $global:MockRegistry.Machine["PHP"] = $null
            $global:MockRegistry.Machine["pvm"] = $null

            # Act
            $result = Setup-PVM

            # Assert - Should work normally despite potential whitespace handling
            $global:MockRegistry.Machine["PHP"] | Should -Be 'null'
            $global:MockRegistry.Machine["pvm"] | Should -Be "C:\PVM"
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\windows\system32;%PHP%;%pvm%"
            $result.code | Should -Be 0
        }
    }

    Context "Integration scenarios" {
        It "Should handle partial setup correctly" {
            # Arrange - PHP is set and in PATH, but pvm is not
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;C:\PHP\8.1"
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = $null

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["pvm"] | Should -Be "C:\PVM"
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;C:\PHP\8.1;%pvm%"
            $result.code | Should -Be 0
        }

        It "Should handle mixed PATH styles (environment variables and actual paths)" {
            # Arrange
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;%PHP%;C:\SomeOtherPath"
            $global:MockRegistry.Machine["PHP"] = "C:\PHP\8.1"
            $global:MockRegistry.Machine["pvm"] = $null

            # Act
            $result = Setup-PVM

            # Assert
            $global:MockRegistry.Machine["pvm"] | Should -Be "C:\PVM"
            $global:MockRegistry.Machine["Path"] | Should -Be "C:\Windows\System32;%PHP%;C:\SomeOtherPath;%pvm%"
            $result.code | Should -Be 0
        }
    }

    Context "Set-EnvVar function tests" {
        It "Should return -1 for null or empty name" {
            $result = Set-EnvVar -name "" -value "test"
            $result | Should -Be -1
            
            $result = Set-EnvVar -name $null -value "test"
            $result | Should -Be -1
            
            $result = Set-EnvVar -name "   " -value "test"
            $result | Should -Be -1
        }

        It "Should trim whitespace from name and set variable" {
            $result = Set-EnvVar -name "  TEST_VAR  " -value "test_value"
            $result | Should -Be 0
            $global:MockRegistry.Machine["TEST_VAR"] | Should -Be "test_value"
        }
    }

    Context "Get-EnvVar-ByName function tests" {
        It "Should return null for null or empty name" {
            $result = Get-EnvVar-ByName -name ""
            $result | Should -Be $null
            
            $result = Get-EnvVar-ByName -name $null
            $result | Should -Be $null
            
            $result = Get-EnvVar-ByName -name "   "
            $result | Should -Be $null
        }

        It "Should trim whitespace from name and get variable" {
            $global:MockRegistry.Machine["TEST_VAR"] = "test_value"
            $result = Get-EnvVar-ByName -name "  TEST_VAR  "
            $result | Should -Be "test_value"
        }
    }
}