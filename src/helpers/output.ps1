
function Add-LogEntry {
    param ($data)

    try {
        $logPath = if ($data.logPath) { $data.logPath } else { $Global:PVMConfig.paths.files.logError }
        $created = New-Directory -path (Split-Path -Path $logPath -Parent)
        if ($created -ne 0) {
            Show-Error -message "`nFailed to create directory $(Split-Path -Path $logPath -Parent)"
            return -1
        }
        $content = "`n$($Global:PVMConfig.constants.LOG_SEPARATOR)"
        $content += "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($data.header)"
        if ($data.exception) {
            $content += "`nMessage: $($data.exception.Exception.Message)"
            $content += "`nPosition: $($data.exception.InvocationInfo.PositionMessage)"
        }
        $null = Add-ContentWrapper -path $logPath -value $content
        return 0
    } catch {
        return -1
    }
}

function Show-SpinnerWhileJob {
    param ($scriptBlock, $message = @{ content = 'Please wait...'; color = 'White' }, [switch]$noClear, $argumentList = @(), $rethrow = $false)

    $spinner = @('|', '/', '-', '\')

    try {
        # Create initialization script to load all PVM functions into the job
        $env:PVM_SRC_FOR_JOB = $Global:PVMConfig.paths.directories.src
        $initScript = {
            . "$($env:PVM_SRC_FOR_JOB)\imports.ps1"
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
        $null = Remove-ItemWrapper -path Env:\PVM_SRC_FOR_JOB -allowOutsideRoot

        return $result.pvmData
    } catch {
        Write-HostWrapper -object "`r$(' ' * ($message.content.Length + 2))`r" -noNewline
        $null = Remove-ItemWrapper -path Env:\PVM_SRC_FOR_JOB -allowOutsideRoot
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

function Get-StatusTable {
    return [ordered]@{
        success = @{
            label          = 'Success'
            color          = 'DarkGreen'
            contrastColor  = 'Black'
        }
        error = @{
            label          = 'Error'
            color          = 'DarkYellow'
            contrastColor  = 'Black'
        }
        warning = @{
            label          = 'Warning'
            color          = 'Yellow'
            contrastColor  = 'Black'
        }
        info = @{
            label          = 'Info'
            color          = 'Cyan'
            contrastColor  = 'Black'
        }
    }
}

function Write-Color {
    param ($message, $foreColor, [switch]$noNewLine, [switch]$underlined)

    Write-HostWrapper -object $message -foregroundColor $foreColor -noNewLine:$noNewLine
    if (-not $noNewLine -and $underlined) {
        Write-HostWrapper -object ('-' * ($message.Trim().Length)) -foregroundColor 'Gray'
    }
}

function Write-BgColor {
    param ($message, $backColor, $foreColor, [switch]$noNewLine)

    Write-HostWrapper -object $message -foregroundColor $foreColor -backgroundColor $backColor -noNewLine:$noNewLine
}

function Write-White {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor White -noNewLine:$noNewLine -underlined:$underlined
}

function Write-DarkGreen {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor DarkGreen -noNewLine:$noNewLine -underlined:$underlined
}

function Write-DarkYellow {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor DarkYellow -noNewLine:$noNewLine -underlined:$underlined
}

function Write-Yellow {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor Yellow -noNewLine:$noNewLine -underlined:$underlined
}

function Write-Cyan {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor Cyan -noNewLine:$noNewLine -underlined:$underlined
}

function Write-Magenta {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor Magenta -noNewLine:$noNewLine -underlined:$underlined
}

function Write-Blue {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor Blue -noNewLine:$noNewLine -underlined:$underlined
}

function Write-DarkGray {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor DarkGray -noNewLine:$noNewLine -underlined:$underlined
}

function Write-Gray {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor Gray -noNewLine:$noNewLine -underlined:$underlined
}

function Show-Success {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    $status = (Get-StatusTable)['success']
    Write-Color -message $message -foreColor $status.color -noNewLine:$noNewLine -underlined:$underlined
}

function Show-Error {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    $status = (Get-StatusTable)['error']
    Write-Color -message $message -foreColor $status.color -noNewLine:$noNewLine -underlined:$underlined
}

function Show-Warning {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    $status = (Get-StatusTable)['warning']
    Write-Color -message $message -foreColor $status.color -noNewLine:$noNewLine -underlined:$underlined
}

function Show-Info {
    param ($message, [switch]$noNewLine, [switch]$underlined)

    $status = (Get-StatusTable)['info']
    Write-Color -message $message -foreColor $status.color -noNewLine:$noNewLine -underlined:$underlined
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
    param ($message, [switch]$noNewLine, [switch]$underlined)

    Write-Color -message $message -foreColor White -noNewLine:$noNewLine -underlined:$underlined
}

function Show-Label {
    param ($label, $foreColor, $backColor = $null, [switch]$noPreNewLine , [switch]$noNewLine)

    if (-not $noPreNewLine) {
        New-Line
    }

    Write-BgColor -message " $label " -backColor $backColor -foreColor $foreColor -noNewLine:$noNewLine
}

function Show-LabelledMessage {
    param ($label, $message, $backColor, $foreColor, [switch]$noPreNewLine , [switch]$noNewLine)

    Show-Label -label $label -foreColor $foreColor -backColor $backColor -noPreNewLine:$noPreNewLine -noNewLine

    $lines = $message.Trim() -split "`n"
    $spaces = ' ' * ($label.Length + 2)
    $msg = $lines -join "`n$spaces "
    Write-White -message " $msg`n" -noNewLine:$noNewLine
}

function Show-LabelledSuccess {
    param ($message, [switch]$noPreNewLine, [switch]$noNewLine)

    $status = (Get-StatusTable)['success']

    Show-LabelledMessage -label $status.label -message $message -backColor $status.color -foreColor $status.contrastColor -noPreNewLine:$noPreNewLine -noNewLine:$noNewLine
}

function Show-LabelledError {
    param ($message, [switch]$noPreNewLine, [switch]$noNewLine)

    $status = (Get-StatusTable)['error']
    Show-LabelledMessage -label $status.label -message $message -backColor $status.color -foreColor $status.contrastColor -noPreNewLine:$noPreNewLine -noNewLine:$noNewLine
}

function Show-LabelledWarning {
    param ($message, [switch]$noPreNewLine, [switch]$noNewLine)

    $status = (Get-StatusTable)['warning']
    Show-LabelledMessage -label $status.label -message $message -backColor $status.color -foreColor $status.contrastColor -noPreNewLine:$noPreNewLine -noNewLine:$noNewLine
}

function Show-LabelledInfo {
    param ($message, [switch]$noPreNewLine, [switch]$noNewLine)

    $status = (Get-StatusTable)['info']
    Show-LabelledMessage -label $status.label -message $message -backColor $status.color -foreColor $status.contrastColor -noPreNewLine:$noPreNewLine -noNewLine:$noNewLine
}

function New-Lines {
    param ($count = 1)

    Write-HostWrapper -object ("`n" * $count) -noNewLine
}

function New-Line {
    New-Lines -count 1
}

function Write-Spaces {
    param ($count = 1)

    Write-HostWrapper -object (' ' * $count) -noNewLine
}

function Write-Space {
    Write-Spaces -count 1
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
    param ($filename, [switch]$wait)

    try {
        if ($Global:PVMConfig.subprocess.enabled -or $Global:PVMConfig.env.SOUNDS_DISABLED) {
            return
        }

        $MediaPlayer = New-Player
        $path = "$($Global:PVMConfig.paths.directories.assets)\sounds\$filename"
        $MediaPlayer.Open($path)
        $duration = Get-Sound-TotalSeconds -path $path
        $MediaPlayer.Play()
        if ($wait) {
            Start-Sleep -Seconds $duration
            $MediaPlayer.Close()
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to play sound"; exception = $_ }
    }
}

function Invoke-SuccessSound {
    param ([switch]$wait)

    Invoke-Sound -filename 'success.mp3' -wait:$wait
}

function Invoke-ErrorSound {
    param ([switch]$wait)

    Invoke-Sound -filename 'error.mp3' -wait:$wait
}

function Invoke-NotifySound {
    param ([switch]$wait)

    Invoke-Sound -filename 'notify.mp3' -wait:$wait
}

function Invoke-PromptSound {
    param ([switch]$wait)

    Invoke-Sound -filename 'prompt.mp3' -wait:$wait
}
