
BeforeAll {
    $script:testEnvironment = Initialize-PVMTestEnvironment -driveName 'setup-check'
    $script:TEST_DRIVE = $TestEnvironment.TestDrive
}

AfterAll {
    Restore-PVMTestEnvironment -environment $testEnvironment
}

Describe "Test-PVMSetup" {
    BeforeAll {
        $global:PVMConfig.rootPath = "$TEST_DRIVE\pvm"
        $script:PHP_CURRENT_VERSION_PATH = $PVMConfig.env.PHP_CURRENT_VERSION_PATH
        $script:PVM_ENV_VAR_NAME = $PVMConfig.env.PVM_ENV_VAR_NAME
        New-Item -ItemType Directory -Path $global:PVMConfig.rootPath -Force | Out-Null
    }

    Context "When PVM is properly set up" {
        It "Should return true when all environment variables are correctly configured" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$($PVMConfig.rootPath);$PHP_CURRENT_VERSION_PATH"
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return "C:\other\paths;%$PVM_ENV_VAR_NAME%;C:\other2\paths"
            }
            Mock Test-DirectoryNotExists { return $false }

            $result = Test-PVMSetup
            $result | Should -Be $true
        }

        It "Should return true when pvm is in path with different casing" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$($PVMConfig.rootPath.ToLower());$($PHP_CURRENT_VERSION_PATH.ToLower())"
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return "C:\other\paths;%$PVM_ENV_VAR_NAME%;C:\other2\paths"
            }
            Mock Test-DirectoryNotExists { return $false }

            $result = Test-PVMSetup
            $result | Should -Be $true
        }

        It "Should return false when the PVM var is null" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith { return $null }

            $result = Test-PVMSetup
            $result | Should -Be $false
        }

        It "Should return false when the path var is null" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$($PVMConfig.rootPath);$PHP_CURRENT_VERSION_PATH"
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith { return $null }
            Mock Test-DirectoryNotExists { return $false }

            $result = Test-PVMSetup
            $result | Should -Be $false
        }
    }

    Context "When PVM is not properly set up" {
        It "Should return false when pvm is not in PATH" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return $PHP_CURRENT_VERSION_PATH
            }

            $result = Test-PVMSetup
            $result | Should -Be $false
        }

        It "Should return false when PHP value is not in PATH" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return $PVMConfig.rootPath
            }

            $result = Test-PVMSetup
            $result | Should -Be $false
        }
    }

    Context "When exceptions occur" {
        It "Should return false and log error when Get-EnvVarByName throws exception" {
            Mock Get-EnvVarByName { throw 'Test exception' }
            Mock Add-LogEntry { return 0 }

            $result = Test-PVMSetup
            $result | Should -Be $false

            Should -Invoke Add-LogEntry -Exactly 1 -ParameterFilter {
                $data.header -eq 'Test-PVMSetup - Failed to check if PVM is set up'
            }
        }
    }
}

Describe "Test-PVMNotSetup" {
    It "Returns true when PVM is not set up" {
        Mock Test-PVMSetup { return $false }

        $result = Test-PVMNotSetup
        $result | Should -Be $true
    }

    It "Returns false when PVM is set up" {
        Mock Test-PVMSetup { return $true }

        $result = Test-PVMNotSetup
        $result | Should -Be $false
    }
}
