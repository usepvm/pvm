
function Test-IsNotQuiet {
    param ($verbosity)

    return ($verbosity -ne 'None')
}

function Show-Scripts {
    Write-Cyan -message "`nAvailable scripts:"

    $scripts = Get-Scripts
    $scripts.Keys | ForEach-Object -Process {
        $name = $_
        $commands = $scripts[$_]
        Write-White -message "`n  $name"
        $commands | ForEach-Object -Process {
            $cmd = $_
            Write-DarkGray -message "   - $cmd"
        }
    }
}

function Use-PesterVersion {
    param ($version)

    Show-Info -message "`nChecking for Pester version: $version"

    $availableVersions = Get-Module -Name Pester -ListAvailable

    if (-not $availableVersions) {
        Show-Error -message "No Pester module found. Please install Pester first."
        return $false
    }

    $targetVersion = Find-PesterVersion -version $version -availableVersions $availableVersions

    if (-not $targetVersion) {
        $availableList = $availableVersions.Version -join ', '
        Show-Error -message "Pester version '$version' not found. Available versions: $availableList"
        return $false
    }

    return Import-PesterVersion -targetVersion $targetVersion
}

function Use-LatestPesterVersion {
    Show-Info -message "`nChecking for latest Pester version"

    $availableVersions = Get-Module -Name Pester -ListAvailable
    $targetVersion = Find-PesterVersion -version 'latest' -availableVersions $availableVersions

    return Import-PesterVersion -targetVersion $targetVersion
}

function Find-PesterVersion {
    param ($version, $availableVersions)

    if ([string]::IsNullOrWhiteSpace($version) -or $version -eq 'latest') {
        return $availableVersions | Sort-Object -Property Version -Descending | Select-Object -First 1
    }

    switch -Regex ($version) {
        '^\d+\.\d+\.\d+$' {
            return $availableVersions | Where-Object -FilterScript { $_.Version -eq $version } | Select-Object -First 1
        }
        '^\d+\.\d+$' {
            return $availableVersions | Where-Object -FilterScript { $_.Version -like "$version.*" } | Sort-Object -Property Version -Descending | Select-Object -First 1
        }
        '^\d+$' {
            return $availableVersions | Where-Object -FilterScript { $_.Version.Major -eq [int]$version } | Sort-Object -Property Version -Descending | Select-Object -First 1
        }
        default {
            return $availableVersions | Where-Object -FilterScript { $_.Version -le $version } | Sort-Object -Property Version -Descending | Select-Object -First 1
        }
    }
}

function Import-PesterVersion {
    param ($targetVersion)

    Import-Module -Name Pester -RequiredVersion $targetVersion.Version
    $pesterVersion = Get-Module -Name Pester

    return $pesterVersion
}

function Show-PesterVersion {
    param ($pesterVersion)

    Show-Info -message "Using Pester version: $($pesterVersion.Version)"

    Show-Info -message "`nPester Info:"
    Show-Message -message "  Version: $($pesterVersion.Version)"
    Show-Message -message "  Path: $($pesterVersion.Path)"
}

function Show-PesterVersionShort {
    param ($pesterVersion)

    Show-Message -message "Pester Version: $($pesterVersion.Version)"
}

function Show-PowerShellInfo {
    param ($psInfo)

    Show-Info -message "`nPowerShell Info:"
    Show-Message -message "  Engine: $($psInfo.Name)"
    Show-Message -message "  Version: $($psInfo.Version)"
    Show-Message -message "  Edition: $($psInfo.Edition)"
    Show-Message -message "  Platform: $($psInfo.Platform)"
    Show-Message -message "  Path: $($psInfo.Path)"
}

function Show-PowerShellInfoShort {
    param ($psInfo)

    Show-Message -message "PowerShell Version: $($psInfo.Version)"
}

function Get-TestsFiles {
    param ($testsNames = $null)

    $allTests = Get-ChildItemWrapper -path "$($PVMConfig.rootPath)\tests\*.tests.ps1" -recurse -file

    if (-not $testsNames) {
        return $allTests
    }

    $testsNames = @($testsNames | Select-Object -Unique)

    $matchedTests = $allTests | Where-Object -FilterScript {
        $testsNames -contains ($_.Name -replace '\.tests\.ps1$', '')
    }

    $foundNames = $matchedTests.Name -replace '\.tests\.ps1$', ''
    $missingNames = $testsNames | Where-Object -FilterScript { $foundNames -notcontains $_ }

    $missingFiles = $missingNames | ForEach-Object -Process {
        [PSCustomObject]@{
            Name     = "$_.tests.ps1"
            FullName = "$($PVMConfig.rootPath)\tests\$_.tests.ps1"
        }
    }

    return @($matchedTests) + @($missingFiles)
}

function Get-AllTestNames {
    param ($exclude = $null)

    return Get-ChildItemWrapper -path "$($PVMConfig.rootPath)\tests" -recurse -file -filter '*.tests.ps1' | ForEach-Object -Process {
        $name = $_.BaseName -replace '\.tests$'
        if ($name -notin $exclude) {
            return $name
        }
    }
}

function Get-CoveredSourceFile {
    param ($testFile, $testsMap)

    return $testsMap[$testFile.FullName]
}

function Get-TestsMap {
    $testsMap = @{}
    Get-ChildItemWrapper -path "$($PVMConfig.rootPath)\src" -recurse -filter '*.ps1' | ForEach-Object -Process {
        $testFile = $_.FullName -replace [regex]::Escape("$($PVMConfig.rootPath)\src"), "$($PVMConfig.rootPath)\tests"
        $testFile = $testFile -replace '.ps1', '.tests.ps1'
        $testsMap[$testFile] = $_
    }

    return $testsMap
}

