
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
        $logPath = if ($data.logPath) { $data.logPath } else { $PVMConfig.paths.files.logError }
        $created = New-Directory -path (Split-Path -Path $logPath -Parent)
        if ($created -ne 0) {
            Show-Error -message "Failed to create directory $(Split-Path -Path $logPath -Parent)"
            return -1
        }
        $content = "`n$($PVMConfig.constants.LOG_SEPARATOR)"
        $content += "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($data.header)"
        if ($data.exception) {
            $content += "`nMessage: $($data.exception.Exception.Message)"
            $content += "`nPosition: $($data.exception.InvocationInfo.PositionMessage)"
        }
        Add-ContentWrapper -path $logPath -value $content
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
            . "$($env:PVM_ROOT_FOR_JOB)\src\imports.ps1"
        }

        # $job = Start-Job -ScriptBlock $scriptBlock -InitializationScript $initScript -ArgumentList (,$argumentList)
        $job = Start-Job -ScriptBlock $scriptBlock -InitializationScript $initScript -ArgumentList $argumentList

        $i = 0
        while ($job.State -eq 'Running') {
            Write-Color -message "`r$($message.content) $($spinner[$i % $spinner.Length])" -foreColor $message.color -noNewline
            Start-Sleep -Milliseconds 100
            $i++
        }

        # Clear the spinner line
        if (-not $noClear) {
            Write-HostWrapper -object "`r$(' ' * ($message.content.Length + 2))`r" -noNewline
        }

        $result = Receive-Job -Job $job -Wait -AutoRemoveJob -ErrorAction Stop
        Remove-ItemWrapper -path Env:\PVM_ROOT_FOR_JOB

        return $result.pvmData
    } catch {
        Write-HostWrapper -object "`r$(' ' * ($message.content.Length + 2))`r" -noNewline
        Remove-ItemWrapper -path Env:\PVM_ROOT_FOR_JOB
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to show spinner while job"; exception = $_ }

        if ($rethrow) {
            throw $_
        }

        return -1
    }
}

function New-Process {
    return [System.Diagnostics.Process]::new()
}

function Show-SpinnerWhileProcess {
    param ($fileName, $processArgs, $message = @{ content = 'Please wait...'; color = 'White' }, [switch]$noClear)

    $proc = $null
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $fileName
        $psi.Arguments = ($processArgs | ForEach-Object -Process {
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

        $proc = New-Process
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
            Write-Color -message "`r$(' ' * ($message.content.Length + 2))`r" -foreColor $message.color -noNewLine
        }

        $proc.WaitForExit()
        $outputText = $stdOutTask.Result + $stdErrTask.Result

        return @{ output = $outputText; code = $proc.ExitCode }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run subprocess"; exception = $_ }
        return @{ output = $null; code = -1 }
    } finally {
        if ($proc) {
            try {
                if ($proc.Responding -and (-not $proc.HasExited)) {
                    $proc.Kill()
                }
            } catch {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to kill subprocess"; exception = $_ }
            }
            $proc.Dispose()
        }
    }
}

function Write-Color {
    param ($message, $foreColor, [switch]$noNewLine)

    Write-HostWrapper -object $message -foregroundColor $foreColor -noNewLine:$noNewLine
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

function New-Lines {
    param ($count = 1)

    Write-HostWrapper -object ("`n" * $count) -noNewLine
}

function New-Line {
    New-Lines -count 1
}

function New-Player {
    Add-Type -AssemblyName PresentationCore
    $MediaPlayer = New-Object -TypeName System.Windows.Media.MediaPlayer

    return $MediaPlayer
}

function Get-Sound-TotalSeconds {
    param ($path)

    $folder = Split-Path -Path $path -Parent
    $file = Split-Path -Path $path -Leaf
    $shell = New-Object -ComObject Shell.Application
    $shellFolder = $shell.Namespace($folder)
    $shellFile = $shellFolder.ParseName($file)

    $duration = $shellFolder.GetDetailsOf($shellFile, 27)
    $ts = [timespan]::Parse($duration)
    $totalSeconds = if ($ts.TotalSeconds -gt 1) { $ts.TotalSeconds } else { 1 }

    return $totalSeconds
}

function Invoke-Sound {
    param ($filename)

    try {
        if ($Global:PVMConfig.subprocess.enabled -or $PVMConfig.env.SOUNDS_DISABLED) {
            return
        }

        $MediaPlayer = New-Player
        $path = "$($PVMConfig.paths.directories.assets)\sounds\$filename"
        $MediaPlayer.Open($path)
        $duration = Get-Sound-TotalSeconds -path $path
        $MediaPlayer.Play()
        Start-Sleep -Seconds $duration
        $MediaPlayer.Close()
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to play sound"; exception = $_ }
    }
}

function Invoke-SuccessSound {
    Invoke-Sound -filename 'success.mp3'
}

function Invoke-ErrorSound {
    Invoke-Sound -filename 'error.mp3'
}

function Invoke-NotifySound {
    Invoke-Sound -filename 'notify.mp3'
}

function Invoke-PromptSound {
    Invoke-Sound -filename 'prompt.mp3'
}
