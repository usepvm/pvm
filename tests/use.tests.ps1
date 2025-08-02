# Tests for Update-PHP-Version function

Describe "Update-PHP-Version Tests" {
    
    BeforeAll {
        # Mock the external functions that Update-PHP-Version depends on
        Mock Get-EnvVar-ByName { }
        Mock Get-All-EnvVars { }
        Mock Set-EnvVar { }
        Mock Log-Data { return $true }
        
        # Mock global variable
        $global:LOG_ERROR_PATH = "C:\temp\error.log"
    }

    Context "Successful PHP version update" {
        
        It "Should successfully update when exact PHP version environment variable exists" {
            # Arrange
            Mock Get-EnvVar-ByName { return "C:\php8.2\php.exe" } -ParameterFilter { $name -eq "php8.2" }
            Mock Set-EnvVar { } -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php8.2\php.exe" }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2"
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php8.2" }
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php8.2\php.exe" }
            Assert-MockCalled Log-Data -Exactly 0
        }

        It "Should find matching PHP version when exact match doesn't exist" {
            # Arrange
            Mock Get-EnvVar-ByName { return $null } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-All-EnvVars { 
                return @{
                    "php8.2.1" = "C:\php8.2.1\php.exe"
                    "php8.2.5" = "C:\php8.2.5\php.exe"
                    "php7.4" = "C:\php7.4\php.exe"
                    "other_var" = "some_value"
                }
            }
            Mock Set-EnvVar { } -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php8.2.1\php.exe" }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2"
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php8.2" }
            Assert-MockCalled Get-All-EnvVars -Exactly 1
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php8.2.1\php.exe" }
            Assert-MockCalled Log-Data -Exactly 0
        }

        It "Should handle different PHP version formats" {
            # Arrange
            Mock Get-EnvVar-ByName { return "C:\php7.4\php.exe" } -ParameterFilter { $name -eq "php7.4" }
            Mock Set-EnvVar { } -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php7.4\php.exe" }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "7.4"
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "PHP_PATH" -and $value -eq "C:\php7.4\php.exe" }
        }
    }

    Context "Error handling scenarios" {
        
        It "Should return -1 and log error when no matching PHP version is found" {
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
            $result | Should -Be -1
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1
            Assert-MockCalled Get-All-EnvVars -Exactly 1
            Assert-MockCalled Set-EnvVar -Exactly 0
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $logPath -eq $LOG_ERROR_PATH -and 
                $message -eq "Update-PHP-Version: Failed to update PHP version for 'PHP_PATH'" 
            }
        }

        It "Should return -1 and log error when matched variable has no content" {
            # Arrange
            Mock Get-EnvVar-ByName { return $null } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-All-EnvVars { 
                return @{
                    "php8.2.1" = ""  # Empty value
                    "php7.4" = "C:\php7.4\php.exe"
                }
            }
            Mock Log-Data { return $true }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2"
            
            # Assert
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $message -eq "Update-PHP-Version: Failed to update PHP version for 'PHP_PATH'" 
            }
            Assert-MockCalled Set-EnvVar -Exactly 0
        }

        It "Should return -1 and log error when Get-EnvVar-ByName throws exception" {
            # Arrange
            Mock Get-EnvVar-ByName { throw "Access denied" } -ParameterFilter { $name -eq "php8.2" }
            Mock Log-Data { return $true }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2"
            
            # Assert
            $result | Should -Be -1
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
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $data -eq "Permission denied"
            }
        }
    }

    Context "Edge cases and parameter validation" {
        
        It "Should handle null or empty parameters gracefully" {
            # Arrange
            Mock Get-EnvVar-ByName { return $null }
            Mock Log-Data { return $true }
            
            # Act
            $result = Update-PHP-Version -variableName "" -variableValue ""
            
            # Assert
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1
        }

        It "Should handle special characters in version numbers" {
            # Arrange
            Mock Get-EnvVar-ByName { return "C:\php8.2-dev\php.exe" } -ParameterFilter { $name -eq "php8.2-dev" }
            Mock Set-EnvVar { }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8.2-dev"
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Set-EnvVar -Exactly 1
        }

        It "Should sort and select first match when multiple versions match pattern" {
            # Arrange
            Mock Get-EnvVar-ByName { return $null } -ParameterFilter { $name -eq "php8" }
            Mock Get-All-EnvVars { 
                return @{
                    "php8.3" = "C:\php8.3\php.exe"
                    "php8.1" = "C:\php8.1\php.exe"
                    "php8.2" = "C:\php8.2\php.exe"
                }
            }
            Mock Set-EnvVar { } -ParameterFilter { $value -eq "C:\php8.1\php.exe" }
            
            # Act
            $result = Update-PHP-Version -variableName "PHP_PATH" -variableValue "8"
            
            # Assert
            $result | Should -Be 0
            # Should select php8.1 as it comes first alphabetically after sorting
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $value -eq "C:\php8.1\php.exe" }
        }
    }

    Context "Integration-like scenarios" {
        
        It "Should handle realistic environment variable scenarios" {
            # Arrange - Simulate a realistic environment
            Mock Get-EnvVar-ByName { return $null } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-All-EnvVars { 
                return @{
                    "PATH" = "C:\Windows\System32"
                    "php8.2.10" = "C:\php\8.2.10\php.exe"
                    "php8.1.25" = "C:\php\8.1.25\php.exe"
                    "php7.4.33" = "C:\php\7.4.33\php.exe"
                    "COMPOSER_HOME" = "C:\composer"
                    "php8.2.5" = "C:\php\8.2.5\php.exe"
                }
            }
            Mock Set-EnvVar { }
            
            # Act
            $result = Update-PHP-Version -variableName "CURRENT_PHP" -variableValue "8.2"
            
            # Assert
            $result | Should -Be 0
            # Should select php8.2.10 (first after sorting: php8.2.10, php8.2.5)
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { 
                $name -eq "CURRENT_PHP" -and $value -eq "C:\php\8.2.10\php.exe" 
            }
        }
    }
}

# Additional helper tests for understanding the function behavior
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
