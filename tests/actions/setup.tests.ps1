
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\setup-drive"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Initialize-PVM" {
    BeforeAll {
        Mock Write-Host {}
        # Mock global variables that the function depends on
        $script:PHP_CURRENT_VERSION_PATH = $PVMConfig.env.PHP_CURRENT_VERSION_PATH = 'C:\php\8.2'
        $script:PVMRoot = "$TEST_DRIVE\PVM"
        $script:PVM_ENV_VAR_NAME = $PVMConfig.env.PVM_ENV_VAR_NAME = 'PVM'
        $PVMConfig.paths.logError = "$TEST_DRIVE\logs\error.log"

        # Initialize mock registry
        $script:MockRegistry = @{
            Machine = @{
                'Path' = 'C:\Windows\System32'
                'PHP' = $null
                'pvm' = $null
            }
        }

        # Mock Add-LogEntry function
        Mock Add-LogEntry { return 0 }

        Mock Test-NotAdmin { return $false }

        # Mock the System.Environment methods
        Mock Get-EnvVarByNameCore {
            param ($name)

            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            return $script:MockRegistry.Machine[$name]
        }

        Mock Set-EnvVarCore {
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

        Mock Get-EnvVarByName -MockWith { return $null }
        Mock Set-EnvVar -MockWith { return 0 }
        Mock Test-DirectoryExists -MockWith { return $false }
        Mock New-Directory { return 0 }
        Mock Add-LogEntry -MockWith { return 0 }
        Mock Optimize-SystemPath -MockWith {}
    }

    Context "When Path environment variable is empty" {
        It "Should add both PVM and PHP paths when neither exists" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith { return $null }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }

            $result = Initialize-PVM

            $result.code | Should -Be 0
            $result.message | Should -Be 'PVM environment has been set up.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$PVM_ENV_VAR_NAME*" } -Exactly 1
        }
    }

    Context "When Path environment variable has existing entries" {
        It "Should only add missing paths" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;C:\Program Files\PowerShell'
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }

            $result = Initialize-PVM

            $result.code | Should -Be 0
            $result.message | Should -Be 'PVM environment has been set up.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$PVM_ENV_VAR_NAME*" } -Exactly 1
        }

        It "Should not add paths that already exist" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;%PVM%'
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }

            $result = Initialize-PVM

            $result.code | Should -Be 0
            $result.message | Should -Be 'PVM environment has been set up.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' } -Exactly 0
        }

        It "Should recognize existing paths in different cases" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;%pvm%'
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$($PVMRoot.ToLower());$($PHP_CURRENT_VERSION_PATH.ToLower())"
            }

            $result = Initialize-PVM

            $result.code | Should -Be 0
            $result.message | Should -Be 'PVM environment has been set up.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' } -Exactly 0
        }
    }

    Context "When directory creation is needed" {
        It "Should create parent directory if it doesn't exist" {
            Mock Get-EnvVarByName -MockWith { return '' }
            Mock Test-DirectoryExists -ParameterFilter { $path -eq (Split-Path -Path $PHP_CURRENT_VERSION_PATH) } -MockWith { return $false }

            $result = Initialize-PVM

            $result.code | Should -Be 0
            Should -Invoke New-Directory -Exactly 1
        }

        It "Should not create directory if it already exists" {
            Mock Get-EnvVarByName -MockWith { return '' }
            Mock Test-DirectoryExists -ParameterFilter { $path -eq (Split-Path -Path $PHP_CURRENT_VERSION_PATH) } -MockWith { return $true }
            Mock New-Item { }

            $result = Initialize-PVM

            $result.code | Should -Be 0
            Should -Invoke New-Directory -Exactly 1
            Should -Invoke New-Item -Exactly 0
        }
    }

    Context "When errors occur" {
        It "Should handle exceptions and log them" {
            Mock Get-EnvVarByName -MockWith { throw 'Test exception' }

            $result = Initialize-PVM

            $result.code | Should -Be -1
            $result.message | Should -Be 'Failed to set up PVM environment.'
            Should -Invoke Add-LogEntry -Exactly 1
        }

        It "Returns error code when New-Directory fails" {
            Mock Get-EnvVarByName -MockWith { return $null }
            Mock New-Directory -MockWith { return -1 }

            $result = Initialize-PVM

            $result.code | Should -Be -1
            $result.message | Should -Be 'Failed to create directory for PHP version.'
        }

        It "Returns error code when Set-EnvVar fails" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;C:\Program Files\PowerShell'
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }
            Mock Set-EnvVar { -1 }

            $result = Initialize-PVM

            $result.code | Should -Be -1
            $result.message | Should -Be 'Failed to set Path environment variable.'
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$PVM_ENV_VAR_NAME*" } -Exactly 1
        }
    }
}

Describe "Initialize-PVMDirectories" {
    It "Returns 0 when all directories and files are created" {
        Mock New-Directory { return 0 }
        $result = Initialize-PVMDirectories
        $result | Should -Be @(0, 0, 0, 0, 0, 0, 0, 0)
    }

    It "Returns -1 when a directory creation fails" {
        Mock New-Directory { return -1 }
        $result = Initialize-PVMDirectories
        $result | Should -Be @(-1, -1, -1, -1, -1, -1, -1, -1)
    }
}

