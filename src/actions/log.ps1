
function Get-ConsoleKey {
    param ($intercept = $true)

    return [System.Console]::ReadKey($intercept)
}

function Format-NiceTimestamp {
    param ($timestamp)

    try {
        $dateTime = [DateTime]::Parse($timestamp)
        $now = Get-Date
        $timeSpan = $now - $dateTime

        # Format the date part
        $dateStr = $dateTime.ToString('dd MMMM')
        $timeStr = $dateTime.ToString('HH:mm:ss')

        # Calculate relative time
        $relativeTime = ''
        if ($timeSpan.Days -eq 0) {
            if ($timeSpan.Hours -eq 0) {
                if ($timeSpan.Minutes -eq 0) {
                    $relativeTime = 'just now'
                } elseif ($timeSpan.Minutes -eq 1) {
                    $relativeTime = '1 minute ago'
                } else {
                    $relativeTime = "$($timeSpan.Minutes) minutes ago"
                }
            } elseif ($timeSpan.Hours -eq 1) {
                $relativeTime = '1 hour ago'
            } else {
                $relativeTime = "$($timeSpan.Hours) hours ago"
            }
        } elseif ($timeSpan.Days -eq 1) {
            $relativeTime = 'yesterday'
        } elseif ($timeSpan.Days -lt 7) {
            $relativeTime = "$($timeSpan.Days) days ago"
        } elseif ($timeSpan.Days -lt 30) {
            $weeks = [Math]::Floor($timeSpan.Days / 7)
            if ($weeks -eq 1) {
                $relativeTime = '1 week ago'
            } else {
                $relativeTime = "$weeks weeks ago"
            }
        } else {
            $months = [Math]::Floor($timeSpan.Days / 30)
            if ($months -eq 1) {
                $relativeTime = '1 month ago'
            } else {
                $relativeTime = "$months months ago"
            }
        }

        return @{
            Date     = $dateStr
            Time     = $timeStr
            Relative = $relativeTime
            DateTime = $dateTime
        }
    } catch {
        return @{
            Date     = $timestamp
            Time     = ''
            Relative = ''
            DateTime = Get-Date
        }
    }
}

