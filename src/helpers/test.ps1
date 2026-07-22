
function Test-IsNotQuiet {
    param ($options)

    return ($options.verbosity -ne 'None')
}

function Show-Scripts {
    Write-Cyan -message "`nAvailable scripts:"

    $scripts = Get-Scripts
    $scripts.Keys | ForEach-Object {
        $name = $_
        $commands = $scripts[$_]
        Write-White -message "`n  $name"
        $commands | ForEach-Object {
            $cmd = $_
            Write-DarkGray -message "   - $cmd"
        }
    }
}