function Set-CoverageConfig {
    param ($config, $testFile, $options, $testsMap)

    $covered = Get-CoveredSourceFile -testFile $testFile -testsMap $testsMap

    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $covered.FullName
    $outputPath = $covered.FullName -replace [regex]::Escape("$($PVMConfig.rootPath)\src"), ''
    $config.CodeCoverage.OutputPath = "$($PVMConfig.rootPath)\storage\coverage\$outputPath.xml"
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputEncoding = 'UTF8'
    $config.CodeCoverage.CoveragePercentTarget = $options.target

    return @{ covered = $covered; config = $config }
}

function Get-SeparatorWidth {
    param ($tests)

    $maxLen = ($tests | ForEach-Object -Process { ("$($_.Name) | $($_.FullName)").Length } | Measure-Object -Maximum).Maximum

    return $maxLen + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 5 / 2)
}

function Write-TestHeader {
    param ($file, $coveredFile, $separatorWidth)

    Show-Info -message "`n`n$('-' * $separatorWidth)"
    Show-Info -message "- Running test: $($file.Name) | $($file.FullName)"
    if ($coveredFile) {
        Show-Info -message "- Covered file: $($coveredFile.Name) | $($coveredFile.FullName)"
    }
    Show-Info -message ('-' * $separatorWidth)
}

function Format-TestResultMessage {
    param ($testResult, $rawDuration, $coverageRaw)

    $durationText = '-'
    $duration = Format-Seconds -totalSeconds $rawDuration
    if ($duration -ne -1) {
        $durationText = '{0,5:0.0}' -f $duration
    }

    if ($null -ne $coverageRaw) {
        $coverageText = '{0,6:00.00}%' -f $coverageRaw
        return 'Passed : {0,-4} | Failed : {1,-3} | Duration : {2,-5} | Coverage : {3,-7}' -f $testResult.PassedCount, $testResult.FailedCount, $durationText, $coverageText
    }

    return 'Passed : {0,-4} | Failed : {1,-3} | Duration : {2,-5}' -f $testResult.PassedCount, $testResult.FailedCount, $durationText
}

function Get-CoverageGroupName {
    param ($coverageRaw)

    if ($null -eq $coverageRaw) {
        return 'n/a'
    }

    if ($coverageRaw -ge 100) {
        return '100%'
    }

    if ($coverageRaw -ge 90) {
        return '90%+'
    }

    if ($coverageRaw -ge 80) {
        return '80%+'
    }

    if ($coverageRaw -ge 70) {
        return '70%+'
    }

    if ($coverageRaw -ge 60) {
        return '60%+'
    }

    if ($coverageRaw -ge 50) {
        return '50%+'
    }

    return '<50%'
}

function Get-FolderGroupName {
    param ($item)

    if ($item.Message -eq 'File not found!') {
        return 'n/a'
    }

    $parent = Split-Path -Path $item.relativeFilePath -Parent

    if (-not $parent) {
        return '(root)'
    }

    return ($parent -replace '\\', '/')
}

function Get-CoverageGroupRank {
    param ($groupName)

    $order = @('<50%', '50%+', '60%+', '70%+', '80%+', '90%+', '100%', 'n/a')
    $rank = [array]::IndexOf($order, $groupName)

    if ($rank -eq -1) { return 999 }

    return $rank
}

function Write-TestsSummary {
    param ($testData, $options, $maxLineLength)

    $sorted = Get-SortedTests -data $testData.testSummary -by $options.sortBy

    $groupExpr = switch ($options.groupBy) {
        'coverage' { { Get-CoverageGroupName -coverageRaw $_.testResultData.coverageRaw } }
        'folder'   { { Get-FolderGroupName -item $_ } }
        default    { $null }
    }

    $grouped = if ($groupExpr) { $sorted | Group-Object -Property $groupExpr } else { @(@{ Name = $null; Group = $sorted }) }

    if ($options.groupBy -eq 'coverage') {
        $grouped = $grouped | Sort-Object -Property { Get-CoverageGroupRank -groupName $_.Name }
    } elseif ($options.groupBy -eq 'folder') {
        $grouped = $grouped | Sort-Object -Property { $_.Name }
    }

    foreach ($group in $grouped) {
        New-Line
        if ($group.Name) { Show-Info -message "  [$($group.Name)]" }

        $group.Group | ForEach-Object -Process {
            $label = "    - $($_.sortedName) "
            $line = $label.PadRight($maxLineLength, '.') + " $($_.message.content)"
            Write-Color -message $line -foreColor $_.message.color
        }
    }
}

function Get-SortedTests {
    param ($data, $by = $null)

    if ($null -ne $by) {
        $direction = $by -match '^-'
        $by = $by -replace '-', ''
    }

    switch ($by) {
        'duration' {
            return $data | Sort-Object -Property @{
                Expression = {
                    if ($null -eq $_.testResultData.duration) {
                        [double]::PositiveInfinity
                    } else {
                        [double]$_.testResultData.duration
                    }
                }

                Descending = $direction
            }
        }
        'coverage' {
            return $data | Sort-Object -Property @{
                Expression = {
                    if ($null -eq $_.testResultData.coverageRaw) {
                        [double]::PositiveInfinity
                    } else {
                        [double]$_.testResultData.coverageRaw
                    }
                }

                Descending = $direction
            }
        }
        'file' {
            return $data | Sort-Object -Property @{ Expression = { [string]$_.sortedName }; Descending = $direction }
        }
    }

    return $data
}

