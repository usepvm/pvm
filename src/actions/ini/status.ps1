
function Get-IniExtensionStatus {
    param ($iniPath, $extNames)

    try {
        if ($extNames -isnot [array] -or $extNames.Count -eq 0) {
            Write-Host -Object "`nPlease provide at least one extension name to check status"
            return -1
        }

        $allMatchesListStatus = @()
        $notFound = @()
        $overallCode = 0
        foreach ($extName in $extNames) {
            $matchesListStatus = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName -includeIniOnly $true
            if ($matchesListStatus.Length -eq 0) {
                $notFound += (
                    @{
                        name   = $extName
                        status = 'Not found'
                        color  = 'Gray'
                    }
                )
                $overallCode = -1
                continue
            }

            $allMatchesListStatus += $matchesListStatus
        }

        $maxLineLength = ($allMatchesListStatus.name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        $notFound | ForEach-Object {
            $name = "$($_.name) ".PadRight($maxLineLength, '.')
            Write-Host -Object "- $name $($_.status)" -ForegroundColor $_.color
        }

        if ($allMatchesListStatus.Count -eq 0) {
            Write-Host -Object "`nNo extensions found matching the search term."
            return -1
        }

        $allMatchesListStatus | ForEach-Object {
            $name = "$($_.name) ".PadRight($maxLineLength, '.')
            Write-Host -Object "- $name " -NoNewline
            Write-Host -Object "$($_.status)" -ForegroundColor $_.color
        }

        return $overallCode
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check status for '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
