
BeforeAll {
    # Initialize mock registry
    $global:MockRegistry = @{
        Machine = @{
            "PATH" = "C:\Windows\System32;C:\Program Files\Git\bin;C:\CustomApp;C:\Program Files\Java\bin"
            "JAVA_HOME" = "C:\Program Files\Java"
            "GIT_HOME" = "C:\Program Files\Git\bin"
            "CUSTOM_APP" = "C:\CustomApp"
            "WINDOWS_DIR" = "C:\Windows"
            "SYSTEM32_DIR" = "C:\Windows\System32"
            "REGULAR_VAR" = "SomeValue"
            "EXISTING_VAR" = "referenced_value"
            "EMPTY_VAR" = ""
        }
        Process = @{}
        User = @{}
    }
    
    # Mock global variable
    $global:LOG_ERROR_PATH = "TestDrive:\logs\error.log"
    
    # Mock Log-Data function
    function Log-Data { 
        param($logPath, $message, $data)
        return "logged: $message - $data"
    }
    
    # Function definitions (inline for testing)
    function Get-EnvVar-ByName {
        param ($name)
        try {
            if ([string]::IsNullOrWhiteSpace($name)) {
                return $null
            }
            $name = $name.Trim()
            return $global:MockRegistry.Machine[$name]
        } catch {
            $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-EnvVar-ByName: Failed to get environment variable '$name'" -data $_.Exception.Message
            return $null
        }
    }
    
    function Set-EnvVar {
        param ($name, $value)
        try {
            if ([string]::IsNullOrWhiteSpace($name)) {
                return -1
            }
            $name = $name.Trim()
            $global:MockRegistry.Machine[$name] = $value
            return 0
        } catch {
            $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-EnvVar: Failed to set environment variable '$name'" -data $_.Exception.Message
            return -1
        }
    }
    
    function Set-PHP-Env {
        param ($name, $value)
        try {
            $content = Get-EnvVar-ByName -name $value
            if ($content) {
                $output = Set-EnvVar -name $name -value $content
            } else {
                $output = Set-EnvVar -name $name -value $value
            }
            return $output
        } catch {
            $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-PHP-Env: Failed to set environment variable '$name'" -data $_.Exception.Message
            return -1
        }
    }
}


