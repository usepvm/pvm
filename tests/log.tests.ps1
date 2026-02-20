
Describe "Format-NiceTimestamp" {
    It "returns 'just now' for current timestamp" {
        $now = Get-Date
        $result = Format-NiceTimestamp $now.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "just now"
    }

    It "returns '1 minute ago' for 1 minute old timestamp" {
        $ts = (Get-Date).AddMinutes(-1)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "1 minute ago"
    }

    It "returns 'X minutes ago for more than 1 minute old timestamp" {
        $ts = (Get-Date).AddMinutes(-30)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "30 minutes ago"
    }

    It "returns '1 hour ago for 1 hour old timestamp" {
        $ts = (Get-Date).AddHours(-1)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "1 hour ago"
    }

    It "returns 'X hours ago for more than 1 hour old timestamp" {
        $ts = (Get-Date).AddHours(-5)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "5 hours ago"
    }
    
    It "returns 'yesterday' for 1 day old timestamp" {
        $ts = (Get-Date).AddDays(-1)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "yesterday"
    }

    It "returns 'X days ago for more than 1 day old timestamp" {
        $ts = (Get-Date).AddDays(-5)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "5 days ago"
    }

    It "returns '1 week ago' for 7 days old timestamp" {
        $ts = (Get-Date).AddDays(-7)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "1 week ago"
    }

    It "returns '2 weeks ago' for 15 days old timestamp" {
        $ts = (Get-Date).AddDays(-15)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "2 weeks ago"
    }

    It "returns '1 month ago' for ~35 days old timestamp" {
        $ts = (Get-Date).AddDays(-35)
        $result = Format-NiceTimestamp $ts.ToString("yyyy-MM-dd HH:mm:ss")
        
        $result.Relative | Should -Be "1 month ago"
    }

    It "handles invalid timestamp input gracefully" {
        $result = Format-NiceTimestamp "not-a-date"
        
        $result.Date | Should -Be "not-a-date"
        $result.Time | Should -Be ""
        $result.Relative | Should -Be ""
    }
}

Describe "Show-Log" {
    BeforeAll {
        $global:DEFAULT_LOG_PAGE_SIZE = 3
        $global:LOG_ERROR_PATH = "TestDrive:\logs\error.log"
        New-Item -ItemType Directory -Path (Split-Path $LOG_ERROR_PATH) -Force | Out-Null
        Mock Write-Host {}
        
        @'
--------------------------
[2025-08-23 14:38:48] Test log entry 1 :
Message: Issue 1
Position: At D:\Code\Tools\pvm\file.ps1:10 char:9
+         throw "Issue $limit"
+         ~~~~~~~~~~~~~~~~~~~~

--------------------------
[2025-08-23 14:38:48] Test log entry 0 :
Message: Issue 0
Position: At D:\Code\Tools\pvm\file.ps1:10 char:9
+         throw "Issue $limit"
+         ~~~~~~~~~~~~~~~~~~~~
'@ | Set-Content $LOG_ERROR_PATH
    }

    It "returns -1 for invalid page size (non-numeric)" {
        $result = Show-Log -pageSize "abc"
        
        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nInvalid page size: abc" 
        } 
    }

    It "returns -1 for invalid page size (zero)" {
        $result = Show-Log -pageSize 0
        
        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPage size must be a positive integer." 
        } 
    }
    
    It "returns -1 for invalid page size (negative number)" {
        $result = Show-Log -pageSize -5
        
        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nPage size must be a positive integer." 
        } 
    }

    It "parses log file and returns 0 for valid page size" {
        # Suppress screen clearing and key reading
        Mock Clear-Host {}
        Mock Get-ConsoleKey { [PSCustomObject]@{ Key = "Q" } }
        
        $result = Show-Log -pageSize 1
        
        $result | Should -Be 0
    }

    It "returns -1 if no entries found" {
        "" | Set-Content $LOG_ERROR_PATH
        
        $result = Show-Log -pageSize 1
        
        $result | Should -Be -1
    }

    It "returns -1 if log file is missing" {
        Mock Test-Path { $false }
        
        $result = Show-Log -pageSize 1
        
        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter { 
            $Object -eq "`nLog file not found: $LOG_ERROR_PATH" 
        }
    }
}

