
param( [string]$operation )


$ProgressPreference = 'SilentlyContinue'


# Load configuration
Get-ChildItem "$PSScriptRoot\core\*.ps1" | ForEach-Object { . $_.FullName }

# Load actions scripts
Get-ChildItem "$PSScriptRoot\actions\*.ps1" | ForEach-Object { . $_.FullName }

if (-not $operation -and $args.Count -eq 0) {
    Write-Host "pvm --help to get the list of commands"
    exit 1
}

$actions = Get-Actions -arguments $args

if (-not $actions.Contains($operation)) {
    $version = (Get-Current-PHP-Version).version
    if ($version) {
        Write-Host "`nRunning version : $version"
    }
    Write-Host "`nUsage:`n"
    $maxLineLength = 60
    $actions.GetEnumerator() | ForEach-Object {
        $dotsCount = $maxLineLength - $_.Value.command.Length
        if ($dotsCount -lt 0) { $dotsCount = 0 }
        $dots = '.' * $dotsCount
        Write-Host "$($_.Value.command) $dots $($_.Value.description)"
    }
    exit 0
}

try {
    if ($operation -ne "setup" -and (-not (Is-PVM-Setup))) {
        Write-Host "`nPVM is not setup. Please run 'pvm setup' first."
        exit 1
    }

    $actions[$operation].action.Invoke()
} catch {
    $logged = Log-Data -logPath $LOG_ERROR_PATH -message "PVM: An error occurred during operation '$operation'" -data $_.Exception.Message
    Write-Host "`nOperation canceled or failed to elevate privileges." -ForegroundColor DarkYellow
    exit 1
}