Describe "Set-PHP-Env" {
    BeforeEach {
        # Reset mock registry to initial state before each test
        $global:MockRegistry.Machine = @{
            "PATH" = "C:\Windows\System32;C:\Program Files\Git\bin;C:\CustomApp;C:\Program Files\Java\bin"
            "JAVA_HOME" = "C:\Program Files\Java"
            "GIT_HOME" = "C:\Program Files\Git\bin"
            "CUSTOM_APP" = "C:\CustomApp"
            "WINDOWS_DIR" = "C:\Windows"
            "SYSTEM32_DIR" = "C:\Windows\System32"
            "REGULAR_VAR" = "SomeValue"
            "EXISTING_VAR" = "referenced_value"
            "EMPTY_VAR" = ""
        }
    }
    
    Context "When value parameter refers to an existing environment variable" {
        
        It "Should set the environment variable to the content of the referenced variable" {
            # Act
            $result = Set-PHP-Env -name "NEW_VAR" -value "EXISTING_VAR"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["NEW_VAR"] | Should -Be "referenced_value"
        }
        
        It "Should handle existing system variables like JAVA_HOME" {
            # Act
            $result = Set-PHP-Env -name "PHP_JAVA_HOME" -value "JAVA_HOME"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["PHP_JAVA_HOME"] | Should -Be "C:\Program Files\Java"
        }
        
        It "Should handle PATH variable reference" {
            # Act
            $result = Set-PHP-Env -name "BACKUP_PATH" -value "PATH"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["BACKUP_PATH"] | Should -Be "C:\Windows\System32;C:\Program Files\Git\bin;C:\CustomApp;C:\Program Files\Java\bin"
        }
        
        It "Should handle empty string content from referenced variable" {
            # Act
            $result = Set-PHP-Env -name "NEW_VAR" -value "EMPTY_VAR"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["NEW_VAR"] | Should -Be "EMPTY_VAR"  # Falls back to literal value
        }
    }
    
    Context "When value parameter does not refer to an existing environment variable" {
        
        It "Should set the environment variable to the literal value" {
            # Act
            $result = Set-PHP-Env -name "NEW_VAR" -value "NON_EXISTING_VAR"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["NEW_VAR"] | Should -Be "NON_EXISTING_VAR"
        }
        
        It "Should handle literal string values correctly" {
            # Act
            $result = Set-PHP-Env -name "TEST_VAR" -value "literal_value"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["TEST_VAR"] | Should -Be "literal_value"
        }
        
        It "Should handle paths as literal values" {
            # Act
            $result = Set-PHP-Env -name "PHP_CONFIG_PATH" -value "C:\PHP\config"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["PHP_CONFIG_PATH"] | Should -Be "C:\PHP\config"
        }
    }
    
    Context "When Set-EnvVar receives invalid input" {
        
        It "Should return -1 when name is null" {
            # Act
            $result = Set-PHP-Env -name $null -value "test_value"
            
            # Assert
            $result | Should -Be -1
        }
        
        It "Should return -1 when name is empty string" {
            # Act
            $result = Set-PHP-Env -name "" -value "test_value"
            
            # Assert
            $result | Should -Be -1
        }
        
        It "Should return -1 when name is whitespace" {
            # Act
            $result = Set-PHP-Env -name "   " -value "test_value"
            
            # Assert
            $result | Should -Be -1
        }
        
        It "Should handle null value parameter gracefully" {
            # Act
            $result = Set-PHP-Env -name "TEST_VAR" -value $null
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["TEST_VAR"] | Should -Be $null
        }
    }
    
    Context "Variable name trimming behavior" {
        
        It "Should trim whitespace from variable names in Set-EnvVar" {
            # Arrange - Add a variable with trimmed name to mock registry
            $global:MockRegistry.Machine["TRIMMED_VAR"] = "trimmed_content"
            
            # Act
            $result = Set-PHP-Env -name "  NEW_VAR  " -value "TRIMMED_VAR"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["NEW_VAR"] | Should -Be "trimmed_content"
            $global:MockRegistry.Machine.ContainsKey("  NEW_VAR  ") | Should -Be $false
        }
        
        It "Should trim whitespace from value when used as variable name lookup" {
            # Arrange
            $global:MockRegistry.Machine["SPACED_VAR"] = "spaced_content"
            
            # Act
            $result = Set-PHP-Env -name "TARGET_VAR" -value "  SPACED_VAR  "
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["TARGET_VAR"] | Should -Be "spaced_content"
        }
    }
    
    Context "Registry state verification" {
        
        It "Should not modify existing variables when setting new ones" {
            # Arrange
            $originalJavaHome = $global:MockRegistry.Machine["JAVA_HOME"]
            
            # Act
            $result = Set-PHP-Env -name "NEW_VAR" -value "new_value"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["JAVA_HOME"] | Should -Be $originalJavaHome
            $global:MockRegistry.Machine["NEW_VAR"] | Should -Be "new_value"
        }
        
        It "Should overwrite existing variables when setting with same name" {
            # Arrange
            $global:MockRegistry.Machine["EXISTING_VAR"] = "old_value"
            
            # Act
            $result = Set-PHP-Env -name "EXISTING_VAR" -value "new_value"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["EXISTING_VAR"] | Should -Be "new_value"
        }
    }
    
    Context "Complex scenarios" {
        
        It "Should handle chained variable references" {
            # Arrange
            $global:MockRegistry.Machine["VAR_A"] = "content_a"
            $global:MockRegistry.Machine["VAR_B"] = "VAR_A"
            
            # Act - This will set VAR_C to the content of VAR_B (which is "VAR_A" literal, not content of VAR_A)
            $result = Set-PHP-Env -name "VAR_C" -value "VAR_B"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["VAR_C"] | Should -Be "VAR_A"
        }
        
        It "Should handle special characters in variable names and values" {
            # Act
            $result = Set-PHP-Env -name "TEST_VAR_123" -value "value@#$%^&*()"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["TEST_VAR_123"] | Should -Be "value@#$%^&*()"
        }
        
        It "Should handle very long values" {
            # Arrange
            $longValue = "x" * 1000
            
            # Act
            $result = Set-PHP-Env -name "LONG_VAR" -value $longValue
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["LONG_VAR"] | Should -Be $longValue
        }
    }
    
    Context "Error handling with mock exceptions" {
        
        BeforeEach {
            # Override functions to throw exceptions for error testing
            function Get-EnvVar-ByName {
                param ($name)
                throw "Simulated registry access error"
            }
            
            function Set-EnvVar-WithError {
                param ($name, $value)
                throw "Simulated registry write error"
            }
        }
        
        It "Should handle Get-EnvVar-ByName exceptions gracefully" {
            # Arrange - Override the function temporarily
            function Get-EnvVar-ByName { throw "Access denied" }
            
            # Act
            $result = Set-PHP-Env -name "TEST_VAR" -value "SOME_VAR"
            
            # Assert
            $result | Should -Be -1
        }
        
        It "Should handle Set-EnvVar exceptions gracefully" {
            function Set-EnvVar { throw "Permission denied" }
            
            # Act
            $result = Set-PHP-Env -name "TEST_VAR" -value "test_value"
            
            # Assert
            $result | Should -Be -1
        }
    }
    
    Context "Real-world PHP environment scenarios" {
        
        It "Should set PHP_HOME from existing JAVA_HOME pattern" {
            # Act
            $result = Set-PHP-Env -name "PHP_HOME" -value "JAVA_HOME"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["PHP_HOME"] | Should -Be "C:\Program Files\Java"
        }
        
        It "Should handle PHP extension directory setup" {
            # Act
            $result = Set-PHP-Env -name "PHP_EXTENSION_DIR" -value "C:\PHP\ext"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["PHP_EXTENSION_DIR"] | Should -Be "C:\PHP\ext"
        }
        
        It "Should copy PATH to PHP_PATH for backup" {
            # Act
            $result = Set-PHP-Env -name "PHP_PATH_BACKUP" -value "PATH"
            
            # Assert
            $result | Should -Be 0
            $global:MockRegistry.Machine["PHP_PATH_BACKUP"] | Should -Be $global:MockRegistry.Machine["PATH"]
        }
    }
}