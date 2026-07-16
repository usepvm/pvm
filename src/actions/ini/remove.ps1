
function Remove-Extension-From-Ini-File {
    param ($iniPath, $extensionObject)

    try {
        $lines = Get-Content -Path $iniPath
        $newLines = @()
        $lineNumber = 1
        foreach ($line in $lines) {
            if ($line -ne $extensionObject.line -or $lineNumber -ne $extensionObject.lineNumber) {
                $newLines += $line
            }

            $lineNumber++
        }
        if ($newLines.Count -eq $lines.Count) {
            return -1
        }

        Set-Content -Path $iniPath -Value $newLines -Encoding UTF8

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to remove extension from php.ini"; exception = $_ }
        return -1
    }
}

function Remove-Extension-From-Ext-Directory {
    param ($extensionDirectory, $extensionObject)

    try {
        $extensionFullPath = "$extensionDirectory\$($extensionObject.fileName)"

        if (Test-File-Not-Exists -path $extensionFullPath) {
            return -1
        }

        if ($extensionObject.fullPath -ne $extensionFullPath) {
            return -1
        }

        Remove-Item -Path $extensionFullPath -Force -ErrorAction Stop

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to remove extension '$($extensionObject.name)' from ext directory"; exception = $_ }
        return -1
    }
}

function Uninstall-Extension {
    param ($iniPath, $extNames, $skipConfirmation = $false)

    try {
        if ($extNames.Count -eq 0) {
            Print-Warning -message "`nPlease provide at least one extension name to uninstall"
            return -1
        }

        $phpDirectory = Split-Path -Path $iniPath -Parent
        $extDirectory = "$phpDirectory\ext"

        if (Test-Directory-Not-Exists -path $extDirectory) {
            Print-Error -Message "`nExtensions directory not found: $extDirectory"
            return -1
        }

        $overallCode = 0
        $results = @()
        foreach ($extName in $extNames) {
            $matchingExtensions = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName
            if ($matchingExtensions.Length -eq 0) {
                $results += @{ name = $extName; status = 'Not Found'; color = 'DarkYellow' }
                $overallCode = -1
                continue
            }

            if ($matchingExtensions.Length -gt 1) {
                Print-Info -message "`nMultiple extensions match '$extName':`n"

                $maxLineLength = ($matchingExtensions.name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
                $index = 0
                $matchingExtensions | ForEach-Object {
                    $name = "$($_.name) ".PadRight($maxLineLength, '.')
                    Print-Host -message "[$index] $name " -noNewLine
                    Write-Color -message "$($_.status)" -foreColor $_.color
                    $index++
                }

                do {
                    $choiceRaw = Read-Host -Prompt "`nSelect a number"
                    $choice = $null

                    if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                        Print-Warning -message 'Please enter a valid positive number.'
                        continue
                    }

                    if ($choice -lt 0 -or $choice -gt $matchingExtensions.Length - 1) {
                        Print-Warning -message "Number must be between 0 and $($matchingExtensions.Length - 1)."
                        continue
                    }

                    break
                } while ($true)

                $selected = $matchingExtensions[$choice]
            } else {
                $selected = $($matchingExtensions)
            }

            if (-not $skipConfirmation) {
                $response = Read-Host -Prompt "`nAre you sure you want to uninstall '$($selected.name)'? (y/n)"
                $response = $response.Trim()
                if ($response -ne 'y' -and $response -ne 'Y') {
                    $results += @{ name = $selected.name; status = 'Uninstallation cancelled'; color = 'Gray' }
                    $overallCode = -1
                    continue
                }
            }

            if (Test-File-Not-Exists -path $selected.fullPath) {
                $results += @{ name = $extName; status = 'Not Found'; color = 'DarkYellow' }
                $overallCode = -1
                continue
            }

            $code = Remove-Extension-From-Ext-Directory -extensionDirectory $extDirectory -extensionObject $selected
            if ($code -ne 0) {
                $results += @{ name = $extName; status = "Failed to remove '$($selected.name)' from ext directory"; color = 'DarkYellow' }
                $overallCode = -1
                continue
            }

            if ($selected.source -like '*ini*') {
                $code = Remove-Extension-From-Ini-File -iniPath $iniPath -extensionObject $selected
                if ($code -ne 0) {
                    $results += @{ name = $extName; status = "Failed to remove '$($selected.name)' from php.ini"; color = 'DarkYellow' }
                    $overallCode = -1
                    continue
                }
            }

            $results += @{ name = $extName; status = 'Uninstalled'; color = 'DarkGreen' }
        }

        $maxLineLength = ($results.name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        Print-Host -message "`nResults:"
        foreach ($item in $results) {
            Print-Host -message "- $($item.name) ".PadRight($maxLineLength, '.') -noNewLine
            Write-Color -message " $($item.status)" -foreColor $item.color
        }

        return $overallCode
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to install '$($extNames -join ', ')'"; exception = $_ }
        return -1
    }
}
