
BeforeAll {
    # Mock dependencies
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\current-drive"
    $PVMConfig.paths.logError = "$TEST_DRIVE\logs\error.log"
    $script:PHP_DIR = "$TEST_DRIVE\php"
    $script:PHP_CURRENT_DIR = $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$PHP_DIR\current"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PHP_CURRENT_DIR -Force | Out-Null

    # Mock Add-LogEntry function
    Mock Write-Host {}

    Mock Add-LogEntry {
        param ($data)
        return $true
    }
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-PHPStatus Function Tests" {
    BeforeEach {
        Mock Get-ZendExtensionsInfo {
            return @(
                @{
                    Name      = 'opcache'
                    Version   = '8.2.0'
                    Copyright = 'Zend'
                    Enabled   = $true
                },
                @{
                    Name      = 'xdebug'
                    Version   = '3.2.0'
                    Copyright = 'Zend'
                    Enabled   = 'false'
                }
            )
        }
    }
    Context "When php.ini file exists and is valid" {
        It "Should detect enabled opcache extension" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                '# PHP Configuration',
                'zend_extension=opcache.dll',
                'zend_extension=some_other.dll'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $true
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should detect enabled xdebug extension" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                '# PHP Configuration',
                'zend_extension=xdebug.dll',
                'extension=mysqli.dll'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $true
        }

        It "Should detect both opcache and xdebug when enabled" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                'zend_extension=opcache.dll',
                'zend_extension=xdebug.dll'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $true
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $true
        }

        It "Should detect disabled (commented) opcache extension" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                '; Disabled opcache',
                ';zend_extension=opcache.dll',
                'extension=mysqli.dll'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should detect disabled (commented) xdebug extension" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                '; Disabled xdebug',
                ';zend_extension=xdebug.dll'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should handle mixed enabled/disabled extensions" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                'zend_extension=opcache.dll',
                ';zend_extension=xdebug.dll'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $true
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should handle extensions with full paths" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                'zend_extension="C:\php\ext\opcache.dll"',
                'zend_extension="C:\php\ext\xdebug.dll"'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $true
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $true
        }

        It "Should handle extensions with spaces in configuration" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                '  zend_extension  =  opcache.dll  ',
                '  ;  zend_extension  =  xdebug.dll  '
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $true
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should return false for both when no zend_extensions found" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            $phpIniContent = @(
                '# PHP Configuration',
                'extension=mysqli.dll',
                'memory_limit=128M'
            )
            $phpIniContent | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should handle empty php.ini file" {
            # Arrange
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            '' | Out-File -FilePath "$testPath\php.ini"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }
    }

    Context "When php.ini file does not exist" {
        It "Should return -1 when php.ini is missing" {
            # Arrange
            $testPath = "$TEST_DRIVE\nonexistent"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }
    }

    Context "When exceptions occur" {
        It "Should handle Get-Content exceptions gracefully" {
            # Arrange - Create a directory instead of a file to cause Get-Content to fail
            $testPath = $PHP_DIR
            New-Item -Path $testPath -ItemType Directory -Force
            New-Item -Path "$testPath\php.ini" -ItemType Directory -Force

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should handle Test-Path exceptions gracefully" {
            # Arrange
            Mock Test-FileNotExists { throw 'Access Denied' }
            Mock Add-LogEntry { return 0 }
            $testPath = $PHP_DIR

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            Should -Invoke Add-LogEntry -Times 1
            ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }
    }
}

