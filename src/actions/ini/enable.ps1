
function Enable-IniExtension {
    param ($iniPath, $extNames)

    try {
        if ($extNames -isnot [array] -or $extNames.Count -eq 0) {
            Write-Host -Object "`nPlease provide at least one extension name to enable"
            return -1
        }

        $results = @()
        $overallCode = 0
        foreach ($extName in $extNames) {
            $matchesListStatus = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName

            if ($matchesListStatus.Length -eq 0) {
                # Write-Host -Object "- '$extName': extension not found" -ForegroundColor DarkGray
                $results += @{ name = $extName; status = 'Not found'; color = 'Gray' }
                $overallCode = -1
                continue
            }

            if ($matchesListStatus.Length -gt 1) {
                Write-Host -Object "`nMultiple extensions match '$extName':`n" -ForegroundColor Cyan

                $maxLineLength = ($matchesListStatus.name | Measure-Object -Maximum Length).Maximum + $PVMConfig.env.MIN_PAD_RIGHT_LENGTH
                $index = 0
                $matchesListStatus | ForEach-Object {
                    $name = "$($_.name) ".PadRight($maxLineLength, '.')
                    Write-Host -Object "[$index] $name " -NoNewline
                    Write-Host -Object "$($_.status)" -ForegroundColor $_.color
                    $index++
                }

                do {
                    $choiceRaw = Read-Host -Prompt "`nSelect a number"
                    $choice = $null

                    if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                        Write-Host -Object 'Please enter a valid positive number.' -ForegroundColor Yellow
                        continue
                    }

                    if ($choice -lt 0 -or $choice -gt $matchesListStatus.Length - 1) {
                        Write-Host -Object "Number must be between 0 and $($matchesListStatus.Length - 1)." -ForegroundColor Yellow
                        continue
                    }

                    break
                } while ($true)

                $selected = $matchesListStatus[$choice]
            } else {
                $selected = $($matchesListStatus)
            }

            if ($selected.status -eq 'Enabled') {
                # Write-Host -Object "- '$($selected.name)' enabled successfully." -ForegroundColor DarkGreen
                $results += @{ name = $selected.name; status = 'Enabled'; color = 'DarkGreen' }
                continue
            }

            $lines = Get-Content -Path $iniPath

            $modified = $false
            $lineNumber = 0
            $newLines = $lines | ForEach-Object {
                $lineNumber++
                if ($_ -eq $selected.line -and $selected.lineNumber -eq $lineNumber -and -not $modified) {
                    $modified = $true
                    return $_ -replace '^[#;]\s*', ''
                }
                return $_
            }

            if (-not $modified) {
                # Write-Host -Object "- '$($selected.name)' enabled successfully." -ForegroundColor DarkGreen
                $results += @{ name = $selected.name; status = 'Enabled'; color = 'DarkGreen' }
                continue
            }

            Backup-IniFile -iniPath $iniPath
            Set-Content -Path $iniPath $newLines -Encoding UTF8

            $results += @{ name = $selected.name; status = 'Enabled'; color = 'DarkGreen' }
            # Write-Host -Object "- '$($selected.name)' enabled successfully." -ForegroundColor DarkGreen
        }

        $maxLineLength = ($results.name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        Write-Host -Object "`nResults:"
        foreach ($item in $results) {
            Write-Host -Object "- $($item.name) ".PadRight($maxLineLength, '.') -NoNewline
            Write-Host -Object " $($item.status)" -ForegroundColor $item.color
        }

        return $overallCode
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to enable extension '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
