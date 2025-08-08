
Describe "Setup-PVM" {
     BeforeAll {
        Mock Write-Host {}
        # Mock global variables that the function depends on
        $global:PHP_CURRENT_ENV_NAME = "PHP"
        $global:PHP_CURRENT_VERSION_PATH = "C:\php\8.2"
        $global:PVMRoot = "C:\PVM"
        $global:LOG_ERROR_PATH = "TestDrive:\logs\error.log"
        
        # Initialize mock registry
        $global:MockRegistry = @{
            Machine = @{
                "Path" = "C:\Windows\System32"
                "PHP" = $null
                "pvm" = $null
            }
            Process = @{}
            User = @{}
        }
        
        # Mock Log-Data function
        Mock Log-Data { return $true }
        
        # Mock the System.Environment methods
        function Get-EnvironmentVariableWrapper {
            param($name, $target)
            
            if ($global:MockRegistryThrowException) {
                throw $global:MockRegistryException
            }
            
            switch ($target) {
                ([System.EnvironmentVariableTarget]::Machine) { return $global:MockRegistry.Machine[$name] }
                ([System.EnvironmentVariableTarget]::Process) { return $global:MockRegistry.Process[$name] }
                ([System.EnvironmentVariableTarget]::User) { return $global:MockRegistry.User[$name] }
                default { return $null }
            }
        }
        function Get-EnvVar-ByName {
            param ($name)
            try {
                if ([string]::IsNullOrWhiteSpace($name)) {
                    return $null
                }
                $name = $name.Trim()
                return Get-EnvironmentVariableWrapper -name $name -target ([System.EnvironmentVariableTarget]::Machine)
            } catch {
                $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-EnvVar-ByName: Failed to get environment variable '$name'" -data $_.Exception.Message
                return $null
            }
        }
        function Set-EnvironmentVariableWrapper {
            param($name, $value, $target)
            
            if ($global:MockRegistryThrowException) {
                throw $global:MockRegistryException
            }
            
            switch ($target) {
                ([System.EnvironmentVariableTarget]::Machine) { 
                    if ($value -eq $null) {
                        $global:MockRegistry.Machine.Remove($name)
                    } else {
                        $global:MockRegistry.Machine[$name] = $value
                    }
                }
                ([System.EnvironmentVariableTarget]::Process) { 
                    if ($value -eq $null) {
                        $global:MockRegistry.Process.Remove($name)
                    } else {
                        $global:MockRegistry.Process[$name] = $value
                    }
                }
                ([System.EnvironmentVariableTarget]::User) { 
                    if ($value -eq $null) {
                        $global:MockRegistry.User.Remove($name)
                    } else {
                        $global:MockRegistry.User[$name] = $value
                    }
                }
            }
        }
        function Set-EnvVar {
            param ($name, $value)
            try {
                if ([string]::IsNullOrWhiteSpace($name)) {
                    return -1
                }
                $name = $name.Trim()
                Set-EnvironmentVariableWrapper -name $name -value $value -target ([System.EnvironmentVariableTarget]::Machine)
                return 0
            } catch {
                $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Set-EnvVar: Failed to set environment variable '$name'" -data $_.Exception.Message
                return -1
            }
        }
        
    }

    BeforeEach {
        # Reset mock registry before each test
        $global:MockRegistry = @{
            Machine = @{
                "Path" = "C:\Windows\System32"
                "PHP" = $null
                "pvm" = $null
            }
            Process = @{}
            User = @{}
        }
    }

    BeforeEach {
        Mock Get-EnvVar-ByName -MockWith { return $null }
        Mock Set-EnvVar -MockWith { return 0 }
        Mock Is-Directory-Exists -MockWith { return $false }
        Mock Make-Directory -MockWith { return $true }
        Mock Log-Data -MockWith { return $true }
        Mock Optimize-SystemPath -MockWith {}
    }

    Context "When Path environment variable is empty" {
        It "Should add both PVM and PHP paths when neither exists" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq "Path" } -MockWith { return "" }
            
            $result = Setup-PVM
            
            $result.code | Should -Be 0
            $result.message | Should -Be "PVM environment has been set up."
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq "Path" -and $value -like "*%PHP%;%pvm%" } -Exactly 1
        }
    }

    Context "When Path environment variable has existing entries" {
        It "Should only add missing paths" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq "Path" } -MockWith { 
                return "C:\Windows\System32;C:\Program Files\PowerShell"
            }
            
            $result = Setup-PVM
            
            $result.code | Should -Be 0
            $result.message | Should -Be "PVM environment has been set up."
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq "Path" -and $value -like "*%PHP%;%pvm%" } -Exactly 1
        }

        It "Should not add paths that already exist" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq "Path" } -MockWith { 
                return "C:\Windows\System32;%PHP%;%pvm%"
            }
            
            $result = Setup-PVM
            
            $result.code | Should -Be 1
            $result.message | Should -Be "PVM environment is already set up."
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq "Path" } -Exactly 0
        }

        It "Should recognize existing paths in different cases" {
            Mock Get-EnvVar-ByName -ParameterFilter { $name -eq "Path" } -MockWith { 
                return "C:\Windows\System32;%php%;%PVM%"
            }
            
            $result = Setup-PVM
            
            $result.code | Should -Be 1
            $result.message | Should -Be "PVM environment is already set up."
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq "Path" } -Exactly 0
        }
    }

    Context "When directory creation is needed" {
        It "Should create parent directory if it doesn't exist" {
            Mock Get-EnvVar-ByName -MockWith { return "" }
            Mock Is-Directory-Exists -ParameterFilter { $path -eq (Split-Path $PHP_CURRENT_VERSION_PATH) } -MockWith { return $false }
            
            $result = Setup-PVM
            
            $result.code | Should -Be 0
            Should -Invoke Make-Directory -Exactly 1
        }

        It "Should not create directory if it already exists" {
            Mock Get-EnvVar-ByName -MockWith { return "" }
            Mock Is-Directory-Exists -ParameterFilter { $path -eq (Split-Path $PHP_CURRENT_VERSION_PATH) } -MockWith { return $true }
            
            $result = Setup-PVM
            
            $result.code | Should -Be 0
            Should -Invoke Make-Directory -Exactly 0
        }
    }

    Context "When environment variables need to be set" {
        It "Should set PHP_CURRENT_ENV_NAME variable" {
            Mock Get-EnvVar-ByName -MockWith { return "" }
            
            $result = Setup-PVM
            
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq $PHP_CURRENT_ENV_NAME -and $value -eq $PHP_CURRENT_VERSION_PATH } -Exactly 1
        }

        It "Should set PVM variable if not set" {
            Mock Get-EnvVar-ByName -MockWith { 
                if ($name -eq "pvm") { return $null }
                return ""
            }
            
            $result = Setup-PVM
            
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq "pvm" -and $value -eq $PVMRoot } -Exactly 1
        }

        It "Should not set PVM variable if already set" {
            Mock Get-EnvVar-ByName -MockWith { 
                if ($name -eq "pvm") { return "existing_value" }
                return ""
            }
            
            $result = Setup-PVM
            
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq "pvm" } -Exactly 0
        }
    }

    Context "When errors occur" {
        It "Should handle exceptions and log them" {
            Mock Get-EnvVar-ByName -MockWith { throw "Test exception" }
            
            $result = Setup-PVM
            
            $result.code | Should -Be -1
            $result.message | Should -Be "Failed to set up PVM environment."
            Should -Invoke Log-Data -Exactly 1
        }
    }

    AfterAll {
        Remove-Item function:Get-EnvVar-ByName
        Remove-Item function:Set-EnvVar
        Remove-Item function:Is-Directory-Exists
        Remove-Item function:Make-Directory
        Remove-Item function:Log-Data
        Remove-Item function:Optimize-SystemPath
        Remove-Item function:Setup-PVM
        
        Remove-Variable PHP_CURRENT_ENV_NAME -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable PHP_CURRENT_VERSION_PATH -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable PVMRoot -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable LOG_ERROR_PATH -Scope Global -ErrorAction SilentlyContinue
    }
}