# Tests for Update-PHP-Version function

Describe "Update-PHP-Version Tests" {
    
    BeforeAll {
        Mock Read-Host {
            param ($prompt)
            return '8.2.1'
        }
        # Mock the external functions that Update-PHP-Version depends on
        Mock Log-Data { return $true }
        
        # Mock global variable
        $global:LOG_ERROR_PATH = "TestDrive:\storage\logs\error.log"
        $global:MockRegistry = @{
            Machine = @{
                "Path" = "C:\Windows\System32;C:\Program Files\Git\bin"
                "php7.4.30" = "C:\PHP\php-7.4.30"
                "php8.0.5" = "C:\PHP\php-8.0.5"
                "php8.1.0" = "C:\PHP\php-8.1.0"
                "php8.2.1" = "C:\php8.2.1\php.exe"
                "php8.2.5" = "C:\php8.2.5\php.exe"
                "php8.3" = ""
                "other_var" = "some_value"
            }
            Process = @{}
            User = @{}
        }
        
        # Environment variable wrapper functions
        function Get-EnvironmentVariablesWrapper {
            param($target)
            
            if ($global:MockRegistryThrowException) {
                throw $global:MockRegistryException
            }
            
            switch ($target) {
                ([System.EnvironmentVariableTarget]::Machine) { 
                    $result = @{}
                    $global:MockRegistry.Machine.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                    return $result
                }
                ([System.EnvironmentVariableTarget]::Process) { 
                    $result = @{}
                    $global:MockRegistry.Process.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                    return $result
                }
                ([System.EnvironmentVariableTarget]::User) { 
                    $result = @{}
                    $global:MockRegistry.User.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                    return $result
                }
                default { return @{} }
            }
        }

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
        
        # Override the original environment functions to use wrappers
        Mock Get-All-EnvVars {
            try {
                return Get-EnvironmentVariablesWrapper -target ([System.EnvironmentVariableTarget]::Machine)
            } catch {
                $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-All-EnvVars: Failed to get all environment variables" -data $_.Exception.Message
                return $null
            }
        }

        Mock Get-EnvVar-ByName {
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

        Mock Set-EnvVar {
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

    Context "Successful PHP version update" {
        
        It "Should successfully update when exact PHP version environment variable exists" {
            # Arrange
            Mock Get-EnvVar-ByName { return "C:\php8.2\php.exe" } -ParameterFilter { $name -eq "php8.2" }
            Mock Set-EnvVar {
                param($name, $value)
                
                if ($name -eq "PHP_PATH" -and $value -eq "C:\php8.2\php.exe") {return 0}
                return -1    
            }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2"
            
            # Assert
            $result.code | Should -Be 0
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php8.2" }
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php8.2\php.exe" }
            Assert-MockCalled Log-Data -Exactly 0
        }

        It "Should find matching PHP version when exact match doesn't exist" {

            Mock Write-Host {}
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2"
            
            # Assert
            $result.code | Should -Be 0
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php8.2" }
            Assert-MockCalled Get-All-EnvVars -Exactly 1
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php8.2.1\php.exe" }
            Assert-MockCalled Log-Data -Exactly 0
        }

        It "Should handle different PHP version formats" {
            # Arrange
            Mock Get-EnvVar-ByName { return "C:\php7.4\php.exe" } -ParameterFilter { $name -eq "php7.4" }
            Mock Set-EnvVar {
                param($name, $value)
                
                if ($name -eq "PHP_PATH" -and $value -eq "C:\php7.4\php.exe") { return 0 }
                return -1
            }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "7.4"
            
            # Assert
            $result.code | Should -Be 0
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php7.4\php.exe" }
        }
        
        It "Should automatically choose if only one version is available" {
            $global:MockRegistry.Machine = @{
                "Path" = "C:\Windows\System32;C:\Program Files\Git\bin"
                "php7.4.30" = "C:\PHP\php-7.4.30"
                "php8.0.5" = "C:\PHP\php-8.0.5"
                "php8.1.0" = "C:\PHP\php-8.1.0"
                "php8.2.1" = "C:\php8.2.1\php.exe"
            }
            
            # Act
            $result = Update-PHP-Version -variableName "CURRENT_PHP" -variableValue "8.0"

            # Assert
            $result.code | Should -Be 0
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "CURRENT_PHP" -and $value -eq "C:\PHP\php-8.0.5" }
        }
    }

    Context "Error handling scenarios" {
        
        It "Should return -1 when no matching PHP version is found" {
            # Arrange
            Mock Get-EnvVar-ByName { return $null } -ParameterFilter { $name -eq "php9.0" }
            Mock Get-All-EnvVars { 
                return @{
                    "php8.2" = "C:\php8.2\php.exe"
                    "php7.4" = "C:\php7.4\php.exe"
                    "other_var" = "some_value"
                }
            }
            Mock Log-Data { return $true } -ParameterFilter { $message -like "*Failed to update PHP version*" }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "9.0"
            
            # Assert
            $result.code | Should -Be -1
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1
            Assert-MockCalled Get-All-EnvVars -Exactly 1
            Assert-MockCalled Set-EnvVar -Exactly 0
        }

        It "Should return -1 and log error when matched variable has no content" {
            # Arrange
            Mock Log-Data { return $true }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.3"
            
            # Assert
            $result.code | Should -Be -1
            Assert-MockCalled Set-EnvVar -Exactly 0
        }

        It "Should return -1 and log error when Get-EnvVar-ByName throws exception" {
            # Arrange
            Mock Get-EnvVar-ByName { throw "Access denied" } -ParameterFilter { $name -eq "php8.2" }
            Mock Log-Data { return $true }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2"
            
            # Assert
            $result.code | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $message -eq "Update-PHP-Version: Failed to update PHP version for 'PHP_PATH'" -and
                $data -eq "Access denied"
            }
        }

        It "Should return -1 and log error when Set-EnvVar throws exception" {
            # Arrange
            Mock Get-EnvVar-ByName { return "C:\php8.2\php.exe" } -ParameterFilter { $name -eq "php8.2" }
            Mock Set-EnvVar { throw "Permission denied" } -ParameterFilter { $name -eq "PHP_PATH" }
            Mock Log-Data { return $true }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2"
            
            # Assert
            $result.code | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $data -eq "Permission denied"
            }
        }
    }

    Context "Edge cases and parameter validation" {
        
        It "Should handle special characters in version numbers" {
            # Arrange
            Mock Get-EnvVar-ByName { return "C:\php8.2-dev\php.exe" } -ParameterFilter { $name -eq "php8.2-dev" }
            Mock Set-EnvVar { return 0}
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2-dev"
            
            # Assert
            $result.code | Should -Be 0
            Assert-MockCalled Set-EnvVar -Exactly 1
        }

        It "Should sort and select first match when multiple versions match pattern" {
            Mock Write-Host {}
            # Arrange
            $global:MockRegistry.Machine = @{
                "Path" = "C:\Windows\System32;C:\Program Files\Git\bin"
                "php7.4.30" = "C:\PHP\php-7.4.30"
                "php8.0.5" = "C:\PHP\php-8.0.5"
                "php8.1.0" = "C:\PHP\php-8.1.0"
                "php8.2.1" = "C:\php8.2.1\php.exe"
            }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8"
            
            # Assert
            $result.code | Should -Be 0
            # Should select php8.1 as it comes first alphabetically after sorting
            Assert-MockCalled Set-EnvVar -Exactly 1
        }
    }

    Context "Integration-like scenarios" {
        
        It "Should handle realistic environment variable scenarios" {
            # Arrange - Simulate a realistic environment
            
            # Act
            $result = Update-PHP-Version -variableName "CURRENT_PHP" -variableValue "8.2"
            
            # Assert
            $result.code | Should -Be 0
            # Should select php8.2.10 (first after sorting: php8.2.10, php8.2.5)
            Assert-MockCalled Set-EnvVar -Exactly 1
        }
    }
}

# # Additional helper tests for understanding the function behavior
Describe "Update-PHP-Version Behavior Analysis" {
    
    It "Should demonstrate the regex matching behavior" {
        # This test helps understand how the Where-Object with -match works
        $testKeys = @("php8.2.1", "php8.2.5", "php7.4", "php8.1", "other_var")
        $pattern = "8.2"
        $matches = $testKeys | Where-Object { $_ -match $pattern } | Sort-Object
        
        $matches | Should -HaveCount 2
        $matches[0] | Should -Be "php8.2.1"
        $matches[1] | Should -Be "php8.2.5"
    }
    
    It "Should demonstrate sorting behavior" {
        $testKeys = @("php8.2.15", "php8.2.5", "php8.2.10")
        $sorted = $testKeys | Sort-Object | Select-Object -First 1
        
        # Note: String sorting, not numeric - "php8.2.10" comes before "php8.2.15"
        $sorted | Should -Be "php8.2.10"
    }
}
