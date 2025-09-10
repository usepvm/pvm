
function Show-Usage {
    Write-Host "`nRunning version : $PVM_VERSION"
    Write-Host "`nUsage:`n"

    $maxLineLength = ($actions.GetEnumerator() | ForEach-Object { $_.Value.command.Length } | Measure-Object -Maximum).Maximum + 10   # Length for command + dots
    $maxDescLength = $Host.UI.RawUI.WindowSize.Width - ($maxLineLength + 20) # Max length per description line
    if ($maxDescLength -lt 100) { $maxDescLength = 100 }

    $actions.GetEnumerator() | ForEach-Object {
        $command = $_.Value.command
        $description = $_.Value.description

        # Dots for first line
        $dotsCount = [Math]::Max($maxLineLength - $command.Length, 0)
        $dots = '.' * $dotsCount

        # First line available space for description
        $descLines = @()

        # Wrap description by spaces without breaking words
        $remaining = $description
        while ($remaining.Length -gt $maxDescLength) {
            $breakPos = $remaining.LastIndexOf(' ', $maxDescLength)
            if ($breakPos -lt 0) { $breakPos = $maxDescLength } # fallback: break mid-word
            $descLines += $remaining.Substring(0, $breakPos)
            $remaining = $remaining.Substring($breakPos).Trim()
        }
        if ($remaining) { $descLines += $remaining }

        # Print first line (command + dots + first part of description)
        Write-Host "  $command $dots $($descLines[0])"

        # Print remaining description lines aligned with first description start
        $indent = (' ' * ($maxLineLength + 4))  # +1 for space after dots
        for ($i = 1; $i -lt $descLines.Count; $i++) {
            Write-Host "$indent$($descLines[$i])"
        }
    }
}

function Show-PVM-Version {
    Write-Host "`nPVM version $PVM_VERSION"
}

function Alias-Handler {
    param($alias)

    if ([string]::IsNullOrWhiteSpace($alias)) {
        return $null
    }

    $alias = $alias.Trim().ToLower()
    switch ($alias) {
        "ls" { return "list" }
        "rm" { return "uninstall" }
        "i"  { return "install" }
        "h"  { return "help" }
        Default { return $alias }
    }
}

function Allowed-Operations {
    return @("help", "setup", "log")
}

function Start-PVM {
    param ($operation, $arguments)
    try {
        
        if ($arguments -match '^(--version|-v)$' -or $operation -eq 'version') {
            Show-PVM-Version
            return 0
        }
        
        $actions = Get-Actions -arguments $arguments
        
        $operation = Alias-Handler -alias $operation
        
        if (-not ($operation -and $actions.Contains($operation))) {
            Show-Usage
            return 0
        }
        
        $allowedOperations = Allowed-Operations

        if (($allowedOperations -notcontains $operation) -and (-not (Is-PVM-Setup))) {
            Write-Host "`nPVM is not setup. Please run 'pvm setup' first."
            return -1
        }
        
        return $($actions[$operation].action.Invoke())
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - An error occurred during operation '$operation'"
            exception = $_
        }
        Write-Host "`nOperation canceled or failed to elevate privileges." -ForegroundColor DarkYellow
        return -1
    }
}