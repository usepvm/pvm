
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\log-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    Mock Show-Error {}
    Mock Show-Warning {}
    Mock Show-Message {}
    Mock Show-Value {}
    Mock Show-Debug {}
    Mock Show-Info {}
    Mock Show-Header {}
    Mock Clear-Host {}
    Mock Write-DarkGray {}
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Format-NiceTimestamp" {
    It "returns 'just now' for current timestamp" {
        $now = Get-Date
        $result = Format-NiceTimestamp $now.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be 'just now'
    }

    It "returns '1 minute ago' for 1 minute old timestamp" {
        $ts = (Get-Date).AddMinutes(-1)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be '1 minute ago'
    }

    It "returns 'X minutes ago for more than 1 minute old timestamp" {
        $ts = (Get-Date).AddMinutes(-30)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be '30 minutes ago'
    }

    It "returns '1 hour ago for 1 hour old timestamp" {
        $ts = (Get-Date).AddHours(-1)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be '1 hour ago'
    }

    It "returns 'X hours ago for more than 1 hour old timestamp" {
        $ts = (Get-Date).AddHours(-5)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be '5 hours ago'
    }

    It "returns 'yesterday' for 1 day old timestamp" {
        $ts = (Get-Date).AddDays(-1)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be 'yesterday'
    }

    It "returns 'X days ago for more than 1 day old timestamp" {
        $ts = (Get-Date).AddDays(-5)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be '5 days ago'
    }

    It "returns '1 week ago' for 7 days old timestamp" {
        $ts = (Get-Date).AddDays(-7)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be '1 week ago'
    }

    It "returns '2 weeks ago' for 15 days old timestamp" {
        $ts = (Get-Date).AddDays(-15)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be '2 weeks ago'
    }

    It "returns '1 month ago' for ~35 days old timestamp" {
        $ts = (Get-Date).AddDays(-35)
        $result = Format-NiceTimestamp $ts.ToString('yyyy-MM-dd HH:mm:ss')

        $result.Relative | Should -Be '1 month ago'
    }

    It "handles invalid timestamp input gracefully" {
        $result = Format-NiceTimestamp 'not-a-date'

        $result.Date | Should -Be 'not-a-date'
        $result.Time | Should -Be ''
        $result.Relative | Should -Be ''
    }
}

Describe "Test-LogPageSize" {
    It "returns -1 for invalid page size (non-numeric)" {
        $result = Test-LogPageSize -pageSize 'abc'

        $result | Should -Be $false
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nInvalid page size: abc"
        }
    }

    It "returns -1 for invalid page size (zero)" {
        $result = Test-LogPageSize -pageSize 0

        $result | Should -Be $false
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nPage size must be a positive integer."
        }
    }

    It "returns -1 for invalid page size (negative number)" {
        $result = Test-LogPageSize -pageSize -5

        $result | Should -Be $false
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nPage size must be a positive integer."
        }
    }

    It "returns true for valid page size" {
        $result = Test-LogPageSize -pageSize 5

        $result | Should -Be $true
    }
}

Describe "Get-LogEntries" {
    BeforeAll {
        $script:LOG_ERROR_PATH = $PVMConfig.paths.files.logError
        New-Item -ItemType Directory -Path (Split-Path -Path $LOG_ERROR_PATH) -Force | Out-Null
    }

    It "returns empty array if no entries found" {
        '' | Set-ContentWrapper -path $LOG_ERROR_PATH

        $result = Get-LogEntries -path $LOG_ERROR_PATH

        $result.Count | Should -Be 0
    }

    It "returns array of log entries" {
        @"
$($PVMConfig.constants.LOG_SEPARATOR)
[2025-08-20 14:38:48] Test log entry 1 :
Message: Issue 1
Position: At D:\Code\Tools\pvm\file.ps1:10 char:9
+         throw "Issue limit"
+         ~~~~~~~~~~~~~~~~~~~~

$($PVMConfig.constants.LOG_SEPARATOR)
[2025-08-23 14:38:48] Test log entry 0 :
Message: Issue 0
Position: At D:\Code\Tools\pvm\file.ps1:10 char:9
+         throw "Issue limit"
+         ~~~~~~~~~~~~~~~~~~~~
"@ | Set-ContentWrapper -path $LOG_ERROR_PATH

        $result = Get-LogEntries -path $LOG_ERROR_PATH

        $result.Length | Should -Be 2
        $result[0].Timestamp | Should -Be '2025-08-23 14:38:48'
        $result[0].Header | Should -Be 'Test log entry 0 :'
        $result[1].Timestamp | Should -Be '2025-08-20 14:38:48'
        $result[1].Header | Should -Be 'Test log entry 1 :'
    }

    It "filters log entries based on search term" {
        @"
$($PVMConfig.constants.LOG_SEPARATOR)
[2025-08-23 14:38:48] Test log entry 1 :
Message: Issue 1
Position: At D:\Code\Tools\pvm\file.ps1:10 char:9
+         throw "Issue limit"
+         ~~~~~~~~~~~~~~~~~~~~

$($PVMConfig.constants.LOG_SEPARATOR)
[2025-08-23 14:38:48] Test log entry 0 :
Message: Issue 0
Position: At D:\Code\Tools\pvm\file.ps1:10 char:9
+         throw "Issue limit"
+         ~~~~~~~~~~~~~~~~~~~~
"@ | Set-ContentWrapper -path $LOG_ERROR_PATH

        $result = @(Get-LogEntries -path $LOG_ERROR_PATH -term 'entry 1')

        $result.Length | Should -Be 1
        $result[0].Timestamp | Should -Be '2025-08-23 14:38:48'
        $result[0].Header | Should -Be 'Test log entry 1 :'
    }
}

