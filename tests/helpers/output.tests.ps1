
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\output-drive"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Show-MsgByExitCode" {
    Context "When displaying messages" {
        It "Displays message without error" {
            Mock Write-Host {}
            $testResult = @{
                message = 'Test message'
                color = 'Gray'
            }
            { Show-MsgByExitCode -result $testResult } | Should -Not -Throw
        }

        It "Displays custom message if provided" {
            Mock Write-Host {}
            $testResult = @{
                message = 'Original message'
            }
            $customMessage = 'Custom message'
            { Show-MsgByExitCode -result $testResult -message $customMessage } | Should -Not -Throw
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
            { Show-MsgByExitCode -result $testResults } | Should -Not -Throw
        }

        It "Handles exceptions gracefully" {
            Mock Write-Host { throw 'Simulated Write-Host failure' }
            $testResult = @{
                message = 'Test message'
                color = 'Gray'
            }
            { Show-MsgByExitCode -result $testResult } | Should -Not -Throw
        }
    }
}

Describe "Add-LogEntry" {
    Context "When logging data" {
        It "Logs data successfully" {
            $script:LOG_ERROR_PATH = $PVMConfig.paths.logError = "$TEST_DRIVE\logs\test.log"
            $result = Add-LogEntry -data @{
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
            Mock New-Directory { throw 'Failed to create directory' }
            # Try to log to a protected location
            $result = Add-LogEntry -data @{
                header = 'Test message'
                exception = 'Test data'
            }
            $result | Should -Be -1
        }

        It "Accepts custom log path" {
            $customLogPath = "$TEST_DRIVE\logs\custom.log"
            $result = Add-LogEntry -data @{
                header = 'Test message'
                logPath = $customLogPath
            }
            $result | Should -Be 0
            Test-Path $customLogPath | Should -Be $true
        }

        It "Returns -1 when unable to create log file" {
            Mock New-Directory { return -1 }
            # Try to log to a protected location
            $result = Add-LogEntry -data @{
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

Describe "Get-ConsoleWidth" {
    It "Returns the console width as an integer" {
        $result = Get-ConsoleWidth
        $result | Should -BeOfType [int]
        $result | Should -BeGreaterThan 0
    }
}

Describe "Show-* helpers Tests" {
    It "Prints message with specified color" {
        Write-Color -message 'Test message' -foreColor 'Red'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Red'
        } -Exactly 1
    }

    It "Prints success message" {
        Show-Success -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'DarkGreen'
        }
    }

    It "Prints error message" {
        Show-Error -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'DarkYellow'
        }
    }

    It "Prints warning message" {
        Show-Warning -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Yellow'
        }
    }

    It "Prints info message" {
        Show-Info -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Cyan'
        }
    }

    It "Prints header message" {
        Show-Header -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Magenta'
        }
    }

    It "Prints section message" {
        Show-Section -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Blue'
        }
    }

    It "Prints debug message" {
        Show-Debug -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'DarkGray'
        }
    }

    It "Prints verbose message" {
        Show-Verbose -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Gray'
        }
    }

    It "Prints value message" {
        Show-Value -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'White'
        }
    }

    It "Prints host message" {
        Show-Message -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'White'
        }
    }

    It "Prints white message" {
        Write-White -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'White'
        }
    }

    It "Prints dark green message" {
        Write-DarkGreen -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'DarkGreen'
        }
    }

    It "Prints dark green message" {
        Write-DarkGreen -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'DarkGreen'
        }
    }

    It "Prints dark yellow message" {
        Write-DarkYellow -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'DarkYellow'
        }
    }

    It "Prints yellow message" {
        Write-Yellow -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Yellow'
        }
    }

    It "Prints cyan message" {
        Write-Cyan -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Cyan'
        }
    }

    It "Prints magenta message" {
        Write-Magenta -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Magenta'
        }
    }

    It "Prints blue message" {
        Write-Blue -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Blue'
        }
    }

    It "Prints dark gray message" {
        Write-DarkGray -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'DarkGray'
        }
    }

    It "Prints gray message" {
        Write-Gray -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'Gray'
        }
    }

    It "Prints default message" {
        Write-Default -message 'Test message'

        Should -Invoke Write-Host -ParameterFilter {
            $Object -match 'Test message' -and $ForegroundColor -eq 'White'
        }
    }

    It "Prints new line" {
        New-Line

        Should -Invoke Write-Host -ParameterFilter {
            $Object -eq "`n" -and $NoNewline
        }
    }

    It "Prints new lines" {
        New-Lines -count 5

        Should -Invoke Write-Host -Exactly 5
    }
}
