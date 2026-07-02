
function Show-Usage {
    Write-Host -Object "`nRunning version : $($PVMConfig.version)"
    Write-Host -Object "`nUsage:`n"

    $actions = Get-Actions -arguments $arguments
    $maxLineLength = ($actions.GetEnumerator() | ForEach-Object { $_.Value.command.Length } | Measure-Object -Maximum).Maximum + $PVMConfig.env.MIN_PAD_RIGHT_LENGTH
    $maxDescLength = (Get-Console-Width) - ($maxLineLength + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2))
    if ($maxDescLength -lt 100) { $maxDescLength = 100 }

    $actions.GetEnumerator() | ForEach-Object {
        $command = $_.Value.command
        $description = $_.Value.description

        # Wrap description by spaces without breaking words
        $descLines = @()
        $remaining = $description
        while ($remaining.Length -gt $maxDescLength) {
            $breakPos = $remaining.LastIndexOf(' ', $maxDescLength)
            if ($breakPos -lt 0) { $breakPos = $maxDescLength } # fallback: break mid-word
            $descLines += $remaining.Substring(0, $breakPos)
            $remaining = $remaining.Substring($breakPos).Trim()
        }
        if ($remaining) { $descLines += $remaining }

        # First line (command + dots + description)
        $label = "  $command "
        $line = $label.PadRight($maxLineLength, '.') + " $($descLines[0])"
        Write-Host -Object $line

        # Remaining description lines aligned under description column
        $indent = ' ' * ($maxLineLength + 1)
        for ($i = 1; $i -lt $descLines.Count; $i++) {
            Write-Host -Object "$indent$($descLines[$i])"
        }
    }
}

function Show-PVM-Version {
    Write-Host -Object "`nPVM version $($PVMConfig.version)"
}

function Get-NestedCommands {
    return @('ini', 'profile', 'cache', 'help')
}

function Resolve-NestedCommand {
    param ($command, $arguments)

    if ($command -notlike '*:*') {
        return $command, $arguments
    }

    $splitted = $command.Split(':')
    $nestedCommand = $splitted[0]

    if ($nestedCommand -in (Get-NestedCommands)) {
        return $nestedCommand, (@($splitted[1]) + $arguments)
    }

    return $command, $arguments
}

function Get-AllowedCommands {
    return @('help', 'setup', 'log', 'update')
}

function Start-PVM {
    param ($command, $arguments)

    try {
        $arguments = @($arguments | Where-Object { $_ -ne $null })

        if ([string]::IsNullOrWhiteSpace($command) -and $arguments.Count -eq 0) {
            Show-Usage
            return 0
        }

        if ([string]::IsNullOrWhiteSpace($command)) {
            $flagCommand = Resolve-FlagCommand -arguments $arguments
            if ($flagCommand) {
                $command   = $flagCommand
                $arguments = @($arguments | Where-Object { -not (Get-FlagMap).Contains($_) })
            }
        } else {
            $command = $command.Trim().ToLower()
        }

        $command, $arguments = Resolve-NestedCommand -command $command -arguments $arguments

        $command = Resolve-Alias -alias $command

        if ([string]::IsNullOrWhiteSpace($command)) {
            Show-Usage
            return 0
        }

        $actions = Get-Actions -arguments $arguments

        if (-not $actions.Contains($command)) {
            Write-Host -Object "`n'$command' is not a valid command." -ForegroundColor DarkYellow
            Show-Usage
            return 0
        }

        $allowedCommands = Get-AllowedCommands

        if (($allowedCommands -notcontains $command) -and (Is-PVM-Not-Setup)) {
            Write-Host -Object "`nPVM is not setup. Please run 'pvm setup' first."
            return -1
        }

        return $($actions[$command].action.Invoke())
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - An error occurred during command '$command'"; exception = $_ }
        Write-Host -Object "`nCommand canceled or failed to elevate privileges." -ForegroundColor DarkYellow
        return -1
    }
}
