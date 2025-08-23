

function Format-NiceTimestamp {
    param($timestamp)
    
    try {
        $dateTime = [DateTime]::Parse($timestamp)
        $now = Get-Date
        $timeSpan = $now - $dateTime
        
        # Format the date part
        $dateStr = $dateTime.ToString("dd MMMM")
        $timeStr = $dateTime.ToString("HH:mm:ss")
        
        # Calculate relative time
        $relativeTime = ""
        if ($timeSpan.Days -eq 0) {
            if ($timeSpan.Hours -eq 0) {
                if ($timeSpan.Minutes -eq 0) {
                    $relativeTime = "just now"
                } elseif ($timeSpan.Minutes -eq 1) {
                    $relativeTime = "1 minute ago"
                } else {
                    $relativeTime = "$($timeSpan.Minutes) minutes ago"
                }
            } elseif ($timeSpan.Hours -eq 1) {
                $relativeTime = "1 hour ago"
            } else {
                $relativeTime = "$($timeSpan.Hours) hours ago"
            }
        } elseif ($timeSpan.Days -eq 1) {
            $relativeTime = "yesterday"
        } elseif ($timeSpan.Days -lt 7) {
            $relativeTime = "$($timeSpan.Days) days ago"
        } elseif ($timeSpan.Days -lt 30) {
            $weeks = [Math]::Floor($timeSpan.Days / 7)
            if ($weeks -eq 1) {
                $relativeTime = "1 week ago"
            } else {
                $relativeTime = "$weeks weeks ago"
            }
        } else {
            $months = [Math]::Floor($timeSpan.Days / 30)
            if ($months -eq 1) {
                $relativeTime = "1 month ago"
            } else {
                $relativeTime = "$months months ago"
            }
        }
        
        return @{
            Date = $dateStr
            Time = $timeStr
            Relative = $relativeTime
            DateTime = $dateTime
        }
    } catch {
        return @{
            Date = $timestamp
            Time = ""
            Relative = ""
            DateTime = Get-Date
        }
    }
}