Describe "Initialize-PVMFiles" {
    BeforeAll {
        Mock New-ExamplePHPProfile { return 0 }
        Mock New-ProfileTemplate { return 0 }
        Mock Set-ZendExtensionsList { return 0 }
        Mock Set-AliasesList { return 0 }
        Mock Set-Scripts-List { return 0 }
    }

    It "Returns -1 when the example profile creation fails" {
        Mock New-ExamplePHPProfile { return -1 }
        $result = Initialize-EnvironmentDirectoriesAndFiles
        $result | Should -Be -1
    }

    It "Returns -1 when the profile template file creation fails" {
        Mock New-ProfileTemplate { return -1 }
        $result = Initialize-EnvironmentDirectoriesAndFiles
        $result | Should -Be -1
    }

    It "Returns -1 when the zend extensions file creation fails" {
        Mock Set-ZendExtensionsList { return -1 }
        $result = Initialize-EnvironmentDirectoriesAndFiles
        $result | Should -Be -1
    }

    It "Returns -1 when the aliases file creation fails" {
        Mock Set-AliasesList { return -1 }
        $result = Initialize-EnvironmentDirectoriesAndFiles
        $result | Should -Be -1
    }

    It "Returns -1 when the scripts file creation fails" {
        Mock Set-Scripts-List { return -1 }
        $result = Initialize-EnvironmentDirectoriesAndFiles
        $result | Should -Be -1
    }
}

Describe "Initialize-EnvironmentDirectoriesAndFiles" {
    It "Returns 0 when all directories and files are created" {
        Mock Initialize-PVMDirectories { return @(0, 0) }
        Mock Initialize-PVMFiles { return @(0, 0) }

        $result = Initialize-EnvironmentDirectoriesAndFiles
        $result | Should -Be 0
    }

    It "Returns -1 when a directory creation fails" {
        Mock Initialize-PVMDirectories { return @(0, -1) }
        Mock Initialize-PVMFiles { return @(0, 0) }

        $result = Initialize-EnvironmentDirectoriesAndFiles
        $result | Should -Be -1
    }

    It "Returns -1 when a file creation fails" {
        Mock Initialize-PVMDirectories { return @(0, 0) }
        Mock Initialize-PVMFiles { return @(0, -1) }

        $result = Initialize-EnvironmentDirectoriesAndFiles
        $result | Should -Be -1
    }
}

Describe "New-EnvFile" {
    BeforeAll {
        $script:PVMRoot = "$TEST_DRIVE\PVM"
        Mock Copy-Item { }
    }

    It "Returns -1 when the .env.example file is not found" {
        Mock Test-FileNotExists { return $true }

        $result = New-EnvFile

        $result | Should -Be -1
        Should -Invoke Copy-Item -Times 0
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -like '*Failed to find .env.example file.*'
        }
    }

    It "Returns 0 when the user does not want to overwrite the .env file" {
        Mock Test-FileNotExists { return $false }
        New-Item -ItemType File -Path "$PVMRoot\.env" -Force | Out-Null
        Mock Read-Host { return 'n' }

        $result = New-EnvFile

        $result | Should -Be -1
        Should -Invoke Copy-Item -Times 0
    }

    It "Returns 0 when the user wants to overwrite the .env file" {
        Mock Test-FileNotExists { return $false }
        New-Item -ItemType File -Path "$PVMRoot\.env" -Force | Out-Null
        Mock Read-Host { return 'y' }

        $result = New-EnvFile

        $result | Should -Be 0
        Should -Invoke Copy-Item -Times 1
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -like '*Created .env file.*'
        }
    }

    It "Returns 0 when the .env is created" {
        Mock Test-FileNotExists -ParameterFilter { $path -eq "$PVMRoot\.env.example"} { return $false }
        Mock Test-FileExists -ParameterFilter { $path -eq "$PVMRoot\.env"} { return $false }
        Mock Read-Host { }

        $result = New-EnvFile

        $result | Should -Be 0
        Should -Invoke Read-Host -Times 0
        Should -Invoke Copy-Item -Times 1
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -like '*Created .env file.*'
        }
    }

    It "Returns -1 when the .env is not created" {
        Mock Test-FileNotExists -ParameterFilter { $path -eq "$PVMRoot\.env.example"} { return $false }
        Mock Test-FileExists -ParameterFilter { $path -eq "$PVMRoot\.env"} { return $false }
        Mock Read-Host { }
        Mock Copy-Item { throw 'Access denied' }

        $result = New-EnvFile

        $result | Should -Be -1
        Should -Invoke Read-Host -Times 0
        Should -Invoke Copy-Item -Times 1
    }
}

Describe "Wait-ForEnvEdit" {
    It "Should prompt the user to edit the .env file" {
        Mock Read-Host { return '' }
        Mock Get-Config { return @{} }

        Wait-ForEnvEdit

        Should -Invoke Read-Host -Times 1
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -like "*Edit $PVMRoot\.env now if you want custom settings*"
        }
    }
}
