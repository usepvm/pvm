
function Show-Usage {
    param ($arguments)

    Show-Message -message "`nRunning version : $($PVMConfig.version)"
    Show-Message -message "`nUsage:`n"

    $actions = Get-Actions -arguments $arguments
    $maxLineLength = ($actions.GetEnumerator() | ForEach-Object { $_.Value.command.Length } | Measure-Object -Maximum).Maximum + $PVMConfig.env.MIN_PAD_RIGHT_LENGTH
    $maxDescLength = (Get-ConsoleWidth) - ($maxLineLength + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2))
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
        Show-Message -message $line

        # Remaining description lines aligned under description column
        $indent = ' ' * ($maxLineLength + 1)
        for ($i = 1; $i -lt $descLines.Count; $i++) {
            Show-Message -message "$indent$($descLines[$i])"
        }
    }
}

function Show-PVMVersion {
    Show-Message -message "`nPVM version $($PVMConfig.version)"
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
    return @('help', 'setup', 'repair', 'log', 'update')
}

function Get-LevenshteinDistance {
    param ($first, $second)

    if ($first -eq $second) {
        return 0
    }

    if ([string]::IsNullOrEmpty($first)) {
        return $second.Length
    }

    if ([string]::IsNullOrEmpty($second)) {
        return $first.Length
    }

    $firstChars = $first.ToCharArray()
    $secondChars = $second.ToCharArray()

    $previousRow = 0..$secondChars.Length
    $currentRow = New-Object 'int[]' ($secondChars.Length + 1)

    for ($i = 1; $i -le $firstChars.Length; $i++) {
        $currentRow[0] = $i

        for ($j = 1; $j -le $secondChars.Length; $j++) {
            $cost = if ($firstChars[$i - 1] -eq $secondChars[$j - 1]) { 0 } else { 1 }
            $deletion = $previousRow[$j] + 1
            $insertion = $currentRow[$j - 1] + 1
            $substitution = $previousRow[$j - 1] + $cost
            $currentRow[$j] = [Math]::Min([Math]::Min($deletion, $insertion), $substitution)
        }

        $temp = $previousRow
        $previousRow = $currentRow
        $currentRow = $temp
    }

    return $previousRow[$secondChars.Length]
}

function Get-ClosestCommandSuggestion {
    param ($command, $actions)

    if ([string]::IsNullOrWhiteSpace($command)) {
        return $null
    }

    $command = $command.Trim().ToLower()
    $actionCandidates = @()
    if ($null -ne $actions) {
        $actionCandidates = $actions.Keys | ForEach-Object { $_.ToLower() } | Select-Object -Unique
    }

    $aliases = Get-Aliases
    $aliasCandidates = @()
    $aliasTargets = @()
    if ($null -ne $aliases) {
        $aliasCandidates = $aliases.Keys | ForEach-Object { $_.ToLower() } | Select-Object -Unique
        $aliasTargets = $aliases.Values | ForEach-Object { $_.ToLower() } | Select-Object -Unique
    }

    $bestDistance = [int]::MaxValue
    $bestCandidate = $null

    foreach ($candidate in $actionCandidates) {
        if ($candidate.StartsWith($command) -or $command.StartsWith($candidate)) {
            $bestDistance = -1
            $bestCandidate = $candidate
            break
        }

        $distance = Get-LevenshteinDistance -first $command -second $candidate
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $bestCandidate = $candidate
        }
    }

    if ($bestDistance -ne -1) {
        foreach ($candidate in $aliasCandidates) {
            $distance = Get-LevenshteinDistance -first $command -second $candidate
            if ($distance -lt $bestDistance) {
                $bestDistance = $distance
                $bestCandidate = $candidate
            }
        }
        foreach ($candidate in $aliasTargets) {
            $distance = Get-LevenshteinDistance -first $command -second $candidate
            if ($distance -lt $bestDistance) {
                $bestDistance = $distance
                $bestCandidate = $candidate
            }
        }
    }

    if ($null -eq $bestCandidate) {
        return $null
    }

    if ($bestDistance -ge 0) {
        switch ($command.Length) {
            { $_ -le 4 } { $maxDistance = 1; break }
            { $_ -le 8 } { $maxDistance = 2; break }
            { $_ -le 12 } { $maxDistance = 3; break }
            default { $maxDistance = 4; break }
        }

        if ($bestDistance -gt $maxDistance) {
            return $null
        }
    }

    if ($aliases.Contains($bestCandidate)) {
        return $aliases[$bestCandidate]
    }

    return $bestCandidate
}

function Start-PVM {
    param ($command, $arguments)

    try {
        $arguments = @($arguments | Where-Object { $_ -ne $null })

        if ([string]::IsNullOrWhiteSpace($command) -and $arguments.Count -eq 0) {
            Show-Usage -arguments $arguments
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

        $alias = $command
        $command = Resolve-Alias -alias $command

        if ([string]::IsNullOrWhiteSpace($command)) {
            Show-Usage -arguments $arguments
            return 0
        }

        $actions = Get-Actions -arguments $arguments

        if (-not $actions.Contains($command)) {
            $suggestion = Get-ClosestCommandSuggestion -command $command -actions $actions
            if ([string]::IsNullOrWhiteSpace($suggestion)) {
                Show-Error -Message "`n'$alias' is not a valid command."
            } else {
                Show-Error -Message "`n'$command' is not a valid command. Did you mean '$suggestion'?"
            }
            Show-Usage -arguments $arguments
            return 0
        }

        $allowedCommands = Get-AllowedCommands

        if (($allowedCommands -notcontains $command) -and (Test-PVMNotSetup)) {
            Show-Message -message "`nPVM is not setup. Please run 'pvm setup' first."
            return -1
        }

        $result = $($actions[$command].action.Invoke())

        # Check for updates after successful command execution (skip for update command itself)
        if ($result -eq 0 -and $command -ne 'update') {
            $null = (Test-CheckForUpdatesQuietly)
        }

        return $result
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - An error occurred during command '$command'"; exception = $_ }
        Show-Error -Message "`nCommand canceled or failed to elevate privileges."
        return -1
    }
}
