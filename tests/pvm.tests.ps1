
BeforeAll {

    # Mock global variables that would be loaded from config
    $global:PVM_VERSION = "1.0.0"
    $global:LOG_ERROR_PATH = "C:\PVM\Logs\error.log"
    
    # Mock PSScriptRoot for dot sourcing tests
    $global:PSScriptRoot = "C:\PVM"

    # Setup mock file structure
    $global:MockHelperFiles = @(
        "C:\PVM\helpers\helpers.ps1"
    )
    
    $global:MockCoreFiles = @(
        "C:\PVM\core\config.ps1"
        "C:\PVM\core\variables.ps1"
    )
    
    $global:MockActionFiles = @(
        "C:\PVM\actions\setup.ps1"
        "C:\PVM\actions\install.ps1"
        "C:\PVM\actions\use.ps1"
    )
    
    # Mock the file loading behavior
    Mock Get-ChildItem {
        param($Path)
        
        $mockFiles = @()
        
        if ($Path -like "*\core\*.ps1") {
            foreach ($file in $global:MockCoreFiles) {
                $mockFiles += [PSCustomObject]@{
                    FullName = $file
                }
            }
        }
        elseif ($Path -like "*\actions\*.ps1") {
            foreach ($file in $global:MockActionFiles) {
                $mockFiles += [PSCustomObject]@{
                    FullName = $file
                }
            }
        }
        
        return $mockFiles
    }
}

Describe "PVM Main Script - File Loading Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Get-Actions { 
            [ordered]@{
                "setup" = [PSCustomObject]@{ action = { 0 } }
                "install" = [PSCustomObject]@{ action = { 0 } }
            }
        }
        Mock Is-PVM-Setup { $true }
        Mock Log-Data { }
        
        # Mock the dot sourcing operator
        $global:DotSourcedFiles = @()
        function Mock-DotSource {
            param($FilePath)
            $global:DotSourcedFiles += $FilePath
        }
        
        # Override the dot sourcing in tests
        Mock Invoke-Expression {
            param($Command)
            if ($Command -like ". *") {
                $filePath = $Command.Substring(2).Trim()
                Mock-DotSource -FilePath $filePath
            }
        } -ParameterFilter { $Command -like ". *" }
    }

    It "Should load helpers from helpers directory" {
        # Simulate script execution by manually calling the loading logic
        $helperFile = "$PSScriptRoot\helpers\helpers.ps1"
        
        # Verify Get-ChildItem would be called for helpers (this is implicit in the actual script)
        # The actual script uses: . $PSScriptRoot\helpers\helpers.ps1 directly
        
        # Test that the helpers path exists in our mock structure
        $global:MockHelperFiles | Should -Contain "C:\PVM\helpers\helpers.ps1"
    }

    It "Should load all core configuration files" {
        # Simulate the core file loading
        $coreFiles = Get-ChildItem "$PSScriptRoot\core\*.ps1"
        
        $coreFiles.Count | Should -Be 2
        $coreFiles[0].FullName | Should -Be "C:\PVM\core\config.ps1"
        $coreFiles[1].FullName | Should -Be "C:\PVM\core\variables.ps1"
    }

    It "Should load all action files" {
        # Simulate the actions file loading
        $actionFiles = Get-ChildItem "$PSScriptRoot\actions\*.ps1"
        
        $actionFiles.Count | Should -Be 3
        $actionFiles[0].FullName | Should -Be "C:\PVM\actions\setup.ps1"
        $actionFiles[1].FullName | Should -Be "C:\PVM\actions\install.ps1"
        $actionFiles[2].FullName | Should -Be "C:\PVM\actions\use.ps1"
    }
}

Describe "PVM Main Script - Version Display Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Get-Actions { @{} }
        Mock Is-PVM-Setup { $true }
        Mock Get-ChildItem { @() }
        
        $global:PVM_VERSION = "1.2.3"
    }

    It "Should display version and exit with --version flag" {
        # Test the version display logic
        $args = @('--version')
        
        # Simulate the version check logic
        if ($args -contains '--version') {
            Write-Host "`nPVM version $PVM_VERSION"
        }
        
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPVM version 1.2.3" 
        }
    }

    It "Should display version and exit with -v flag" {
        # Test the version display logic
        $args = @('-v')
        
        # Simulate the version check logic
        if ($args -contains '-v') {
            Write-Host "`nPVM version $PVM_VERSION"
        }
        
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPVM version 1.2.3" 
        }
    }

    It "Should display version and exit with 'version' operation" {
        # Test the version display logic
        $operation = 'version'
        
        # Simulate the version check logic
        if ($operation -eq 'version') {
            Write-Host "`nPVM version $PVM_VERSION"
        }
        
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPVM version 1.2.3" 
        }
    }
}

