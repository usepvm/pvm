
BeforeAll {
    # Mock global variables that would be loaded from config
    $global:PVM_VERSION = '1.0.0'
    $global:LOG_ERROR_PATH = 'TestDrive:\logs\error.log'
}

Describe "Show-Usage Tests" {
    BeforeEach {
        Mock Get-Current-PHP-Version { @{ version = '8.2.0' } }
        Mock Write-Host { }

        # Mock the Get-Actions function to return a predictable set
        Mock Get-Actions {
            [ordered]@{
                'setup' = @{
                    command = 'pvm setup'
                    description = 'Setup the environment variables and paths for PHP.'
                }
                'current' = @{
                    command = 'pvm current'
                    description = 'Display active version.'
                }
            }
        }

        # Set the $actions variable that Show-Usage expects
        $script:actions = Get-Actions
    }

    It "Should display current version when available" {
        $global:PVM_VERSION = '2.0'
        Show-Usage

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Running version : 2.0*' }
    }

    It "Should display usage header" {
        Show-Usage

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*Usage:*' }
    }

    It "Should display all available commands with descriptions" {
        Show-Usage

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*pvm setup*Setup the environment*' }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*pvm current*Display active version*' }
    }

    It "Uses fallback maxDescLength when window is small" {
        # Narrow the host width to force fallback to 100
        $origSize = $Host.UI.RawUI.WindowSize
        $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(80,25)

        $longDesc = ('X' * 200)
        $script:actions = [ordered]@{
            'testcmd' = @{ command = 'pvm testcmd'; description = $longDesc }
        }

        Show-Usage

        # restore
        $Host.UI.RawUI.WindowSize = $origSize
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*pvm testcmd*' }
    }

    It "Breaks mid-word when no space within maxDescLength" {
        Mock Write-Host {}

        # Create description with no spaces in the first 150 chars
        $noSpace = ('A' * 150) + ' rest of description'
        $script:actions = [ordered]@{
            'nospace' = @{ command = 'pvm nospace'; description = $noSpace }
        }

        Show-Usage

        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*pvm nospace*' }
    }

    It "Writes additional description lines when wrapping occurs" {
        Mock Write-Host {}

        # Create description with spaces to force multiple wrapped lines
        $spaced = (1..10 | ForEach-Object { ('word' + $_) }) -join ' '
        $script:actions = [ordered]@{
            'multiline' = @{ command = 'pvm multiline'; description = $spaced }
        }

        Show-Usage

        # Ensure additional lines were written (calls beyond the initial line)
        Assert-MockCalled Write-Host -ParameterFilter { $Object -like '*multiline*' }
    }
}

Describe "Show-PVM-Version Function Tests" {
    BeforeEach {
        Mock Write-Host { }
        $global:PVM_VERSION = '1.2.3'
    }

    It "Should display version with proper formatting" {
        Show-PVM-Version

        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nPVM version 1.2.3"
        }
    }

    It "Should display version when PVM_VERSION is null" {
        $global:PVM_VERSION = $null
        Show-PVM-Version

        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nPVM version "
        }
    }

    It "Should display version when PVM_VERSION is empty string" {
        $global:PVM_VERSION = ''
        Show-PVM-Version

        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nPVM version "
        }
    }

    It "Should display version with different version formats" {
        $testVersions = @('1.0.0', '2.5.1-beta', '3.0.0-alpha.1', 'v1.0.0', '1.0.0.0')

        foreach ($version in $testVersions) {
            $global:PVM_VERSION = $version
            Show-PVM-Version

            Assert-MockCalled Write-Host -ParameterFilter {
                $Object -eq "`nPVM version $version"
            }
        }
    }

    It "Should handle special characters in version" {
        $global:PVM_VERSION = '1.0.0-RC1+build.123'
        Show-PVM-Version

        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nPVM version 1.0.0-RC1+build.123"
        }
    }
}

Describe "Resolve-Alias Tests" {
    $testCases = @(
        @{ Command = 'h'; Expected = 'help' }
        @{ Command = 'H'; Expected = 'help' }
        @{ Command = 'ls'; Expected = 'list' }
        @{ Command = 'rm'; Expected = 'uninstall' }
        @{ Command = 'i'; Expected = 'install' }
        @{ Command = 'LS'; Expected = 'list' }
        @{ Command = 'RM'; Expected = 'uninstall' }
        @{ Command = 'I'; Expected = 'install' }
        @{ Command = 'install'; Expected = 'install' }
        @{ Command = 'list'; Expected = 'list' }
        @{ Command = 'uninstall'; Expected = 'uninstall' }
        @{ Command = 'unknown'; Expected = 'unknown' }
        @{ Command = ''; Expected = $null }
        @{ Command = '    '; Expected = $null }
        @{ Command = $null; Expected = $null }
    )

    It "Returns '<Expected>' when '<Command>' is passed" -TestCases $testCases {
        param ($Command, $Expected)
        $result = Resolve-Alias -alias $Command
        $result | Should -Be $Expected
    }
}

