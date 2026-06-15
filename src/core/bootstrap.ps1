
function Show-Usage {
    Write-Host -Object "`nRunning version : $PVM_VERSION"
    Write-Host -Object "`nUsage:`n"

    $actions = Get-Actions -arguments $arguments
    $maxLineLength = ($actions.GetEnumerator() | ForEach-Object { $_.Value.command.Length } | Measure-Object -Maximum).Maximum + $MIN_PAD_RIGHT_LENGTH
    $maxDescLength = $Host.UI.RawUI.WindowSize.Width - ($maxLineLength + ($MIN_PAD_RIGHT_LENGTH * 2)) # Max length per description line
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
    Write-Host -Object "`nPVM version $PVM_VERSION"
}

function Get-NestedCommands {
    return @('ini', 'profile', 'cache')
}

function Get-Aliases {
    return @{
        '?'  = 'help';
        'h'  = 'help';
        'init' = 'setup';
        'cur' = 'current';
        'ls' = 'list';
        'i'  = 'install';
        'u'  = 'uninstall';
        'switch' = 'use';
        'on' = 'enable';
        'off' = 'disable';
        'a'  = 'add';
        '+'  = 'add';
        'rm' = 'remove';
        '-'  = 'remove';
        'del' = 'delete';
        'cls' = 'clear';
    }
}

function Resolve-Alias {
    param ($alias)

    if ([string]::IsNullOrWhiteSpace($alias)) {
        return $null
    }

    $alias = $alias.Trim().ToLower()
    $aliases = Get-Aliases

    if ($aliases.ContainsKey($alias)) {
        return $aliases[$alias]
    }
    
    return $alias
}

function Get-AllowedCommands {
    return @('help', 'setup', 'log')
}

function Start-PVM {
    param ($command, $arguments)

    try {
        if ([string]::IsNullOrWhiteSpace($command)) {
            Show-Usage
            return 0
        }

        $command = $command.Trim().ToLower()

        if ($arguments -match '^(--version|-v)$' -or $command -eq 'version') {
            Show-PVM-Version
            return 0
        }

        if ($command -like '*:*') {
            $splitted = $command.Split(':')
            $nestedCommand = $splitted[0]
            if ($nestedCommand -in (Get-NestedCommands)) {
                $command = $nestedCommand
                $arguments = @($splitted[1]) + $arguments
            }
        }

        $command = Resolve-Alias -alias $command

        $actions = Get-Actions -arguments $arguments

        if (-not $actions.Contains($command)) {
            Show-Usage
            return 0
        }

        $allowedCommands = Get-AllowedCommands

        if (($allowedCommands -notcontains $command) -and (-not (Is-PVM-Setup))) {
            Write-Host -Object "`nPVM is not setup. Please run 'pvm setup' first."
            return -1
        }

        return $($actions[$command].action.Invoke())
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - An error occurred during command '$command'"; exception = $_ }
        Write-Host -Object "`nCommand canceled or failed to elevate privileges." -ForegroundColor DarkYellow
        return -1
    }
}
