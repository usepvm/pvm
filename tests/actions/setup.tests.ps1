
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
}

AfterAll {
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Setup-PVM" {
    BeforeAll {
        Mock Write-Host {}
        # Mock global variables that the function depends on
        $script:PHP_CURRENT_VERSION_PATH = $PVMConfig.env.PHP_CURRENT_VERSION_PATH = 'C:\php\8.2'
        $script:PVMRoot = 'TestDrive:\PVM'
        $script:PVM_ENV_VAR_NAME = $PVMConfig.env.PVM_ENV_VAR_NAME = 'PVM'
        $PVMConfig.paths.logError = 'TestDrive:\logs\error.log'

        # Initialize mock registry
        $script:MockRegistry = @{
            Machine = @{
                'Path' = 'C:\Windows\System32'
                'PHP' = $null
                'pvm' = $null
            }
        }

        # Mock Log-Data function
        Mock Log-Data { return 0 }

        Mock Is-Not-Admin { return $false }

        # Mock the System.Environment methods
        Mock Get-EnvVar-ByName-Core {
            param ($name)

            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            return $script:MockRegistry.Machine[$name]
        }

        Mock Set-EnvVar-Core {
            param ($name, $value)

            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            if ($null -eq $value) {
                $script:MockRegistry.Machine.Remove($name)
            } else {
                $script:MockRegistry.Machine[$name] = $value
            }
        }
    }

    BeforeEach {
        # Reset mock registry before each test
        $script:MockRegistry = @{
            Machine = @{
                'Path' = 'C:\Windows\System32'
                'pvm' = $null
            }
        }

        Mock Get-EnvVar-ByName -MockWith { return $null }
        Mock Set-EnvVar -MockWith { return 0 }
        Mock Is-Directory-Exists -MockWith { return $false }
        Mock Make-Directory { return 0 }
        Mock Log-Data -MockWith { return 0 }
        Mock Optimize-SystemPath -MockWith {}
    }

    Context "When Path environment variable is empty" {
        It "Should add both PVM and PHP paths when neither exists" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith { return $null }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }

            $result = Setup-PVM

            $result.code | Should -Be 0
            $result.message | Should -Be 'PVM environment has been set up.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$PVM_ENV_VAR_NAME*" } -Exactly 1
        }
    }

    Context "When Path environment variable has existing entries" {
        It "Should only add missing paths" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;C:\Program Files\PowerShell'
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }

            $result = Setup-PVM

            $result.code | Should -Be 0
            $result.message | Should -Be 'PVM environment has been set up.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$PVM_ENV_VAR_NAME*" } -Exactly 1
        }

        It "Should not add paths that already exist" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;%PVM%'
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }

            $result = Setup-PVM

            $result.code | Should -Be 0
            $result.message | Should -Be 'PVM environment has been set up.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' } -Exactly 0
        }

        It "Should recognize existing paths in different cases" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;%pvm%'
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$($PVMRoot.ToLower());$($PHP_CURRENT_VERSION_PATH.ToLower())"
            }

            $result = Setup-PVM

            $result.code | Should -Be 0
            $result.message | Should -Be 'PVM environment has been set up.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' } -Exactly 0
        }
    }

    Context "When directory creation is needed" {
        It "Should create parent directory if it doesn't exist" {
            Mock Get-EnvVar-ByName -MockWith { return '' }
            Mock Is-Directory-Exists -ParameterFilter { $path -eq (Split-Path -Path $PHP_CURRENT_VERSION_PATH) } -MockWith { return $false }

            $result = Setup-PVM

            $result.code | Should -Be 0
            Should -Invoke Make-Directory -Exactly 1
        }

        It "Should not create directory if it already exists" {
            Mock Get-EnvVar-ByName -MockWith { return '' }
            Mock Is-Directory-Exists -ParameterFilter { $path -eq (Split-Path -Path $PHP_CURRENT_VERSION_PATH) } -MockWith { return $true }
            Mock New-Item { }

            $result = Setup-PVM

            $result.code | Should -Be 0
            Should -Invoke Make-Directory -Exactly 1
            Should -Invoke New-Item -Exactly 0
        }
    }

    Context "When errors occur" {
        It "Should handle exceptions and log them" {
            Mock Get-EnvVar-ByName -MockWith { throw 'Test exception' }

            $result = Setup-PVM

            $result.code | Should -Be -1
            $result.message | Should -Be 'Failed to set up PVM environment.'
            Should -Invoke Log-Data -Exactly 1
        }

        It "Returns error code when Make-Directory fails" {
            Mock Get-EnvVar-ByName -MockWith { return $null }
            Mock Make-Directory -MockWith { return -1 }

            $result = Setup-PVM

            $result.code | Should -Be -1
            $result.message | Should -Be 'Failed to create directory for PHP version.'
        }

        It "Returns error code when Set-EnvVar fails" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;C:\Program Files\PowerShell'
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }
            Mock Set-EnvVar { -1 }

            $result = Setup-PVM

            $result.code | Should -Be -1
            $result.message | Should -Be 'Failed to set Path environment variable.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$PVM_ENV_VAR_NAME*" } -Exactly 1
        }
    }
}