Describe "Get-CurrentPHPVersion Function Tests" {
    Context "When PHP current version symlink exists and is valid" {
        BeforeEach {
            # Mock Get-Item to return a symlink object
            Mock Get-Item {
                return @{
                    Target = 'C:\php\8.2.0'
                }
            } -ParameterFilter { $Path -eq $PHP_CURRENT_DIR }

            # Mock Get-PHPStatus
            Mock Get-PHPStatus {
                return @{ opcache = $true; xdebug = $false }
            }
        }

        It "Should return correct version information when symlink is valid" {
            # Act
            Mock Get-PHPInstallInfo {@{
                Version = '8.2.0'
                Arch = 'x64'
                BuildType = 'ts'
                InstallPath = 'C:\php\8.2.0'
            }}
            Mock Test-DirectoryExists { return $true }
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be '8.2.0'
            $result.path | Should -Be 'C:\php\8.2.0'
            $result.status.opcache | Should -Be $true
            $result.status.xdebug | Should -Be $false
        }

        It "Should call Get-PHPStatus with correct path" {
            # Act
            Mock Get-PHPInstallInfo {@{
                Version = '8.2.0'
                Arch = 'x64'
                BuildType = 'ts'
                InstallPath = 'C:\php\8.2.0'
            }}
            Mock Test-DirectoryExists { return $true }
            $null = Get-CurrentPHPVersion

            # Assert
            Should -Invoke Get-PHPStatus -Times 1 -ParameterFilter { $phpPath -eq 'C:\php\8.2.0' }
        }
    }

    Context "When PHP current version path does not exist" {
        It "returns empty result when path does not exist" {
            # Arrange
            Mock Get-Item { return @{ Target = 'C:\php\8.2.0' } }
            Mock Test-DirectoryExists { return $false }

            # Act
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be $null
            $result.path | Should -Be $null
            ($result.status | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result.status | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should return null values when path does not exist" {
            # Arrange
            Mock Get-Item { throw 'Path does not exist' }

            # Act
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be $null
            $result.path | Should -Be $null
            ($result.status | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result.status | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should call Add-LogEntry when exception occurs" {
            # Arrange
            Mock Get-Item { throw 'Path does not exist' }
            Mock Add-LogEntry { return 0 }

            # Act
            $null = Get-CurrentPHPVersion

            # Assert
            Should -Invoke Add-LogEntry -Times 1
        }
    }

    Context "When Get-Item returns null" {
        BeforeEach {
            Mock Get-Item {
                return $null
            } -ParameterFilter { $Path -eq $PHP_CURRENT_DIR }
        }

        It "Should handle null Get-Item result" {
            # Act
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be $null
            $result.path | Should -Be $null
            ($result.status | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result.status | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }
    }

    Context "When Get-PHPStatus fails" {
        BeforeEach {
            Mock Get-Item {
                return @{
                    Target = 'C:\php\8.1.0'
                }
            } -ParameterFilter { $Path -eq $PHP_CURRENT_DIR }

            # Mock Get-PHPStatus to return -1 (error case)
            Mock Get-PHPStatus {
                return @{ opcache = $false; xdebug = $false }
            }
        }

        It "Should handle Get-PHPStatus error gracefully" {
            Mock Get-PHPInstallInfo {@{
                Version = '8.1.0'
                Arch = 'x64'
                BuildType = 'ts'
                InstallPath = 'C:\php\8.1.0'
            }}
            Mock Test-DirectoryExists { return $true }
            # Act
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be '8.1.0'
            $result.path | Should -Be 'C:\php\8.1.0'
            $result.status.opcache | Should -Be $false
            $result.status.xdebug | Should -Be $false
        }
    }
}

Describe "Integration Tests" {
    Context "Real-world scenarios" {
        It "Should work end-to-end with actual file system" {
            Mock Get-PHPInstallInfo {@{
                Version = '8.2.0'
                Arch = 'x64'
                BuildType = 'ts'
                InstallPath = "$PHP_DIR\8.2.0"
            }}
            # Arrange
            $testPhpPath = "$PHP_DIR\8.2.0"
            $testCurrentPath = "$PHP_DIR\current"

            New-Item -Path $testPhpPath -ItemType Directory -Force

            $phpIniContent = @(
                'zend_extension=opcache.dll',
                ';zend_extension=xdebug.dll',
                'memory_limit=256M'
            )
            $phpIniContent | Out-File -FilePath "$testPhpPath\php.ini"

            Mock Get-Item {
                return @{
                    Target = $testPhpPath
                }
            } -ParameterFilter { $Path -eq $testCurrentPath }

            # Act
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be '8.2.0'
            $result.path | Should -Be $testPhpPath
            ($result.status | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $true
            ($result.status | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }
    }
}
