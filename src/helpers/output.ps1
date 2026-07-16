
function Display-Msg-By-ExitCode {
    param ($result, $message = $null)

    try {
        if ($result.messages -and $result.messages.Count -gt 1) {
            foreach ($msg in $result.messages) {
                if (-not $msg.color) {
                    $msg.color = 'White'
                }
                Print-Color -message $($msg.content) -foreColor $msg.color
            }
        } else {
            if ($message) {
                $result.message = $message
            }
            if (-not $result.color) {
                $result.color = 'Gray'
            }

            Print-Color -message "`n$($result.message)" -foreColor $result.color
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to display message by exit code"; exception = $_ }
    }
}

function Log-Data {
    param ($data)

    try {
        $logPath = if ($data.logPath) { $data.logPath } else { $PVMConfig.paths.logError }
        $created = Make-Directory -path (Split-Path -Path $logPath)
        if ($created -ne 0) {
            Print-Host -message "Failed to create directory $(Split-Path -Path $logPath)"
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
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to format seconds"; exception = $_ }
        return -1
    }
}

function Get-Console-Width {
    return $Host.UI.RawUI.WindowSize.Width
}

function Print-Color {
    param ($message, $foreColor)

    Write-Host $message -ForegroundColor $foreColor
}

function Print-Success {
    param($message)

    Print-Color $message -foreColor DarkGreen
}

function Print-Error {
    param($message)

    Print-Color $message -foreColor DarkYellow
}

function Print-Warning {
    param($message)

    Print-Color $message -foreColor Yellow
}

function Print-Info {
    param($message)

    Print-Color $message -foreColor Cyan
}

function Print-Header {
    param($message)

    Print-Color $message -foreColor Magenta
}

function Print-Section {
    param($message)

    Print-Color $message -foreColor Blue
}

function Print-Debug {
    param($message)

    Print-Color $message -foreColor DarkGray
}

function Print-Verbose {
    param($message)

    Print-Color $message -foreColor Gray
}

function Print-Value {
    param($message)

    Print-Color $message -foreColor White
}

function Print-Host {
    param($message)

    Write-Host $message
}

function Write-White {
    param($message)

    Print-Color $message -foreColor White
}

function Write-DarkGreen {
    param($message)

    Print-Color $message -foreColor DarkGreen
}

function Write-DarkYellow {
    param($message)

    Print-Color $message -foreColor DarkYellow
}

function Write-Yellow {
    param($message)

    Print-Color $message -foreColor Yellow
}

function Write-Cyan {
    param($message)

    Print-Color $message -foreColor Cyan
}

function Write-Magenta {
    param($message)

    Print-Color $message -foreColor Magenta
}

function Write-Blue {
    param($message)

    Print-Color $message -foreColor Blue
}

function Write-DarkGray {
    param($message)

    Print-Color $message -foreColor DarkGray
}

function Write-Gray {
    param($message)

    Print-Color $message -foreColor Gray
}

function Write-Default {
    param($message)

    Print-Host $message
}
