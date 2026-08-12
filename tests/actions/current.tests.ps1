
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\current-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:PHP_CURRENT_DIR = $PVMConfig.env.PHP_CURRENT_VERSION_PATH
    $script:PHP_DIR = $PVMConfig.paths.php

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PHP_CURRENT_DIR -Force | Out-Null

    Mock Show-Error {}

    Mock Add-LogEntry {
        param ($data)
        return $true
    }
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-PHPStatus Function Tests" {
    Context "When php.ini file exists and is valid" {
        It "Should detect enabled opcache extension" {
            # Arrange
            Mock Test-FileNotExists { return $false }
            Mock Get-MatchingPHPExtensionsStatus -ParameterFilter { $extName -match 'opcache' } {
                return @( @{ name = 'opcache'; status = 'Enabled'; enabled = $true; color = 'DarkGreen' } )
            }
            Mock Get-MatchingPHPExtensionsStatus -ParameterFilter { $extName -match 'xdebug' } {
                return @( @{ name = 'xdebug'; status = 'Disabled'; enabled = $false; color = 'DarkYellow' } )
            }

            # Act
            $result = Get-PHPStatus -phpPath $PHP_DIR

            # Assert
            ($result | Where-Object -FilterScript { $_.Name -like '*opcache*' }).Enabled | Should -Be $true
            ($result | Where-Object -FilterScript { $_.Name -like '*xdebug*' }).Enabled | Should -Be $false
        }

        It "Should detect enabled xdebug extension" {
            # Arrange
            Mock Test-FileNotExists { return $false }
            Mock Get-MatchingPHPExtensionsStatus -ParameterFilter { $extName -match 'opcache'} {
                return @( @{ name = 'opcache'; status = 'Disabled'; enabled = $false; color = 'DarkYellow' } )
            }
            Mock Get-MatchingPHPExtensionsStatus -ParameterFilter { $extName -match 'xdebug' } {
                return @( @{ name = 'xdebug'; status = 'Enabled'; enabled = $true; color = 'DarkGreen' } )
            }

            # Act
            $result = Get-PHPStatus -phpPath $PHP_DIR

            # Assert
            ($result | Where-Object -FilterScript { $_.Name -like '*opcache*' }).Enabled | Should -Be $false
            ($result | Where-Object -FilterScript { $_.Name -like '*xdebug*' }).Enabled | Should -Be $true
        }

        It "Should detect both opcache and xdebug when enabled" {
            # Arrange
            Mock Test-FileNotExists { return $false }
            Mock Get-MatchingPHPExtensionsStatus -ParameterFilter { $extName -match 'opcache'} {
                return @( @{ name = 'opcache'; status = 'Enabled'; enabled = $true; color = 'DarkGreen' } )
            }
            Mock Get-MatchingPHPExtensionsStatus -ParameterFilter { $extName -match 'xdebug' } {
                return @( @{ name = 'xdebug'; status = 'Enabled'; enabled = $true; color = 'DarkGreen' } )
            }

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object -FilterScript { $_.Name -like '*opcache*' }).Enabled | Should -Be $true
            ($result | Where-Object -FilterScript { $_.Name -like '*xdebug*' }).Enabled | Should -Be $true
        }

        It "Should detect both opcache and xdebug when disabled" {
            # Arrange
            Mock Test-FileNotExists { return $false }
            Mock Get-MatchingPHPExtensionsStatus -ParameterFilter { $extName -match 'opcache'} {
                return @( @{ name = 'opcache'; status = 'Disabled'; enabled = $false; color = 'DarkYellow' } )
            }
            Mock Get-MatchingPHPExtensionsStatus -ParameterFilter { $extName -match 'xdebug' } {
                return @( @{ name = 'xdebug'; status = 'Disabled'; enabled = $false; color = 'DarkYellow' } )
            }

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object -FilterScript { $_.Name -like '*opcache*' }).Enabled | Should -Be $false
            ($result | Where-Object -FilterScript { $_.Name -like '*xdebug*' }).Enabled | Should -Be $false
        }

        It "Should return false for both when no zend_extensions found" {
            # Arrange
            Mock Test-FileNotExists { return $false }
            Mock Get-MatchingPHPExtensionsStatus { return @() }

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            ($result | Where-Object -FilterScript { $_.Name -like '*opcache*' }).text | Should -Be 'Not Found'
            ($result | Where-Object -FilterScript { $_.Name -like '*xdebug*' }).text | Should -Be 'Not Found'
        }
    }

    Context "When php.ini file does not exist" {
        It "Should return -1 when php.ini is missing" {
            # Arrange
            $testPath = "$TEST_DRIVE\nonexistent"

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            $result.Length | Should -Be 0
        }
    }

    Context "When exceptions occur" {
        It "Should handle Get-Content exceptions gracefully" {
            # Arrange
            Mock Get-MatchingPHPExtensionsStatus { throw 'Access Denied' }

            # Act
            $result = Get-PHPStatus -phpPath $testPath

            # Assert
            $result.Length | Should -Be 0
        }

        It "Should handle Test-Path exceptions gracefully" {
            # Arrange
            Mock Test-FileNotExists { throw 'Access Denied' }
            Mock Add-LogEntry { return 0 }

            # Act
            $result = Get-PHPStatus -phpPath $PHP_DIR

            # Assert
            Should -Invoke Add-LogEntry -Times 1
            $result.Length | Should -Be 0
        }
    }
}

Describe "Get-CurrentPHPVersion Function Tests" {
    Context "When PHP current version symlink exists and is valid" {
        BeforeEach {
            # Mock Get-ItemWrapper to return a symlink object
            Mock Get-ItemWrapper {
                return @{
                    FullName = 'C:\php\current'
                    Target = 'C:\php\8.2.0'
                }
            } -ParameterFilter { $path -eq $PHP_CURRENT_DIR }
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
            $result.link | Should -Be 'C:\php\current'
        }
    }

    Context "When PHP current version path does not exist" {
        It "returns empty result when path does not exist" {
            # Arrange
            Mock Get-ItemWrapper { return @{ Target = 'C:\php\8.2.0' } }
            Mock Test-DirectoryExists { return $false }

            # Act
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be $null
            $result.path | Should -Be $null
            ($result.status | Where-Object -FilterScript { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result.status | Where-Object -FilterScript { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should return null values when path does not exist" {
            # Arrange
            Mock Get-ItemWrapper { throw 'Path does not exist' }

            # Act
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be $null
            $result.path | Should -Be $null
            ($result.status | Where-Object -FilterScript { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result.status | Where-Object -FilterScript { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }

        It "Should call Add-LogEntry when exception occurs" {
            # Arrange
            Mock Get-ItemWrapper { throw 'Path does not exist' }
            Mock Add-LogEntry { return 0 }

            # Act
            $null = Get-CurrentPHPVersion

            # Assert
            Should -Invoke Add-LogEntry -Times 1
        }
    }

    Context "When Get-ItemWrapper returns null" {
        BeforeEach {
            Mock Get-ItemWrapper {
                return $null
            } -ParameterFilter { $path -eq $PHP_CURRENT_DIR }
        }

        It "Should handle null Get-ItemWrapper result" {
            # Act
            $result = Get-CurrentPHPVersion

            # Assert
            $result.version | Should -Be $null
            $result.path | Should -Be $null
            ($result.status | Where-Object -FilterScript { $_.Name -eq 'opcache' }).Enabled | Should -Be $false
            ($result.status | Where-Object -FilterScript { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
        }
    }
}
