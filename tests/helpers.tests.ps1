# Load required modules and functions
. "$PSScriptRoot\..\src\functions\helpers.ps1"

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
            $logged = Log-Data -data @{
                header = "Get-All-EnvVars: Failed to get all environment variables"
                exception = $_
            }
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
            $logged = Log-Data -data @{
                header = "Get-EnvVar-ByName: Failed to get environment variable '$name'"
                exception = $_
            }
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
            $logged = Log-Data -data @{
                header = "Set-EnvVar: Failed to set environment variable '$name'"
                exception = $_
            }
            return -1
        }
    }
    
}

Describe "Get-Data-From-Cache" {    
    It "Returns data from cache file" {
        Mock Get-Content { return @'
            {
                "Releases": [
                    "/downloads/releases/php-7.4.33-Win32-vc15-x64.zip",
                    "/downloads/releases/php-8.0.30-Win32-vs16-x64.zip",
                    "/downloads/releases/php-8.4.12-Win32-vs17-x64.zip"
                ],
                "Archives": [
                    "/downloads/releases/archives/php-5.5.0-Win32-VC11-x64.zip",
                    "/downloads/releases/archives/php-5.5.1-Win32-VC11-x64.zip"
                ]
            }
'@
        }
        $list = Get-Data-From-Cache -cacheFileName "test.json"
        $list.Releases[0] | Should -Be "/downloads/releases/php-7.4.33-Win32-vc15-x64.zip"
        $list.Archives[0] | Should -Be "/downloads/releases/archives/php-5.5.0-Win32-VC11-x64.zip"
    }
    
    It "Handles exceptions gracefully" {
        Mock Get-Content { throw "Simulated exception" }
        $list = Get-Data-From-Cache -cacheFileName "test.json"
        $list.Count | Should -Be 0
    }
}

