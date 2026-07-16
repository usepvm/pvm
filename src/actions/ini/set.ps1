
function Set-IniSetting {
    param ($iniPath, $keys, $enable = $true)

    try {
        if ($keys -isnot [array] -or $keys.Count -eq 0) {
            Print-Warning -message "`nPlease specify at least one 'key=value' (pvm ini set memory_limit=512M)."
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
                Print-Error -message 'Invalid input.'
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
                Print-Info -message "`nMultiple settings match '$searchKey':`n"

                $maxLineLength = ($matchesList.name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $index = 0
                $matchesList | ForEach-Object {
                    $k = "$($_.name) ".PadRight($maxLineLength, '.')
                    $v = if ($_.value -eq '') { '(not set)' } else { $_.value }
                    Print-Host -message "[$index] $k $v " -noNewLine
                    Write-Color -message $_.status -foreColor $_.color
                    $index++
                }

                do {
                    $choiceRaw = Read-Host -Prompt "`nSelect a number"
                    $choice = $null

                    if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                        Print-Warning -message 'Please enter a valid positive number.'
                        continue
                    }

                    if ($choice -lt 0 -or $choice -gt $matchesList.Length - 1) {
                        Print-Warning -message "Number must be between 0 and $($matchesList.Length - 1)."
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

            $null = Backup-IniFile -iniPath $iniPath

            $lines = Get-Content -Path $iniPath
            $lines[$selected.lineNo] = $newLine
            Set-Content -Path $iniPath -Value $lines -Encoding UTF8

            $status = if ($enable) { 'Enabled' } else { 'Disabled' }
            $color = if ($enable) { 'DarkGreen' } else { 'DarkYellow' }

            $updatedSettings[$selected.name] = @{ key = $selected.name; value = $inputValue; status = $status; color = $color }
        }

        $updatedSettings = $notFound + $updatedSettings

        $maxLineLength = ($updatedSettings.Values | ForEach-Object { $_.key } | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        Print-Host -message "`n" -noNewLine
        foreach ($key in $updatedSettings.Keys) {
            $item = $updatedSettings[$key]
            $name = "$($item.key) ".PadRight($maxLineLength, '.')
            Print-Host -message "- $name $($item.value) " -noNewLine
            Write-Color -message $item.status -foreColor $item.color
        }

        return $overallCode
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set ini setting '$($keys -join ', ')'"; exception = $_ }
        return -1
    }
}
