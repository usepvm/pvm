
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
        return $availableVersions | Sort-Object Version -Descending | Select-Object -First 1
    }

    switch -Regex ($version) {
        '^\d+\.\d+\.\d+$' {
            return $availableVersions | Where-Object { $_.Version -eq $version } | Select-Object -First 1
        }
        '^\d+\.\d+$' {
            return $availableVersions | Where-Object { $_.Version -like "$version.*" } | Sort-Object Version -Descending | Select-Object -First 1
        }
        '^\d+$' {
            return $availableVersions | Where-Object { $_.Version.Major -eq [int]$version } | Sort-Object Version -Descending | Select-Object -First 1
        }
        default {
            return $availableVersions | Where-Object { $_.Version -le $version } | Sort-Object Version -Descending | Select-Object -First 1
        }
    }
}

function Import-PesterVersion {
    param ($targetVersion)

    Import-Module Pester -RequiredVersion $targetVersion.Version -Force
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

function Get-PowerShellInfo {
    $psInfo = @{
        Version = $PSVersionTable.PSVersion
        Edition = $PSVersionTable.PSEdition
        Platform = if ($PSVersionTable.Platform) { $PSVersionTable.Platform } else { 'Windows' }
        Path = $PSHome
    }

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $psInfo.Name = 'PowerShell Core (pwsh)'
    } else {
        $psInfo.Name = 'Windows PowerShell (powershell)'
    }

    return $psInfo
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

function Get-PVMRootDirectory {
    return (Resolve-Path -Path "$PSScriptRoot\..\..").Path
}

function Get-TestsFiles {
    param ($testsNames = $null)

    $root = Get-PVMRootDirectory
    $allTests = Get-ChildItem -Path "$root\tests\*.tests.ps1" -Recurse -File

    if (-not $testsNames) {
        return $allTests
    }

    $testsNames = @($testsNames | Select-Object -Unique)

    $matchedTests = $allTests | Where-Object {
        $testsNames -contains ($_.Name -replace '\.tests\.ps1$', '')
    }

    $foundNames = $matchedTests.Name -replace '\.tests\.ps1$', ''
    $missingNames = $testsNames | Where-Object { $foundNames -notcontains $_ }

    $missingFiles = $missingNames | ForEach-Object {
        [PSCustomObject]@{
            Name     = "$_.tests.ps1"
            FullName = "$root\tests\$_.tests.ps1"
        }
    }

    return @($matchedTests) + @($missingFiles)
}

function Get-AllTestNames {
    param ($exclude = $null)

    $root = Get-PVMRootDirectory

    return Get-ChildItem -Path "$root\tests\*.tests.ps1" -Recurse -File | Where-Object {
        $name = $_.Name -replace '\.tests\.ps1$', ''
        -not ($exclude -contains $name)
    } | ForEach-Object {
        $_.Name -replace '\.tests\.ps1$', ''
    }
}

function Get-CoveredSourceFile {
    param ($testFile, $testsMap)

    return $testsMap[$testFile.FullName]
}

function Get-TestsMap {
    param ($root)

    $testsMap = @{}
    Get-ChildItem -Path "$root\src" -Recurse -Filter '*.ps1' | ForEach-Object {
        $testFile = $_.FullName -replace [regex]::Escape("$root\src"), "$root\tests"
        $testFile = $testFile -replace '.ps1', '.tests.ps1'
        $testsMap[$testFile] = $_
    }

    return $testsMap
}

function Initialize-PesterConfig {
    param ($options)

    $config = New-PesterConfiguration
    $config.Output.Verbosity = $options.verbosity

    if ($null -ne $options.tag) {
        $config.Filter.Tag = $options.tag
    }

    return $config
}

function Set-CoverageConfig {
    param ($config, $testFile, $options, $root, $testsMap)

    $covered = Get-CoveredSourceFile -testFile $testFile -testsMap $testsMap

    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $covered.FullName
    $outputPath = $covered.FullName -replace [regex]::Escape("$root\src"), ''
    $config.CodeCoverage.OutputPath = "$root\storage\coverage\$outputPath.xml"
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputEncoding = 'UTF8'
    $config.CodeCoverage.CoveragePercentTarget = $options.target

    return @{ covered = $covered; config = $config }
}

function Get-SeparatorWidth {
    param ($tests, $root)

    $maxLen = ($tests | ForEach-Object { ("$($_.Name) | $($_.FullName)").Length } | Measure-Object -Maximum).Maximum

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

function Invoke-TestFile {
    param ($config, $file = $null, $options = $null, $separatorWidth = 60, $testsMap = $null)

    $testResultData = @{ passedCount = 0; failedCount = 0; duration = 0; coverageRaw = $null }
    $root = Get-PVMRootDirectory
    $relativeFilePath = $file.FullName -replace [regex]::Escape("$root\tests\"), ''
    $sortedName = if ($options -and $options.groupBy -and $options.groupBy -eq 'folder') { $file.Name } else { $relativeFilePath }

    if (Test-FileNotExists -path $file.FullName) {
        return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; Message = 'File not found!'; testResultData = $testResultData }
    }

    if (-not $options) {
        $options = @{ coverage = $false; target = 75 }
    }

    $coveredFile = $null
    if ($options.coverage) {
        $coverageConfig = Set-CoverageConfig -config $config -testFile $file -options $options -root $root -testsMap $testsMap
        $coveredFile = $coverageConfig.covered
        $config = $coverageConfig.config
    }

    if (Test-IsNotQuiet -options $options) {
        Write-TestHeader -file $file -coveredFile $coveredFile -separatorWidth $separatorWidth
    }

    try {
        $config.Run.Path = $file.FullName
        $config.Run.PassThru = $true
        $testResult = Invoke-Pester -Configuration $config

        $rawDuration = $testResult.Duration.TotalSeconds

        if ($options.coverage) {
            $coverageRaw = [double]$testResult.CodeCoverage.CoveragePercent
        } else {
            $coverageRaw = $null
        }
        $message = Format-TestResultMessage -testResult $testResult -rawDuration $rawDuration -coverageRaw $coverageRaw

        $testResultData.passedCount = $testResult.PassedCount
        $testResultData.failedCount = $testResult.FailedCount
        $testResultData.duration = $rawDuration
        $testResultData.coverageRaw = $coverageRaw

        $code = if ($testResult.FailedCount -gt 0) { -1 } else { 0 }

        return @{ code = $code; Name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; Message = $message; testResultData = $testResultData }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"; exception = $_ }
        return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; Message = 'Failed to run test, check log.'; testResultData = $testResultData }
    }
}

function Initialize-Tests {
    param ($testsNames = $null, $options = $null, $exclude = $null, $pesterVersion = $null)

    if ($null -ne $exclude) {
        $testsNames = Get-AllTestNames -exclude $exclude
    }

    $tests = Get-TestsFiles -testsNames $testsNames

    return Invoke-Tests -tests $tests -options $options -pesterVersion $pesterVersion
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
    param ($relativeFilePath)

    $parent = Split-Path -Path $relativeFilePath -Parent

    if (-not $parent) {
        return '(root)'
    }

    return ($parent -replace '\\', '/')
}

function Get-ResultColor {
    param ($item, $target)

    if ($item.code -ne 0) { return 'DarkYellow' }

    if ($null -ne $item.testResultData.coverageRaw -and $item.testResultData.coverageRaw -lt $target) { return 'DarkGray' }

    return 'DarkGreen'
}

function Get-CoverageGroupRank {
    param ($groupName)

    $order = @('<50%', '50%+', '60%+', '70%+', '80%+', '90%+', '100%', 'n/a')
    $rank = [array]::IndexOf($order, $groupName)

    if ($rank -eq -1) { return 999 }

    return $rank
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

function Write-GroupedResults {
    param ($sorted, $groupExpr, $maxLineLength, $target, $groupBy = $null)

    $grouped = if ($groupExpr) { $sorted | Group-Object -Property $groupExpr } else { @(@{ Name = $null; Group = $sorted }) }

    if ($groupBy -eq 'coverage') {
        $grouped = $grouped | Sort-Object { Get-CoverageGroupRank -groupName $_.Name }
    } elseif ($groupBy -eq 'folder') {
        $grouped = $grouped | Sort-Object { $_.Name }
    }

    foreach ($group in $grouped) {
        if ($group.Name) { Show-Info -message "`n  [$($group.Name)]" }

        $group.Group | ForEach-Object {
            $label = "    - $($_.sortedName) "
            $line = $label.PadRight($maxLineLength, '.') + " $($_.Message)"
            Write-Color -message $line -foreColor (Get-ResultColor -item $_ -target $target)
        }
    }
}

function Write-TestsSummary {
    param ($testSummary, $options, $maxLineLength)

    $totalFailedTests = $testSummary | Where-Object { $_.code -ne 0 } | ForEach-Object { $_.testResultData.failedCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $totalDuration = $testSummary | ForEach-Object { $_.testResultData.duration } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    $totalDurationFormatted = Format-Seconds -totalSeconds $totalDuration

    if ($totalFailedTests -gt 0) {
        $color = 'DarkYellow'
    } else {
        $color = 'DarkGreen'
    }
    $content = " Files tested : $($testSummary.Count) | Total failed tests: $totalFailedTests"
    if ($totalDurationFormatted -ne -1) {
        $content += " | Total duration: $totalDurationFormatted"
    }
    Write-Color -message "$content`n" -foreColor $color

    $sorted = Sort-Tests -data $testSummary -by $options.sortBy

    $groupExpr = switch ($options.groupBy) {
        'coverage' { { Get-CoverageGroupName -coverageRaw $_.testResultData.coverageRaw } }
        'folder'   { { Get-FolderGroupName -item $_ } }
        default    { $null }
    }

    Write-GroupedResults -sorted $sorted -groupExpr $groupExpr -maxLineLength $maxLineLength -target $options.target -groupBy $options.groupBy

    if ($totalFailedTests -gt 0) {
        return -1
    } else {
        return 0
    }
}

function Invoke-Tests {
    param ($tests = $null, $options = $null, $pesterVersion = $null)

    try {
        if ($pesterVersion) {
            $pesterInfo = Use-PesterVersion -version $pesterVersion
        } else {
            $pesterInfo = Use-LatestPesterVersion
        }

        if (-not $pesterInfo) {
            Show-Error -message "`nNo Pester module found. Please install Pester first."
            return -1
        }

        if (-not $options) {
            $options = @{ verbosity = 'Normal'; coverage = $false; tag = $null; target = 75; groupBy = $null }
        }

        $verbosityOptions = @('None', 'Normal', 'Detailed', 'Diagnostic')
        if ($verbosityOptions -notcontains $options.verbosity) {
            Show-Error -message "`nInvalid verbosity option. Allowed values are: $($verbosityOptions -join ', ')"
            return -1
        }

        $psInfo = Get-PowerShellInfo
        if (Test-IsNotQuiet -options $options) {
            Show-PesterVersion -pesterVersion $pesterInfo
            Show-PowerShellInfo -psInfo $psInfo
        } else {
            Show-PesterVersionShort -pesterVersion $pesterInfo
            Show-PowerShellInfoShort -psInfo $psInfo
        }

        $config = Initialize-PesterConfig -options $options
        $separatorWidth = Get-SeparatorWidth -tests $tests
        $root = Get-PVMRootDirectory
        $testsMap = if ($options.coverage) { Get-TestsMap -root $root } else { $null }

        Show-Info -message "`nRunning tests with verbosity: $($options.verbosity)"

        $testSummary = $tests | ForEach-Object {
            Invoke-TestFile -config $config -file $_ -options $options -separatorWidth $separatorWidth -testsMap $testsMap
        }

        $maxLineLength = ($testSummary.relativeFilePath | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 3)

        Show-Message -message "`n----------------------------------------------------------------"
        Show-Message -message "`n`nTests Settings:"
        Show-Message -message " PowerShell Engine ..... $($psInfo.Name)"
        Show-Message -message " PowerShell ............ $($psInfo.Version)"
        Show-Message -message " Pester ................ $($pesterInfo.Version)"
        Show-Message -message "`nTest Results Summary:"
        Show-Message -message " Coverage .............. $($options.target)%"
        Show-Message -message " Verbosity ............. $($options.verbosity)`n"

        if ($testSummary.Count -eq 0) {
            Show-Error -message 'No tests found.'
            return -1
        }

        return Write-TestsSummary -testSummary $testSummary -options $options -maxLineLength $maxLineLength
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run tests"; exception = $_ }
        Show-Error -message "`nFailed to run tests, check log: $($PVMConfig.paths.logError)"
        return -1
    }
}

function Sort-Tests {
    param ($data, $by = $null)

    if ($null -ne $by) {
        $direction = $by -match '^-'
        $by = $by -replace '-', ''
    }

    switch ($by) {
        'duration' {
            return $data | Sort-Object @{
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
            return $data | Sort-Object @{
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
            return $data | Sort-Object @{ Expression = { [string]$_.sortedName }; Descending = $direction }
        }
    }

    return $data
}
