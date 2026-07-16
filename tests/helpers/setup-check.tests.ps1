
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\setup-check-drive"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Test-PVM-Setup" {
    BeforeAll {
        $global:PVMRoot = "$TEST_DRIVE\pvm"
        $script:PHP_CURRENT_VERSION_PATH = $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$TEST_DRIVE\pvm\php"
        $script:PVM_ENV_VAR_NAME = $PVMConfig.env.PVM_ENV_VAR_NAME
        New-Item -ItemType Directory -Path $global:PVMRoot -Force | Out-Null
    }

    Context "When PVM is properly set up" {
        It "Should return true when all environment variables are correctly configured" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return "C:\other\paths;%$PVM_ENV_VAR_NAME%;C:\other2\paths"
            }
            Mock Test-Directory-Not-Exists { return $false }

            $result = Test-PVM-Setup
            $result | Should -Be $true
        }

        It "Should return true when pvm is in path with different casing" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$($PVMRoot.ToLower());$($PHP_CURRENT_VERSION_PATH.ToLower())"
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return "C:\other\paths;%$PVM_ENV_VAR_NAME%;C:\other2\paths"
            }
            Mock Test-Directory-Not-Exists { return $false }

            $result = Test-PVM-Setup
            $result | Should -Be $true
        }

        It "Should return false when the PVM var is null" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith { return $null }

            $result = Test-PVM-Setup
            $result | Should -Be $false
        }

        It "Should return false when the path var is null" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith { return $null }
            Mock Test-Directory-Not-Exists { return $false }

            $result = Test-PVM-Setup
            $result | Should -Be $false
        }
    }

    Context "When PVM is not properly set up" {
        It "Should return false when pvm is not in PATH" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return $PHP_CURRENT_VERSION_PATH
            }

            $result = Test-PVM-Setup
            $result | Should -Be $false
        }

        It "Should return false when PHP value is not in PATH" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return $PVMRoot
            }

            $result = Test-PVM-Setup
            $result | Should -Be $false
        }
    }

    Context "When exceptions occur" {
        It "Should return false and log error when Get-EnvVar-ByName throws exception" {
            Mock Get-EnvVar-ByName { throw 'Test exception' }
            Mock Add-LogEntry { return 0 }

            $result = Test-PVM-Setup
            $result | Should -Be $false

            Should -Invoke Add-LogEntry -Exactly 1 -ParameterFilter {
                $data.header -eq 'Test-PVM-Setup - Failed to check if PVM is set up'
            }
        }
    }
}

Describe "Test-PVM-Not-Setup" {
    It "Returns true when PVM is not set up" {
        Mock Test-PVM-Setup { return $false }

        $result = Test-PVM-Not-Setup
        $result | Should -Be $true
    }

    It "Returns false when PVM is set up" {
        Mock Test-PVM-Setup { return $true }

        $result = Test-PVM-Not-Setup
        $result | Should -Be $false
    }
}