Describe "Write-LogEntry" {
    It "writes 1 log entry to console" {
        $header = 'Test log entry 1 :'
        $errorMessage = 'Issue 1'
        $position = 'At D:\Code\Tools\pvm\file.ps1:10 char:9'
        $message = $header + "`nMessage : $errorMessage" + "`nPosition : $position" + '+         throw "Issue $limit"' + '+         ~~~~~~~~~~~~~~~~~~~~'
        $entry = @{
            NiceTime = @{ Date = '23 August'; DateTime = '8/23/2025 14:38:48'; Time = '14:38:48'; Relative = '1 day ago' }
            Timestamp = '2025-08-23 14:38:48'
            Header = $header
            Message = $message
            Position = $position
            ErrorMessage = $errorMessage
        }

        { Write-LogEntry -entry $entry } | Should -Not -Throw
    }
}

Describe "Write-LogPage" {
    It "writes all log entries to console" {
        Mock Write-LogEntry {}
        $header1 = 'Test log entry 1 :'; $errorMessage1 = 'Issue 1'; $position1 = 'At D:\Code\Tools\pvm\file.ps1:10 char:9'
        $message1 = $header + "`nMessage : $errorMessage" + "`nPosition : $position" + '+         throw "Issue $limit"' + '+         ~~~~~~~~~~~~~~~~~~~~'
        $header2 = 'Test log entry 2 :'; $errorMessage2 = 'Issue 2'; $position2 = 'At D:\Code\Tools\pvm\file.ps1:12 char:5'
        $message2 = $header + "`nMessage : $errorMessage" + "`nPosition : $position" + '+         throw "Issue $limit"' + '+         ~~~~~~~~~~~~~~~~~~~~'
        $entries = @(
            @{
                NiceTime = @{ Date = '23 August'; DateTime = '8/23/2025 14:38:48'; Time = '14:38:48'; Relative = '3 days ago' }
                Timestamp = '2025-08-23 14:38:48'
                Header = $header1
                Message = $message1
                Position = $position1
                ErrorMessage = $errorMessage1
            };
            @{
                NiceTime = @{ Date = '25 August'; DateTime = '8/25/2025 11:38:48'; Time = '11:38:48'; Relative = '1 day ago' }
                Timestamp = '2025-08-25 11:38:48'
                Header = $header2
                Message = $message2
                Position = $position2
                ErrorMessage = $errorMessage2
            }
        )

        { Write-LogPage -entries $entries -startIndex 0 -pageSize 5 } | Should -Not -Throw
        Should -Invoke Clear-Host -Times 1
        Should -Invoke Show-Info -Times 1
        Should -Invoke Show-Header -Times 1
        Should -Invoke Write-DarkGray -Times 1
        Should -Invoke Write-LogEntry -Times 2
    }
}

