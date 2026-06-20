
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
    $script:PVMConfigBackup = $PVMConfig.Clone()
    $script:LOG_ERROR_PATH = $PVMConfig.paths.logError = 'TestDrive:\logs\error.log'
    $script:STORAGE_PATH = $PVMConfig.paths.storage = 'TestDrive:\storage'
    $script:PATH_VAR_BACKUP_PATH = $PVMConfig.paths.pathVarBackup = 'TestDrive:\logs\path_backup.log'

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

    Mock Is-Not-Admin { return $false }

    # Create wrapper functions that use our mock registry
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
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-All-EnvVars" {
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
