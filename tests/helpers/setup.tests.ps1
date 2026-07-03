
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
}

AfterAll {
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Is-PVM-Setup" {
    BeforeAll {
        $global:PVMRoot = 'TestDrive:\pvm'
        $script:PHP_CURRENT_VERSION_PATH = $PVMConfig.env.PHP_CURRENT_VERSION_PATH = 'TestDrive:\pvm\php'
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
            Mock Is-Directory-Not-Exists { return $false }

            $result = Is-PVM-Setup
            $result | Should -Be $true
        }

        It "Should return true when pvm is in path with different casing" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$($PVMRoot.ToLower());$($PHP_CURRENT_VERSION_PATH.ToLower())"
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return "C:\other\paths;%$PVM_ENV_VAR_NAME%;C:\other2\paths"
            }
            Mock Is-Directory-Not-Exists { return $false }

            $result = Is-PVM-Setup
            $result | Should -Be $true
        }

        It "Should return false when the PVM var is null" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith { return $null }

            $result = Is-PVM-Setup
            $result | Should -Be $false
        }

        It "Should return false when the path var is null" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$PVMRoot;$PHP_CURRENT_VERSION_PATH"
            }
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'Path' } -MockWith { return $null }
            Mock Is-Directory-Not-Exists { return $false }

            $result = Is-PVM-Setup
            $result | Should -Be $false
        }
    }

    Context "When PVM is not properly set up" {
        It "Should return false when pvm is not in PATH" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return $PHP_CURRENT_VERSION_PATH
            }

            $result = Is-PVM-Setup
            $result | Should -Be $false
        }

        It "Should return false when PHP value is not in PATH" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return $PVMRoot
            }

            $result = Is-PVM-Setup
            $result | Should -Be $false
        }
    }

    Context "When exceptions occur" {
        It "Should return false and log error when Get-EnvVar-ByName throws exception" {
            Mock Get-EnvVar-ByName { throw 'Test exception' }
            Mock Log-Data { return 0 }

            $result = Is-PVM-Setup
            $result | Should -Be $false

            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq 'Is-PVM-Setup - Failed to check if PVM is set up'
            }
        }
    }
}

Describe "Is-PVM-Not-Setup" {
    It "Returns true when PVM is not set up" {
        Mock Is-PVM-Setup { return $false }

        $result = Is-PVM-Not-Setup
        $result | Should -Be $true
    }

    It "Returns false when PVM is set up" {
        Mock Is-PVM-Setup { return $true }

        $result = Is-PVM-Not-Setup
        $result | Should -Be $false
    }
}
