
function Show-Msg-By-ExitCode {
    param ($result, $message = $null)

    try {
        if ($result.messages -and $result.messages.Count -gt 1) {
            foreach ($msg in $result.messages) {
                if (-not $msg.color) {
                    $msg.color = 'White'
                }
                Write-Color -message $($msg.content) -foreColor $msg.color
            }
        } else {
            if ($message) {
                $result.message = $message
            }
            if (-not $result.color) {
                $result.color = 'Gray'
            }

            Write-Color -message "`n$($result.message)" -foreColor $result.color
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to display message by exit code"; exception = $_ }
    }
}

function Add-LogEntry {
    param ($data)

    try {
        $logPath = if ($data.logPath) { $data.logPath } else { $PVMConfig.paths.logError }
        $created = New-Directory -path (Split-Path -Path $logPath)
        if ($created -ne 0) {
            Show-Message -message "Failed to create directory $(Split-Path -Path $logPath)"
            return -1
        }
        $content = "`n--------------------------"
        $content += "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($data.header)"
        if ($data.exception) {
            $content += "`nMessage: $($data.exception.Exception.Message)"
            $content += "`nPosition: $($data.exception.InvocationInfo.PositionMessage)"
        }
        Add-Content -Path $logPath -Value $content
        return 0
    } catch {
        return -1
    }
}

function Format-Seconds {
    param ($totalSeconds)

    try {
        if ($null -ne $totalSeconds) {
            $totalSeconds = [Single] $totalSeconds
        }

        if ($null -eq $totalSeconds -or $totalSeconds -lt 0) {
            $totalSeconds = 0
        }

        if ($totalSeconds -lt 60) {
            $rounded = [math]::Round($totalSeconds, 1)
            return '{0}s' -f $rounded
        }

        $hours = [int][math]::Floor($totalSeconds / 3600)
        $minutes = [int][math]::Floor(($totalSeconds % 3600) / 60)
        $seconds = [int][math]::Floor($totalSeconds % 60)

        if ($hours -gt 0) {
            return '{0:D2}:{1:D2}:{2:D2}' -f $hours, $minutes, $seconds
        }

        return '{0:D2}:{1:D2}' -f $minutes, $seconds
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to format seconds"; exception = $_ }
        return -1
    }
}

function Get-Console-Width {
    return $Host.UI.RawUI.WindowSize.Width
}

function Write-Color {
    param ($message, $foreColor, [switch]$noNewLine)

    Write-Host $message -ForegroundColor $foreColor -NoNewline:$noNewLine
}

function Write-White {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor White -noNewLine:$noNewLine
}

function Write-DarkGreen {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor DarkGreen -noNewLine:$noNewLine
}

function Write-DarkYellow {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor DarkYellow -noNewLine:$noNewLine
}

function Write-Yellow {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor Yellow -noNewLine:$noNewLine
}

function Write-Cyan {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor Cyan -noNewLine:$noNewLine
}

function Write-Magenta {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor Magenta -noNewLine:$noNewLine
}

function Write-Blue {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor Blue -noNewLine:$noNewLine
}

function Write-DarkGray {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor DarkGray -noNewLine:$noNewLine
}

function Write-Gray {
    param($message, [switch]$noNewLine)

    Write-Color $message -foreColor Gray -noNewLine:$noNewLine
}

function Write-Default {
    param($message, [switch]$noNewLine)

    Show-Message $message -noNewLine:$noNewLine
}

function Show-Success {
    param($message, [switch]$noNewLine)

    Write-DarkGreen $message -noNewLine:$noNewLine
}

function Show-Error {
    param($message, [switch]$noNewLine)

    Write-DarkYellow $message -noNewLine:$noNewLine
}

function Show-Warning {
    param($message, [switch]$noNewLine)

    Write-Yellow $message -noNewLine:$noNewLine
}

function Show-Info {
    param($message, [switch]$noNewLine)

    Write-Cyan $message -noNewLine:$noNewLine
}

function Show-Header {
    param($message, [switch]$noNewLine)

    Write-Magenta $message -noNewLine:$noNewLine
}

function Show-Section {
    param($message, [switch]$noNewLine)

    Write-Blue $message -noNewLine:$noNewLine
}

function Show-Debug {
    param($message, [switch]$noNewLine)

    Write-DarkGray $message -noNewLine:$noNewLine
}

function Show-Verbose {
    param($message, [switch]$noNewLine)

    Write-Gray $message -noNewLine:$noNewLine
}

function Show-Value {
    param($message, [switch]$noNewLine)

    Write-White $message -noNewLine:$noNewLine
}

function Show-Message {
    param($message, [switch]$noNewLine)

    Write-Host $message -NoNewline:$noNewLine
}