Describe "Start-PVM Function Tests" {
    BeforeEach {
        Mock Write-Host { }
        Mock Show-Usage { }
        Mock Show-PVM-Version { }
        Mock Get-Actions {
            [ordered]@{
                'setup' = @{ action = { return 0 } }
                'install' = @{ action = { return 0 } }
                'use' = @{ action = { return 0 } }
                'list' = @{ action = { return 0 } }
            }
        }
        Mock Is-PVM-Setup { $true }
        Mock Log-Data { 0 }
        Mock Resolve-Alias {
            param ($alias)

            if ([string]::IsNullOrWhiteSpace($alias)) {
                return $null
            }

            $alias = $alias.ToLower().Trim()
            switch ($alias) {
                'ls' { return 'list' }
                'rm' { return 'uninstall' }
                'i'  { return 'install' }
                Default { return $alias }
            }
        }

        $global:PVM_VERSION = '1.2.3'
    }

    Context "Version Display Path Tests" {
        It "Should show version and return 0 with --version argument" {
            $result = Start-PVM -command 'install' -arguments @('--version')

            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should show version and return 0 with -v argument" {
            $result = Start-PVM -command 'install' -arguments @('-v')

            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should show version and return 0 with version command" {
            $result = Start-PVM -command 'version' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should show version when both version flag and version command are present" {
            $result = Start-PVM -command 'version' -arguments @('--version')

            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
        }

        It "Should show version with --version in mixed arguments" {
            $result = Start-PVM -command 'install' -arguments @('8.2.0', '--version', 'extra')

            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
        }

        It "Should show version with -v in mixed arguments" {
            $result = Start-PVM -command 'use' -arguments @('8.1.0', '-v', '--force')

            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            Assert-MockCalled Get-Actions -Times 0
        }

        It "Should not show version with partial matches" {
            $result = Start-PVM -command 'install' -arguments @('--verbose', '-version')

            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 0
            Assert-MockCalled Get-Actions -Times 1
        }
    }

    Context "Command Validation Path Tests" {
        It "Should show usage and return 0 when command is null" {
            $result = Start-PVM -command $null -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Resolve-Alias -Times 1
        }

        It "Should show usage and return 0 when command is empty string" {
            $result = Start-PVM -command '' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Resolve-Alias -Times 1
        }

        It "Should show usage and return 0 when command is whitespace" {
            $result = Start-PVM -command '   ' -arguments @()

            $result = Start-PVM -command '   ' -arguments @()
            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
        }

        It "Should show usage and return 0 when command not in actions" {
            $result = Start-PVM -command 'invalid-command' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Resolve-Alias -Times 1
        }

        It "Should proceed when command exists in actions" {
            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 0
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Resolve-Alias -Times 1
        }

        It "Should handle alias conversion correctly" {
            $result = Start-PVM -command 'i' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Resolve-Alias -Times 1 -ParameterFilter { $alias -eq 'i' }
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should handle case where Get-Actions returns empty hashtable" {
            Mock Get-Actions { @{} }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
        }
    }

    Context "Setup Validation Path Tests" {
        It "Should skip setup check for setup command" {
            Mock Is-PVM-Setup { $false }

            $result = Start-PVM -command 'setup' -arguments @()

            $result | Should -Be 0
            # The setup check condition should not evaluate Is-PVM-Setup for setup command
            Assert-MockCalled Is-PVM-Setup -Times 0
        }

        It "Should require setup when PVM is not setup for non-setup command" {
            Mock Is-PVM-Setup { $false }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be -1
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $Object -eq "`nPVM is not setup. Please run 'pvm setup' first."
            }
        }

        It "Should proceed when PVM is setup for non-setup command" {
            Mock Is-PVM-Setup { $true }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Write-Host -Times 0 -ParameterFilter {
                $Object -like '*PVM is not setup*'
            }
        }

        It "Should handle different commands requiring setup check" {
            $commandsRequiringSetup = @('install', 'use', 'list', 'current', 'ini', 'profile', 'cache')
            Mock Is-PVM-Setup { $false }

            foreach ($op in $commandsRequiringSetup) {
                Mock Get-Actions {
                    [ordered]@{
                        $op = @{ action = { return 0 } }
                    }
                }

                $result = Start-PVM -command $op -arguments @()

                $result | Should -Be -1
                Assert-MockCalled Write-Host -ParameterFilter {
                    $Object -eq "`nPVM is not setup. Please run 'pvm setup' first."
                }
            }
        }
    }

    Context "Action Execution Path Tests" {
        It "Should execute action and return 0" {
            Mock Get-Actions {
                [ordered]@{
                    'install' = @{ action = { return 0 } }
                }
            }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be 0
        }

        It "Should execute action and return non-zero exit code" {
            Mock Get-Actions {
                [ordered]@{
                    'install' = @{ action = { return -1 } }
                }
            }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be -1
        }

        It "Should execute action and return custom exit code" {
            Mock Get-Actions {
                [ordered]@{
                    'use' = @{ action = { return 42 } }
                }
            }

            $result = Start-PVM -command 'use' -arguments @()

            $result | Should -Be 42
        }

        It "Should execute complex action logic" {
            Mock Test-Path { $true }
            Mock Get-Actions {
                [ordered]@{
                    'test' = @{
                        action = {
                            if (Test-Path 'C:\Test') { return 0 } else { return -1 }
                        }
                    }
                }
            }

            $result = Start-PVM -command 'test' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Test-Path -Times 1
        }
    }

    Context "Error Handling Path Tests" {
        It "Should catch exception and return -1" {
            Mock Get-Actions {
                [ordered]@{
                    'install' = @{
                        action = { throw 'Test exception' }
                    }
                }
            }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $Object -eq "`nCommand canceled or failed to elevate privileges." -and
                $ForegroundColor -eq 'DarkYellow'
            }
        }

        It "Should handle exception with proper logging data" {
            Mock Get-Actions {
                [ordered]@{
                    'install' = @{
                        action = { throw 'Detailed test exception' }
                    }
                }
            }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.header -eq "Start-PVM - An error occurred during command 'install'" -and
                $data.exception.Exception.Message -like '*Detailed test exception*'
            }
        }

        It "Should handle different exception types" {
            $exceptions = @(
                [System.UnauthorizedAccessException]::new('Access denied'),
                [System.IO.FileNotFoundException]::new('File not found'),
                [System.ArgumentException]::new('Invalid argument'),
                [System.InvalidOperationException]::new('Invalid command state')
            )

            foreach ($exception in $exceptions) {
                Mock Get-Actions {
                    [ordered]@{
                        'test' = @{
                            action = { throw $exception }
                        }
                    }
                }

                $result = Start-PVM -command 'test' -arguments @()

                $result | Should -Be -1
                Assert-MockCalled Log-Data -ParameterFilter {
                    $data.exception.Exception.Message -like "*$($exception.Message)*"
                }
            }
        }

        It "Should handle exception during Get-Actions call" {
            Mock Get-Actions { throw 'Get-Actions failed' }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.exception.Exception.Message -like '*Get-Actions failed*'
            }
        }

        It "Should handle exception during Resolve-Alias call" {
            Mock Resolve-Alias { throw 'Alias handler failed' }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.exception.Exception.Message -like '*Alias handler failed*'
            }
        }

        It "Should handle exception during Is-PVM-Setup call" {
            Mock Is-PVM-Setup { throw 'Setup check failed' }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.exception.Exception.Message -like '*Setup check failed*'
            }
        }

        It "Should handle exception when Log-Data fails" {
            Mock Log-Data { -1 }
            Mock Get-Actions {
                [ordered]@{
                    'install' = @{
                        action = { throw 'Test exception' }
                    }
                }
            }

            $result = Start-PVM -command 'install' -arguments @()

            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $ForegroundColor -eq 'DarkYellow'
            }
        }

        It "Should handle null command in exception logging" {
            Mock Get-Actions { throw 'Early exception' }

            $result = Start-PVM -command $null -arguments @()

            $result | Should -Be -1
            Assert-MockCalled Log-Data -Times 1 -ParameterFilter {
                $data.header -eq "Start-PVM - An error occurred during command ''"
            }
        }
    }

    Context "Edge Cases and Boundary Tests" {
        It "Should handle null arguments parameter" {
            $result = Start-PVM -command 'setup' -arguments $null

            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1 -ParameterFilter { $arguments -eq $null }
        }

        It "Should handle empty arguments array" {
            $result = Start-PVM -command 'setup' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1 -ParameterFilter { $arguments.Count -eq 0 }
        }

        It "Should handle large arguments array" {
            $largeArgs = 1..100 | ForEach-Object { "arg$_" }

            $result = Start-PVM -command 'setup' -arguments $largeArgs

            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1 -ParameterFilter { $arguments.Count -eq 100 }
        }

        It "Should handle version flag with other parameters" {
            $result = Start-PVM -command 'install' -arguments @('8.2.0', '--version', '--force', 'extra')

            $result | Should -Be 0
            Assert-MockCalled Show-PVM-Version -Times 1
            # Should short-circuit before other calls
            Assert-MockCalled Get-Actions -Times 0
        }

        It "Should handle multiple commands through alias handler" {
            Mock Resolve-Alias { param ($alias)
                switch ($alias) {
                    'i' { return 'install' }
                    'u' { return 'use' }
                    'l' { return 'list' }
                    default { return $alias }
                }
            }

            $testCases = @(
                @{ input = 'i'; expected = 'install' },
                @{ input = 'u'; expected = 'use' },
                @{ input = 'l'; expected = 'list' },
                @{ input = 'unknown'; expected = 'unknown' }
            )

            foreach ($case in $testCases) {
                Mock Get-Actions {
                    [ordered]@{
                        'install' = @{ action = { return 10 } }
                        'use' = @{ action = { return 20 } }
                        'list' = @{ action = { return 30 } }
                    }
                }

                $result = Start-PVM -command $case.input -arguments @()

                Assert-MockCalled Resolve-Alias -ParameterFilter { $alias -eq $case.input }

                if ($case.expected -in @('install', 'use', 'list')) {
                    $result | Should -BeGreaterThan 0
                    Assert-MockCalled Show-Usage -Times 0
                } else {
                    $result | Should -Be 0
                    Assert-MockCalled Show-Usage -Times 1
                }
            }
        }

        It "Should preserve argument order and content" {
            $testArgs = @('arg1', '--flag', 'value with spaces', '123')

            Start-PVM -command 'setup' -arguments $testArgs

            Assert-MockCalled Get-Actions -Times 1 -ParameterFilter {
                $arguments.Count -eq 4 -and
                $arguments[0] -eq 'arg1' -and
                $arguments[1] -eq '--flag' -and
                $arguments[2] -eq 'value with spaces' -and
                $arguments[3] -eq '123'
            }
        }
    }

    Context "Nested Command Tests" {
        BeforeEach {
            Mock Get-Actions {
                [ordered]@{
                    'install' = @{ action = { return Invoke-Install -arguments @() } }
                    'list' = @{ action = { return Invoke-List -arguments @() } }
                    'ini' = @{ action = { return Invoke-Ini -arguments @() } }
                    'cache' = @{ action = { return Invoke-Cache -arguments @() } }
                }
            }
        }

        It "Should execute nested command" -tag i {
            Mock Invoke-Ini { return 0 }
            $result = Start-PVM -command 'ini:get' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Invoke-Ini -Times 1
        }

        It "Should execute non nested command" -tag ii {
            Mock Show-Usage { }
            $result = Start-PVM -command 'install:8.2.0' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Show-Usage -Times 1
        }
    }

    Context "Integration Path Tests" {
        It "Should execute complete happy path" {
            Mock Get-Actions {
                [ordered]@{
                    'install' = @{ action = { return 0 } }
                }
            }
            Mock Is-PVM-Setup { $true }

            $result = Start-PVM -command 'install' -arguments @('8.2.0')

            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Resolve-Alias -Times 1
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Show-Usage -Times 0
            Assert-MockCalled Show-PVM-Version -Times 0
            Assert-MockCalled Log-Data -Times 0
        }

        It "Should handle complete setup workflow" {
            Mock Get-Actions {
                [ordered]@{
                    'setup' = @{ action = { return 0 } }
                }
            }
            Mock Resolve-Alias { param ($alias) return $alias }
            # Is-PVM-Setup should not be called for setup command

            $result = Start-PVM -command 'setup' -arguments @()

            $result | Should -Be 0
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Resolve-Alias -Times 1
            Assert-MockCalled Is-PVM-Setup -Times 0
            Assert-MockCalled Show-Usage -Times 0
        }

        It "Should handle complete error workflow" {
            Mock Get-Actions {
                [ordered]@{
                    'install' = @{
                        action = { throw [System.UnauthorizedAccessException]::new('Access denied') }
                    }
                }
            }
            Mock Resolve-Alias { param ($alias) return $alias }
            Mock Is-PVM-Setup { $true }
            Mock Log-Data { 0 }

            $result = Start-PVM -command 'install' -arguments @('8.2.0')

            $result | Should -Be -1
            Assert-MockCalled Get-Actions -Times 1
            Assert-MockCalled Resolve-Alias -Times 1
            Assert-MockCalled Is-PVM-Setup -Times 1
            Assert-MockCalled Log-Data -Times 1
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
                $ForegroundColor -eq 'DarkYellow'
            }
        }
    }
}
