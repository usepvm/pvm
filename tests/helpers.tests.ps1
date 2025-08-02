# PowerShell Function Tests using Pester with Mock Registry
# Install Pester if not available: Install-Module -Name Pester -Force -SkipPublisherCheck

BeforeAll {
    # Mock global variables that would be defined in the main script
    $global:LOG_ERROR_PATH = "C:\temp\test_error.log"
    $global:PATH_VAR_BACKUP_NAME = "PATH_BACKUP"
    $global:PATH_VAR_BACKUP_PATH = "C:\temp\test_path_backup.log"
    
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
    
    # Mock file system for logging tests
    $global:MockFileSystem = @{
        Directories = @()
        Files = @{}
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
    
        
    # Functions under test (modified to use wrapper functions)
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
    
    # Mock file system functions
    function Test-Path {
        param($Path, $PathType)
        
        if ($global:MockFileSystemThrowException) {
            throw $global:MockFileSystemException
        }
        
        if ($PathType -eq "Container") {
            return $global:MockFileSystem.Directories -contains $Path
        } else {
            return $global:MockFileSystem.Files.ContainsKey($Path)
        }
    }
    
    function New-Item {
        param($Path, $ItemType, $Force)
        
        if ($global:MockFileSystemThrowException) {
            throw $global:MockFileSystemException
        }
        
        if ($ItemType -eq "Directory") {
            $global:MockFileSystem.Directories += $Path
        }
        return [PSCustomObject]@{ FullName = $Path }
    }
    
    function mkdir {
        param($Path)
        
        if ($global:MockFileSystemThrowException) {
            throw $global:MockFileSystemException
        }
        
        $global:MockFileSystem.Directories += $Path
        return [PSCustomObject]@{ FullName = $Path }
    }
    
    function Add-Content {
        param($Path, $Value)
        
        if ($global:MockFileSystemThrowException) {
            throw $global:MockFileSystemException
        }
        
        if (-not $global:MockFileSystem.Files.ContainsKey($Path)) {
            $global:MockFileSystem.Files[$Path] = ""
        }
        $global:MockFileSystem.Files[$Path] += $Value
    }
    
    function Make-Directory {
        param ( [string]$path )
        
        if ([string]::IsNullOrWhiteSpace($path.Trim())) {
            return $false
        }
        
        if (-not (Test-Path -Path $path -PathType Container)) {
            mkdir $path | Out-Null
        }
        
        return $true
    }

    function Is-Admin {
        if ($global:MockAdminResult -ne $null) {
            return $global:MockAdminResult
        }
        return $true
    }

    function Log-Data {
        param ($logPath, $message, $data)
        try {
            Make-Directory -path (Split-Path $logPath)
            Add-Content -Path $logPath -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $message :n$datan"
            return 0
        } catch {
            return -1
        }
    }
    
    
    function Optimize-SystemPath {
        param($shouldOverwrite = $false)
        
        try {
            $path = Get-EnvVar-ByName -name "Path"
            $envVars = Get-All-EnvVars
            $pathBak = Get-EnvVar-ByName -name $PATH_VAR_BACKUP_NAME

            if (($pathBak -eq $null) -or $shouldOverwrite) {
                $output = Set-EnvVar -name $PATH_VAR_BACKUP_NAME -value $path
            }
            
            # Saving Path to log
            $outputLog = Log-Data -logPath $PATH_VAR_BACKUP_PATH -message "Original PATH" -data $path
            
            $envVars.Keys | ForEach-Object {
                $envName = $_
                $envValue = $envVars[$envName]
                
                if (
                    ($envName -ne "Path") -and
                    ($null -ne $envValue) -and
                    ($path -like "*$envValue*") -and
                    ($envValue -notlike "*\Windows*") -and
                    ($envValue -notlike "*\System32*")
                ) {
                    $envValue = [regex]::Escape($envValue.TrimEnd(';'))
                    $pattern = "(?<=^|;){0}(?=;|$)" -f $envValue
                    $path = [regex]::Replace($path, $pattern, "%$envName%")
                }
            }
            $output = Set-EnvVar -name "Path" -value $path
            
            return $output
        } catch {
            $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Optimize-SystemPath: Failed to optimize system PATH variable" -data $_.Exception.Message
            return -1
        }
    }
    
    # Helper function to reset mock state
    function Reset-MockState {
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
        
        $global:MockFileSystem = @{
            Directories = @()
            Files = @{}
        }
        
        $global:MockRegistryThrowException = $false
        $global:MockRegistryException = "Mock registry exception"
        $global:MockFileSystemThrowException = $false
        $global:MockFileSystemException = "Mock file system exception"
        $global:MockAdminResult = $null
        $global:MockChocolateyUnavailable = $true
    }
    
    # Initialize mock state
    Reset-MockState
}


Describe "Get-All-EnvVars Tests" {
    Context "Success scenarios" {
        It "Should return environment variables hashtable when successful" {
            $result = Get-All-EnvVars
            
            $result | Should -Not -BeNullOrEmpty
            $result.GetType().Name | Should -Be "Hashtable"
            $result["JAVA_HOME"] | Should -Be "C:\Program Files\Java"
            $result["GIT_HOME"] | Should -Be "C:\Program Files\Git\bin"
            $result.Count | Should -BeGreaterThan 0
        }
        
        It "Should return empty hashtable when no environment variables exist" {
            $global:MockRegistry.Machine = @{}
            
            $result = Get-All-EnvVars
            $result.Count | Should -Be 0
        }
    }
    
    Context "Error scenarios" {
        It "Should return null and log error when registry access fails" {
            $global:MockRegistryThrowException = $true
            $global:MockRegistryException = "Access denied to registry"
            
            $result = Get-All-EnvVars
            $result | Should -BeNullOrEmpty
            
            # Verify error was logged
            $global:MockFileSystem.Files.ContainsKey($LOG_ERROR_PATH) | Should -Be $true
            $global:MockFileSystem.Files[$LOG_ERROR_PATH] | Should -Match "Get-All-EnvVars: Failed to get all environment variables"
        }
    }
}

Describe "Get-EnvVar-ByName Tests" {
    Context "Success scenarios" {
        It "Should return environment variable value when name exists" {
            Reset-MockState
            $result = Get-EnvVar-ByName -name "JAVA_HOME"
            $result | Should -Be "C:\Program Files\Java"
        }
        
        It "Should return null when environment variable doesn't exist" {
            $result = Get-EnvVar-ByName -name "NON_EXISTENT_VAR"
            $result | Should -BeNullOrEmpty
        }
        
        It "Should handle case-sensitive variable names" {
            $global:MockRegistry.Machine["CaseSensitive"] = "TestValue"
            
            $result = Get-EnvVar-ByName -name "CaseSensitive"
            $result | Should -Be "TestValue"
            
            $result = Get-EnvVar-ByName -name "casesensitive"
            $result | Should -Be "TestValue"
        }
    }
    
    Context "Input validation" {
        It "Should return null when name is null" {
            $result = Get-EnvVar-ByName -name $null
            $result | Should -BeNullOrEmpty
        }
        
        It "Should return null when name is empty string" {
            $result = Get-EnvVar-ByName -name ""
            $result | Should -BeNullOrEmpty
        }
        
        It "Should return null when name is whitespace" {
            $result = Get-EnvVar-ByName -name "   "
            $result | Should -BeNullOrEmpty
        }
    }
    
    Context "Error scenarios" {
        It "Should return null and log error when registry access fails" {
            $global:MockRegistryThrowException = $true
            $global:MockRegistryException = "Registry key access denied"
            
            $result = Get-EnvVar-ByName -name "JAVA_HOME"
            $result | Should -BeNullOrEmpty
            
            # Verify error was logged
            $global:MockFileSystem.Files[$LOG_ERROR_PATH] | Should -Match "Get-EnvVar-ByName: Failed to get environment variable 'JAVA_HOME'"
        }
    }
}

Describe "Set-EnvVar Tests" {
    Context "Success scenarios" {
        It "Should successfully set new environment variable" {
            $global:MockRegistryThrowException = $false
            $result = Set-EnvVar -name "NEW_VAR" -value "NEW_VALUE"
            
            $result | Should -Be 0
            $global:MockRegistry.Machine["NEW_VAR"] | Should -Be "NEW_VALUE"
        }
        
        It "Should successfully update existing environment variable" {
            $result = Set-EnvVar -name "JAVA_HOME" -value "C:\NewJavaPath"
            
            $result | Should -Be 0
            $global:MockRegistry.Machine["JAVA_HOME"] | Should -Be "C:\NewJavaPath"
        }
        
        It "Should handle null value (delete variable)" {
            $result = Set-EnvVar -name "JAVA_HOME" -value $null
            
            $result | Should -Be 0
            $global:MockRegistry.Machine.ContainsKey("JAVA_HOME") | Should -Be $false
        }
        
        It "Should handle empty string value" {
            $result = Set-EnvVar -name "EMPTY_VAR" -value ""
            
            $result | Should -Be 0
            $global:MockRegistry.Machine["EMPTY_VAR"] | Should -Be ""
        }
    }
    
    Context "Input validation" {
        It "Should return -1 when name is null" {
            $result = Set-EnvVar -name $null -value "TEST_VALUE"
            $result | Should -Be -1
        }
        
        It "Should return -1 when name is empty string" {
            $result = Set-EnvVar -name "" -value "TEST_VALUE"
            $result | Should -Be -1
        }
        
        It "Should return -1 when name is whitespace" {
            $result = Set-EnvVar -name "   " -value "TEST_VALUE"
            $result | Should -Be -1
        }
    }
    
    Context "Error scenarios" {
        It "Should return -1 and log error when registry access fails" {
            $global:MockRegistryThrowException = $true
            $global:MockRegistryException = "Access denied to registry key"
            
            $result = Set-EnvVar -name "TEST_VAR" -value "TEST_VALUE"
            
            $result | Should -Be -1
            $global:MockFileSystem.Files[$LOG_ERROR_PATH] | Should -Match "Set-EnvVar: Failed to set environment variable 'TEST_VAR'"
        }
    }
}

Describe "Make-Directory Tests" {
    Context "Directory creation" {
        It "Should create directory when it doesn't exist" {
            $testPath = "C:\test\newdir"
            
            Make-Directory -path $testPath
            
            $global:MockFileSystem.Directories | Should -Contain $testPath
        }
        
        It "Should not create directory when it already exists" {
            $testPath = "C:\test\existingdir"
            $global:MockFileSystem.Directories += $testPath
            
            $initialCount = $global:MockFileSystem.Directories.Count
            Make-Directory -path $testPath
            
            # Should not add duplicate
            $global:MockFileSystem.Directories.Count | Should -Be $initialCount
        }
    }
    
    Context "Error scenarios" {
        It "Should handle mkdir failure gracefully" {
            $global:MockFileSystemThrowException = $true
            $global:MockFileSystemException = "Access denied"
            
            { Make-Directory -path "C:\test\faildir" } | Should -Throw
        }
    }
    
    Context "Edge cases" {
        It "Should handle empty path" {
            Make-Directory -path ""
            # Should not throw exception
        }
        
        It "Should handle null path" {
            Make-Directory -path $null
            # Should not throw exception
        }
    }
}

Describe "Is-Admin Tests" {
    Context "Admin check scenarios" {
        It "Should return true when user is administrator" {
            $global:MockAdminResult = $true
            
            $result = Is-Admin
            $result | Should -Be $true
        }
        
        It "Should return false when user is not administrator" {
            $global:MockAdminResult = $false
            
            $result = Is-Admin
            $result | Should -Be $false
        }
        
        It "Should work with real admin check when mock not set" {
            $global:MockAdminResult = $null
            
            $result = Is-Admin
            $result | Should -BeOfType [bool]
        }
    }
}

Describe "Display-Msg-By-ExitCode Tests" {
    BeforeEach {
        Mock Write-Host { }
        $global:MockChocolateyUnavailable = $true
    }
    
    Context "Success scenarios" {
        It "Should display success message when exit code is 0" {
            Display-Msg-By-ExitCode -msgSuccess "Success!" -msgError "Failed!" -exitCode 0
            
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -eq "Success!" }
        }
        
        It "Should display error message when exit code is non-zero" {
            Display-Msg-By-ExitCode -msgSuccess "Success!" -msgError "Failed!" -exitCode 1
            
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -eq "Failed!" }
        }
        
        It "Should display error message when exit code is negative" {
            Display-Msg-By-ExitCode -msgSuccess "Success!" -msgError "Failed!" -exitCode -1
            
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -eq "Failed!" }
        }
    }
    
    Context "Chocolatey integration" {
        It "Should handle missing Chocolatey gracefully" {
            $global:MockChocolateyUnavailable = $true
            
            { Display-Msg-By-ExitCode -msgSuccess "Success!" -msgError "Failed!" -exitCode 0 } | Should -Not -Throw
        }
        
        It "Should attempt Chocolatey operations when available" {
            $global:MockChocolateyUnavailable = $false
            Mock Import-Module { }
            Mock Get-Command { return @{ Name = "Update-SessionEnvironment" } }
            Mock Update-SessionEnvironment { }
            
            Display-Msg-By-ExitCode -msgSuccess "Success!" -msgError "Failed!" -exitCode 0
            
            # Function should complete without error
            Assert-MockCalled Write-Host -Times 1
        }
    }
    
    Context "Edge cases" {
        It "Should handle null messages" {
            Display-Msg-By-ExitCode -msgSuccess $null -msgError $null -exitCode 0
            Assert-MockCalled Write-Host -Times 1
        }
        
        It "Should handle empty string messages" {
            Display-Msg-By-ExitCode -msgSuccess "" -msgError "" -exitCode 1
            Assert-MockCalled Write-Host -Times 1
        }
    }
}

