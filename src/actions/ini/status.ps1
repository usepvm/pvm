
function Get-IniExtensionStatus {
    param ($iniPath, $extNames)

    try {
        if ($extNames -isnot [array] -or $extNames.Count -eq 0) {
            Print-Warning -message "`nPlease provide at least one extension name to check status"
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
            Write-Color -message "- $name $($_.status)" -foreColor $_.color
        }

        if ($allMatchesListStatus.Count -eq 0) {
            Print-Error -message "`nNo extensions found matching the search term."
            return -1
        }

        $allMatchesListStatus | ForEach-Object {
            $name = "$($_.name) ".PadRight($maxLineLength, '.')
            Print-Host -message "- $name " -noNewLine
            Write-Color -message "$($_.status)" -foreColor $_.color
        }

        return $overallCode
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check status for '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