Describe "Initialize-PVMDirectories" {
    It "Returns 0 when all directories and files are created" {
        Mock Make-Directory { return 0 }
        $result = Initialize-PVMDirectories
        $result | Should -Be @(0, 0, 0, 0, 0, 0, 0)
    }

    It "Returns -1 when a directory creation fails" {
        Mock Make-Directory { return -1 }
        $result = Initialize-PVMDirectories
        $result | Should -Be @(-1, -1, -1, -1, -1, -1, -1)
    }
}

Describe "Initialize-PVMFiles" {
    BeforeAll {
        Mock Create-Example-PHP-Profile { return 0 }
        Mock Create-Profile-Template { return 0 }
        Mock Set-Zend-Extensions-List { return 0 }
        Mock Set-Aliases-List { return 0 }
    }

    It "Returns -1 when the example profile creation fails" {
        Mock Create-Example-PHP-Profile { return -1 }
        $result = Setup-Environment-Directories-And-Files
        $result | Should -Be -1
    }

    It "Returns -1 when the profile template file creation fails" {
        Mock Create-Profile-Template { return -1 }
        $result = Setup-Environment-Directories-And-Files
        $result | Should -Be -1
    }

    It "Returns -1 when the zend extensions file creation fails" {
        Mock Set-Zend-Extensions-List { return -1 }
        $result = Setup-Environment-Directories-And-Files
        $result | Should -Be -1
    }

    It "Returns -1 when the aliases file creation fails" {
        Mock Set-Aliases-List { return -1 }
        $result = Setup-Environment-Directories-And-Files
        $result | Should -Be -1
    }
}

Describe "Setup-Environment-Directories-And-Files" {
    It "Returns 0 when all directories and files are created" {
        Mock Initialize-PVMDirectories { return @(0, 0) }
        Mock Initialize-PVMFiles { return @(0, 0) }

        $result = Setup-Environment-Directories-And-Files
        $result | Should -Be 0
    }

    It "Returns -1 when a directory creation fails" {
        Mock Initialize-PVMDirectories { return @(0, -1) }
        Mock Initialize-PVMFiles { return @(0, 0) }

        $result = Setup-Environment-Directories-And-Files
        $result | Should -Be -1
    }

    It "Returns -1 when a file creation fails" {
        Mock Initialize-PVMDirectories { return @(0, 0) }
        Mock Initialize-PVMFiles { return @(0, -1) }

        $result = Setup-Environment-Directories-And-Files
        $result | Should -Be -1
    }
}

Describe "Create-Env-File" {
    BeforeAll {
        $script:PVMRoot = 'TestDrive:\PVM'
        Mock Copy-Item { }
    }

    It "Returns -1 when the .env.example file is not found" {
        Mock Is-File-Not-Exists { return $true }

        $result = Create-Env-File

        $result | Should -Be -1
        Assert-MockCalled Copy-Item -Times 0
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like '*Failed to find .env.example file.*'
        }
    }

    It "Returns 0 when the user does not want to overwrite the .env file" {
        Mock Is-File-Not-Exists { return $false }
        New-Item -ItemType File -Path "$PVMRoot\.env" -Force | Out-Null
        Mock Read-Host { return 'n' }

        $result = Create-Env-File

        $result | Should -Be 0
        Assert-MockCalled Copy-Item -Times 0
    }

    It "Returns 0 when the user wants to overwrite the .env file" {
        Mock Is-File-Not-Exists { return $false }
        New-Item -ItemType File -Path "$PVMRoot\.env" -Force | Out-Null
        Mock Read-Host { return 'y' }

        $result = Create-Env-File

        $result | Should -Be 0
        Assert-MockCalled Copy-Item -Times 1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like '*Created .env file.*'
        }
    }

    It "Returns 0 when the .env is created" {
        Mock Is-File-Not-Exists -ParameterFilter { $path -eq "$PVMRoot\.env.example"} { return $false }
        Mock Is-File-Exists -ParameterFilter { $path -eq "$PVMRoot\.env"} { return $false }
        Mock Read-Host { }

        $result = Create-Env-File

        $result | Should -Be 0
        Assert-MockCalled Read-Host -Times 0
        Assert-MockCalled Copy-Item -Times 1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like '*Created .env file.*'
        }
    }

    It "Returns -1 when the .env is not created" {
        Mock Is-File-Not-Exists -ParameterFilter { $path -eq "$PVMRoot\.env.example"} { return $false }
        Mock Is-File-Exists -ParameterFilter { $path -eq "$PVMRoot\.env"} { return $false }
        Mock Read-Host { }
        Mock Copy-Item { throw 'Access denied' }

        $result = Create-Env-File

        $result | Should -Be -1
        Assert-MockCalled Read-Host -Times 0
        Assert-MockCalled Copy-Item -Times 1
    }
}

Describe "Pause-ForEnvEdit" {
    It "Should prompt the user to edit the .env file" {
        Mock Read-Host { return '' }

        Pause-ForEnvEdit

        Assert-MockCalled Read-Host -Times 1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like "*Edit $PVMRoot\.env now if you want custom settings*"
        }
    }
}
