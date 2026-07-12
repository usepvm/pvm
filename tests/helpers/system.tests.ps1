
BeforeAll {
    Mock Write-Host {}
    # Create a mock registry to simulate environment variables
    $script:MockRegistry = @{
        Machine = @{
            'Path' = 'C:\Windows\System32;C:\Program Files\Git\bin;C:\CustomApp;C:\Program Files\Java\bin'
            'JAVA_HOME' = 'C:\Program Files\Java'
            'GIT_HOME' = 'C:\Program Files\Git\bin'
            'CUSTOM_APP' = 'C:\CustomApp'
            'WINDOWS_DIR' = 'C:\Windows'
            'SYSTEM32_DIR' = 'C:\Windows\System32'
            'REGULAR_VAR' = 'SomeValue'
        }
    }

    # Setup test environment
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\system-drive"
    $script:LOG_ERROR_PATH = $PVMConfig.paths.logError = "$TEST_DRIVE\logs\error.log"
    $script:STORAGE_PATH = $PVMConfig.paths.storage = "$TEST_DRIVE\storage"
    $script:PATH_VAR_BACKUP_PATH = $PVMConfig.paths.pathVarBackup = "$TEST_DRIVE\logs\path_backup.log"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path "$STORAGE_PATH\php\8.1" -Force | Out-Null
    New-Item -ItemType Directory -Path "$STORAGE_PATH\php\8.2" -Force | Out-Null

    # Mock file system for logging tests
    $script:MockFileSystem = @{
        Directories = @("$($STORAGE_PATH)\php\8.1", "$($STORAGE_PATH)\php\8.2")
        Files = @{
            "$($LOG_ERROR_PATH)" = @()
            "$($PATH_VAR_BACKUP_PATH)" = @()
        }
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

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Is-OS-64Bit" {
    It "Returns a boolean value indicating OS architecture" {
        $result = Is-OS-64Bit
        $result | Should -BeOfType [bool]
    }
}

Describe "Get-All-EnvVars-Core" {
    It "Returns machine-level environment variables" {
        $result = Get-All-EnvVars-Core
        $result | Should -Not -BeNullOrEmpty
        $result.GetType().Name | Should -Be 'Hashtable'
    }
}

Describe "Get-EnvVar-ByName-Core" {
    It "Returns environment variable value by name" {
        # Test with a known system variable that should exist
        $result = Get-EnvVar-ByName-Core -name 'Path'
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType [string]
    }

    It "Returns null for non-existent variable" {
        $result = Get-EnvVar-ByName-Core -name 'NONEXISTENT_VAR_12345'
        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-All-EnvVars" {
    BeforeAll {
        Mock Get-All-EnvVars-Core {
            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            $result = @{}
            $script:MockRegistry.Machine.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
            return $result
        }
    }

    Context "When retrieving environment variables" {
        It "Returns environment variables" {
            $result = Get-All-EnvVars
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be 'Hashtable'
        }
    }

    Context "When an exception occurs" {
        It "Returns null" {
            Mock Get-All-EnvVars-Core { throw $script:MockRegistryException }
            $result = Get-All-EnvVars
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Get-EnvVar-ByName" {
    BeforeAll {
        Mock Is-Not-Admin { return $false }
        Mock Get-All-EnvVars-Core {
            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            $result = @{}
            $script:MockRegistry.Machine.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
            return $result
        }
        Mock Get-EnvVar-ByName-Core {
            param ($name)

            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            return $script:MockRegistry.Machine[$name]
        }
    }

    Context "When variable exists" {
        It "Returns the variable value" {
            # Set a test variable
            Set-EnvVar -name 'TEST_VAR' -value 'TEST_VALUE'

            $result = Get-EnvVar-ByName -name 'TEST_VAR'
            $result | Should -Be 'TEST_VALUE'

            # Cleanup
            Set-EnvVar -name 'TEST_VAR' -value $null
        }
    }

    Context "When variable doesn't exist" {
        It "Returns null for non-existent variable" {
            $result = Get-EnvVar-ByName -name 'NON_EXISTENT_VAR'
            $result | Should -Be $null
        }

        It "Returns null for empty name" {
            $result = Get-EnvVar-ByName -name ''
            $result | Should -Be $null
        }

        It "Returns null for whitespace name" {
            $result = Get-EnvVar-ByName -name '   '
            $result | Should -Be $null
        }

        It "Returns null for null name" {
            $result = Get-EnvVar-ByName -name $null
            $result | Should -Be $null
        }
    }

    Context "When an exception occurs" {
        It "Returns null when an exception occurs" {
            Mock Get-EnvVar-ByName-Core { throw 'Simulated exception' }
            $result = Get-EnvVar-ByName -name 'SIMULATED_EXCEPTION'
            $result | Should -Be $null
        }
    }
}

Describe "Set-EnvVar" {
    BeforeAll {
        Mock Is-Not-Admin { return $false }
        Mock Get-EnvVar-ByName-Core {
            param ($name)

            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            return $script:MockRegistry.Machine[$name]
        }
    }

    Context "When setting environment variables" {
        It "Sets a new variable successfully (admin required)" {
            $result = Set-EnvVar -name 'TEST_VAR_SET' -value 'TEST_VALUE'
            $result | Should -Be 0

            $value = Get-EnvVar-ByName -name 'TEST_VAR_SET'
            $value | Should -Be 'TEST_VALUE'

            # Cleanup
            Set-EnvVar -name 'TEST_VAR_SET' -value $null
        }

        It "Returns -1 for empty name" {
            $result = Set-EnvVar -name '' -value 'TEST_VALUE'
            $result | Should -Be -1
        }
    }

    Context "When running as not admin" {
        It "Elevates and sets a new variable successfully" {
            Mock Is-Not-Admin { return $true }
            Mock Run-PS-Command { return 0 }
            $result = Set-EnvVar -name 'SIMULATED_EXCEPTION' -value 'TEST_VALUE'
            $result | Should -Be 0
        }
    }

    Context "When an exception occurs" {
        It "Returns -1 when an exception occurs" {
            Mock Set-EnvVar-Core { throw 'Simulated exception' }
            $result = Set-EnvVar -name 'SIMULATED_EXCEPTION' -value 'TEST_VALUE'
            $result | Should -Be -1
        }
    }
}

Describe "Optimize-SystemPath" {
    BeforeAll {
        Mock Is-Not-Admin { return $false }
        Mock Get-All-EnvVars-Core {
            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            $result = @{}
            $script:MockRegistry.Machine.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
            return $result
        }
        Mock Get-EnvVar-ByName-Core {
            param ($name)

            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            return $script:MockRegistry.Machine[$name]
        }
    }

    Context "When optimizing system PATH" {
        BeforeEach {
            # Set a test PATH with some variables
            $testPath = 'C:\Test1;C:\Test2;C:\Windows\System32'
            Set-EnvVar -name 'TEST_PATH1' -value 'C:\Test1'
            Set-EnvVar -name 'TEST_PATH2' -value 'C:\Test2'
            Set-EnvVar -name 'Path' -value $testPath
        }

        AfterEach {
            # Cleanup
            Set-EnvVar -name 'TEST_PATH1' -value $null
            Set-EnvVar -name 'TEST_PATH2' -value $null
        }

        It "Optimizes PATH by replacing paths with variables" {
            $result = Optimize-SystemPath
            $result | Should -Be 0

            $newPath = Get-EnvVar-ByName -name 'Path' -optimized $true
            $newPath | Should -Match '%TEST_PATH1%'
            $newPath | Should -Match '%TEST_PATH2%'
            $newPath | Should -Not -Match 'C:\\Test1'
            $newPath | Should -Not -Match 'C:\\Test2'
            $newPath | Should -Match 'C:\\Windows\\System32'  # System paths should remain
        }

        It "Creates a backup log file" {
            $result = Optimize-SystemPath
            $result | Should -Be 0

            Test-Path $PATH_VAR_BACKUP_PATH | Should -Be $true
            Get-Content -Path $PATH_VAR_BACKUP_PATH -Raw | Should -Match 'Original PATH'
        }

        It "Handles exceptions gracefully" {
            Mock Get-EnvVar-ByName { throw 'Simulated exception' }
            $result = Optimize-SystemPath
            $result | Should -Be -1

            # Check that an error was logged
            Test-Path $LOG_ERROR_PATH | Should -Be $true
            Get-Content -Path $LOG_ERROR_PATH -Raw | Should -Match 'Optimize-SystemPath - Failed to optimize system PATH variable'
        }

        It "Sets Path variable successfully after optimization" {
            Mock Get-EnvVar-ByName { return 'C:\Test1;C:\Test2;%var1%;C:\Windows\System32;%var1%' }
            Mock Set-EnvVar { return 0 }

            $result = Optimize-SystemPath

            $result | Should -Be 0
        }

        It "Handles missing Path variable gracefully" {
            Mock Get-EnvVar-ByName { return $null }
            Mock Remove-PathDuplicates { return '' }

            $result = Optimize-SystemPath

            $result | Should -Be 0
        }
    }
}

Describe "Run-Ps-Command" {
    Context "When executing PowerShell commands" {
        It "Passes -NoProfile and Bypass execution policy" {
            $mockProcess = @{ ExitCode = 0 }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {}
            Mock Start-Process { return $mockProcess }

            $result = Run-Ps-Command -command "Write-Host -Object 'hello'"

            Should -Invoke Start-Process -Times 1 -ParameterFilter {
                $FilePath -eq 'powershell.exe' -and
                $ArgumentList -contains '-NoProfile' -and
                $ArgumentList -contains '-ExecutionPolicy' -and
                $ArgumentList -contains 'Bypass'
            }
            $result | Should -Be 0
        }

        It "Returns the process exit code" {
            $mockProcess = @{ ExitCode = 42 }
            $mockProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {}
            Mock Start-Process { return $mockProcess }

            $result = Run-Ps-Command -command "Write-Error 'fail'"

            $result | Should -Be 42
        }
    }
}

Describe "Is-Admin" {
    Context "When checking admin status" {
        It "Returns a boolean value" {
            $result = Is-Admin
            $result | Should -BeOfType [bool]
        }
    }
}

Describe "Is-Not-Admin" {
    It "Returns a boolean value" {
        $result = Is-Not-Admin
        $result | Should -BeOfType [bool]
    }

    It "Returns true when not running as admin" {
        Mock Is-Admin { return $false }
        $result = Is-Not-Admin
        $result | Should -Be $true
    }

    It "Returns false when running as admin" {
        Mock Is-Admin { return $true }
        $result = Is-Not-Admin
        $result | Should -Be $false
    }
}