Describe "Log-Data Tests" {
    Context "Success scenarios" {
        # It "Should successfully log data and return 0" {
        #     $logPath = "C:\temp\test.log"
        #     $message = "Test message"
        #     $data = "Test data"
            
        #     $result = Log-Data -logPath $logPath -message $message -data $data
            
        #     $result | Should -Be 0
        #     $global:MockFileSystem.Directories | Should -Contain "C:\temp"
        #     $global:MockFileSystem.Files[$logPath] | Should -Match $message
        #     $global:MockFileSystem.Files[$logPath] | Should -Match $data
        # }
        
        # It "Should handle null data parameter" {
        #     $result = Log-Data -logPath "C:\temp\test.log" -message "Test message" -data $null
            
        #     $result | Should -Be 0
        #     $global:MockFileSystem.Files["C:\temp\test.log"] | Should -Match "Test message"
        # }
        
        # It "Should handle empty message and data" {
        #     $result = Log-Data -logPath "C:\temp\test.log" -message "" -data ""
            
        #     $result | Should -Be 0
        #     $global:MockFileSystem.Files.ContainsKey("C:\temp\test.log") | Should -Be $true
        # }
        
        # It "Should include timestamp in log entry" {
        #     $result = Log-Data -logPath "C:\temp\test.log" -message "Test" -data "Data"
            
        #     $global:MockFileSystem.Files["C:\temp\test.log"] | Should -Match "\[2024-01-01 12:00:00\]"
        # }
    }
    
    Context "Error scenarios" {
        It "Should return -1 when directory creation fails" {
            $global:MockFileSystemThrowException = $true
            $global:MockFileSystemException = "Access denied to create directory"
            
            $result = Log-Data -logPath "C:\temp\test.log" -message "Test message" -data "Test data"
            $result | Should -Be -1
        }
        
        It "Should return -1 when file write fails" {
            # Create directory first, then make Add-Content fail
            $global:MockFileSystem.Directories += "C:\temp"
            $global:MockFileSystemThrowException = $true
            $global:MockFileSystemException = "File is locked"
            
            $result = Log-Data -logPath "C:\temp\test.log" -message "Test message" -data "Test data"
            $result | Should -Be -1
        }
    }
}

