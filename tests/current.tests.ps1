# Comprehensive Tests for Get-PHP-Status and Get-Current-PHP-Version Functions

BeforeAll {
    # Mock dependencies
    $global:LOG_ERROR_PATH = "C:\temp\error.log"
    $global:PHP_CURRENT_VERSION_PATH = "C:\php\current"
    
    # Mock Log-Data function
    Mock Write-Host {}
    function Log-Data {
        param($logPath, $message, $data)
        return $true
    }
}

Describe "Get-PHP-Status Function Tests" {
    
    Context "When php.ini file exists and is valid" {
        
        It "Should detect enabled opcache extension" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                "# PHP Configuration",
                "zend_extension=opcache.dll",
                "zend_extension=some_other.dll"
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $false
        }
        
        It "Should detect enabled xdebug extension" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                "# PHP Configuration",
                "zend_extension=xdebug.dll",
                "extension=mysqli.dll"
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $true
        }
        
        It "Should detect both opcache and xdebug when enabled" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                "zend_extension=opcache.dll",
                "zend_extension=xdebug.dll"
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $true
        }
        
        It "Should detect disabled (commented) opcache extension" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                "; Disabled opcache",
                ";zend_extension=opcache.dll",
                "extension=mysqli.dll"
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $false
        }
        
        It "Should detect disabled (commented) xdebug extension" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                "; Disabled xdebug",
                ";zend_extension=xdebug.dll"
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $false
        }
        
        It "Should handle mixed enabled/disabled extensions" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                "zend_extension=opcache.dll",
                ";zend_extension=xdebug.dll"
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $false
        }
        
        It "Should handle extensions with full paths" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                'zend_extension="C:\php\ext\opcache.dll"',
                'zend_extension="C:\php\ext\xdebug.dll"'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $true
        }
        
        It "Should handle extensions with spaces in configuration" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                "  zend_extension  =  opcache.dll  ",
                "  ;  zend_extension  =  xdebug.dll  "
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $false
        }
        
        It "Should return false for both when no zend_extensions found" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                "# PHP Configuration",
                "extension=mysqli.dll",
                "memory_limit=128M"
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $false
        }
        
        It "Should handle empty php.ini file" {
            # Arrange
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            "" | Out-File -FilePath "$testPath\php.ini"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $false
        }
    }
    
    Context "When php.ini file does not exist" {
        
        It "Should return -1 when php.ini is missing" {
            # Arrange
            $testPath = "TestDrive:\nonexistent"
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $false
        }
    }
    
    Context "When exceptions occur" {
        
        It "Should handle Get-Content exceptions gracefully" {
            # Arrange - Create a directory instead of a file to cause Get-Content to fail
            $testPath = "TestDrive:\php"
            New-Item -Path $testPath -ItemType Directory -Force
            New-Item -Path "$testPath\php.ini" -ItemType Directory -Force
            
            # Act
            $result = Get-PHP-Status -phpPath $testPath
            
            # Assert
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $false
        }
    }
}

