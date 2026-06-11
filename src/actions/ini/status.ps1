
function Get-IniExtensionStatus {
    param ($iniPath, $extNames)

    try {
        if ($extNames -isnot [array] -or $extNames.Count -eq 0) {
            Write-Host "`nPlease provide at least one extension name to check status"
            return -1
        }

        $allMatchesListStatus = @()
        $notFound = @()
        $overallCode = 0
        foreach ($extName in $extNames) {
            $matchesListStatus = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName
            if ($matchesListStatus.Length -eq 0) {
                $notFound += (@{
                    name = $extName
                    status = 'Not found'
                    color = 'Gray'
                })
                $overallCode = -1
                continue
            }

            $allMatchesListStatus += $matchesListStatus
        }

        $maxLineLength = ($allMatchesListStatus.name | Measure-Object -Maximum Length).Maximum + $MIN_PAD_RIGHT_LENGTH
        $notFound | ForEach-Object {
            $name = "$($_.name) ".PadRight($maxLineLength, '.')
            Write-Host "- $name $($_.status)" -ForegroundColor $_.color
        }

        if ($allMatchesListStatus.Count -eq 0) {
            Write-Host "`nNo extensions found matching the search term."
            return -1
        }

        $allMatchesListStatus | ForEach-Object {
            $name = "$($_.name) ".PadRight($maxLineLength, '.')
            Write-Host "- $name " -NoNewline
            Write-Host "$($_.status)" -ForegroundColor $_.color
        }

        return $overallCode
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check status for '$extName'"; exception = $_ }
        return -1
    }
}