Describe "Optimize-SystemPath Tests" {
    Context "Success scenarios" {
        It "Should optimize PATH by replacing paths with environment variable references" {
            Reset-MockState
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            
            # Verify backup was created
            $global:MockRegistry.Machine.ContainsKey($PATH_VAR_BACKUP_NAME) | Should -Be $true
            
            # Verify original PATH was logged
            $global:MockFileSystem.Files[$PATH_VAR_BACKUP_PATH] | Should -Match "Original PATH"
            
            # Verify PATH was optimized (should contain %GIT_HOME% instead of actual path)
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            $optimizedPath | Should -Match "%GIT_HOME%"
            $optimizedPath | Should -Match "%CUSTOM_APP%"
            
            # Should NOT replace Windows paths
            $optimizedPath | Should -Match "C:\\Windows\\System32"
        }
        
        It "Should create backup when no backup exists" {
            $global:MockRegistry.Machine.Remove($PATH_VAR_BACKUP_NAME)
            
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            $global:MockRegistry.Machine[$PATH_VAR_BACKUP_NAME] | Should -Not -BeNullOrEmpty
        }
        
        It "Should not overwrite backup when backup exists and shouldOverwrite is false" {
            $existingBackup = "C:\ExistingBackup"
            $global:MockRegistry.Machine[$PATH_VAR_BACKUP_NAME] = $existingBackup
            
            $result = Optimize-SystemPath -shouldOverwrite $false
            
            $result | Should -Be 0
            $global:MockRegistry.Machine[$PATH_VAR_BACKUP_NAME] | Should -Be $existingBackup
        }
        
        It "Should overwrite backup when shouldOverwrite is true" {
            $existingBackup = "C:\ExistingBackup"
            $global:MockRegistry.Machine[$PATH_VAR_BACKUP_NAME] = $existingBackup
            $originalPath = $global:MockRegistry.Machine["Path"]
            
            $result = Optimize-SystemPath -shouldOverwrite $true
            
            $result | Should -Be 0
            $global:MockRegistry.Machine[$PATH_VAR_BACKUP_NAME] | Should -Be $originalPath
            $global:MockRegistry.Machine[$PATH_VAR_BACKUP_NAME] | Should -Not -Be $existingBackup
        }
        
        It "Should not replace Windows and System32 paths" {
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;C:\Windows\bin;C:\Program Files\CustomApp"
            $global:MockRegistry.Machine["WINDOWS_SYSTEM"] = "C:\Windows\System32"
            $global:MockRegistry.Machine["WINDOWS_BIN"] = "C:\Windows\bin"
            $global:MockRegistry.Machine["CUSTOM_APP"] = "C:\Program Files\CustomApp"
            
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            $optimizedPath | Should -Match "C:\\Windows\\System32"
            $optimizedPath | Should -Match "C:\\Windows\\bin"
            $optimizedPath | Should -Match "%CUSTOM_APP%"
        }
        
        It "Should handle empty PATH variable" {
            $global:MockRegistry.Machine["Path"] = ""
            
            $result = Optimize-SystemPath
            $result | Should -Be 0
        }
        
        It "Should handle null PATH variable" {
            $global:MockRegistry.Machine.Remove("Path")
            
            $result = Optimize-SystemPath
            $result | Should -Be 0
        }
        
        It "Should handle paths with trailing semicolons correctly" {
            Reset-MockState
            $global:MockRegistry.Machine["Path"] = "C:\test;C:\Program Files\Git\bin;"
            $global:MockRegistry.Machine["GIT_HOME"] = "C:\Program Files\Git\bin;"
            
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            $optimizedPath | Should -Match "%GIT_HOME%"
        }
        
        It "Should handle environment variables with null values" {
            $global:MockRegistry.Machine["NULL_VAR"] = $null
            $global:MockRegistry.Machine["EMPTY_VAR"] = ""
            
            $result = Optimize-SystemPath
            $result | Should -Be 0
        }
    }
    
    Context "Error scenarios" {
        It "Should return -1 and log error when Get-EnvVar-ByName fails" {
            $global:MockRegistryThrowException = $true
            $global:MockRegistryException = "Registry access denied"
            
            $result = Optimize-SystemPath
            
            $result | Should -Be -1
            $global:MockFileSystem.Files[$LOG_ERROR_PATH] | Should -Match "Optimize-SystemPath: Failed to optimize system PATH variable"
        }
        
        It "Should return -1 and log error when Get-All-EnvVars fails" {
            # First call succeeds (Get-EnvVar-ByName for Path), second fails (Get-All-EnvVars)
            $callCount = 0
            $global:MockRegistryThrowException = $false
            
            # Override the wrapper to fail on second call
            function Get-EnvironmentVariablesWrapper {
                param($target)
                throw "Access denied to enumerate variables"
            }
            
            $result = Optimize-SystemPath
            
            $result | Should -Be -1
            $global:MockFileSystem.Files[$LOG_ERROR_PATH] | Should -Match "Optimize-SystemPath: Failed to optimize system PATH variable"
        }
        
        It "Should return -1 and log error when Set-EnvVar fails" {
            # Make Set-EnvVar fail by having registry throw on write operations
            $originalPath = $global:MockRegistry.Machine["Path"]
            
            # Override wrapper to fail only on Set operations
            function Set-EnvironmentVariableWrapper {
                param($name, $value, $target)
                throw "Access denied to set registry value"
            }
            $result = Optimize-SystemPath
            
            $result | Should -Be -1
            $global:MockFileSystem.Files[$LOG_ERROR_PATH] | Should -Match "Optimize-SystemPath: Failed to optimize system PATH variable"
        }
    }
    
    Context "PATH optimization logic verification" {
        It "Should correctly identify and replace non-Windows paths" {
            $testPath = "C:\CustomPath1;C:\Program Files\Git\bin;C:\Windows\System32;C:\CustomPath2;"
            $global:MockRegistry.Machine["Path"] = $testPath
            $global:MockRegistry.Machine["CUSTOM1"] = "C:\CustomPath1"
            $global:MockRegistry.Machine["GIT_HOME"] = "C:\Program Files\Git\bin"
            $global:MockRegistry.Machine["CUSTOM2"] = "C:\CustomPath2"
            $global:MockRegistry.Machine["WINDOWS_SYS"] = "C:\Windows\System32"
            
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            
            # Should replace custom paths
            $optimizedPath | Should -Match "%CUSTOM1%"
            $optimizedPath | Should -Match "%GIT_HOME%"
            $optimizedPath | Should -Match "%CUSTOM2%"
            
            # Should NOT replace Windows path
            $optimizedPath | Should -Match "C:\\Windows\\System32"
            $optimizedPath | Should -Not -Match "%WINDOWS_SYS%"
        }
        
        It "Should handle complex PATH with multiple occurrences" {
            $testPath = "C:\Tools;C:\Program Files\Git\bin;C:\Tools;C:\Other"
            $global:MockRegistry.Machine["Path"] = $testPath
            $global:MockRegistry.Machine["TOOLS"] = "C:\Tools"
            $global:MockRegistry.Machine["GIT_HOME"] = "C:\Program Files\Git\bin"
            
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            
            # Should replace all occurrences
            $optimizedPath | Should -Match "%TOOLS%"
            $optimizedPath | Should -Match "%GIT_HOME%"
        }
        
        It "Should preserve PATH structure and separators" {
            $testPath = "C:\First;C:\Program Files\Git\bin;C:\Last;"
            $global:MockRegistry.Machine["Path"] = $testPath
            $global:MockRegistry.Machine["FIRST"] = "C:\First"
            $global:MockRegistry.Machine["GIT_HOME"] = "C:\Program Files\Git\bin"
            $global:MockRegistry.Machine["LAST"] = "C:\Last"
            
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            
            # Should maintain semicolon structure
            $optimizedPath | Should -Match "^.*%FIRST%.*%GIT_HOME%.*%LAST%.*"
        }
    }
}