Describe "Get-Current-PHP-Version Function Tests" {
    
    Context "When PHP current version symlink exists and is valid" {
        
        BeforeEach {
            # Mock Get-Item to return a symlink object
            Mock Get-Item {
                return @{
                    Target = "C:\php\8.2.0"
                }
            } -ParameterFilter { $Path -eq $PHP_CURRENT_VERSION_PATH }
            
            # Mock Get-PHP-Status
            Mock Get-PHP-Status {
                return @{ opcache = $true; xdebug = $false }
            }
        }
        
        It "Should return correct version information when symlink is valid" {
            # Act
            Mock Is-Directory-Exists { return $true }
            $result = Get-Current-PHP-Version
            
            # Assert
            $result.version | Should -Be "8.2.0"
            $result.path | Should -Be "C:\php\8.2.0"
            $result.status.opcache | Should -Be $true
            $result.status.xdebug | Should -Be $false
        }
        
        It "Should call Get-PHP-Status with correct path" {
            Mock Is-Directory-Exists { return $true }
            # Act
            $result = Get-Current-PHP-Version
            
            # Assert
            Assert-MockCalled Get-PHP-Status -Times 1 -ParameterFilter { $phpPath -eq "C:\php\8.2.0" }
        }
    }
    
    Context "When PHP current version path exists but is not a symlink" {
        
        BeforeEach {
            # Mock Get-Item to return a regular directory (no Target property)
            Mock Get-Item {
                return @{
                    # No Target property - regular directory/file
                }
            } -ParameterFilter { $Path -eq $PHP_CURRENT_VERSION_PATH }
            
            Mock Get-PHP-Status {
                return @{ opcache = $false; xdebug = $true }
            }
        }   
    }
    
    Context "When PHP current version path does not exist" {
        
        BeforeEach {
            # Mock Get-Item to throw an exception
            Mock Get-Item {
                throw "Path does not exist"
            } -ParameterFilter { $Path -eq $PHP_CURRENT_VERSION_PATH }
        }
        
        It "Should return null values when path does not exist" {
            # Act
            $result = Get-Current-PHP-Version
            
            # Assert
            $result.version | Should -Be $null
            $result.path | Should -Be $null
            $result.status.opcache | Should -Be $false
            $result.status.xdebug | Should -Be $false
        }
        
        It "Should call Log-Data when exception occurs" {
            # Arrange
            Mock Log-Data { return $true }
            
            # Act
            $result = Get-Current-PHP-Version
            
            # Assert
            Assert-MockCalled Log-Data -Times 1
        }
    }
    
    Context "When Get-Item returns null" {
        
        BeforeEach {
            Mock Get-Item {
                return $null
            } -ParameterFilter { $Path -eq $PHP_CURRENT_VERSION_PATH }
        }
        
        It "Should handle null Get-Item result" {
            # Act
            $result = Get-Current-PHP-Version
            
            # Assert
            $result.version | Should -Be $null
            $result.path | Should -Be $null
            $result.status.opcache | Should -Be $false
            $result.status.xdebug | Should -Be $false
        }
    }
    
    Context "When Get-PHP-Status fails" {
        
        BeforeEach {
            Mock Get-Item {
                return @{
                    Target = "C:\php\8.1.0"
                }
            } -ParameterFilter { $Path -eq $PHP_CURRENT_VERSION_PATH }
            
            # Mock Get-PHP-Status to return -1 (error case)
            Mock Get-PHP-Status {
                return @{ opcache = $false; xdebug = $false }
            }
        }
        
        It "Should handle Get-PHP-Status error gracefully" -Tag i {
            Mock Is-Directory-Exists { return $true }
            # Act
            $result = Get-Current-PHP-Version
            
            # Assert
            $result.version | Should -Be "8.1.0"
            $result.path | Should -Be "C:\php\8.1.0"
            $result.status | Should -Be -Equal @{ opcache = $false; xdebug = $false }
        }
    }
}

Describe "Integration Tests" {
    
    Context "Real-world scenarios" {
        
        It "Should work end-to-end with actual file system" {
            # Arrange
            $testPhpPath = "TestDrive:\php\8.2.0"
            $testCurrentPath = "TestDrive:\php\current"
            
            New-Item -Path $testPhpPath -ItemType Directory -Force
            
            $phpIniContent = @(
                "zend_extension=opcache.dll",
                ";zend_extension=xdebug.dll",
                "memory_limit=256M"
            )
            $phpIniContent | Out-File -FilePath "$testPhpPath\php.ini"
            
            # Mock the global variable and Get-Item for this test
            $global:PHP_CURRENT_VERSION_PATH = $testCurrentPath
            
            Mock Get-Item {
                return @{
                    Target = $testPhpPath
                }
            } -ParameterFilter { $Path -eq $testCurrentPath }
            
            # Act
            $result = Get-Current-PHP-Version
            
            # Assert
            $result.version | Should -Be "8.2.0"
            $result.path | Should -Be $testPhpPath
            $result.status.opcache | Should -Be $true
            $result.status.xdebug | Should -Be $false
        }
    }
}
