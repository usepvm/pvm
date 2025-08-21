

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
    
    if ($pageSize -notmatch '^-?\d+$') {
        Write-Host "`nInvalid page size: $pageSize" -ForegroundColor Red
        return -1
    }
    
    try {
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
                    
                    # Check if this is a structured error log with File: Line: Message: format
                    if ($fullMessageText -match '(?s)File:\s*(.+?)\s*\nLine:\s*(\d+)\s*\nMessage:\s*\n(.*)') {
                        $file = $matches[1].Trim()
                        $lineNumber = $matches[2].Trim()
                        $errorMessage = $matches[3].Trim()
                    }
                    
                    # Format the timestamp nicely
                    $niceTime = Format-NiceTimestamp $timestamp
                    
                    $parsedEntries += [PSCustomObject]@{
                        Timestamp = $timestamp
                        Operation = $operation
                        Message = $fullMessageText
                        File = $file
                        Line = $lineNumber
                        ErrorMessage = $errorMessage
                        RawEntry = $entry.Trim()
                        NiceTime = $niceTime
                    }
                }
            }
        }
        
        # Reverse the order to show most recent first
        $reversedEntries = $parsedEntries[-1..-($parsedEntries.Length)]
        # [Array]::Reverse($reversedEntries)
        # $reversedEntries = [Array]::Reverse($parsedEntries) # $parsedEntries | Sort-Object { $_.NiceTime.DateTime } -Descending
        
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
            # Write-Host "`nLog file: $LogPath`n" -ForegroundColor Gray
            
            # Display current page of entries
            $endIndex = [Math]::Min($currentIndex + $PageSize - 1, $totalEntries - 1)
            
            Write-Host ("-" * 80) "`n" -ForegroundColor DarkGray
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
                
                # Display entry with nice formatting
                Write-Host "Time    : " -NoNewline -ForegroundColor Gray
                Write-Host "$($entry.NiceTime.Date) @ $($entry.NiceTime.Time) " -NoNewline -ForegroundColor White
                Write-Host "($($entry.NiceTime.Relative))" -ForegroundColor DarkGray
                
                # Check if this is a structured error entry
                if ($entry.File -and $entry.Line -and $entry.ErrorMessage) {
                    # Display structured error format
                    Write-Host "File    : " -NoNewline -ForegroundColor Gray
                    Write-Host "$($entry.File)" -ForegroundColor White
                    
                    Write-Host "Line    : " -NoNewline -ForegroundColor Gray
                    Write-Host "$($entry.Line)" -ForegroundColor White
                    
                    Write-Host "Message : " -NoNewline -ForegroundColor Gray
                    
                    # Handle multi-line error messages with proper indentation (23 spaces to align with "Message :")
                    $errorLines = $entry.ErrorMessage -split "`n"
                    foreach ($errorLine in $errorLines) {
                        if ($errorLine.Trim() -ne '') {
                            Write-Host "$($errorLine)" -ForegroundColor White
                        }
                    }
                } else {
                    # Display regular format for non-structured entries
                    Write-Host "Function: " -NoNewline -ForegroundColor Gray
                    Write-Host "$($entry.Operation)" -ForegroundColor $operationColor
                    
                    Write-Host "Message : " -NoNewline -ForegroundColor Gray
                    
                    # Handle multi-line messages with proper indentation
                    $messageLines = $entry.Message -split "`n"
                    if ($messageLines.Count -eq 1) {
                        Write-Host "$($entry.Message)" -ForegroundColor White
                    } else {
                        Write-Host "$($messageLines[0])" -ForegroundColor White
                        for ($j = 1; $j -lt $messageLines.Count; $j++) {
                            Write-Host "          $($messageLines[$j])" -ForegroundColor White
                        }
                    }
                }
                
                Write-Host ""
                Write-Host ("-" * 80) -ForegroundColor DarkGray
                Write-Host ""
            }
            
            $currentIndex += $PageSize
            # Show navigation prompt if there are more entries
            if ($currentIndex -lt $totalEntries) {
                Write-Host "`nPress Left/Up arrow for previous page, Right/Down arrow, [Enter] or [Space] for next page, [Q] to quit: " -NoNewline -ForegroundColor Yellow
                
                $key = [System.Console]::ReadKey($true) # $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                
                switch ($key.Key) {
                    { $_ -in @("LeftArrow", "UpArrow") } { $currentIndex = [Math]::Max(0, $currentIndex - (2 * $PageSize)) }
                    { $_ -in @("RightArrow", "DownArrow", "Enter", "Spacebar") } { continue }
                    { $_ -in @('q', 'Q') } { return 0 }
                    default { $currentIndex -= $PageSize }
                }
            } else {
                Write-Host "End of log reached. Press Left/Up arrow to go back or any other key to exit..." -ForegroundColor Green
                $key = [System.Console]::ReadKey($true)  # $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
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
            file = $($_.InvocationInfo.ScriptName)
            line = $($_.InvocationInfo.ScriptLineNumber)
            message = $_.Exception.Message
            positionMessage = $_.InvocationInfo.PositionMessage
        }
        return -1
    }
}