
function Show-SubProcessOutput {
    param ($output)

    if ($output -is [string]) {
        try {
            $structured = @($output | ConvertFrom-Json)
            if ($structured -is [array]) {
                foreach ($item in $structured) {
                    Write-Color -message $item.message -foreColor $item.color -noNewLine:$item.noNewLine
                }
            }
        } catch {
            foreach ($line in $output) {
                Show-Message -message $line
            }
        }
    } else {
        foreach ($line in $output) {
            Show-Message -message $line
        }
    }
}

function Invoke-RunScripts {
    param ($scriptName)

    try {
        if ([string]::IsNullOrWhiteSpace($scriptName)) {
            Write-Yellow -message "`nPlease provide a script name to run: pvm run <script-name>"
            Show-Scripts
            return -1
        }

        if ($scriptName -eq 'list') {
            Show-Scripts
            return 0
        }

        $scripts = Get-Scripts
        if (-not $scripts.Contains($scriptName)) {
            Write-Yellow -message "`nScript '$scriptName' not found."
            Show-Scripts
            return -1
        }

        $scriptCommands = $scripts[$scriptName]

        Write-Cyan -message "`nRunning script: $scriptName ($($scriptCommands.Count) commands)`n"

        $runInSubProcess = $scriptCommands.Count -gt 1
        $results = @()
        foreach ($scriptCommand in $scriptCommands) {
            Write-Gray -message "Command: pvm $scriptCommand"
            $parts = $scriptCommand -split ' '
            $command = $parts[0]
            $scriptArgs = if ($parts.Count -gt 1) { $parts[1..($parts.Count - 1)] } else { @() }

            if ($command -ne 'test') {
                Write-Yellow -message "`nInvalid command in script: '$command'`n"
                $results += -1
                continue
            }

            if ($runInSubProcess) {
                $result = Invoke-PVMSubprocess -command $command -arguments $scriptArgs
                $results += $result
            } else {
                $actions = Get-Actions -arguments $scriptArgs
                $result = $($actions[$command].action.Invoke())
                return $result
            }

            Show-SubProcessOutput -output $result.output
            New-Lines -count 3
        }

        if ($results | Where-Object { $_ -and $_.code -ne 0 }) { return -1 }
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run script"; exception = $_ }
        return -1
    }
}