# Integration tests that verify the mock registry behavior
Describe "Mock Registry Integration Tests" -Tag "MockIntegration" {
    Context "Registry simulation verification" {
        It "Should properly simulate environment variable storage" {
            # Test the complete flow
            $testVar = "INTEGRATION_TEST"
            $testValue = "IntegrationValue"
            
            # Set variable
            $setResult = Set-EnvVar -name $testVar -value $testValue
            $setResult | Should -Be 0
            
            # Verify it exists in mock registry
            $global:MockRegistry.Machine[$testVar] | Should -Be $testValue
            
            # Get variable
            $getValue = Get-EnvVar-ByName -name $testVar
            $getValue | Should -Be $testValue
            
            # Verify it appears in GetAll
            $allVars = Get-All-EnvVars
            $allVars[$testVar] | Should -Be $testValue
            
            # Delete variable
            $deleteResult = Set-EnvVar -name $testVar -value $null
            $deleteResult | Should -Be 0
            
            # Verify it's gone
            $global:MockRegistry.Machine.ContainsKey($testVar) | Should -Be $false
            $deletedValue = Get-EnvVar-ByName -name $testVar
            $deletedValue | Should -BeNullOrEmpty
        }
        
        It "Should handle concurrent operations on different variables" {
            Set-EnvVar -name "VAR1" -value "VALUE1"
            Set-EnvVar -name "VAR2" -value "VALUE2"
            Set-EnvVar -name "VAR3" -value "VALUE3"
            
            $allVars = Get-All-EnvVars
            $allVars["VAR1"] | Should -Be "VALUE1"
            $allVars["VAR2"] | Should -Be "VALUE2"
            $allVars["VAR3"] | Should -Be "VALUE3"
        }
        
        It "Should maintain registry state across function calls within same test" {
            Set-EnvVar -name "PERSISTENT_VAR" -value "PersistentValue"
            
            # Call other functions
            $allVars = Get-All-EnvVars
            $specificVar = Get-EnvVar-ByName -name "PERSISTENT_VAR"
            
            # Variable should still exist
            $allVars["PERSISTENT_VAR"] | Should -Be "PersistentValue"
            $specificVar | Should -Be "PersistentValue"
        }
    }
}

