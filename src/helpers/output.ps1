
function Show-MsgByExitCode {
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
        Add-Content-Wrapper -path $logPath -value $content
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

function Get-ConsoleWidth {
    return $Host.UI.RawUI.WindowSize.Width
}

function Show-SpinnerWhileJob {
    param ($scriptBlock, $message = @{ content = 'Please wait...'; color = 'White' }, [switch]$noClear, $argumentList = @(), $rethrow = $false)

    $spinner = @('|', '/', '-', '\')

    try {
        # Create initialization script to load all PVM functions into the job
        $env:PVM_ROOT_FOR_JOB = $PVMRoot
        $initScript = {
            . "$($env:PVM_ROOT_FOR_JOB)\src\import.ps1"
        }

        # $job = Start-Job -ScriptBlock $scriptBlock -InitializationScript $initScript -ArgumentList (,$argumentList)
        $job = Start-Job -ScriptBlock $scriptBlock -InitializationScript $initScript -ArgumentList $argumentList

        $i = 0
        while ($job.State -eq 'Running') {
            Write-Color -message "`r$($message.content) $($spinner[$i % $spinner.Length])" -foreColor $message.color -NoNewline
            Start-Sleep -Milliseconds 100
            $i++
        }

        # Clear the spinner line
        if (-not $noClear) {
            Write-Color -message "`r$(' ' * ($message.content.Length + 2))`r" -foreColor $message.color -NoNewline
        }

        $result = Receive-Job -Job $job -Wait -AutoRemoveJob -ErrorAction Stop
        Remove-Item Env:\PVM_ROOT_FOR_JOB -ErrorAction SilentlyContinue

        return $result.pvmData
    } catch {
        Write-Yellow -message "`r$(' ' * ($message.content.Length + 2))`r" -NoNewline
        Remove-Item Env:\PVM_ROOT_FOR_JOB -ErrorAction SilentlyContinue
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to show spinner while job"; exception = $_ }

        if ($rethrow) {
            throw $_
        }

        return -1
    }
}

function Show-SpinnerWhileProcess  {
    param ($fileName, $processArgs, $message = @{ content = 'Please wait...'; color = 'White' }, [switch]$noClear)

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $fileName
        $psi.Arguments = ($processArgs | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_ -replace '"', '\"') + '"'
            } else {
                $_
            }
        }) -join ' '
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::new()
        $proc.StartInfo = $psi
        $null = $proc.Start()

        $stdOutTask = $proc.StandardOutput.ReadToEndAsync()
        $stdErrTask = $proc.StandardError.ReadToEndAsync()

        $spinner = @('|', '/', '-', '\')
        $i = 0
        while (-not $proc.HasExited) {
            Write-Color -message "`r$($message.content) $($spinner[$i % $spinner.Length])" -foreColor $message.color -noNewLine
            Start-Sleep -Milliseconds 100
            $i++
        }

        # Clear the spinner line
        if (-not $noClear) {
            Write-Color -message "`r$(' ' * ($message.content.Length + 2))`r" -foreColor $message.color -NoNewline
        }

        $proc.WaitForExit()
        $outputText = $stdOutTask.Result + $stdErrTask.Result

        return @{ output = $outputText; code = $proc.ExitCode }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run subprocess"; exception = $_ }
        return @{ output = $null; code = -1 }
    }
}

function Write-Color {
    param ($message, $foreColor, [switch]$noNewLine)

    if ($script:PVMSubprocessMode) {
        $script:StructuredOutput += @{
            message = $message
            color = $foreColor
            noNewLine = $noNewLine.IsPresent
        }
    } else {
        Write-Host -Object $message -ForegroundColor $foreColor -NoNewline:$noNewLine
    }
}

function Write-White {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor White -noNewLine:$noNewLine
}

function Write-DarkGreen {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor DarkGreen -noNewLine:$noNewLine
}

function Write-DarkYellow {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor DarkYellow -noNewLine:$noNewLine
}

function Write-Yellow {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor Yellow -noNewLine:$noNewLine
}

function Write-Cyan {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor Cyan -noNewLine:$noNewLine
}

function Write-Magenta {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor Magenta -noNewLine:$noNewLine
}

function Write-Blue {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor Blue -noNewLine:$noNewLine
}

function Write-DarkGray {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor DarkGray -noNewLine:$noNewLine
}

function Write-Gray {
    param ($message, [switch]$noNewLine)

    Write-Color -message $message -foreColor Gray -noNewLine:$noNewLine
}

function Write-Default {
    param ($message, [switch]$noNewLine)

    Show-Message -message $message -noNewLine:$noNewLine
}

function Show-Success {
    param ($message, [switch]$noNewLine)

    Write-DarkGreen -message $message -noNewLine:$noNewLine
}

function Show-Error {
    param ($message, [switch]$noNewLine)

    Write-DarkYellow -message $message -noNewLine:$noNewLine
}

function Show-Warning {
    param ($message, [switch]$noNewLine)

    Write-Yellow -message $message -noNewLine:$noNewLine
}

function Show-Info {
    param ($message, [switch]$noNewLine)

    Write-Cyan -message $message -noNewLine:$noNewLine
}

function Show-Header {
    param ($message, [switch]$noNewLine)

    Write-Magenta -message $message -noNewLine:$noNewLine
}

function Show-Section {
    param ($message, [switch]$noNewLine)

    Write-Blue -message $message -noNewLine:$noNewLine
}

function Show-Debug {
    param ($message, [switch]$noNewLine)

    Write-DarkGray -message $message -noNewLine:$noNewLine
}

function Show-Verbose {
    param ($message, [switch]$noNewLine)

    Write-Gray -message $message -noNewLine:$noNewLine
}

function Show-Value {
    param ($message, [switch]$noNewLine)

    Write-White -message $message -noNewLine:$noNewLine
}

function Show-Message {
    param ($message, [switch]$noNewLine)

    Write-White -message $message -noNewLine:$noNewLine
}

function New-Line {
    New-Lines -count 1
}

function New-Lines {
    param ($count = 1)

    Show-Message -message ("`n" * $count) -noNewLine
}
