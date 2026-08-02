
BeforeAll {
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\output-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Show-MsgByExitCode" {
    BeforeAll {
        Mock Write-Color {}
    }
    Context "When displaying messages" {
        It "Displays message without error" {
            $testResult = @{
                message = 'Test message'
                color = 'Gray'
            }
            { Show-MsgByExitCode -result $testResult } | Should -Not -Throw
        }

        It "Displays custom message if provided" {
            $testResult = @{
                message = 'Original message'
            }
            $customMessage = 'Custom message'
            { Show-MsgByExitCode -result $testResult -message $customMessage } | Should -Not -Throw
        }

        It "Displays list of messages if provided" {
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
            Mock Write-Color { throw 'Simulated Write-Host failure' }
            $testResult = @{
                message = 'Test message'
                color = 'Gray'
            }
            { Show-MsgByExitCode -result $testResult } | Should -Not -Throw
        }
    }
}

Describe "Add-LogEntry" {
    BeforeAll {
        Mock Show-Message {}
    }
    Context "When logging data" {
        It "Logs data successfully" {
            $script:LOG_ERROR_PATH = $PVMConfig.paths.logError
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

Describe "Show-SpinnerWhileJob" {
    BeforeAll {
        Mock Write-Color {}
        Mock Write-Yellow {}

        $PVMRoot = $PVMConfig.paths.pvmRoot
        New-Item -Path "$PVMRoot\src" -ItemType Directory -Force | Out-Null
        Set-Content -Path "$PVMRoot\src\imports.ps1" -Value '# no-op for tests'

        $RealStartJob = Get-Command Start-Job -CommandType Cmdlet
        $script:keepRunning = $true
        Mock Start-Job {
            param ($scriptBlock, $initializationScript, $argumentList)

            if ($initializationScript) {
                $null = & $initializationScript
            }

            $script:job = & $RealStartJob -ScriptBlock { $scriptBlock }
            $script:job | Wait-Job | Out-Null   # let it actually finish first

            if ($script:keepRunning) {
                $script:setState = $script:job.GetType().GetMethod(
                    'SetJobState',
                    [System.Reflection.BindingFlags]'NonPublic, Instance',
                    $null,
                    [Type[]]@([System.Management.Automation.JobState]),
                    $null
                )
                $null = $script:setState.Invoke($script:job, @([System.Management.Automation.JobState]::Running))
            }

            return $script:job
        }
    }
    Context "When executing job with spinner" {
        It "Executes script block and returns result" {
            Mock Start-Sleep { $null = $script:setState.Invoke($script:job, @([System.Management.Automation.JobState]::Completed)) }
            Mock Receive-Job {
                return @{ pvmData = @{ result = 'success' } }
            }

            $scriptBlock = { return @{ result = 'success' } }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -message @{ content = "Processing"; color = 'Cyan' }

            $result | Should -Not -Be -1
        }

        It "Uses custom message for spinner" {
            Mock Start-Sleep { $null = $script:setState.Invoke($script:job, @([System.Management.Automation.JobState]::Completed)) }
            Mock Receive-Job {
                return @{ pvmData = @{ result = 'success' } }
            }

            $scriptBlock = { return @{ result = 'success' } }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -message @{ content = "Custom Message"; color = 'Cyan' }

            # Verify Show-Message was called (spinner and clear)
            Should -Invoke Write-Color -Times 2
        }

        It "Passes argument list to job" {
            $script:keepRunning = $false
            Mock Receive-Job {
                return @{ result = 'success' }
            }

            $scriptBlock = { param ($a, $b) return @{ result = "$a$b" } }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -argumentList @('arg1', 'arg2')

            Should -Invoke Start-Job
        }

        It "Does not clear spinner line when noClear is set" {
            $script:keepRunning = $true
            Mock Start-Sleep { $null = $script:setState.Invoke($script:job, @([System.Management.Automation.JobState]::Completed)) }
            Mock Receive-Job {
                return @{ pvmData = @{ result = 'success' } }
            }

            $scriptBlock = { return @{ result = 'success' } }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -message @{ content = "Processing"; color = 'Cyan' } -noClear

            # Verify that the clear line (spaces) is not called when noClear is set
            # The clear happens at line 114 in the source
            Should -Invoke Write-Color -Times 1
        }

        It "Clears spinner line by default" {
            $script:keepRunning = $true
            Mock Start-Sleep { $null = $script:setState.Invoke($script:job, @([System.Management.Automation.JobState]::Completed)) }
            Mock Receive-Job {
                return @{ pvmData = @{ result = 'success' } }
            }

            $scriptBlock = { return @{ result = 'success' } }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -message @{ content = "Processing"; color = 'Cyan' }

            # Should be called twice: once for spinner, once for clear
            Should -Invoke Write-Color -Times 2
        }

        It "Returns -1 when job fails and rethrow is false" {
            $script:keepRunning = $false
            Mock Receive-Job {
                throw "Job failed"
            }

            Mock Add-LogEntry {}

            $scriptBlock = { throw "Job failed" }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -rethrow:$false

            $result | Should -Be -1
        }

        It "Rethrows exception when job fails and rethrow is true" {
            $script:keepRunning = $false
            Mock Receive-Job {
                throw "Job failed"
            }

            Mock Add-LogEntry {}

            $scriptBlock = { throw "Job failed" }

            { Show-SpinnerWhileJob -scriptBlock $scriptBlock -rethrow:$true } | Should -Throw
        }

        It "Logs error when job fails" {
            $script:keepRunning = $false
            Mock Receive-Job {
                throw "Job failed"
            }

            Mock Add-LogEntry {}

            $scriptBlock = { throw "Job failed" }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -rethrow:$false

            Should -Invoke Add-LogEntry -Exactly 1
        }

        It "Cleans up environment variable after job completion" {
            $script:keepRunning = $false
            Mock Receive-Job {
                return @{ pvmData = @{ result = 'success' } }
            }

            Mock Remove-Item {}

            $scriptBlock = { return @{ result = 'success' } }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock

            Should -Invoke Remove-Item -ParameterFilter {
                $Path -eq 'Env:\PVM_ROOT_FOR_JOB'
            }
        }

        It "Cleans up environment variable after job failure" {
            $script:keepRunning = $false
            Mock Receive-Job {
                throw "Job failed"
            }

            Mock Add-LogEntry {}
            Mock Remove-Item {}

            $scriptBlock = { throw "Job failed" }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -rethrow:$false

            Should -Invoke Remove-Item -ParameterFilter {
                $Path -eq 'Env:\PVM_ROOT_FOR_JOB'
            }
        }

        It "Removes job properties from result" {
            $script:keepRunning = $false
            Mock Receive-Job {
                # Return an object with the actual job properties that need filtering
                $result = [PSCustomObject]@{
                    pvmData = @{ result = 'success' }
                    result = 'success'
                    RunspaceId = 'some-id'
                    PSComputerName = 'computer'
                    PSShowComputerName = $true
                    PSSourceJobInstanceId = 'job-id'
                }
                return $result
            }

            $scriptBlock = { return @{ result = 'success' } }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock

            $result.RunspaceId | Should -BeNullOrEmpty
            $result.PSComputerName | Should -BeNullOrEmpty
            $result.PSShowComputerName | Should -BeNullOrEmpty
            $result.PSSourceJobInstanceId | Should -BeNullOrEmpty
        }

        It "Calls Start-Sleep during spinner loop" {
            $script:keepRunning = $true
            Mock Start-Sleep { $null = $script:setState.Invoke($script:job, @([System.Management.Automation.JobState]::Completed)) }
            Mock Receive-Job {
                return @{ pvmData = @{ result = 'success' } }
            }

            # Use a real job that takes time to complete to trigger spinner loop
            $scriptBlock = {
                Start-Sleep -Milliseconds 200
                return @{ result = 'success' }
            }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock -message @{ content = "Processing"; color = 'Cyan' }

            # Start-Sleep should be called during spinner loop
            Should -Invoke Start-Sleep
        }

        It "Passes initialization script to Start-Job" {
            $script:keepRunning = $false
            Mock Receive-Job {
                return @{ pvmData = @{ result = 'success' } }
            }

            $scriptBlock = { return @{ result = 'success' } }
            $result = Show-SpinnerWhileJob -scriptBlock $scriptBlock

            # Verify Start-Job was called with initializationScript parameter
            Should -Invoke Start-Job -ParameterFilter {
                $null -ne $initializationScript
            }
        }
    }
}

Describe "Show-SpinnerWhileProcess" {
    BeforeAll {
        Mock Write-Color {}
    }

    Context "When process succeeds" {
        It "Returns exit code 0 and captured stdout" {
            $result = Show-SpinnerWhileProcess -fileName 'cmd.exe' -processArgs @('/c', 'echo hello')

            $result.code | Should -Be 0
            $result.output | Should -Match 'hello'
        }
    }

    Context "When process exits with non-zero code" {
        It "Returns the process exit code" {
            $result = Show-SpinnerWhileProcess -fileName 'cmd.exe' -processArgs @('/c', 'exit 5')

            $result.code | Should -Be 5
        }
    }

    Context "When process writes to stderr" {
        It "Captures stderr in combined output" {
            $result = Show-SpinnerWhileProcess -fileName 'cmd.exe' -processArgs @('/c', 'echo err-message 1>&2')

            $result.output | Should -Match 'err-message'
        }
    }

    Context "When processArgs is not provided" {
        It "Runs without arguments" {
            $result = Show-SpinnerWhileProcess -fileName 'hostname.exe'

            $result.code | Should -Be 0
        }
    }

    Context "When displaying the spinner" {
        It "Uses the provided message" {
            Show-SpinnerWhileProcess -fileName 'cmd.exe' -processArgs @('/c', 'echo hi') -message @{ content = 'Custom'; color = 'Cyan' }

            # Verify Show-Message was called (spinner and clear)
            Should -Invoke Write-Color -Times 2
        }

        It "Defaults to 'Please wait...' when no message is provided" {
            Show-SpinnerWhileProcess -fileName 'cmd.exe' -processArgs @('/c', 'echo hi')

            Should -Invoke Write-Color -ParameterFilter { $message -match 'Please wait...' }
        }

        It "Clears the spinner line after completion" {
            Show-SpinnerWhileProcess -fileName 'cmd.exe' -processArgs @('/c', 'echo hi') -message @{ content = 'Clearing'; color = 'Cyan' }

            Should -Invoke Write-Color -ParameterFilter { $message -eq "`r$(' ' * ('Clearing'.Length + 2))`r" }
        }
    }

    Context "When clearing the spinner" {
        It "Does not clear the spinner line when noClear is set" {
            $result = Show-SpinnerWhileProcess -fileName 'cmd.exe' -processArgs @('/c', 'echo hi') -noClear

            # Verify that the clear line (spaces) is not called when noClear is set
            # The clear happens at line 114 in the source
            Should -Invoke Write-Color -Times 1
        }
    }

    Context "When the process fails to start" {
        BeforeAll {
            Mock Add-LogEntry {}
        }

        It "Returns -1 with null output" {
            $result = Show-SpinnerWhileProcess -fileName 'nonexistent-exe-xyz-12345.exe' -processArgs @()

            $result.code | Should -Be -1
            $result.output | Should -Be $null
        }

        It "Logs the error" {
            Show-SpinnerWhileProcess -fileName 'nonexistent-exe-xyz-12345.exe' -processArgs @()

            Should -Invoke Add-LogEntry -Times 1 -ParameterFilter {
                $data.header -match 'Show-SpinnerWhileProcess - Failed to run subprocess'
            }
        }
    }
}

Describe "Write-Host helpers Tests" {
    BeforeEach {
        $script:currentPVMSubprocess = @{ enabled = $Global:PVMSubprocess.enabled; structuredOutput = $Global:PVMSubprocess.structuredOutput }
    }

    AfterEach {
        $Global:PVMSubprocess = $script:currentPVMSubprocess
    }

    Context "Write-Color Tests" {
        It "Prints message with specified color" {
            $Global:PVMSubprocess.enabled = $false
            Mock Write-Host-Wrapper {}

            Write-Color -message 'Test message' -foreColor 'Red'

            Should -Invoke Write-Host-Wrapper -ParameterFilter {
                $object -match 'Test message' -and
                $foregroundColor -eq 'Red' -and
                $noNewLine -eq $false
            } -Exactly 1
        }

        It "Stores structured output when subprocess mode is enabled" {
            $Global:PVMSubprocess.structuredOutput = @()
            $Global:PVMSubprocess.enabled = $true
            Mock Write-Host-Wrapper {}

            Write-Color -message 'Test message' -foreColor 'Red'

            Should -Invoke Write-Host-Wrapper -Exactly 0
            $Global:PVMSubprocess.structuredOutput.Count | Should -Be 1
            $Global:PVMSubprocess.structuredOutput[0].message | Should -Be 'Test message'
            $Global:PVMSubprocess.structuredOutput[0].color | Should -Be 'Red'
            $Global:PVMSubprocess.structuredOutput[0].noNewLine | Should -Be $false
        }
    }

    Context "Write-Color wrappers Tests" {
        BeforeEach {
            Mock Write-Color {}
        }

        It "Prints white message" {
            Write-White -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'White'
            }
        }

        It "Prints dark green message" {
            Write-DarkGreen -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'DarkGreen'
            }
        }

        It "Prints dark green message" {
            Write-DarkGreen -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'DarkGreen'
            }
        }

        It "Prints dark yellow message" {
            Write-DarkYellow -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'DarkYellow'
            }
        }

        It "Prints yellow message" {
            Write-Yellow -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'Yellow'
            }
        }

        It "Prints cyan message" {
            Write-Cyan -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'Cyan'
            }
        }

        It "Prints magenta message" {
            Write-Magenta -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'Magenta'
            }
        }

        It "Prints blue message" {
            Write-Blue -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'Blue'
            }
        }

        It "Prints dark gray message" {
            Write-DarkGray -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'DarkGray'
            }
        }

        It "Prints gray message" {
            Write-Gray -message 'Test message'

            Should -Invoke Write-Color -ParameterFilter {
                $message -match 'Test message' -and $foreColor -eq 'Gray'
            }
        }
    }

    Context "Show-* Tests" {
        It "Prints success message" {
            Mock Write-DarkGreen {}

            Show-Success -message 'Test message'

            Should -Invoke Write-DarkGreen -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints error message" {
            Mock Write-DarkYellow {}

            Show-Error -message 'Test message'

            Should -Invoke Write-DarkYellow -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints warning message" {
            Mock Write-Yellow {}

            Show-Warning -message 'Test message'

            Should -Invoke Write-Yellow -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints info message" {
            Mock Write-Cyan {}

            Show-Info -message 'Test message'

            Should -Invoke Write-Cyan -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints header message" {
            Mock Write-Magenta {}

            Show-Header -message 'Test message'

            Should -Invoke Write-Magenta -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints section message" {
            Mock Write-Blue {}

            Show-Section -message 'Test message'

            Should -Invoke Write-Blue -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints debug message" {
            Mock Write-DarkGray {}

            Show-Debug -message 'Test message'

            Should -Invoke Write-DarkGray -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints verbose message" {
            Mock Write-Gray {}

            Show-Verbose -message 'Test message'

            Should -Invoke Write-Gray -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints value message" {
            Mock Write-White {}

            Show-Value -message 'Test message'

            Should -Invoke Write-White -ParameterFilter {
                $message -match 'Test message'
            }
        }

        It "Prints host message" {
            Mock Write-White {}

            Show-Message -message 'Test message'

            Should -Invoke Write-White -ParameterFilter {
                $message -match 'Test message'
            }
        }
    }

    Context "New-Line* Test" {
        It "Prints new lines" {
            Mock Write-Host-Wrapper {}

            New-Lines -count 5

            Should -Invoke Write-Host-Wrapper -Exactly 1 -ParameterFilter {
                $object -eq ("`n" * 5) -and $noNewLine
            }
        }
        It "Prints new line" {
            Mock New-Lines {}

            New-Line

            Should -Invoke New-Lines -ParameterFilter {
                $count -eq 1
            }
        }
    }
}

