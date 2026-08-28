
function Test-IsNotQuiet {
    param ($verbosity)

    return ($verbosity -ne 'None')
}

function Show-Scripts {
    Write-Cyan -message "`nAvailable scripts:"

    $scripts = Get-Scripts
    $scripts.Keys | ForEach-Object -Process {
        $name = $_
        $commands = $scripts[$_]
        Write-White -message "`n  $name"
        $commands | ForEach-Object -Process {
            $cmd = $_
            Write-DarkGray -message "   - $cmd"
        }
    }
}
