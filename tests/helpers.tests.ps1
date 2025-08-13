# Load required modules and functions
. "$PSScriptRoot\..\src\helpers\helpers.ps1"

Describe "System Functions Tests" {
    BeforeAll {
        
        Mock Write-Host {}
        # Create a mock registry to simulate environment variables
        $global:MockRegistry = @{
            Machine = @{
                "Path" = "C:\Windows\System32;C:\Program Files\Git\bin;C:\CustomApp;C:\Program Files\Java\bin"
                "JAVA_HOME" = "C:\Program Files\Java"
                "GIT_HOME" = "C:\Program Files\Git\bin"
                "CUSTOM_APP" = "C:\CustomApp"
                "WINDOWS_DIR" = "C:\Windows"
                "SYSTEM32_DIR" = "C:\Windows\System32"
                "REGULAR_VAR" = "SomeValue"
            }
            Process = @{}
            User = @{}
        }
        
        # Setup test environment
        $global:LOG_ERROR_PATH = "TestDrive:\logs\error.log"
        $global:STORAGE_PATH = "TestDrive:\storage"
        $global:PATH_VAR_BACKUP_PATH = "TestDrive:\logs\path_backup.log"
        
        New-Item -ItemType Directory -Path "$STORAGE_PATH\php\8.1" -Force | Out-Null
        New-Item -ItemType Directory -Path "$STORAGE_PATH\php\8.2" -Force | Out-Null
        
        
        # Mock file system for logging tests
        $global:MockFileSystem = @{
            Directories = @("$($STORAGE_PATH)\php\8.1", "$($STORAGE_PATH)\php\8.2")
            Files = @{
                "$($LOG_ERROR_PATH)" = @()
                "$($PATH_VAR_BACKUP_PATH)" = @()
            }
        }
    
        # Create wrapper functions that use our mock registry
        function Get-EnvironmentVariablesWrapper {
            param($target)
            
            if ($global:MockRegistryThrowException) {
                throw $global:MockRegistryException
            }
            
            switch ($target) {
                ([System.EnvironmentVariableTarget]::Machine) { 
                    $result = @{}
                    $global:MockRegistry.Machine.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                    return $result
                }
                ([System.EnvironmentVariableTarget]::Process) { 
                    $result = @{}
                    $global:MockRegistry.Process.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                    return $result
                }
                ([System.EnvironmentVariableTarget]::User) { 
                    $result = @{}
                    $global:MockRegistry.User.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                    return $result
                }
                default { return @{} }
            }
        }

        function Get-All-EnvVars {
            try {
                return Get-EnvironmentVariablesWrapper -target ([System.EnvironmentVariableTarget]::Machine)
            } catch {
                $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Get-All-EnvVars: Failed to get all environment variables" -data $_.Exception.Message
                return $null
            }
        }
        
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

    Describe "Get-All-Subdirectories" {
        Context "When path is valid" {
            It "Returns subdirectories for an existing path" {
                $result = Get-All-Subdirectories -path $STORAGE_PATH
                $result | Should -Not -BeNullOrEmpty
                $result.Count | Should -BeGreaterThan 0
            }
        }

        Context "When path is invalid" {
            It "Returns null for empty path" {
                $result = Get-All-Subdirectories -path ""
                $result | Should -Be $null
            }

            It "Returns null for whitespace path" {
                $result = Get-All-Subdirectories -path "   "
                $result | Should -Be $null
            }

            It "Returns null for non-existent path" {
                $result = Get-All-Subdirectories -path "C:\Nonexistent\Path"
                $result | Should -Be $null
            }
        }
    }

    Describe "Get-All-EnvVars" {
        Context "When retrieving environment variables" {
            It "Returns environment variables" {
                $result = Get-All-EnvVars
                $result | Should -Not -BeNullOrEmpty
                $result.GetType().Name | Should -Be "Hashtable"
            }
        }
    }

    Describe "Get-EnvVar-ByName" {
        Context "When variable exists" {
            It "Returns the variable value" {
                # Set a test variable
                Set-EnvVar -name "TEST_VAR" -value "TEST_VALUE"
                
                $result = Get-EnvVar-ByName -name "TEST_VAR"
                $result | Should -Be "TEST_VALUE"
                
                # Cleanup
                Set-EnvVar -name "TEST_VAR" -value $null
            }
        }

        Context "When variable doesn't exist" {
            It "Returns null for non-existent variable" {
                $result = Get-EnvVar-ByName -name "NON_EXISTENT_VAR"
                $result | Should -Be $null
            }

            It "Returns null for empty name" {
                $result = Get-EnvVar-ByName -name ""
                $result | Should -Be $null
            }

            It "Returns null for whitespace name" {
                $result = Get-EnvVar-ByName -name "   "
                $result | Should -Be $null
            }
        }
    }

    Describe "Set-EnvVar" {
        Context "When setting environment variables" {
            It "Sets a new variable successfully (admin required)" {
                $result = Set-EnvVar -name "TEST_VAR_SET" -value "TEST_VALUE"
                $result | Should -Be 0
                
                $value = Get-EnvVar-ByName -name "TEST_VAR_SET"
                $value | Should -Be "TEST_VALUE"
                
                # Cleanup
                Set-EnvVar -name "TEST_VAR_SET" -value $null
            }

            It "Returns -1 for empty name" {
                $result = Set-EnvVar -name "" -value "TEST_VALUE"
                $result | Should -Be -1
            }
        }
    }

    Describe "Get-PHP-Path-By-Version" {
        BeforeEach {
            Mock Is-Directory-Exists {
                param ($path)                    
                return (Test-Path $path)
            }
        }
        Context "When version exists" {
            It "Returns correct path for existing version" {                
                $result = Get-PHP-Path-By-Version -version "8.1"
                $result | Should -Be "$STORAGE_PATH\php\8.1"
            }
        }

        Context "When version doesn't exist" {
            It "Returns null for non-existent version" {
                $result = Get-PHP-Path-By-Version -version "5.6"
                $result | Should -Be $null
            }

            It "Returns null for empty version" {
                $result = Get-PHP-Path-By-Version -version ""
                $result | Should -Be $null
            }

            It "Returns null for whitespace version" {
                $result = Get-PHP-Path-By-Version -version "   "
                $result | Should -Be $null
            }
        }
    }

    Describe "Make-Symbolic-Link" {
        Context "When creating symbolic links" {
            It "Creates a symbolic link successfully (admin required)" -Skip:(! (Is-Admin)) {
                $linkPath = "TestDrive:\test_link"
                $targetPath = "$STORAGE_PATH\php\8.1"
                
                $result = Make-Symbolic-Link -link $linkPath -target $targetPath
                $result.code | Should -Be 0
                
                Test-Path $linkPath | Should -Be $true
                (Get-Item $linkPath).LinkType | Should -Be "SymbolicLink"
            }

            It "Returns -1 for empty link path" {
                $result = Make-Symbolic-Link -link "" -target "TestDrive:\target"
                $result.code | Should -Be -1
            }

            It "Returns -1 for empty target path" {
                $result = Make-Symbolic-Link -link "TestDrive:\link" -target ""
                $result.code | Should -Be -1
            }
        }
    }

    Describe "Is-Directory-Exists" {
        Context "When checking directory existence" {
            It "Returns true for existing directory" {
                $result = Is-Directory-Exists -path $STORAGE_PATH
                $result | Should -Be $true
            }

            It "Returns false for non-existent directory" {
                $result = Is-Directory-Exists -path "C:\Nonexistent\Path"
                $result | Should -Be $false
            }

            It "Returns false for empty path" {
                $result = Is-Directory-Exists -path ""
                $result | Should -Be $false
            }

            It "Returns false for whitespace path" {
                $result = Is-Directory-Exists -path "   "
                $result | Should -Be $false
            }
        }
    }

    Describe "Make-Directory" {
        Context "When creating directories" {
            It "Creates a new directory successfully" {
                $newDir = "TestDrive:\new_dir"
                $result = Make-Directory -path $newDir
                $result | Should -Be 0
                Test-Path $newDir | Should -Be $true
            }

            It "Returns 0 for existing directory" {
                $result = Make-Directory -path $STORAGE_PATH
                $result | Should -Be 0
            }

            It "Returns -1 for empty path" {
                $result = Make-Directory -path ""
                $result | Should -Be -1
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

    Describe "Display-Msg-By-ExitCode" {
        Context "When displaying messages" {
            It "Displays message without error" {
                Mock Write-Host {}
                $testResult = @{
                    message = "Test message"
                    color = "Gray"
                }
                { Display-Msg-By-ExitCode -result $testResult } | Should -Not -Throw
            }
        }
    }

    Describe "Log-Data" {
        Context "When logging data" {
            It "Logs data successfully" {
                $logPath = "TestDrive:\logs\test.log"
                $result = Log-Data -logPath $logPath -message "Test message" -data "Test data"
                $result | Should -Be 0
                Test-Path $logPath | Should -Be $true
                # Get the actual content
                $content = Get-Content $logPath -Raw
                
                # Verify the complete log format
                $content | Should -Match "\[.*\] Test message :\s*Test data"
                
                # Alternatively, you could check parts separately
                $content | Should -Match "Test message"
                $content | Should -Match "Test data"
                $content | Should -Match (Get-Date -Format "yyyy-MM-dd")
            }

            It "Returns -1 when unable to create directory" {
                Mock Make-Directory { throw "Failed to create directory" }
                # Try to log to a protected location
                $result = Log-Data -logPath "C:\Windows\test.log" -message "Test" -data "Test"
                $result | Should -Be -1
            }
        }
    }

    Describe "Optimize-SystemPath" {
        Context "When optimizing system PATH" {
            BeforeEach {
                # Set a test PATH with some variables
                $testPath = "C:\Test1;C:\Test2;C:\Windows\System32"
                Set-EnvVar -name "TEST_PATH1" -value "C:\Test1"
                Set-EnvVar -name "TEST_PATH2" -value "C:\Test2"
                Set-EnvVar -name "Path" -value $testPath
            }

            AfterEach {
                # Cleanup
                Set-EnvVar -name "TEST_PATH1" -value $null
                Set-EnvVar -name "TEST_PATH2" -value $null
            }

            It "Optimizes PATH by replacing paths with variables" -Skip:(! (Is-Admin)) {
                $result = Optimize-SystemPath
                $result | Should -Be 0
                
                $newPath = Get-EnvVar-ByName -name "Path"
                $newPath | Should -Match "%TEST_PATH1%"
                $newPath | Should -Match "%TEST_PATH2%"
                $newPath | Should -Not -Match "C:\\Test1"
                $newPath | Should -Not -Match "C:\\Test2"
                $newPath | Should -Match "C:\\Windows\\System32"  # System paths should remain
            }

            It "Creates a backup log file" {
                $result = Optimize-SystemPath
                $result | Should -Be 0
                
                Test-Path $PATH_VAR_BACKUP_PATH | Should -Be $true
                Get-Content $PATH_VAR_BACKUP_PATH -Raw | Should -Match "Original PATH"
            }
        }
    }
}