function Show-Log {
    param ($pageSize = $PVMConfig.env.DEFAULT_LOG_PAGE_SIZE, $term = $null)

    try {
        if ($pageSize -notmatch '^-?\d+$') {
            Write-Host -Object "`nInvalid page size: $pageSize" -ForegroundColor Red
            return -1
        }

        $pageSize = [int]$pageSize
        if ($pageSize -le 0) {
            Write-Host -Object "`nPage size must be a positive integer." -ForegroundColor Red
            return -1
        }

        # Check if log file exists
        if (Test-File-Not-Exists -path $PVMConfig.paths.logError) {
            Write-Host -Object "`nLog file not found: $($PVMConfig.paths.logError)" -ForegroundColor Red
            return -1
        }

        # Read the entire log file
        $logContent = Get-Content -Path $PVMConfig.paths.logError -Raw

        # Split by the separator and filter out empty entries
        $logEntries = $logContent -split '-{26}' | Where-Object { $_.Trim() -ne '' }

        # Parse each entry into objects
        $parsedEntries = @()
        foreach ($entry in $logEntries) {
            if ($term -and ($entry -notmatch [regex]::Escape($term))) {
                continue
            }
            $lines = $entry.Trim() -split "`n"
            if ($lines.Count -ge 1) {
                # Changed from 2 to 1 to catch single-line entries
                # Extract timestamp from first line
                $firstLine = $lines[0].Trim()
                if ($firstLine -match '^\[(.+?)\]\s*(.+?)$') {
                    $timestamp = $matches[1]
                    $firstMessage = $matches[2]

                    # Get remaining content
                    $remainingContent = @()
                    if ($lines.Count -gt 1) {
                        $remainingContent = $lines[1..($lines.Count - 1)] | Where-Object { $_.Trim() -ne '' }
                    }

                    # Combine first message with remaining content
                    $fullMessage = @($firstMessage) + $remainingContent | Where-Object { $_.Trim() -ne '' }
                    $fullMessageText = ($fullMessage -join "`n").Trim()

                    # Parse structured error information if present
                    $errorMessage = $null
                    $positionDetail = $null
                    $header = $null

                    if ($fullMessageText -match '(?s)Message:\s*(.+?)\s*\nPosition:\s*(.*)') {
                        $errorMessage = $matches[1].Trim()
                        $positionDetail = $matches[2].Trim()
                        $header = $firstMessage.Trim()
                    }

                    # Format the timestamp nicely
                    $niceTime = Format-NiceTimestamp $timestamp

                    $parsedEntries += @{
                        Timestamp      = $timestamp
                        Message        = $fullMessageText
                        ErrorMessage   = $errorMessage
                        PositionDetail = $positionDetail
                        Header         = $header
                        RawEntry       = $entry.Trim()
                        NiceTime       = $niceTime
                    }
                }
            }
        }

        # Reverse the order to show most recent first
        $reversedEntries = $parsedEntries[-1.. - ($parsedEntries.Length)]

        if ($reversedEntries.Count -eq 0) {
            Write-Host -Object "`nNo log entries found." -ForegroundColor Yellow
            return -1
        }

        # Display entries with pagination
        $currentIndex = 0
        $totalEntries = $reversedEntries.Count

        while ($currentIndex -lt $totalEntries) {
            # Clear screen for cleaner display
            Clear-Host

            # Show header
            Write-Host -Object "`n=== PVM Log Viewer ===" -ForegroundColor Cyan
            Write-Host -Object "`nShowing entries $($currentIndex + 1)-$([Math]::Min($currentIndex + $PageSize, $totalEntries)) of $totalEntries (most recent first)`n" -ForegroundColor Green

            # Display current page of entries
            $endIndex = [Math]::Min($currentIndex + $PageSize - 1, $totalEntries - 1)

            Write-Host -Object ('-' * 80) -ForegroundColor DarkGray
            for ($i = $currentIndex; $i -le $endIndex; $i++) {
                $entry = $reversedEntries[$i]

                # Display structured error format
                Write-Host -Object 'Header  : ' -NoNewline
                Write-Host -Object "$($entry.Header)" -ForegroundColor White

                Write-Host -Object 'Message : ' -NoNewline
                # Handle multi-line error messages with proper indentation (23 spaces to align with "Message :")
                $errorLines = $entry.ErrorMessage -split "`n"
                foreach ($errorLine in $errorLines) {
                    if ($errorLine.Trim() -ne '') {
                        Write-Host -Object "$($errorLine)" -ForegroundColor White
                    }
                }

                # Display entry with nice formatting
                Write-Host -Object 'When    : ' -NoNewline
                Write-Host -Object "$($entry.NiceTime.Date) @ $($entry.NiceTime.Time) " -NoNewline -ForegroundColor White
                Write-Host -Object "($($entry.NiceTime.Relative))" -ForegroundColor DarkGray

                Write-Host -Object 'Where   : ' -NoNewline
                Write-Host -Object "$($entry.PositionDetail)" -ForegroundColor White

                Write-Host -Object ('-' * 80) -ForegroundColor DarkGray
            }

            $currentIndex += $PageSize
            # Show navigation prompt if there are more entries
            if ($currentIndex -lt $totalEntries) {
                Write-Host -Object "`nPress Left/Up arrow for previous page, Right/Down arrow, [Enter] or [Space] for next page, [Q] to quit: " -NoNewline -ForegroundColor Yellow

                $key = Get-ConsoleKey

                switch ($key.Key) {
                    { $_ -in @('LeftArrow', 'UpArrow') } { $currentIndex = [Math]::Max(0, $currentIndex - (2 * $PageSize)) }
                    { $_ -in @('RightArrow', 'DownArrow', 'Enter', 'Spacebar') } { continue }
                    { $_ -in @('q', 'Q') } { return 0 }
                    default { $currentIndex -= $PageSize }
                }
            } else {
                Write-Host -Object 'End of log reached. Press Left/Up arrow to go back or any other key to exit...' -ForegroundColor Green
                $key = Get-ConsoleKey
                if ($key.Key -in @('LeftArrow', 'UpArrow')) {
                    # Go back one page from the end
                    $currentIndex = [Math]::Max(0, $currentIndex - (2 * $PageSize))
                }
            }
        }

        Clear-Host
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to show log"; exception = $_ }
        return -1
    }
}
