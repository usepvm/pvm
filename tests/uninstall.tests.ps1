# Tests for Uninstall-PHP function

Describe "Uninstall-PHP Tests" {
    
    BeforeAll {
        # Mock the external functions that Uninstall-PHP depends on
        Mock Get-EnvVar-ByName { }
        Mock Get-Current-PHP-Version { }
        Mock Set-EnvVar { }
        Mock Remove-Item { }
        Mock Log-Data { return $true }
        
        # Mock global variables
        $global:PHP_CURRENT_ENV_NAME = "PHP"
        $global:LOG_ERROR_PATH = "C:\temp\error.log"
    }

    Context "Successful PHP uninstallation" {
        
        It "Should successfully uninstall PHP version that is not currently active" {
            # Arrange
            $version = "8.2"
            $phpPath = "C:\php\8.2"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-Current-PHP-Version { return @{ version = "7.4" } }
            Mock Remove-Item { } -ParameterFilter { $Path -eq $phpPath -and $Recurse -eq $true -and $Force -eq $true }
            Mock Set-EnvVar {
                param($name, $value)
                if ($name -eq "php8.2" -and $value -eq $null) { return 0 }
                return -1
            }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php8.2" }
            Assert-MockCalled Get-Current-PHP-Version -Exactly 1
            Assert-MockCalled Remove-Item -Exactly 1 -ParameterFilter { $Path -eq $phpPath -and $Recurse -eq $true -and $Force -eq $true }
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "php8.2" -and $value -eq $null }
            Assert-MockCalled Set-EnvVar -Exactly 0 -ParameterFilter { $name -eq $PHP_CURRENT_ENV_NAME }
            Assert-MockCalled Log-Data -Exactly 0
        }

        It "Should successfully uninstall PHP version that is currently active and reset current version" {
            # Arrange
            $version = "8.2"
            $phpPath = "C:\php\8.2"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-Current-PHP-Version { return @{ version = "8.2" } }
            Mock Remove-Item { } -ParameterFilter { $Path -eq $phpPath }
            Mock Set-EnvVar {
                param($name, $value)

                if (
                    ($name -eq $PHP_CURRENT_ENV_NAME -and $value -eq 'null') -or
                    ($name -eq "php8.2" -and $value -eq $null)
                    ) { return 0 }
                return -1

            }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php8.2" }
            Assert-MockCalled Get-Current-PHP-Version -Exactly 1
            Assert-MockCalled Remove-Item -Exactly 1 -ParameterFilter { $Path -eq $phpPath }
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "php8.2" -and $value -eq $null }
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq $PHP_CURRENT_ENV_NAME -and $value -eq 'null' }
            Assert-MockCalled Log-Data -Exactly 0
        }

        It "Should handle case when Get-Current-PHP-Version returns null" {
            # Arrange
            $version = "7.4"
            $phpPath = "C:\php\7.4"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php7.4" }
            Mock Get-Current-PHP-Version { return $null }
            Mock Remove-Item { }
            Mock Set-EnvVar { 
                param($name, $value)
                if ($name -eq "php7.4" -and $value -eq $null) { return 0 }
                return -1
            }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Set-EnvVar -Exactly 0 -ParameterFilter { $name -eq $PHP_CURRENT_ENV_NAME }
            Assert-MockCalled Remove-Item -Exactly 1
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { $name -eq "php7.4" -and $value -eq $null }
        }

        It "Should handle case when Get-Current-PHP-Version returns object without version property" {
            # Arrange
            $version = "8.1"
            $phpPath = "C:\php\8.1"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.1" }
            Mock Get-Current-PHP-Version { return @{ path = "C:\php\8.2" } } # No version property
            Mock Remove-Item { }
            Mock Set-EnvVar { 
                param($name, $value)
                if ($name -eq "php8.1" -and $value -eq $null) { return 0 }
                return -1
            }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Set-EnvVar -Exactly 0 -ParameterFilter { $name -eq $PHP_CURRENT_ENV_NAME }
        }

        It "Should handle different version formats" {
            # Arrange
            $testCases = @(
                @{ version = "7.4.33"; envName = "php7.4.33" }
                @{ version = "8.2.10"; envName = "php8.2.10" }
                @{ version = "8"; envName = "php8" }
            )
            
            foreach ($testCase in $testCases) {
                Mock Get-EnvVar-ByName { return "C:\php\$($testCase.version)" } -ParameterFilter { $name -eq $testCase.envName }
                Mock Get-Current-PHP-Version { return @{ version = "different" } }
                Mock Remove-Item { }
                Mock Set-EnvVar { 
                    param($name, $value)
                    if ($name -eq $testCase.envName -and $value -eq $null) { return 0 }
                    return -1
                }
                
                # Act
                $result = Uninstall-PHP -version $testCase.version
                
                # Assert
                $result | Should -Be 0
                Assert-MockCalled Get-EnvVar-ByName -ParameterFilter { $name -eq $testCase.envName }
                Assert-MockCalled Set-EnvVar -ParameterFilter { $name -eq $testCase.envName -and $value -eq $null }
            }
        }
    }

    Context "PHP version not found scenario" {
        
        It "Should return -2 when PHP version environment variable does not exist" {
            # Arrange
            $version = "9.0"
            Mock Get-EnvVar-ByName { return $null } -ParameterFilter { $name -eq "php9.0" }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be -2
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php9.0" }
            Assert-MockCalled Get-Current-PHP-Version -Exactly 0
            Assert-MockCalled Remove-Item -Exactly 0
            Assert-MockCalled Set-EnvVar -Exactly 0
            Assert-MockCalled Log-Data -Exactly 0
        }

        It "Should return -2 when PHP version environment variable is empty string" {
            # Arrange
            $version = "8.3"
            Mock Get-EnvVar-ByName { return "" } -ParameterFilter { $name -eq "php8.3" }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be -2
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1
            Assert-MockCalled Remove-Item -Exactly 0
            Assert-MockCalled Set-EnvVar -Exactly 0
        }
    }

    Context "Error handling scenarios" {
        
        It "Should return -1 and log error when Get-EnvVar-ByName throws exception" {
            # Arrange
            $version = "8.2"
            Mock Get-EnvVar-ByName { throw "Access denied to registry" } -ParameterFilter { $name -eq "php8.2" }
            Mock Log-Data { return $true }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $logPath -eq $LOG_ERROR_PATH -and 
                $message -eq "Uninstall-PHP: Failed to uninstall PHP version '8.2'" -and
                $data -eq "Access denied to registry"
            }
        }

        It "Should return -1 and log error when Get-Current-PHP-Version throws exception" {
            # Arrange
            $version = "8.2"
            $phpPath = "C:\php\8.2"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-Current-PHP-Version { throw "Unable to determine current PHP version" }
            Mock Log-Data { return $true }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $message -eq "Uninstall-PHP: Failed to uninstall PHP version '8.2'" -and
                $data -eq "Unable to determine current PHP version"
            }
        }

        It "Should return -1 and log error when Remove-Item throws exception" {
            # Arrange
            $version = "8.2"
            $phpPath = "C:\php\8.2"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-Current-PHP-Version { return @{ version = "7.4" } }
            Mock Remove-Item { throw "Access denied to path C:\php\8.2" } -ParameterFilter { $Path -eq $phpPath }
            Mock Log-Data { return $true }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $data -eq "Access denied to path C:\php\8.2"
            }
        }

        It "Should return -1 and log error when Set-EnvVar throws exception for environment variable cleanup" {
            # Arrange
            $version = "8.2"
            $phpPath = "C:\php\8.2"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-Current-PHP-Version { return @{ version = "7.4" } }
            Mock Remove-Item { } -ParameterFilter { $Path -eq $phpPath }
            Mock Set-EnvVar { throw "Permission denied" } -ParameterFilter { $name -eq "php8.2" }
            Mock Log-Data { return $true }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $data -eq "Permission denied"
            }
        }

        It "Should return -1 and log error when Set-EnvVar throws exception for current version reset" {
            # Arrange
            $version = "8.2"
            $phpPath = "C:\php\8.2"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.2" }
            Mock Get-Current-PHP-Version { return @{ version = "8.2" } }
            Mock Remove-Item { } -ParameterFilter { $Path -eq $phpPath }
            Mock Set-EnvVar { } -ParameterFilter { $name -eq "php8.2" -and $value -eq $null }
            Mock Set-EnvVar { throw "Cannot set current PHP environment variable" } -ParameterFilter { $name -eq $PHP_CURRENT_ENV_NAME }
            Mock Log-Data { return $true }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be -1
            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter { 
                $data -eq "Cannot set current PHP environment variable"
            }
        }
    }

    Context "Edge cases and parameter validation" {
        
        It "Should handle null version parameter" {
            # Arrange
            Mock Get-EnvVar-ByName { return $null } -ParameterFilter { $name -eq "php" }
            
            # Act
            $result = Uninstall-PHP -version $null
            
            # Assert
            $result | Should -Be -2
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php" }
        }

        It "Should handle empty string version parameter" {
            # Arrange
            Mock Get-EnvVar-ByName { return $null } -ParameterFilter { $name -eq "php" }
            
            # Act
            $result = Uninstall-PHP -version ""
            
            # Assert
            $result | Should -Be -2
            Assert-MockCalled Get-EnvVar-ByName -Exactly 1 -ParameterFilter { $name -eq "php" }
        }

    }

    Context "Return code validation" {
        
        It "Should return exactly 0 for successful uninstallation" {
            # Arrange
            $version = "8.1"
            Mock Get-EnvVar-ByName { return "C:\php\8.1" }
            Mock Get-Current-PHP-Version { return @{ version = "8.2" } }
            Mock Remove-Item { }
            Mock Set-EnvVar { 
                param($name, $value)
                if ($name -eq "php8.1" -and $value -eq $null) { return 0 }
                return -1
            }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -BeExactly 0
            $result.GetType() | Should -Be ([int])
        }

        It "Should return exactly -2 when PHP version not found" {
            # Arrange
            Mock Get-EnvVar-ByName { return $null }
            
            # Act
            $result = Uninstall-PHP -version "nonexistent"
            
            # Assert
            $result | Should -BeExactly -2
            $result.GetType() | Should -Be ([int])
        }

        It "Should return exactly -1 for any exception" {
            # Arrange
            Mock Get-EnvVar-ByName { throw "Any error" }
            Mock Log-Data { return $true }
            
            # Act
            $result = Uninstall-PHP -version "8.2"
            
            # Assert
            $result | Should -BeExactly -1
            $result.GetType() | Should -Be ([int])
        }
    }

    Context "Integration-like scenarios" {
        
        It "Should handle realistic uninstallation scenario with file system operations" {
            # Arrange
            $version = "8.2.15"
            $phpPath = "C:\tools\php\8.2.15"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.2.15" }
            Mock Get-Current-PHP-Version { 
                return @{ 
                    version = "8.1.25"
                    path = "C:\tools\php\8.1.25\php.exe"
                } 
            }
            Mock Remove-Item { } -ParameterFilter { 
                $Path -eq $phpPath -and 
                $Recurse -eq $true -and 
                $Force -eq $true 
            }
            Mock Set-EnvVar { 
                param($name, $value)
                if ($name -eq "php8.2.15" -and $value -eq $null) { return 0 }
                return -1
            }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Remove-Item -Exactly 1 -ParameterFilter { 
                $Path -eq $phpPath -and $Recurse -eq $true -and $Force -eq $true 
            }
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { 
                $name -eq "php8.2.15" -and $value -eq $null 
            }
            # Should not reset current version since it's different
            Assert-MockCalled Set-EnvVar -Exactly 0 -ParameterFilter { 
                $name -eq $PHP_CURRENT_ENV_NAME 
            }
        }
        
        It "Should handle complete uninstallation of currently active version" {
            # Arrange
            $version = "8.2.15"
            $phpPath = "C:\tools\php\8.2.15"
            Mock Get-EnvVar-ByName { return $phpPath } -ParameterFilter { $name -eq "php8.2.15" }
            Mock Get-Current-PHP-Version { 
                return @{ 
                    version = "8.2.15"  # Same as the version being uninstalled
                } 
            }
            Mock Remove-Item { }

            Mock Set-EnvVar { 
                param($name, $value)
                
                
                if (
                    ($name -eq $PHP_CURRENT_ENV_NAME -and $value -eq 'null') -or
                    ($name -eq "php8.2.15" -and $value -eq $null)
                ) { return 0 }
                return -1
            }
            
            # Act
            $result = Uninstall-PHP -version $version
            
            # Assert
            $result | Should -Be 0
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { 
                $name -eq "php8.2.15" -and $value -eq $null 
            }
            Assert-MockCalled Set-EnvVar -Exactly 1 -ParameterFilter { 
                $name -eq $PHP_CURRENT_ENV_NAME -and $value -eq 'null' 
            }
        }
    }
}