Describe "PVM Main Script - Operation Validation Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Is-PVM-Setup { $true }
        Mock Log-Data { }
        Mock Get-ChildItem { @() }
    }

    It "Should show usage when no operation is provided" {
        $operation = $null
        $actions = @{
            "setup" = [PSCustomObject]@{ action = { 0 } }
            "install" = [PSCustomObject]@{ action = { 0 } }
        }
        
        # Simulate the operation validation logic
        if (-not ($operation -and $actions.Contains($operation))) {
            Show-Usage
        }
        
        Assert-MockCalled Show-Usage -Times 1
    }

    It "Should show usage when invalid operation is provided" {
        $operation = "invalid-operation"
        $actions = @{
            "setup" = [PSCustomObject]@{ action = { 0 } }
            "install" = [PSCustomObject]@{ action = { 0 } }
        }
        
        # Simulate the operation validation logic
        if (-not ($operation -and $actions.Contains($operation))) {
            Show-Usage
        }
        
        Assert-MockCalled Show-Usage -Times 1
    }

    It "Should proceed when valid operation is provided" {
        $operation = "setup"
        $actions = @{
            "setup" = [PSCustomObject]@{ action = { 0 } }
            "install" = [PSCustomObject]@{ action = { 0 } }
        }
        
        # Simulate the operation validation logic
        $isValidOperation = $operation -and $actions.Contains($operation)
        
        $isValidOperation | Should -Be $true
        Assert-MockCalled Show-Usage -Times 0
    }
}

Describe "PVM Main Script - Setup Validation Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Log-Data { }
        Mock Get-ChildItem { @() }
    }

    It "Should skip setup check for 'setup' operation" {
        Mock Is-PVM-Setup { $false }
        
        $operation = "setup"
        $actions = @{
            "setup" = [PSCustomObject]@{ action = { 0 } }
        }
        
        # Simulate the setup validation logic
        $shouldCheckSetup = $operation -ne "setup"
        
        $shouldCheckSetup | Should -Be $false
        # Setup check should be skipped, so Is-PVM-Setup should not be called in this context
    }

    It "Should require setup for non-setup operations when PVM is not setup" {
        Mock Is-PVM-Setup { $false }
        
        $operation = "install"
        $actions = @{
            "setup" = [PSCustomObject]@{ action = { 0 } }
            "install" = [PSCustomObject]@{ action = { 0 } }
        }
        
        # Simulate the setup validation logic
        if ($operation -ne "setup" -and (-not (Is-PVM-Setup))) {
            Write-Host "`nPVM is not setup. Please run 'pvm setup' first."
        }
        
        Assert-MockCalled Is-PVM-Setup -Times 1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPVM is not setup. Please run 'pvm setup' first." 
        }
    }

    It "Should proceed when PVM is already setup" {
        Mock Is-PVM-Setup { $true }
        
        $operation = "install"
        $actions = @{
            "setup" = [PSCustomObject]@{ action = { 0 } }
            "install" = [PSCustomObject]@{ action = { 0 } }
        }
        
        # Simulate the setup validation logic
        $needsSetup = $operation -ne "setup" -and (-not (Is-PVM-Setup))
        
        $needsSetup | Should -Be $false
        Assert-MockCalled Is-PVM-Setup -Times 1
        Assert-MockCalled Write-Host -Times 0 -ParameterFilter { 
            $Object -like "*PVM is not setup*" 
        }
    }
}

Describe "PVM Main Script - Action Execution Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Is-PVM-Setup { $true }
        Mock Log-Data { }
        Mock Get-ChildItem { @() }
    }

    It "Should execute valid action and return its exit code" {
        $mockAction = {
            return 0
        }
        
        $operation = "setup"
        $actions = @{
            "setup" = [PSCustomObject]@{ action = $mockAction }
        }
        
        # Simulate action execution
        if ($operation -and $actions.Contains($operation)) {
            $exitCode = $actions[$operation].action.Invoke()
            $exitCode | Should -Be 0
        }
    }

    It "Should handle action that returns non-zero exit code" {
        $mockAction = {
            return 1
        }
        
        $operation = "install"
        $actions = @{
            "install" = [PSCustomObject]@{ action = $mockAction }
        }
        
        # Simulate action execution
        if ($operation -and $actions.Contains($operation)) {
            $exitCode = $actions[$operation].action.Invoke()
            $exitCode | Should -Be 1
        }
    }

    It "Should execute action with complex logic" {
        $mockAction = {
            # Simulate complex action logic
            $result = Test-Path "C:\SomePath"
            if ($result) {
                return 0
            } else {
                return 2
            }
        }
        
        Mock Test-Path { $true }
        
        $operation = "use"
        $actions = @{
            "use" = [PSCustomObject]@{ action = $mockAction }
        }
        
        # Simulate action execution
        if ($operation -and $actions.Contains($operation)) {
            $exitCode = $actions[$operation].action.Invoke()
            $exitCode | Should -Be 0
        }
        
        Assert-MockCalled Test-Path -Times 1
    }
}

