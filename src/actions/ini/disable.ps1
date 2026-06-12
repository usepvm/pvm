
function Disable-IniExtension {
    param ($iniPath, $extNames)

    try {
        if ($extNames -isnot [array] -or $extNames.Count -eq 0) {
            Write-Host "`nPlease provide at least one extension name to disable"
            return -1
        }

        $results = @()
        $overallCode = 0
        foreach ($extName in $extNames) {
            $matchesListStatus = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName

            if ($matchesListStatus.Length -eq 0) {
                # Write-Host "- '$extName'`: extension not found" -ForegroundColor DarkGray
                $results += @{ name = $extName; status = 'Not found'; color = 'Gray' }
                $overallCode = -1
                continue
            }

            if ($matchesListStatus.Length -gt 1) {
                Write-Host "`nMultiple extensions match '$extName':`n" -ForegroundColor Cyan

                $maxLineLength = ($matchesListStatus.name | Measure-Object -Maximum Length).Maximum + $MIN_PAD_RIGHT_LENGTH
                $index = 0
                $matchesListStatus | ForEach-Object {
                    $name = "$($_.name) ".PadRight($maxLineLength, '.')
                    Write-Host "[$index] $name " -NoNewline
                    Write-Host "$($_.status)" -ForegroundColor $_.color
                    $index++
                }

                do {
                    $choiceRaw = Read-Host "`nSelect a number"
                    $choice = $null

                    if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                        Write-Host 'Please enter a valid positive number.' -ForegroundColor Yellow
                        continue
                    }

                    if ($choice -lt 0 -or $choice -gt $matchesListStatus.Length - 1) {
                        Write-Host "Number must be between 0 and $($matchesListStatus.Length - 1)." -ForegroundColor Yellow
                        continue
                    }

                    break
                } while ($true)

                $selected = $matchesListStatus[$choice]
            } else {
                $selected = $($matchesListStatus)
            }

            if ($selected.status -eq 'Disabled') {
                # Write-Host "- '$($selected.name)' disabled successfully." -ForegroundColor DarkGreen
                $results += @{ name = $selected.name; status = 'Disabled'; color = 'DarkYellow' }
                continue
            }

            $lines = Get-Content $iniPath

            $modified = $false
            $lineNumber = 0
            $updatedLines = $lines | ForEach-Object {
                $lineNumber++
                if ($_ -eq $selected.line -and $selected.lineNumber -eq $lineNumber -and -not $modified -and ($_ -notmatch '^\s*;')) {
                    $modified = $true
                    return ";$_"
                }
                return $_
            }

            if (-not $modified) {
                # Write-Host "- '$($selected.name)' disabled successfully." -ForegroundColor DarkGreen
                $results += @{ name = $selected.name; status = 'Disabled'; color = 'DarkYellow' }
                continue
            }

            Backup-IniFile $iniPath
            Set-Content $iniPath $updatedLines -Encoding UTF8
            # Write-Host "- '$($selected.name)' disabled successfully." -ForegroundColor DarkGreen
            $results += @{ name = $selected.name; status = 'Disabled'; color = 'DarkYellow' }
        }

        $maxLineLength = ($results.name | Measure-Object -Maximum Length).Maximum + ($MIN_PAD_RIGHT_LENGTH * 2)
        Write-Host "`nResults:"
        foreach ($item in $results) {
            Write-Host "- $($item.name) ".PadRight($maxLineLength, '.') -NoNewline
            Write-Host " $($item.status)" -ForegroundColor $item.color
        }

        return $overallCode
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to disable extension '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