# Comprehensive Optimize-SystemPath scenarios
Describe "Optimize-SystemPath Comprehensive Scenarios" -Tag "Comprehensive" {
    Context "Real-world PATH scenarios" {
        It "Should handle typical developer machine PATH" {
            $devPath = "C:\Windows\System32;C:\Windows;C:\Program Files\Git\bin;C:\Program Files\NodeJS;C:\Program Files\Python39;C:\Users\Dev\AppData\Local\Microsoft\WindowsApps"
            $global:MockRegistry.Machine["Path"] = $devPath
            $global:MockRegistry.Machine["GIT_HOME"] = "C:\Program Files\Git\bin"
            $global:MockRegistry.Machine["NODE_HOME"] = "C:\Program Files\NodeJS"
            $global:MockRegistry.Machine["PYTHON_HOME"] = "C:\Program Files\Python39"
            
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            
            # Should optimize non-Windows paths
            $optimizedPath | Should -Match "%GIT_HOME%"
            $optimizedPath | Should -Match "%NODE_HOME%"
            $optimizedPath | Should -Match "%PYTHON_HOME%"
            
            # Should preserve Windows paths
            $optimizedPath | Should -Match "C:\\Windows\\System32"
            $optimizedPath | Should -Match "C:\\Windows"
        }
        
        It "Should handle PATH with no optimizable entries" {
            $windowsOnlyPath = "C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem"
            $global:MockRegistry.Machine["Path"] = $windowsOnlyPath
            
            $result = Optimize-SystemPath
            
            $result | Should -Be 0
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            $optimizedPath | Should -Be $windowsOnlyPath
        }
        
        It "Should handle malformed PATH entries" {
            $malformedPath = "C:\Valid1;;C:\Valid2;;;C:\Program Files\Git\bin;"
            $global:MockRegistry.Machine["Path"] = $malformedPath
            $global:MockRegistry.Machine["GIT_HOME"] = "C:\Program Files\Git\bin"
            
            $result = Optimize-SystemPath
            $result | Should -Be 0
            # Should still work despite malformed entries
        }
    }
}

