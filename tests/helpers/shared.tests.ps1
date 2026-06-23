
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

Describe "Get-EnvConfig" {
    BeforeEach {
        $script:envRoot = 'TestDrive:\envconfig'
        New-Item -ItemType Directory -Path $script:envRoot -Force | Out-Null
    }

    Context "When .env file is missing" {
        It "Copies .env.example to .env" {
            Set-Content -Path "$envRoot\.env.example" -Value 'KEY=value'
            Get-EnvConfig -rootPath $envRoot

            $result = Get-Content -Path "$envRoot\.env"
            $result | Should -Be 'KEY=value'
        }
    }

    Context "When .env file exists" {
        It "Writes a verbose message with the env file path" {
            Set-Content -Path "$envRoot\.env" -Value 'KEY=value'
            Mock Write-Verbose {}

            Get-EnvConfig -rootPath $envRoot -Verbose

            Assert-MockCalled Write-Verbose -ParameterFilter {
                $Message -eq "Using .env from: $envRoot\.env"
            } -Times 1 -Exactly
        }

        It "Returns a hashtable of parsed key=value pairs" {
            @'
PHP_CURRENT_VERSION_PATH=C:\pvm\php
CACHE_MAX_HOURS=168
DEFAULT_LOG_PAGE_SIZE=5
'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 3
            $result['PHP_CURRENT_VERSION_PATH'] | Should -Be 'C:\pvm\php'
            $result['CACHE_MAX_HOURS'] | Should -Be '168'
            $result['DEFAULT_LOG_PAGE_SIZE'] | Should -Be '5'
        }

        It "Skips empty lines and comment lines" {
            @'

# Top-level comment
   # Indented comment

KEY=value

'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result.Count | Should -Be 1
            $result['KEY'] | Should -Be 'value'
        }

        It "Trims whitespace around keys and values" {
            '  KEY  =  value  ' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['KEY'] | Should -Be 'value'
        }

        It "Removes matching double quotes from values" {
            'QUOTED="hello world"' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['QUOTED'] | Should -Be 'hello world'
        }

        It "Removes matching single quotes from values" {
            "QUOTED='hello world'" | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['QUOTED'] | Should -Be 'hello world'
        }

        It "Keeps unquoted values unchanged" {
            'PLAIN=hello world' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['PLAIN'] | Should -Be 'hello world'
        }

        It "Keeps values with mismatched or unclosed quotes unchanged" {
            @'
MISMATCHED="value'
UNCLOSED="value
'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['MISMATCHED'] | Should -Be '"value'''
            $result['UNCLOSED'] | Should -Be '"value'
        }

        It "Ignores lines that are not key=value pairs" {
            @'
NOT_A_PAIR
ALSO NOT VALID
VALID=yes
'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result.Count | Should -Be 1
            $result['VALID'] | Should -Be 'yes'
        }

        It "Parses empty values" {
            'EMPTY=' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['EMPTY'] | Should -Be ''
        }

        It "Preserves inline comments as part of the value" {
            'CACHE_MAX_HOURS=168 # Cached available versions expiration in hours' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['CACHE_MAX_HOURS'] | Should -Be '168 # Cached available versions expiration in hours'
        }

        It "Returns an empty hashtable when the file has only comments and blank lines" {
            @'
# comment only

'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 0
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
    Context "When checking admin status" {
        It "Returns a boolean value" {
            $result = Is-Not-Admin
            $result | Should -BeOfType [bool]
        }
    }
}

Describe "Display-Msg-By-ExitCode" {
    Context "When displaying messages" {
        It "Displays message without error" {
            Mock Write-Host {}
            $testResult = @{
                message = 'Test message'
                color = 'Gray'
            }
            { Display-Msg-By-ExitCode -result $testResult } | Should -Not -Throw
        }

        It "Displays custom message if provided" {
            Mock Write-Host {}
            $testResult = @{
                message = 'Original message'
            }
            $customMessage = 'Custom message'
            { Display-Msg-By-ExitCode -result $testResult -message $customMessage } | Should -Not -Throw
        }

        It "Displays list of messages if provided" {
            Mock Write-Host { }
            $testResults = @{
                code = 0
                messages = @(
                    @{ content = 'Message 1'; color = 'Red' }
                    @{ content = 'Message 2'; color = 'Green' }
                    @{ content = 'Message 3' }
                )
            }
            { Display-Msg-By-ExitCode -result $testResults } | Should -Not -Throw
        }

        It "Handles exceptions gracefully" {
            Mock Write-Host { throw 'Simulated Write-Host failure' }
            $testResult = @{
                message = 'Test message'
                color = 'Gray'
            }
            { Display-Msg-By-ExitCode -result $testResult } | Should -Not -Throw
        }
    }
}

Describe "Log-Data" {
    Context "When logging data" {
        It "Logs data successfully" {
            $script:LOG_ERROR_PATH = $PVMConfig.paths.logError = 'TestDrive:\logs\test.log'
            $result = Log-Data -data @{
                header = 'Test message'
                exception = @{
                    Exception = @{ Message = 'Test data' }
                    InvocationInfo = @{
                        ScriptName = 'test.ps1'
                        ScriptLineNumber = 1
                        PositionMessage = 'Test position'
                    }
                }
            }
            $result | Should -Be 0
            Test-Path $LOG_ERROR_PATH | Should -Be $true
            # Get the actual content
            $content = Get-Content -Path $LOG_ERROR_PATH -Raw

            # Verify the complete log format
            $content | Should -Match '\[.*\] Test message(.|\s)*Message: Test data'

            # Alternatively, you could check parts separately
            $content | Should -Match 'Test message'
            $content | Should -Match 'Test data'
            $content | Should -Match (Get-Date -Format 'yyyy-MM-dd')
        }

        It "Returns -1 when unable to create directory" {
            Mock Make-Directory { throw 'Failed to create directory' }
            # Try to log to a protected location
            $result = Log-Data -data @{
                header = 'Test message'
                exception = 'Test data'
            }
            $result | Should -Be -1
        }

        It "Accepts custom log path" {
            $customLogPath = 'TestDrive:\logs\custom.log'
            $result = Log-Data -data @{
                header = 'Test message'
                logPath = $customLogPath
            }
            $result | Should -Be 0
            Test-Path $customLogPath | Should -Be $true
        }

        It "Returns -1 when unable to create log file" {
            Mock Make-Directory { return -1 }
            # Try to log to a protected location
            $result = Log-Data -data @{
                header = 'Test message'
                exception = 'Test data'
            }
            $result | Should -Be -1
        }
    }
}

Describe "Format-Seconds" {
    Context "When formatting seconds" {
        It "Formats seconds less than 60 with decimal precision" {
            $result = Format-Seconds -totalSeconds 30.5
            $result | Should -Be '30.5s'

            $result = Format-Seconds -totalSeconds 45.123
            $result | Should -Be '45.1s'

            $result = Format-Seconds -totalSeconds 0
            $result | Should -Be '0s'
        }

        It "Formats minutes and seconds without hours" {
            $result = Format-Seconds -totalSeconds 90
            $result | Should -Be '01:30'

            $result = Format-Seconds -totalSeconds 125
            $result | Should -Be '02:05'

            $result = Format-Seconds -totalSeconds 3599
            $result | Should -Be '59:59'
        }

        It "Formats hours, minutes, and seconds" {
            $result = Format-Seconds -totalSeconds 3600
            $result | Should -Be '01:00:00'

            $result = Format-Seconds -totalSeconds 3661
            $result | Should -Be '01:01:01'

            $result = Format-Seconds -totalSeconds 7325
            $result | Should -Be '02:02:05'

            $result = Format-Seconds -totalSeconds 86400
            $result | Should -Be '24:00:00'
        }

        It "Handles negative values by converting to zero" {
            $result = Format-Seconds -totalSeconds -10
            $result | Should -Be '0s'

            $result = Format-Seconds -totalSeconds -100.5
            $result | Should -Be '0s'
        }

        It "Handles decimal values in minute ranges" {
            $result = Format-Seconds -totalSeconds 90.7
            $result | Should -Be '01:30'

            $result = Format-Seconds -totalSeconds 125.9
            $result | Should -Be '02:05'
        }

        It "Handles decimal values in hour ranges" {
            $result = Format-Seconds -totalSeconds 3600.5
            $result | Should -Be '01:00:00'

            $result = Format-Seconds -totalSeconds 3661.8
            $result | Should -Be '01:01:01'
        }

        It "Handles null input" {
            $result = Format-Seconds -totalSeconds $null
            $result | Should -Be '0s'
        }

        It "Handles string input that can be converted" {
            $result = Format-Seconds -totalSeconds '90'
            $result | Should -Be '01:30'
        }

        It "Handles string input that cannot be converted" {
            $result = Format-Seconds -totalSeconds 'not a number'
            $result | Should -Be -1
        }
    }
}

Describe "Resolve-Arch" {
    Context "When searching in arguments" {
        It "Returns x86 when x86 is in arguments" {
            $arguments = @('some_arg', 'x86', 'another_arg')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x86'
        }

        It "Returns x64 when x64 is in arguments" {
            $arguments = @('some_arg', 'x64', 'another_arg')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x64'
        }

        It "Returns first matching architecture when multiple are present" {
            $arguments = @('x86', 'x64', 'other')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x86'
        }

        It "Returns null when no matching architecture in arguments" {
            $arguments = @('some_arg', 'another_arg', 'third_arg')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Case insensitivity" {
        It "Returns lowercase x86 when uppercase X86 provided" {
            $arguments = @('X86')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x86'
        }

        It "Returns lowercase x64 when mixed case X64 provided" {
            $arguments = @('X64')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x64'
        }
    }

    Context "With default choice" {
        It "Returns x64 as default when 64-bit OS and choseDefault is true" {
            Mock Is-OS-64Bit { return $true }
            $arguments = @('some_arg', 'other_arg')

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x64'
        }

        It "Returns x86 as default when 32-bit OS and choseDefault is true" {
            Mock Is-OS-64Bit { return $false }
            $arguments = @('some_arg', 'other_arg')

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x86'
        }

        It "Returns argument arch even when choseDefault is true" {
            Mock Is-OS-64Bit { return $true }
            $arguments = @('x86', 'some_arg')

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x86'
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
            $result | Should -Be 'x64'
        }

        It "Returns null when arguments is null" {
            $result = Resolve-Arch -arguments $null
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Resolve-BuildType" {
    Context "When searching in arguments" {
        It "Returns nts when nts is in arguments" {
            $arguments = @('some_arg', 'nts', 'another_arg')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'nts'
        }

        It "Returns ts when ts is in arguments" {
            $arguments = @('some_arg', 'ts', 'another_arg')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'ts'
        }

        It "Returns first matching architecture when multiple are present" {
            $arguments = @('ts', 'nts', 'other')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'ts'
        }

        It "Returns null when no matching architecture in arguments" {
            $arguments = @('some_arg', 'another_arg', 'third_arg')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Case insensitivity" {
        It "Returns lowercase nts when uppercase NTS provided" {
            $arguments = @('NTS')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'nts'
        }

        It "Returns lowercase TS when mixed case TS provided" {
            $arguments = @('TS')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'TS'
        }
    }

    Context "With default choice" {
        It "Returns ts as default when choseDefault is true" {
            $arguments = @('some_arg', 'other_arg')

            $result = Resolve-BuildType -arguments $arguments -choseDefault $true
            $result | Should -Be 'ts'
        }

        It "Returns argument arch even when choseDefault is true" {
            $arguments = @('nts', 'some_arg')

            $result = Resolve-BuildType -arguments $arguments -choseDefault $true
            $result | Should -Be 'nts'
        }
    }

    Context "With empty or null inputs" {
        It "Returns null when arguments array is empty and choseDefault is false" {
            $arguments = @()
            $result = Resolve-BuildType -arguments $arguments -choseDefault $false
            $result | Should -BeNullOrEmpty
        }

        It "Returns default when arguments array is empty and choseDefault is true" {
            $arguments = @()

            $result = Resolve-BuildType -arguments $arguments -choseDefault $true
            $result | Should -Be 'ts'
        }

        It "Returns null when arguments is null" {
            $result = Resolve-BuildType -arguments $null
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Set-Aliases-List" {
    BeforeAll {
        $script:TEMPLATES_PATH = $PVMConfig.paths.templates = 'TestDrive:\\storage\data\templates'
        $PVMConfig.paths.aliasesList = "$TEMPLATES_PATH\aliases.json"
        New-Item -ItemType Directory -Force -Path $script:TEMPLATES_PATH | Out-Null
        $script:DEFAULT_ALIASES = $PVMConfig.defaults.aliases
    }

    It "Creates aliases.json" {
        $result = Set-Aliases-List
        $result | Should -Be 0

        $result = Get-Aliases
        $result.Count | Should -Be $DEFAULT_ALIASES.Count
    }

    It "Returns -1 when exception is thrown" {
        Mock Set-Content { throw 'Test exception' }
        $result = Set-Aliases-List
        $result | Should -Be -1
    }
}

Describe "Get-Aliases" {
    BeforeAll {
        $script:TEMPLATES_PATH = $PVMConfig.paths.templates = 'TestDrive:\\storage\data\templates'
        $script:ALIASES_LIST_PATH = $PVMConfig.paths.aliasesList = "$TEMPLATES_PATH\aliases.json"
        New-Item -ItemType Directory -Path $script:TEMPLATES_PATH | Out-Null
        $testContent = [ordered]@{'?'  = 'help'; 'i'  = 'install'; 'init' = 'setup'}
        $testContent | ConvertTo-Json -Depth 10 | Set-Content -Path $ALIASES_LIST_PATH
        $script:DEFAULT_ALIASES = $PVMConfig.defaults.aliases
    }

    It "Returns aliases from aliases.json or PVMConfig.defaults.aliases" {
        $result = Get-Aliases
        $result.Count | Should -Be 3
        $result['?'] | Should -Be 'help'
        $result['i'] | Should -Be 'install'
        $result['init'] | Should -Be 'setup'
    }

    It "Falls back to DEFAULT_ALIASES value" {
        Remove-Item -Path "$script:TEMPLATES_PATH\aliases.json"
        $result = Get-Aliases
        $result.Count | Should -Be $DEFAULT_ALIASES.Count
    }

    It "Returns default value when exception is thrown" {
        Mock Is-File-Exists { return $true }
        Mock Get-Content { throw 'Test exception' }
        $result = Get-Aliases
        $result.Count | Should -Be $DEFAULT_ALIASES.Count
    }
}

Describe "Resolve-Alias Tests" {
    $testCases = @(
        @{ Command = '?'; Expected = 'help' }
        @{ Command = 'h'; Expected = 'help' }
        @{ Command = 'H'; Expected = 'help' }
        @{ Command = 'INIT'; Expected = 'setup' }
        @{ Command = 'CUR'; Expected = 'current' }
        @{ Command = 'ACTive'; Expected = 'current' }
        @{ Command = 'ls'; Expected = 'list' }
        @{ Command = 'list'; Expected = 'list' }
        @{ Command = 'u'; Expected = 'uninstall' }
        @{ Command = 'U'; Expected = 'uninstall' }
        @{ Command = 'uninstall'; Expected = 'uninstall' }
        @{ Command = 'I'; Expected = 'install' }
        @{ Command = 'install'; Expected = 'install' }
        @{ Command = 'SWITCH'; Expected = 'use' }
        @{ Command = 'ON'; Expected = 'enable' }
        @{ Command = 'OFF'; Expected = 'disable' }
        @{ Command = 'A'; Expected = 'add' }
        @{ Command = '+'; Expected = 'add' }
        @{ Command = 'rm'; Expected = 'remove' }
        @{ Command = '-'; Expected = 'remove' }
        @{ Command = 'i'; Expected = 'install' }
        @{ Command = 'LS'; Expected = 'list' }
        @{ Command = 'RM'; Expected = 'remove' }
        @{ Command = 'DEL'; Expected = 'delete' }
        @{ Command = 'CLS'; Expected = 'clear' }
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

Describe "Get-FlagMap" {
    It "Returns PVMConfig.defaults.flags" {
        $result = Get-FlagMap
        $result.Count | Should -Be $PVMConfig.defaults.flags.Count
    }
}

Describe "Resolve-FlagCommand" {
    $testCases = @(
        @{ Command = '--version'; Expected = 'version' }
        @{ Command = '-v'; Expected = 'version' }
        @{ Command = '--help'; Expected = 'help' }
        @{ Command = '-h'; Expected = 'help' }
        @{ Command = 'unknown'; Expected = $null }
        @{ Command = ''; Expected = $null }
        @{ Command = '    '; Expected = $null }
    )

    It "Returns '<Expected>' when '<Command>' is passed" -TestCases $testCases {
        param ($Command, $Expected)
        $result = Resolve-FlagCommand -arguments @($Command)
        $result | Should -Be $Expected
    }
}

Describe "Get-Config" {
    Context "When .env file exists" {
        BeforeAll {
            $script:testRoot = 'TestDrive:\pvm'
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
            @'
PHP_CURRENT_VERSION_PATH=C:\pvm\php
PVM_ENV_VAR_NAME=PVM
CACHE_MAX_HOURS=168
DEFAULT_LOG_PAGE_SIZE=5
DEFAULT_PARTIAL_LIST_SIZE=10
MIN_PAD_RIGHT_LENGTH=20
MIN_LINE_LENGTH=50
'@ | Set-Content -Path "$testRoot\.env"
        }

        It "Returns a hashtable with all expected sections" {
            $result = Get-Config -rootPath $testRoot

            $result | Should -BeOfType [hashtable]
            $result.ContainsKey('version') | Should -Be $true
            $result.ContainsKey('paths') | Should -Be $true
            $result.ContainsKey('links') | Should -Be $true
            $result.ContainsKey('env') | Should -Be $true
            $result.ContainsKey('defaults') | Should -Be $true
        }

        It "Sets the correct version" {
            $result = Get-Config -rootPath $testRoot
            $result.version | Should -Be '2.6'
        }

        It "Sets paths correctly" {
            $result = Get-Config -rootPath $testRoot
            $result.paths.storage | Should -Be "$testRoot\storage"
            $result.paths.php | Should -Be "$testRoot\storage\php"
            $result.paths.data | Should -Be "$testRoot\storage\data"
            $result.paths.templates | Should -Be "$testRoot\storage\data\templates"
            $result.paths.cache | Should -Be "$testRoot\storage\data\cache"
            $result.paths.profiles | Should -Be "$testRoot\storage\data\profiles"
            $result.paths.log | Should -Be "$testRoot\storage\logs"
            $result.paths.logError | Should -Be "$testRoot\storage\logs\error.log"
        }

        It "Sets env variables from .env file" {
            $result = Get-Config -rootPath $testRoot
            $result.env.PHP_CURRENT_VERSION_PATH | Should -Be 'C:\pvm\php'
            $result.env.PVM_ENV_VAR_NAME | Should -Be 'PVM'
            $result.env.CACHE_MAX_HOURS | Should -Be 168
            $result.env.DEFAULT_LOG_PAGE_SIZE | Should -Be 5
        }

        It "Sets default zend extensions" {
            $result = Get-Config -rootPath $testRoot
            $result.defaults.zendExtensions | Should -Be @('opcache', 'xdebug')
        }

        It "Sets default extensions list" {
            $result = Get-Config -rootPath $testRoot
            $result.defaults.extensions | Should -Contain 'curl'
            $result.defaults.extensions | Should -Contain 'mbstring'
            $result.defaults.extensions | Should -Contain 'opcache'
        }

        It "Sets aliases dictionary" {
            $result = Get-Config -rootPath $testRoot
            $result.defaults.aliases['?'] | Should -Be 'help'
            $result.defaults.aliases['i'] | Should -Be 'install'
            $result.defaults.aliases['ls'] | Should -Be 'list'
        }
    }
}