Describe "Cache-Data" {
    It "Caches data successfully" {
        Mock ConvertTo-Json { return '{"Releases":["php-8.4.12.zip"],"Archives":["php-5.5.0.zip"]}' }
        Mock Make-Directory { return 0 }
        Mock Set-Content { }
        $code = Cache-Data -cacheFileName "test" -data @{"Releases" = @("php-8.4.12.zip"); "Archives" = @("php-5.5.0.zip")}
        $code | Should -Be 0
    }
    
    It "Fails to creade cache directory" {
        Mock ConvertTo-Json { return '{"Releases":["php-8.4.12.zip"],"Archives":["php-5.5.0.zip"]}' }
        Mock Make-Directory { return -1 }
        Mock Set-Content { }
        $code = Cache-Data -cacheFileName "test" -data @{"Releases" = @("php-8.4.12.zip"); "Archives" = @("php-5.5.0.zip")}
        $code | Should -Be -1
    }
    
    It "Handles exceptions gracefully" {
        Mock ConvertTo-Json { throw "Simulated exception" }
        $code = Cache-Data -cacheFileName "test" -data @{"Releases" = @("php-8.4.12.zip"); "Archives" = @("php-5.5.0.zip")}
        $code | Should -Be -1
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
        
        It "Returns null when an exception occurs" {
            # Simulate an exception by passing a path that causes an error
            Mock Get-ChildItem { throw "Simulated exception" }
            $result = Get-All-Subdirectories -path $STORAGE_PATH
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


Describe "Make-Symbolic-Link" {
    Context "When creating symbolic links" {
        It "Creates a symbolic link successfully when running as admin" {
            # Mock Is-Admin to return true
            Mock Is-Admin { return $true }
            
            # Mock New-Item to simulate successful symbolic link creation
            Mock New-Item { 
                param($ItemType, $Path, $Target)
                if ($ItemType -eq "SymbolicLink") {
                    # Create a dummy file to simulate the link
                    New-Item -Path $Path -ItemType File -Force | Out-Null
                    return @{ FullName = $Path }
                }
            } -ParameterFilter { $ItemType -eq "SymbolicLink" }
            
            $linkPath = "TestDrive:\test_link"
            $targetPath = "$STORAGE_PATH\php\8.1"
            
            $result = Make-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be 0
            $result.message | Should -Match "Created symbolic link"
            $result.color | Should -Be "DarkGreen"
            
            # Verify New-Item was called with correct parameters
            Assert-MockCalled New-Item -ParameterFilter { 
                $ItemType -eq "SymbolicLink" -and 
                $Path -eq $linkPath -and 
                $Target -eq $targetPath 
            }
        }
        
        It "Returns -1 if fails to create symbolic link" {
            Mock Is-Admin { return $false }
            Mock Run-Command { return -1 }
            $linkPath = "TestDrive:\test_link_fail"
            $targetPath = "$STORAGE_PATH\php\8.1"
            $result = Make-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be -1
            $result.message | Should -Be "Failed to make symbolic link '$linkPath' -> '$targetPath'"
            $result.color | Should -Be "DarkYellow"
        }
        
        It "Creates a symbolic link successfully using elevated command" {
            # Mock Is-Admin to return false
            Mock Is-Admin { return $false }
            
            # Mock Run-Command to simulate successful elevation
            Mock Run-Command { return 0 }
            
            $linkPath = "TestDrive:\test_link_2"
            $targetPath = "$STORAGE_PATH\php\8.1"
            
            $result = Make-Symbolic-Link -link $linkPath -target $targetPath
            
            $result.code | Should -Be 0
            $result.message | Should -Match "Created symbolic link"
            $result.color | Should -Be "DarkGreen"
            
            # Verify Run-Command was called with the symbolic link command
            Assert-MockCalled Run-Command -ParameterFilter { 
                $command -like "*New-Item -ItemType SymbolicLink*" -and
                $command -like "*$linkPath*" -and
                $command -like "*$targetPath*"
            }
        }
        
        It "Returns -1 if target directory does not exist" {
            $result = Make-Symbolic-Link -link "TestDrive:\link" -target "C:\Nonexistent\Target"
            $result.code | Should -Be -1
            $result.message | Should -Match "Target directory 'C:\\Nonexistent\\Target' does not exist!"
            $result.color | Should -Be "DarkYellow"
        }
        
        It "Returns -1 if link already exists and is not a symbolic link" {
            # Create a regular file to simulate existing non-link
            $existingPath = "TestDrive:\existing_file"
            New-Item -Path $existingPath -ItemType File -Force | Out-Null
            
            $result = Make-Symbolic-Link -link $existingPath -target "$STORAGE_PATH\php\8.1"
            $result.code | Should -Be -1
            $result.message | Should -Be "Link '$existingPath' is not a symbolic link!"
            $result.color | Should -Be "DarkYellow"
            
            # Cleanup
            Remove-Item -Path $existingPath -Force
        }
        
        It "Handles exceptions gracefully" {
            Mock Is-Directory-Exists { throw "Simulated exception" }
            $result = Make-Symbolic-Link -link "TestDrive:\link" -target "TestDrive:\target"
            $result.code | Should -Be -1
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
        
        It "Displays custom message if provided" {
            Mock Write-Host {}
            $testResult = @{
                message = "Original message"
            }
            $customMessage = "Custom message"
            { Display-Msg-By-ExitCode -result $testResult -message $customMessage } | Should -Not -Throw
        }
        
        It "Displays list of messages if provided" {
            Mock Write-Host { }
            $testResults = @{
                code = 0
                messages = @(
                    @{ content = "Message 1"; color = "Red" }
                    @{ content = "Message 2"; color = "Green" }
                    @{ content = "Message 3" }
                )
            }
            { Display-Msg-By-ExitCode -result $testResults } | Should -Not -Throw
        }
        
        It "Handles exceptions gracefully" {
            Mock Write-Host { throw "Simulated Write-Host failure" }
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
            $LOG_ERROR_PATH = "TestDrive:\logs\test.log"
            $result = Log-Data -data @{
                header = "Test message"
                exception = @{
                    Exception = @{ Message = "Test data" }
                    InvocationInfo = @{
                        ScriptName = "test.ps1"
                        ScriptLineNumber = 1
                        PositionMessage = "Test position"
                    }
                }
            }
            $result | Should -Be 0
            Test-Path $LOG_ERROR_PATH | Should -Be $true
            # Get the actual content
            $content = Get-Content $LOG_ERROR_PATH -Raw
            
            # Verify the complete log format
            $content | Should -Match "\[.*\] Test message(.|\s)*Message: Test data"
            
            # Alternatively, you could check parts separately
            $content | Should -Match "Test message"
            $content | Should -Match "Test data"
            $content | Should -Match (Get-Date -Format "yyyy-MM-dd")
        }

        It "Returns -1 when unable to create directory" {
            Mock Make-Directory { throw "Failed to create directory" }
            # Try to log to a protected location
            $result = Log-Data @{
                header = "Test message"
                exception = "Test data"
            }
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

        It "Optimizes PATH by replacing paths with variables" {
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
        
        It "Handles exceptions gracefully" {
            Mock Get-All-EnvVars { throw "Simulated exception" }
            $result = Optimize-SystemPath
            $result | Should -Be -1
            
            # Check that an error was logged
            Test-Path $LOG_ERROR_PATH | Should -Be $true
            Get-Content $LOG_ERROR_PATH -Raw | Should -Match "Optimize-SystemPath - Failed to optimize system PATH variable"
        }
    }
}

Describe "Format-Seconds" {
    Context "When formatting seconds" {
        It "Formats seconds less than 60 with decimal precision" {
            $result = Format-Seconds -totalSeconds 30.5
            $result | Should -Be "30.5s"
            
            $result = Format-Seconds -totalSeconds 45.123
            $result | Should -Be "45.1s"
            
            $result = Format-Seconds -totalSeconds 0
            $result | Should -Be "0s"
        }
        
        It "Formats minutes and seconds without hours" {
            $result = Format-Seconds -totalSeconds 90
            $result | Should -Be "01:30"
            
            $result = Format-Seconds -totalSeconds 125
            $result | Should -Be "02:05"
            
            $result = Format-Seconds -totalSeconds 3599
            $result | Should -Be "59:59"
        }
        
        It "Formats hours, minutes, and seconds" {
            $result = Format-Seconds -totalSeconds 3600
            $result | Should -Be "01:00:00"
            
            $result = Format-Seconds -totalSeconds 3661
            $result | Should -Be "01:01:01"
            
            $result = Format-Seconds -totalSeconds 7325
            $result | Should -Be "02:02:05"
            
            $result = Format-Seconds -totalSeconds 86400
            $result | Should -Be "24:00:00"
        }
        
        It "Handles negative values by converting to zero" {
            $result = Format-Seconds -totalSeconds -10
            $result | Should -Be "0s"
            
            $result = Format-Seconds -totalSeconds -100.5
            $result | Should -Be "0s"
        }
        
        It "Handles decimal values in minute ranges" {
            $result = Format-Seconds -totalSeconds 90.7
            $result | Should -Be "01:30"
            
            $result = Format-Seconds -totalSeconds 125.9
            $result | Should -Be "02:05"
        }
        
        It "Handles decimal values in hour ranges" {
            $result = Format-Seconds -totalSeconds 3600.5
            $result | Should -Be "01:00:00"
            
            $result = Format-Seconds -totalSeconds 3661.8
            $result | Should -Be "01:01:01"
        }
        
        It "Handles null input" {
            $result = Format-Seconds -totalSeconds $null
            $result | Should -Be 0
        }
        
        It "Handles string input that can be converted" {
            $result = Format-Seconds -totalSeconds "90"
            $result | Should -Be "01:30"
        }
    }
}

Describe "Can-Use-Cache" {
    BeforeAll {
        $global:CACHE_PATH = "TestDrive:\cache"
        $global:CACHE_MAX_HOURS = 168
    
        New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null
    }
    Context "When cache file exists" {
        It "Returns true when cache file is within max age" {
            $cacheFileName = "test_cache"
            $cacheFile = "$cacheFileName.json"
            
            # Create a cache file with recent timestamp
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'
            
            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }
        
        It "Returns false when cache file is older than max age" {
            $cacheFileName = "old_cache"
            $cacheFile = "$cacheFileName.json"
            
            # Create a cache file with old timestamp (older than CACHE_MAX_HOURS)
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'
            
            # Set file modification time to be older than CACHE_MAX_HOURS (168 hours)
            $oldTime = (Get-Date).AddHours(-200)
            (Get-Item "$CACHE_PATH\$cacheFile").LastWriteTime = $oldTime
            
            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $false
        }
        
        It "Returns false when cache file is exactly at max age boundary" {
            $cacheFileName = "boundary_cache"
            $cacheFile = "$cacheFileName.json"
            
            # Create a cache file
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'
            
            # Set file modification time to be exactly at CACHE_MAX_HOURS
            $boundaryTime = (Get-Date).AddHours(-$CACHE_MAX_HOURS)
            (Get-Item "$CACHE_PATH\$cacheFile").LastWriteTime = $boundaryTime
            
            $result = Can-Use-Cache -cacheFileName $cacheFileName
            # Since the function uses -lt (less than), equality should return false
            $result | Should -Be $false
        }
    }
    
    Context "When cache file does not exist" {
        It "Returns false when cache file does not exist" {
            $cacheFileName = "nonexistent_cache"
            
            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $false
        }
    }
    
    Context "With edge cases" {
        It "Returns false for empty cache file name" {
            $result = Can-Use-Cache -cacheFileName ""
            $result | Should -Be $false
        }
        
        It "Returns false for null cache file name" {
            $result = Can-Use-Cache -cacheFileName $null
            $result | Should -Be $false
        }
        
        It "Handles exceptions gracefully" {
            Mock Test-Path { throw "Simulated exception" }
            { Can-Use-Cache -cacheFileName "test" } | Should -Not -Throw
            $result = Can-Use-Cache -cacheFileName "test"
            $result | Should -Be $false
        }
    }
    
    Context "With special file names" {
        It "Works with file names containing special characters" {
            $cacheFileName = "cache-with_special.chars"
            $cacheFile = "$cacheFileName.json"
            
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'
            
            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }
        
        It "Works with file names containing numbers" {
            $cacheFileName = "cache123available_versions456"
            $cacheFile = "$cacheFileName.json"
            
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'
            
            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }
    }
}

Describe "Resolve-Arch" {
    Context "When searching in arguments" {
        It "Returns x86 when x86 is in arguments" {
            $arguments = @("some_arg", "x86", "another_arg")
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be "x86"
        }
        
        It "Returns x64 when x64 is in arguments" {
            $arguments = @("some_arg", "x64", "another_arg")
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be "x64"
        }
        
        It "Returns first matching architecture when multiple are present" {
            $arguments = @("x86", "x64", "other")
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be "x86"
        }
        
        It "Returns null when no matching architecture in arguments" {
            $arguments = @("some_arg", "another_arg", "third_arg")
            $result = Resolve-Arch -arguments $arguments
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context "Case insensitivity" {
        It "Returns lowercase x86 when uppercase X86 provided" {
            $arguments = @("X86")
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be "x86"
        }
        
        It "Returns lowercase x64 when mixed case X64 provided" {
            $arguments = @("X64")
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be "x64"
        }
    }
    
    Context "With default choice" {
        It "Returns x64 as default when 64-bit OS and choseDefault is true" {
            Mock Is-OS-64Bit { return $true }
            $arguments = @("some_arg", "other_arg")
            
            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be "x64"
        }
        
        It "Returns x86 as default when 32-bit OS and choseDefault is true" {
            Mock Is-OS-64Bit { return $false }
            $arguments = @("some_arg", "other_arg")
            
            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be "x86"
        }
        
        It "Returns argument arch even when choseDefault is true" {
            Mock Is-OS-64Bit { return $true }
            $arguments = @("x86", "some_arg")
            
            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be "x86"
        }
    }
    
    Context "With empty or null inputs" {
        It "Returns null when arguments array is empty and choseDefault is false" {
            $arguments = @()
            $result = Resolve-Arch -arguments $arguments -choseDefault $false
            $result | Should -BeNullOrEmpty
        }
        
        It "Returns default when arguments array is empty and choseDefault is true" {
            Mock Is-OS-64Bit { return $true }
            $arguments = @()
            
            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be "x64"
        }
        
        It "Returns null when arguments is null" {
            $result = Resolve-Arch -arguments $null
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Get-PHPInstallInfo" {
    Context "When PHP DLL exists" {
        It "Returns PHP install info with NTS build type" {
            $testPath = "TestDrive:\php\8.3"
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null
            
            # Create a mock NTS DLL file
            New-Item -Path "$testPath\php8nts.dll" -ItemType File -Force | Out-Null
            
            Mock Get-ChildItem {
                return @{
                    VersionInfo = @{ ProductVersion = "8.3.0" }
                    Name = "php8nts.dll"
                    FullName = "$testPath\php8nts.dll"
                }
            }
            
            Mock Get-BinaryArchitecture-From-DLL { return "x64" }
            
            $result = Get-PHPInstallInfo -path $testPath
            
            $result | Should -Not -BeNullOrEmpty
            $result.Version | Should -Be "8.3.0"
            $result.Arch | Should -Be "x64"
            $result.BuildType | Should -Be "NTS"
            $result.Dll | Should -Be "php8nts.dll"
            $result.InstallPath | Should -Be $testPath
        }
        
        It "Returns PHP install info with TS build type" {
            $testPath = "TestDrive:\php\8.2"
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null
            
            Mock Get-ChildItem {
                return @{
                    VersionInfo = @{ ProductVersion = "8.2.5" }
                    Name = "php8ts.dll"
                    FullName = "$testPath\php8ts.dll"
                }
            }
            
            Mock Get-BinaryArchitecture-From-DLL { return "x86" }
            
            $result = Get-PHPInstallInfo -path $testPath
            
            $result.BuildType | Should -Be "TS"
            $result.Arch | Should -Be "x86"
            $result.Version | Should -Be "8.2.5"
        }
        
        It "Returns first DLL when multiple match" {
            $testPath = "TestDrive:\php\8.1"
            
            Mock Get-ChildItem {
                return @(
                    @{
                        VersionInfo = @{ ProductVersion = "8.1.0" }
                        Name = "php81nts.dll"
                        FullName = "$testPath\php81nts.dll"
                    },
                    @{
                        VersionInfo = @{ ProductVersion = "8.1.0" }
                        Name = "php81ts.dll"
                        FullName = "$testPath\php81ts.dll"
                    }
                ) | Select-Object -First 1
            }
            
            Mock Get-BinaryArchitecture-From-DLL { return "x64" }
            
            $result = Get-PHPInstallInfo -path $testPath
            $result.Dll | Should -Be "php81nts.dll"
        }
    }
    
    Context "When PHP DLL does not exist" {
        It "Returns null when no DLL found" {
            $testPath = "TestDrive:\php\empty"
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null
            
            Mock Get-ChildItem { return $null }
            
            $result = Get-PHPInstallInfo -path $testPath
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Is-Two-PHP-Versions-Equal" {
    Context "When both versions are equal" {
        It "Returns true when all properties match" {
            $version1 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            $version2 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $true
        }
        
        It "Returns true for x86 TS build versions" {
            $version1 = @{
                version = "8.1.5"
                arch = "x86"
                buildType = "TS"
            }
            $version2 = @{
                version = "8.1.5"
                arch = "x86"
                buildType = "TS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $true
        }
    }
    
    Context "When versions differ" {
        It "Returns false when version numbers differ" {
            $version1 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            $version2 = @{
                version = "8.2.0"
                arch = "x64"
                buildType = "NTS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
        
        It "Returns false when architecture differs" {
            $version1 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            $version2 = @{
                version = "8.3.0"
                arch = "x86"
                buildType = "NTS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
        
        It "Returns false when build type differs" {
            $version1 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            $version2 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "TS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
    }
    
    Context "With null or incomplete versions" {
        It "Returns false when first version is null" {
            $version2 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $null -version2 $version2
            $result | Should -Be $false
        }
        
        It "Returns false when second version is null" {
            $version1 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $null
            $result | Should -Be $false
        }
        
        It "Returns false when both versions are null" {
            $result = Is-Two-PHP-Versions-Equal -version1 $null -version2 $null
            $result | Should -Be $false
        }
        
        It "Returns false when a property value is missing (null)" {
            $version1 = @{
                version = "8.3.0"
                arch = $null
                buildType = "NTS"
            }
            $version2 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
    }
    
    Context "With edge cases" {
        It "Returns true for versions with additional properties" {
            $version1 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
                Dll = "php8_nts.dll"
                InstallPath = "C:\php\8.3"
            }
            $version2 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $true
        }
        
        It "Returns false when version is empty string vs null" {
            $version1 = @{
                version = ""
                arch = "x64"
                buildType = "NTS"
            }
            $version2 = @{
                version = "8.3.0"
                arch = "x64"
                buildType = "NTS"
            }
            
            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
    }
}

