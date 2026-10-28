
function Disable-IniExtension {
    param ($iniPath, $extNames)

    try {
        if ($extNames -isnot [array] -or $extNames.Count -eq 0) {
            Show-LabelledWarning -message "Please provide at least one extension name to disable"
            return -1
        }

        $results = @()
        $overallCode = 0
        foreach ($extName in $extNames) {
            $matchesListStatus = Get-MatchingPHPExtensionsStatus -iniPath $iniPath -extName $extName

            if ($matchesListStatus.Length -eq 0) {
                $results += @{ name = $extName; status = 'Not found'; color = 'Gray' }
                $overallCode = -1
                continue
            }

            if ($matchesListStatus.Length -gt 1) {
                Write-Cyan -message "`nMultiple extensions match '$extName':" -underlined

                $maxLineLength = ($matchesListStatus.name | Measure-Object -Maximum Length).Maximum + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $index = 0
                $matchesListStatus | ForEach-Object -Process {
                    $name = "$($_.name) ".PadRight($maxLineLength, '.')
                    Show-Message -message "[$index] $name " -noNewLine
                    Write-Color -message "$($_.status)" -foreColor $_.color
                    $index++
                }

                do {
                    $choiceRaw = Read-HostWrapper -prompt "`nSelect a number"
                    $choice = $null

                    if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                        Show-Warning -message "`nPlease enter a valid positive number."
                        continue
                    }

                    if ($choice -lt 0 -or $choice -gt $matchesListStatus.Length - 1) {
                        Show-Warning -message "`nNumber must be between 0 and $($matchesListStatus.Length - 1)."
                        continue
                    }

                    break
                } while ($true)

                $selected = $matchesListStatus[$choice]
            } else {
                $selected = $($matchesListStatus)
            }

            if ($selected.status -eq 'Disabled') {
                $results += @{ name = $selected.name; status = 'Disabled'; color = 'DarkYellow' }
                continue
            }

            $lines = Get-ContentWrapper -path $iniPath

            $modified = $false
            $lineNumber = 0
            $updatedLines = $lines | ForEach-Object -Process {
                $lineNumber++
                if ($_ -eq $selected.line -and $selected.lineNumber -eq $lineNumber -and -not $modified -and ($_ -notmatch '^\s*;')) {
                    $modified = $true
                    return ";$_"
                }
                return $_
            }

            if (-not $modified) {
                $results += @{ name = $selected.name; status = 'Disabled'; color = 'DarkYellow' }
                continue
            }

            $null = Backup-IniFile -iniPath $iniPath
            $code = Set-ContentWrapper -path $iniPath -value $updatedLines
            $status = 'Disabled'
            $color = 'DarkYellow'
            if ($code -ne 0) {
                $status = 'Failed!'
                $color = 'DarkGray'
                $overallCode = -1
            }
            $results += @{ name = $selected.name; status = $status; color = $color }
        }

        $maxLineLength = ($results.name | Measure-Object -Maximum Length).Maximum + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        Write-White -message "`nResults:" -underlined
        foreach ($item in $results) {
            Show-Message -message "- $($item.name) ".PadRight($maxLineLength, '.') -noNewLine
            Write-Color -message " $($item.status)" -foreColor $item.color
        }

        return $overallCode
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to disable extension '$($extNames -join ', ')'"; exception = $_ }
        Show-LabelledError -message 'Failed to disable requested extensions'
        return -1
    }
}