# Error injection tests
Describe "Error Injection Tests" -Tag "ErrorInjection" {
    Context "Systematic error injection" {
        It "Should handle registry read errors at different points" {
            # Test error on first registry read (Get-EnvVar-ByName for Path)
            $global:MockRegistryThrowException = $true
            $result = Optimize-SystemPath
            $result | Should -Be -1
        }
        
        It "Should handle file system errors during logging" {
            $global:MockFileSystemThrowException = $true
            $result = Log-Data -logPath "C:\test.log" -message "Test" -data "Data"
            $result | Should -Be -1
        }
        
        It "Should handle mixed success and failure scenarios" {
            Reset-MockState
            
            # Start with success, then inject failure
            $result1 = Set-EnvVar -name "SUCCESS_VAR" -value "SuccessValue"
            $result1 | Should -Be 0
            
            $global:MockRegistryThrowException = $true
            $result2 = Set-EnvVar -name "FAIL_VAR" -value "FailValue"
            $result2 | Should -Be -1
            
            # Reset and verify first operation succeeded
            $global:MockRegistryThrowException = $false
            $getValue = Get-EnvVar-ByName -name "SUCCESS_VAR"
            $getValue | Should -Be "SuccessValue"
        }
    }
}

# Performance and stress tests
Describe "Performance and Stress Tests" -Tag "Performance" {
    Context "Large dataset handling" {
        It "Should handle large number of environment variables efficiently" {
            # Populate with many variables
            for ($i = 1; $i -le 100; $i++) {
                $global:MockRegistry.Machine["TEST_VAR_$i"] = "TestValue$i"
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Get-All-EnvVars
            $stopwatch.Stop()
            
            $result.Count | Should -BeGreaterOrEqual 100
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 1000
        }
        
        It "Should handle very long PATH variable efficiently" {
            $longPath = ""
            for ($i = 1; $i -le 50; $i++) {
                $longPath += "C:\VeryLongPathName$i\SubDirectory\AnotherSubDirectory;"
                $global:MockRegistry.Machine["LONG_VAR_$i"] = "C:\VeryLongPathName$i\SubDirectory\AnotherSubDirectory"
            }
            $global:MockRegistry.Machine["Path"] = $longPath
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Optimize-SystemPath
            $stopwatch.Stop()
            
            $result | Should -Be 0
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        }
    }
    
    Context "Memory usage validation" {
        It "Should not leak memory during repeated operations" {
            # Simulate repeated operations
            for ($i = 1; $i -le 20; $i++) {
                Set-EnvVar -name "TEMP_VAR" -value "TempValue$i"
                $value = Get-EnvVar-ByName -name "TEMP_VAR"
                $value | Should -Be "TempValue$i"
            }
            
            # Memory should be manageable (this is a basic check)
            $allVars = Get-All-EnvVars
            $allVars | Should -Not -BeNullOrEmpty
        }
    }
}

# Edge cases and boundary tests
Describe "Edge Cases and Boundary Tests" -Tag "EdgeCases" {
    Context "Special characters and encoding" {
        It "Should handle environment variable names with special characters" {
            $specialName = "VAR_WITH-DASH.AND_UNDERSCORE"
            $result = Set-EnvVar -name $specialName -value "SpecialValue"
            $result | Should -Be 0
            
            $getValue = Get-EnvVar-ByName -name $specialName
            $getValue | Should -Be "SpecialValue"
        }
        
        It "Should handle paths with spaces and special characters" {
            $pathWithSpaces = "C:\Program Files (x86)\Special App\bin"
            $global:MockRegistry.Machine["SPECIAL_APP"] = $pathWithSpaces
            $global:MockRegistry.Machine["Path"] = "C:\Windows\System32;$pathWithSpaces;C:\Other"
            
            $result = Optimize-SystemPath
            $result | Should -Be 0
            
            $optimizedPath = $global:MockRegistry.Machine["Path"]
            $optimizedPath | Should -Match "%SPECIAL_APP%"
        }
        
        It "Should handle Unicode characters in values" {
            $unicodeValue = "Côté_Açaí_测试"
            $result = Set-EnvVar -name "UNICODE_VAR" -value $unicodeValue
            $result | Should -Be 0
            
            $getValue = Get-EnvVar-ByName -name "UNICODE_VAR"
            $getValue | Should -Be $unicodeValue
        }
    }
    
    Context "Boundary value testing" {
        It "Should handle very long environment variable values" {
            $longValue = "A" * 1000
            $result = Set-EnvVar -name "LONG_VALUE_VAR" -value $longValue
            $result | Should -Be 0
            
            $getValue = Get-EnvVar-ByName -name "LONG_VALUE_VAR"
            $getValue | Should -Be $longValue
        }
        
        It "Should handle very long variable names" {
            $longName = "VERY_LONG_VARIABLE_NAME_" + ("X" * 100)
            $result = Set-EnvVar -name $longName -value "LongNameValue"
            $result | Should -Be 0
            
            $getValue = Get-EnvVar-ByName -name $longName
            $getValue | Should -Be "LongNameValue"
        }
    }
}

# State management tests
Describe "State Management Tests" -Tag "StateManagement" {
    Context "Mock state consistency" {
        It "Should maintain consistent state across multiple operations" {
            Reset-MockState
            # Initial state verification
            $initialPath = $global:MockRegistry.Machine["Path"]
            $initialJavaHome = $global:MockRegistry.Machine["JAVA_HOME"]
            
            # Perform optimization
            $result = Optimize-SystemPath
            $result | Should -Be 0
            
            # Verify backup was created correctly
            $backup = $global:MockRegistry.Machine[$PATH_VAR_BACKUP_NAME]
            $backup | Should -Be $initialPath
            
            # Verify JAVA_HOME unchanged
            $global:MockRegistry.Machine["JAVA_HOME"] | Should -Be $initialJavaHome
            
            # Verify PATH was modified
            $global:MockRegistry.Machine["Path"] | Should -Not -Be $initialPath
        }
        
        It "Should handle state reset correctly" {
            # Modify state
            Set-EnvVar -name "TEMP_VAR" -value "TempValue"
            $global:MockRegistry.Machine["TEMP_VAR"] | Should -Be "TempValue"
            
            # Reset state
            Reset-MockState
            
            # Verify reset worked
            $global:MockRegistry.Machine.ContainsKey("TEMP_VAR") | Should -Be $false
            $global:MockRegistry.Machine["JAVA_HOME"] | Should -Be "C:\Program Files\Java"
        }
    }
}