Describe "Get-LogNavigation" {
    It "returns null if currentIndex is out of range" {
        Mock Get-ConsoleKey { @{ Key = 'Q' } }

        $result = Get-LogNavigation -currentIndex 99 -pageSize 3 -totalEntries 100

        $result | Should -Be $null
        Should -Invoke Get-ConsoleKey -Times 1
        Should -Invoke Show-Warning -Times 1
    }

    It "go back one page from the end" {
        Mock Get-ConsoleKey { @{ Key = 'LeftArrow' } }

        $currentIndex = 99; $pageSize = 3
        $result = Get-LogNavigation -currentIndex $currentIndex -pageSize $pageSize -totalEntries 100

        $result | Should -Be ($currentIndex - $pageSize)
        Should -Invoke Get-ConsoleKey -Times 1
        Should -Invoke Show-Warning -Times 1
    }

    It "prevents navigation beyond the start of the log" {
        Mock Get-ConsoleKey { @{ Key = 'LeftArrow' } }

        $currentIndex = 0; $pageSize = 5
        $result = Get-LogNavigation -currentIndex $currentIndex -pageSize $pageSize -totalEntries 100

        $result | Should -Be 0
        Should -Invoke Show-Warning -Times 1
    }

    It "go forward one page" {
        Mock Get-ConsoleKey { @{ Key = 'RightArrow' } }

        $currentIndex = 0; $pageSize = 5
        $result = Get-LogNavigation -currentIndex $currentIndex -pageSize $pageSize -totalEntries 100

        $result | Should -Be ($currentIndex + $pageSize)
        Should -Invoke Show-Warning -Times 1
    }

    It "returns null when user presses Q" {
        Mock Get-ConsoleKey { @{ Key = 'Q' } }

        $currentIndex = 0; $pageSize = 5
        $result = Get-LogNavigation -currentIndex $currentIndex -pageSize $pageSize -totalEntries 100

        $result | Should -Be $null
        Should -Invoke Show-Warning -Times 1
    }

    It "returns currentIndex when user presses any other key" {
        Mock Get-ConsoleKey { @{ Key = 'A' } }

        $currentIndex = 0; $pageSize = 5
        $result = Get-LogNavigation -currentIndex $currentIndex -pageSize $pageSize -totalEntries 100

        $result | Should -Be $currentIndex
        Should -Invoke Show-Warning -Times 1
    }
}

Describe "Show-Log" {
    BeforeAll {
        $script:LOG_ERROR_PATH = $PVMConfig.paths.files.logError
        New-Item -ItemType Directory -Path (Split-Path -Path $LOG_ERROR_PATH) -Force | Out-Null
    }

    It "returns -1 for invalid page size" {
        Mock Test-LogPageSize { return $false }

        $result = Show-Log -pageSize -1

        $result | Should -Be -1
    }

    It "returns -1 if log file does not exist" {
        Mock Test-LogPageSize { return $true }
        Mock Test-FileNotExists { return $true }

        $result = Show-Log -pageSize 1

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1
    }

    It "returns -1 if log file is empty" {
        Mock Test-FileNotExists { return $false }
        Mock Get-LogEntries { return @() }

        $result = Show-Log -pageSize 5

        $result | Should -Be -1
        Should -Invoke Show-Warning -Times 1
    }

    It "displays log entries" {
        Mock Test-FileNotExists { return $false }
        $header1 = 'Test log entry 1 :'; $errorMessage1 = 'Issue 1'; $position1 = 'At D:\Code\Tools\pvm\file.ps1:10 char:9'
        $message1 = $header + "`nMessage : $errorMessage" + "`nPosition : $position" + '+         throw "Issue $limit"' + '+         ~~~~~~~~~~~~~~~~~~~~'
        $header2 = 'Test log entry 2 :'; $errorMessage2 = 'Issue 2'; $position2 = 'At D:\Code\Tools\pvm\file.ps1:12 char:5'
        $message2 = $header + "`nMessage : $errorMessage" + "`nPosition : $position" + '+         throw "Issue $limit"' + '+         ~~~~~~~~~~~~~~~~~~~~'
        $entries = @(
            @{
                NiceTime = @{ Date = '23 August'; DateTime = '8/23/2025 14:38:48'; Time = '14:38:48'; Relative = '3 days ago' }
                Timestamp = '2025-08-23 14:38:48'
                Header = $header1
                Message = $message1
                Position = $position1
                ErrorMessage = $errorMessage1
            };
            @{
                NiceTime = @{ Date = '25 August'; DateTime = '8/25/2025 11:38:48'; Time = '11:38:48'; Relative = '1 day ago' }
                Timestamp = '2025-08-25 11:38:48'
                Header = $header2
                Message = $message2
                Position = $position2
                ErrorMessage = $errorMessage2
            }
        )
        Mock Get-LogEntries { return $entries }
        Mock Write-LogPage { }
        $script:callCount = 0
        Mock Get-LogNavigation {
            $script:callCount++
            if ($script:callCount -eq 1) { return 1 }
            return $null
        }

        $result = Show-Log -pageSize 1

        $result | Should -Be 0
        Should -Invoke Write-LogPage -Times 2
        Should -Invoke Get-LogNavigation -Times 2
        Should -Invoke Clear-Host -Times 1
    }

    It "Handles unexpected error reading log file and returns -1" {
        Mock Add-LogEntry { }
        Mock Test-FileNotExists { return $false }
        Mock Get-LogEntries { throw 'Error' }

        $result = Show-Log -pageSize 1

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1
        Should -Invoke Add-LogEntry -Times 1
    }
}
