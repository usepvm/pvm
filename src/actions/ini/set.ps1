
function Set-IniSetting {
    param ($iniPath, $keys, $enable = $true)

    try {
        if ($keys -isnot [array] -or $keys.Count -eq 0) {
            Write-Host -Object "`nPlease specify at least one 'key=value' (pvm ini set memory_limit=512M)."
            return -1
        }

        $updatedSettings = [ordered]@{}
        $notFound = [ordered]@{}
        $overallCode = 0
        foreach ($key in $keys) {
            # Parse optional inline value from key=value syntax
            if ($key -match '^(?<k>[^=]+)(=(?<v>.*))?$') {
                $searchKey = $matches['k'].Trim()
                $inputValue = if ($null -ne $matches['v']) { $matches['v'].Trim() } else { $null }
            } else {
                Write-Host -Object 'Invalid input.' -ForegroundColor DarkGray
                $overallCode = -1
                continue
            }

            $matchesList = Get-Matching-PHPSettings -iniPath $iniPath -searchKey $searchKey

            if ($matchesList.Count -eq 0) {
                if ($notFound.Keys -notcontains $key) {
                    $notFound[$key] += @{ key = $searchKey; value = $null; status = 'Not Found'; color = 'Gray' }
                }

                $overallCode = -1
                continue
            }

            if ($matchesList.Length -gt 1) {
                Write-Host -Object "`nMultiple settings match '$searchKey':`n" -ForegroundColor Cyan

                $maxLineLength = ($matchesList.name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $index = 0
                $matchesList | ForEach-Object {
                    $k = "$($_.name) ".PadRight($maxLineLength, '.')
                    $v = if ($_.value -eq '') { '(not set)' } else { $_.value }
                    Write-Host -Object "[$index] $k $v " -NoNewline
                    Write-Host -Object $_.status -ForegroundColor $_.color
                    $index++
                }

                do {
                    $choiceRaw = Read-Host -Prompt "`nSelect a number"
                    $choice = $null

                    if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                        Write-Host -Object 'Please enter a valid positive number.' -ForegroundColor Yellow
                        continue
                    }

                    if ($choice -lt 0 -or $choice -gt $matchesList.Length - 1) {
                        Write-Host -Object "Number must be between 0 and $($matchesList.Length - 1)." -ForegroundColor Yellow
                        continue
                    }

                    break
                } while ($true)

                $selected = $matchesList[$choice]
            } else {
                $selected = $($matchesList)
            }

            if (-not $inputValue) {
                $inputValue = Read-Host -Prompt "Enter new value for '$($selected.name)'"
            }

            $newLine = if ($enable) { "$($selected.name) = $inputValue" } else { ";$($selected.name) = $inputValue" }

            Backup-IniFile -iniPath $iniPath

            $lines = Get-Content -Path $iniPath
            $lines[$selected.lineNo] = $newLine
            Set-Content -Path $iniPath $lines -Encoding UTF8

            $status = if ($enable) { 'Enabled' } else { 'Disabled' }
            $color = if ($enable) { 'DarkGreen' } else { 'DarkYellow' }

            $updatedSettings[$selected.name] = @{ key = $selected.name; value = $inputValue; status = $status; color = $color }
        }

        $updatedSettings = $notFound + $updatedSettings

        $maxLineLength = ($updatedSettings.Values | ForEach-Object { $_.key } | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        Write-Host -Object "`n" -NoNewline
        foreach ($key in $updatedSettings.Keys) {
            $item = $updatedSettings[$key]
            $name = "$($item.key) ".PadRight($maxLineLength, '.')
            Write-Host -Object "- $name $($item.value) " -NoNewline
            Write-Host -Object $item.status -ForegroundColor $item.color
        }

        return $overallCode
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set ini setting '$($keys -join ', ')'"; exception = $_ }
        return -1
    }
}
