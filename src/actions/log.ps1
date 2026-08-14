
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
            $relativeTime = if ($weeks -eq 1) { '1 week ago' } else { "$weeks weeks ago" }
        } else {
            $months = [Math]::Floor($timeSpan.Days / 30)
            $relativeTime = if ($months -eq 1) { '1 month ago' } else { "$months months ago" }
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

function Test-LogPageSize {
    param ($pageSize)

    if ($pageSize -notmatch '^-?\d+$') {
        Show-Error -message "`nInvalid page size: $pageSize"
        return $false
    }

    if ([int]$pageSize -le 0) {
        Show-Error -message "`nPage size must be a positive integer."
        return $false
    }

    return $true
}

function Get-LogEntries {
    param ($path, $term = $null)

    # Read the entire log file
    $logContent = Get-ContentWrapper -path $path -raw

    # Split by the separator and filter out empty entries
    $logEntries = $logContent -split [regex]::Escape($PVMConfig.constants.LOG_SEPARATOR) | Where-Object -FilterScript { $_.Trim() -ne '' }

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
                    $remainingContent = $lines[1..($lines.Count - 1)] | Where-Object -FilterScript { $_.Trim() -ne '' }
                }

                # Combine first message with remaining content
                $fullMessage = @($firstMessage) + $remainingContent | Where-Object -FilterScript { $_.Trim() -ne '' }
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

    return $reversedEntries
}

function Write-LogEntry {
    param ($entry)

    # Display structured error format
    Show-Message -message 'Header  : ' -noNewLine
    Show-Value -message "$($entry.Header)"

    Show-Message -message 'Message : ' -noNewLine
    # Handle multi-line error messages with proper indentation (23 spaces to align with "Message :")
    $errorLines = $entry.ErrorMessage -split "`n"
    foreach ($errorLine in $errorLines) {
        if ($errorLine.Trim() -ne '') {
            Show-Value -message "$($errorLine)"
        }
    }

    # Display entry with nice formatting
    Show-Message -message 'When    : ' -noNewLine
    Show-Value -message "$($entry.NiceTime.Date) @ $($entry.NiceTime.Time) " -noNewLine
    Show-Debug -message "($($entry.NiceTime.Relative))"

    Show-Message -message 'Where   : ' -noNewLine
    Show-Value -message "$($entry.PositionDetail)"

    Show-Debug -message ('-' * 80)
}

function Write-LogPage {
    param ($entries, $startIndex, $pageSize)

    $totalEntries = $entries.Length
    $endIndex = [Math]::Min($startIndex + $pageSize - 1, $totalEntries - 1)

    # Clear screen for cleaner display
    Clear-Host

    # Show header
    Show-Info -message "`n=== PVM Log Viewer ==="
    Show-Header -message "`nShowing entries $($startIndex + 1)-$($endIndex + 1) of $totalEntries (most recent first)`n"

    # Display current page of entries
    $endIndex = [Math]::Min($currentIndex + $pageSize - 1, $totalEntries - 1)

    Write-DarkGray -message ('-' * 80)
    for ($i = $startIndex; $i -le $endIndex; $i++) {
        Write-LogEntry -entry $entries[$i]
    }
}

function Get-LogNavigation {
    param ($currentIndex, $pageSize, $totalEntries)

    # $currentIndex += $pageSize
    # Show navigation prompt if there are more entries
    $isLastPage = ($currentIndex + $pageSize) -ge $totalEntries
    if ($isLastPage) {
        Show-Warning -message 'End of log reached. Press Left/Up arrow to go back or any other key to exit...'

        $key = Get-ConsoleKey
        if ($key.Key -in @('LeftArrow', 'UpArrow')) {
            # Go back one page from the end
            return [Math]::Max(0, $currentIndex - $pageSize)
        }
        return $null
    }

    Show-Warning -message "`nPress Left/Up arrow for previous page, Right/Down arrow, [Enter] or [Space] for next page, [Q] to quit: " -noNewLine

    $key = Get-ConsoleKey
    switch ($key.Key) {
        { $_ -in @('LeftArrow', 'UpArrow') } { return [Math]::Max(0, $currentIndex - $pageSize) }
        { $_ -in @('RightArrow', 'DownArrow', 'Enter', 'Spacebar') } { return ($currentIndex + $pageSize) }
        { $_ -in @('q', 'Q') } { return $null }
        default { return $currentIndex }
    }
}

function Show-Log {
    param ($pageSize = $PVMConfig.env.DEFAULT_LOG_PAGE_SIZE, $term = $null)

    try {
        if (-not (Test-LogPageSize -pageSize $pageSize)) {
            return -1
        }

        $pageSize = [int]$pageSize

        # Check if log file exists
        if (Test-FileNotExists -path $PVMConfig.paths.logError) {
            Show-Error -message "`nLog file not found: $($PVMConfig.paths.logError)"
            return -1
        }

        $entries = @(Get-LogEntries -path $PVMConfig.paths.logError -term $term)

        if ($entries.Length -eq 0) {
            Show-Warning -message "`nNo log entries found."
            return -1
        }

        # Display entries with pagination
        $currentIndex = 0
        $totalEntries = $entries.Length

        while ($currentIndex -lt $totalEntries) {
            Write-LogPage -entries $entries -startIndex $currentIndex -pageSize $pageSize

            $nextIndex = Get-LogNavigation -currentIndex $currentIndex -pageSize $pageSize -totalEntries $totalEntries

            if ($null -eq $nextIndex) {
                break
            }

            $currentIndex = $nextIndex
        }

        Clear-Host
        return 0
    } catch {
        Show-Error -message "`nFailed to show log: $($PVMConfig.paths.logError)"
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to show log"; exception = $_ }
        return -1
    }
}