Describe "Sound Functions" {
    BeforeAll {
        $Global:PVMConfig.paths.assets = "C:\pvm\assets"
    }

    BeforeEach {
        $script:currentPVMSubprocess = @{ mode = $Global:PVMSubprocess.enabled; structuredOutput = $Global:PVMSubprocess.structuredOutput }
    }

    AfterEach {
        $Global:PVMSubprocess = $script:currentPVMSubprocess
    }

    Context "New-Player" {
        It "loads PresentationCore and returns a MediaPlayer instance" {
            Mock Add-Type {}
            Mock New-Object { @{ PSTypeName = 'FakeMediaPlayer' } }

            $result = New-Player

            Should -Invoke Add-Type -Times 1 -Exactly
            Should -Invoke New-Object -Times 1 -Exactly
            $result.PSTypeName | Should -Be 'FakeMediaPlayer'
        }
    }

    Context "Get-Sound-TotalSeconds" {
        BeforeEach {
            $script:fakeShellFile = [PSCustomObject]@{}
            $script:fakeShellFolder = [PSCustomObject]@{}
            $script:fakeShell = [PSCustomObject]@{}

            $script:fakeShellFolder | Add-Member -MemberType ScriptMethod -Name ParseName -Value { param($f) $script:fakeShellFile }
            $script:fakeShell | Add-Member -MemberType ScriptMethod -Name Namespace -Value { param($f) $script:fakeShellFolder }

            Mock New-Object { $script:fakeShell } -ParameterFilter { $ComObject -eq 'Shell.Application' }
        }

        It "returns TotalSeconds when duration is greater than 1 second" {
            $script:fakeShellFolder | Add-Member -MemberType ScriptMethod -Name GetDetailsOf -Value { param($f, $i) "0:00:05" } -Force

            $result = Get-Sound-TotalSeconds -path "C:\music\song.mp3"

            $result | Should -Be 5
        }

        It "returns 1 when duration is 1 second or less" {
            $script:fakeShellFolder | Add-Member -MemberType ScriptMethod -Name GetDetailsOf -Value { param($f, $i) "0:00:00" } -Force

            $result = Get-Sound-TotalSeconds -path "C:\music\song.mp3"

            $result | Should -Be 1
        }
    }

    Context "Invoke-Sound" {
        BeforeEach {
            $script:playerCalls = @{ Open = $null; Play = $false }
            $script:fakePlayer = [PSCustomObject]@{}
            $script:fakePlayer | Add-Member -MemberType ScriptMethod -Name Open -Value { param($p) $script:playerCalls.Open = $p }
            $script:fakePlayer | Add-Member -MemberType ScriptMethod -Name Play -Value { $script:playerCalls.Play = $true }

            Mock New-Player { $script:fakePlayer }
            Mock Get-Sound-TotalSeconds { 3 }
            Mock Start-Sleep {}
            Mock Add-LogEntry {}
        }

        It "opens the file, plays it, and sleeps for its duration" {
            $Global:PVMSubprocess.enabled = $false
            $PVMConfig.env.SOUNDS_DISABLED = $false

            Invoke-Sound -path "C:\music\song.mp3"

            $script:playerCalls.Open | Should -Be "C:\music\song.mp3"
            $script:playerCalls.Play | Should -BeTrue
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 3 }
        }

        It "logs and does not throw when playback fails" {
            $Global:PVMSubprocess.enabled = $false
            $PVMConfig.env.SOUNDS_DISABLED = $false

            Mock New-Player { throw "boom" }

            { Invoke-Sound -path "C:\music\song.mp3" } | Should -Not -Throw
            Should -Invoke Add-LogEntry -Times 1 -Exactly
        }

        It "does not play sound in subprocess mode" {
            Mock New-Player {}
            $Global:PVMSubprocess.enabled = $true

            Invoke-Sound -path "C:\music\song.mp3"

            Should -Invoke New-Player -Times 0
        }

        It "does not play sound when sounds are disabled" {
            Mock New-Player {}
            $Global:PVMSubprocess.enabled = $false
            $PVMConfig.env.SOUNDS_DISABLED = $true

            Invoke-Sound -path "C:\music\song.mp3"

            Should -Invoke New-Player -Times 0
        }
    }

    Context "Invoke-<Type>Sound wrappers" {
        BeforeEach {
            Mock Invoke-Sound {}
        }

        It "Invoke-SuccessSound plays success.mp3 from assets path" {
            Invoke-SuccessSound
            Should -Invoke Invoke-Sound -Times 1 -Exactly -ParameterFilter {
                $path -eq "$($PVMConfig.paths.assets)\sounds\success.mp3"
            }
        }

        It "Invoke-ErrorSound plays error.mp3 from assets path" {
            Invoke-ErrorSound
            Should -Invoke Invoke-Sound -Times 1 -Exactly -ParameterFilter {
                $path -eq "$($PVMConfig.paths.assets)\sounds\error.mp3"
            }
        }

        It "Invoke-PromptSound plays prompt.mp3 from assets path" {
            Invoke-PromptSound
            Should -Invoke Invoke-Sound -Times 1 -Exactly -ParameterFilter {
                $path -eq "$($PVMConfig.paths.assets)\sounds\prompt.mp3"
            }
        }
    }
}