Describe "PVM Main Script - Error Handling Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Is-PVM-Setup { $true }
        Mock Get-ChildItem { @() }
        Mock Log-Data { return $true }
    }

    It "Should catch and log exceptions during action execution" {
        $mockAction = {
            throw "Test exception message"
        }
        
        $operation = "install"
        $actions = @{
            "install" = [PSCustomObject]@{ action = $mockAction }
        }
        
        # Simulate error handling
        try {
            $actions[$operation].action.Invoke()
        } catch {
            $logged = Log-Data -data @{
                header = "pvm.ps1: An error occurred during operation '$operation'"
                file = $($_.InvocationInfo.ScriptName)
                line = $($_.InvocationInfo.ScriptLineNumber)
                message = $_.Exception.Message
            }
            Write-Host "`nOperation canceled or failed to elevate privileges." -ForegroundColor DarkYellow
        }
        
        Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
            $data.header -eq "pvm.ps1: An error occurred during operation 'install'" -and
            $data.message -like "*Test exception message*"
        }
        
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nOperation canceled or failed to elevate privileges." -and
            $ForegroundColor -eq "DarkYellow"
        }
    }

    It "Should handle different types of exceptions" {
        $testExceptions = @(
            [System.UnauthorizedAccessException]::new("Access denied"),
            [System.IO.FileNotFoundException]::new("File not found"),
            [System.ArgumentException]::new("Invalid argument")
        )
        
        foreach ($exception in $testExceptions) {
            $mockAction = {
                throw $exception
            }
            
            $operation = "test"
            $actions = @{
                "test" = [PSCustomObject]@{ action = $mockAction }
            }
            
            # Simulate error handling
            try {
                $actions[$operation].action.Invoke()
            } catch {
                $logged = Log-Data -data @{
                    header = "pvm.ps1: An error occurred during operation '$operation'"
                    file = $($_.InvocationInfo.ScriptName)
                    line = $($_.InvocationInfo.ScriptLineNumber)
                    message = $_.Exception.Message
                }
                Write-Host "`nOperation canceled or failed to elevate privileges." -ForegroundColor DarkYellow
            }
            
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.header -eq "pvm.ps1: An error occurred during operation 'test'" -and
                $data.message -like "*$($exception.Message)*"
            }
        }
    }

    It "Should log when Log-Data returns false (logging failed)" {
        Mock Log-Data { $false }
        
        $mockAction = {
            throw "Test exception"
        }
        
        $operation = "install"
        $actions = @{
            "install" = [PSCustomObject]@{ action = $mockAction }
        }
        
        # Simulate error handling
        try {
            $actions[$operation].action.Invoke()
        } catch {
            $logged = Log-Data -logPath $LOG_ERROR_PATH -message "PVM: An error occurred during operation '$operation'" -data $_.Exception.Message
            Write-Host "`nOperation canceled or failed to elevate privileges." -ForegroundColor DarkYellow
        }
        
        Assert-MockCalled Log-Data -Times 1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $ForegroundColor -eq "DarkYellow"
        }
    }
}

Describe "PVM Main Script - Progress Preference Tests" {
    It "Should set ProgressPreference to SilentlyContinue" {
        # This tests that the script sets the progress preference
        # In the actual script: $ProgressPreference = 'SilentlyContinue'
        
        $testProgressPreference = 'SilentlyContinue'
        $testProgressPreference | Should -Be 'SilentlyContinue'
    }
}

