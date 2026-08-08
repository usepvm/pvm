
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
    param ($scriptName, $files = @())

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
            try {
                Write-Gray -message "Command: pvm $scriptCommand"
                $parts = $scriptCommand -split ' '
                $command = $parts[0]
                $scriptArgs = if ($parts.Count -gt 1) { $parts[1..($parts.Count - 1)] } else { @() }

                if ($command -ne 'test') {
                    Write-Yellow -message "`nInvalid command in script: '$command'`n"
                    $results += @{ code = -1; output = $null }
                    continue
                }

                if ($runInSubProcess) {
                    $verbosityArg = $scriptArgs | Where-Object { $_ -match '^--verbosity=' }
                    if ($verbosityArg -and $verbosityArg -ne '--verbosity=None') {
                        Write-Yellow -message "`nInvalid verbosity in multi-command script '$scriptName': '$scriptCommand' (only --verbosity=None is allowed when a script has more than one command)`n"
                        $results += @{ code = -2; output = $null }
                        continue
                    }

                    $scriptArgs = $scriptArgs + $files
                    $result = Invoke-PVMSubprocess -command $command -arguments $scriptArgs
                    $results += $result
                } else {
                    $actions = Get-Actions -arguments $scriptArgs
                    $result = $($actions[$command].data.action.Invoke())
                    return $result
                }

                Show-SubProcessOutput -output $result.output
                New-Lines -count 3
            } catch {
                Write-Yellow -message "`nFailed to run command: pvm $scriptCommand, check logs at '$($PVMConfig.paths.logError)'`n"
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run script"; exception = $_ }
                $results += @{ code = -1; output = $null }
            }
        }

        if ($results | Where-Object { $_ -and $_.code -eq -1 }) {
            Invoke-ErrorSound
            return -1
        }

        if ($results | Where-Object { $_ -and $_.code -eq -2 }) {
            Invoke-NotifySound
            return -1
        }

        Invoke-SuccessSound
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run script"; exception = $_ }
        return -1
    }
}