function Show-Log {
    param($pageSize = 10)
    
    try {
        if ($pageSize -notmatch '^\d+$' -or [int]$pageSize -le 0) {
            Write-Host "`nInvalid page size: $pageSize" -ForegroundColor Red
            return -1
        }

        $pageSize = [int]$pageSize
        if ($pageSize -le 0) {
            Write-Host "`nPage size must be a positive integer." -ForegroundColor Red
            return -1
        }
        
        $LogPath = $LOG_ERROR_PATH
        
        # Check if log file exists
        if (-not (Test-Path $LogPath)) {
            Write-Host "Log file not found: $LogPath" -ForegroundColor Red
            return -1
        }

        # Read the entire log file
        $logContent = Get-Content $LogPath -Raw
        
        # Split by the separator and filter out empty entries
        $logEntries = $logContent -split '-{26}' | Where-Object { $_.Trim() -ne '' }
        
        # Parse each entry into objects
        $parsedEntries = @()
        foreach ($entry in $logEntries) {
            $lines = $entry.Trim() -split "`n"
            if ($lines.Count -ge 1) {  # Changed from 2 to 1 to catch single-line entries
                # Extract timestamp and operation from first line
                $firstLine = $lines[0].Trim()
                if ($firstLine -match '^\[(.+?)\]\s*(.+?)\s*:\s*(.*)$') {
                    $timestamp = $matches[1]
                    $operation = $matches[2]
                    $firstMessage = $matches[3]
                    
                    # Get remaining content
                    $remainingContent = @()
                    if ($lines.Count -gt 1) {
                        $remainingContent = $lines[1..($lines.Count-1)] | Where-Object { $_.Trim() -ne '' }
                    }
                    
                    # Combine first message with remaining content
                    $fullMessage = @($firstMessage) + $remainingContent | Where-Object { $_.Trim() -ne '' }
                    $fullMessageText = ($fullMessage -join "`n").Trim()
                    
                    # Parse structured error information if present
                    $file = $null
                    $lineNumber = $null
                    $errorMessage = $null
                    $positionDetail = $null
                    $header = $null
                    
                    # Check if this is a structured error log with File: Line: Message: Position: format
                    if ($fullMessageText -match '(?s)Message:\s*(.+?)\s*\nPosition:\s*(.*)') {
                        $errorMessage = $matches[1].Trim()
                        $positionDetail = $matches[2].Trim()
                        $header = $firstMessage.Trim(':')
                    }
                    
                    # Format the timestamp nicely
                    $niceTime = Format-NiceTimestamp $timestamp
                    
                    $parsedEntries += [PSCustomObject]@{
                        Timestamp = $timestamp
                        Operation = $operation
                        Message = $fullMessageText
                        ErrorMessage = $errorMessage
                        PositionDetail = $positionDetail
                        Header = $header
                        RawEntry = $entry.Trim()
                        NiceTime = $niceTime
                    }
                }
            }
        }
        
        # Reverse the order to show most recent first
        $reversedEntries = $parsedEntries[-1..-($parsedEntries.Length)]
        
        if ($reversedEntries.Count -eq 0) {
            Write-Host "No log entries found." -ForegroundColor Yellow
            return
        }
        
        # Display entries with pagination
        $currentIndex = 0
        $totalEntries = $reversedEntries.Count
        
        while ($currentIndex -lt $totalEntries) {
            # Clear screen for cleaner display
            Clear-Host
            
            # Show header
            Write-Host "`n=== PVM Log Viewer ===" -ForegroundColor Cyan
            Write-Host "`nShowing entries $($currentIndex + 1)-$([Math]::Min($currentIndex + $PageSize, $totalEntries)) of $totalEntries (most recent first)`n" -ForegroundColor Green
            
            # Display current page of entries
            $endIndex = [Math]::Min($currentIndex + $PageSize - 1, $totalEntries - 1)
            
            Write-Host ("-" * 80) -ForegroundColor DarkGray
            for ($i = $currentIndex; $i -le $endIndex; $i++) {
                $entry = $reversedEntries[$i]
                
                # Color code based on operation type
                $operationColor = switch -Wildcard ($entry.Operation) {
                    "*Failed*" { "Red" }
                    "*Error*" { "Red" }
                    "*Warning*" { "Yellow" }
                    "*Success*" { "Green" }
                    default { "White" }
                }
                
                # Display structured error format
                Write-Host "Header  : " -NoNewline -ForegroundColor Gray
                Write-Host "$($entry.Header)" -ForegroundColor White
                
                Write-Host "Message : " -NoNewline -ForegroundColor Gray
                # Handle multi-line error messages with proper indentation (23 spaces to align with "Message :")
                $errorLines = $entry.ErrorMessage -split "`n"
                foreach ($errorLine in $errorLines) {
                    if ($errorLine.Trim() -ne '') {
                        Write-Host "$($errorLine)" -ForegroundColor White
                    }
                }
                
                # Display entry with nice formatting
                Write-Host "When    : " -NoNewline -ForegroundColor Gray
                Write-Host "$($entry.NiceTime.Date) @ $($entry.NiceTime.Time) " -NoNewline -ForegroundColor White
                Write-Host "($($entry.NiceTime.Relative))" -ForegroundColor DarkGray
                
                Write-Host "Where   : " -NoNewline -ForegroundColor Gray
                Write-Host "$($entry.PositionDetail)" -ForegroundColor White
                
                Write-Host ("-" * 80) -ForegroundColor DarkGray
            }
            
            $currentIndex += $PageSize
            # Show navigation prompt if there are more entries
            if ($currentIndex -lt $totalEntries) {
                Write-Host "`nPress Left/Up arrow for previous page, Right/Down arrow, [Enter] or [Space] for next page, [Q] to quit: " -NoNewline -ForegroundColor Yellow
                
                $key = [System.Console]::ReadKey($true)
                
                switch ($key.Key) {
                    { $_ -in @("LeftArrow", "UpArrow") } { $currentIndex = [Math]::Max(0, $currentIndex - (2 * $PageSize)) }
                    { $_ -in @("RightArrow", "DownArrow", "Enter", "Spacebar") } { continue }
                    { $_ -in @('q', 'Q') } { return 0 }
                    default { $currentIndex -= $PageSize }
                }
            } else {
                Write-Host "End of log reached. Press Left/Up arrow to go back or any other key to exit..." -ForegroundColor Green
                $key = [System.Console]::ReadKey($true)
                if ($key.Key -in @("LeftArrow", "UpArrow")) {
                    # Go back one page from the end
                    $currentIndex = [Math]::Max(0, $currentIndex - (2 * $PageSize))
                }
            }
        }
        
        Clear-Host
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name): Failed to show log"
            exception = $_
        }
        return -1
    }
}