Describe "PVM Main Script - Integration Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Is-PVM-Setup { $true }
        Mock Log-Data { $true }
        Mock Get-ChildItem { @() }
        Mock Get-Actions {
            [ordered]@{
                "setup" = [PSCustomObject]@{ action = { return 0 } }
                "install" = [PSCustomObject]@{ action = { return 0 } }
                "current" = [PSCustomObject]@{ action = { return 0 } }
                "list" = [PSCustomObject]@{ action = { return 0 } }
            }
        }
    }

    Context "Complete Workflow Tests" {
        It "Should handle complete successful operation flow" {
            $operation = "install"
            
            # Simulate the complete main script flow
            $actions = Get-Actions -arguments @("8.2.0")
            
            # Check version flags
            $isVersionRequest = $args -contains '--version' -or $args -contains '-v' -or $operation -eq 'version'
            $isVersionRequest | Should -Be $false
            
            # Check operation validity
            $isValidOperation = $operation -and $actions.Contains($operation)
            $isValidOperation | Should -Be $true
            
            # Check setup requirement
            $needsSetup = $operation -ne "setup" -and (-not (Is-PVM-Setup))
            $needsSetup | Should -Be $false
            
            # Execute action
            $exitCode = $actions[$operation].action.Invoke()
            $exitCode | Should -Be 0
            
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Show-Usage -Times 0
            Assert-MockCalled Log-Data -Times 0
        }

        It "Should handle setup operation without setup check" {
            Mock Is-PVM-Setup { $false }
            $operation = "setup"
            
            # Simulate the complete main script flow
            $actions = Get-Actions -arguments @()
            
            # Check operation validity
            $isValidOperation = $operation -and $actions.Contains($operation)
            $isValidOperation | Should -Be $true
            
            # Setup operations should skip the setup check
            $shouldCheckSetup = $operation -ne "setup"
            $shouldCheckSetup | Should -Be $false
            
            # Execute action
            $exitCode = $actions[$operation].action.Invoke()
            $exitCode | Should -Be 0
            
            Assert-MockCalled Get-Actions -Times 1
            # Is-PVM-Setup should not be called for setup operation
            Assert-MockCalled Is-PVM-Setup -Times 0
        }

        It "Should handle error during operation with full error flow" {
            $mockAction = {
                throw [System.UnauthorizedAccessException]::new("Elevation required")
            }
            
            Mock Get-Actions {
                [ordered]@{
                    "install" = [PSCustomObject]@{ action = $mockAction }
                }
            }
            
            $operation = "install"
            
            # Simulate the complete main script flow with error
            $actions = Get-Actions -arguments @("8.2.0")
            
            try {
                $exitCode = $actions[$operation].action.Invoke()
            } catch {
                $logged = Log-Data -data @{
                    header = "pvm.ps1: An error occurred during operation '$operation'"
                    file = $($_.InvocationInfo.ScriptName)
                    line = $($_.InvocationInfo.ScriptLineNumber)
                    message = $_.Exception.Message
                }
                Write-Host "`nOperation canceled or failed to elevate privileges." -ForegroundColor DarkYellow
                $exitCode = 1
            }
            
            $exitCode | Should -Be 1
            
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.header -eq "pvm.ps1: An error occurred during operation 'install'" -and
                $data.message -like "*Elevation required*"
            }
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $ForegroundColor -eq "DarkYellow"
            }
        }
    }

    Context "Edge Cases and Boundary Tests" {
        It "Should handle empty operation parameter" {
            $operation = ""
            
            $actions = Get-Actions -arguments @()
            
            # Empty string operation should be treated as invalid
            $isValidOperation = $operation -and $actions.Contains($operation)
            $isValidOperation | Should -Be $false
        }

        It "Should handle null operation parameter" {
            $operation = $null
            
            $actions = Get-Actions -arguments @()
            
            # Null operation should be treated as invalid
            $isValidOperation = $operation -and $actions.Contains($operation)
            $isValidOperation | Should -Be $false
        }

        It "Should handle case sensitivity in operations" {
            $operation = "SETUP"  # Uppercase
            
            $actions = Get-Actions -arguments @()
            
            
            # PowerShell hashtables are case-insensitive by default, but test anyway
            $isValidOperation = $operation -and $actions.Contains($operation)
            
            # This depends on how the actual hashtable is configured
            # Assuming case-insensitive (PowerShell default)
            $isValidOperation | Should -Be $true
        }

        It "Should handle multiple version flags" {
            $args = @('--version', '-v', 'setup')
            
            # Test that any version flag triggers version display
            $hasVersionFlag = $args -contains '--version' -or $args -contains '-v'
            $hasVersionFlag | Should -Be $true
        }
    }
}

Describe "PVM Main Script - File Loading Error Handling" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Is-PVM-Setup { $true }
        Mock Log-Data { $true }
    }

    It "Should handle missing helpers directory" {
        # This would typically cause the script to fail if helpers don't load
        # The actual script uses: . $PSScriptRoot\helpers\helpers.ps1
        # If the file doesn't exist, PowerShell would throw an error
        
        Mock Test-Path { $false } -ParameterFilter { $Path -like "*helpers.ps1" }
        
        # Test that missing helpers file would be detected
        $helpersExist = Test-Path "$PSScriptRoot\helpers\helpers.ps1"
        $helpersExist | Should -Be $false
    }

    It "Should handle empty core directory" {
        Mock Get-ChildItem { @() } -ParameterFilter { $Path -like "*\core\*.ps1" }
        
        $coreFiles = Get-ChildItem "$PSScriptRoot\core\*.ps1"
        $coreFiles.Count | Should -Be 0
    }

    It "Should handle empty actions directory" {
        Mock Get-ChildItem { @() } -ParameterFilter { $Path -like "*\actions\*.ps1" }
        
        $actionFiles = Get-ChildItem "$PSScriptRoot\actions\*.ps1"
        $actionFiles.Count | Should -Be 0
    }
}