
function Get-PowerShell-Info {
    $psInfo = @{
        Name = $PSVersionTable.PSVersion.ToString()
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

function Write-PowerShell-Info {
    $psInfo = Get-PowerShell-Info
    Write-Host -Object "`nPowerShell Info:" -ForegroundColor Cyan
    Write-Host -Object "  Engine: $($psInfo.Name)" -ForegroundColor Gray
    Write-Host -Object "  Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
    Write-Host -Object "  Edition: $($psInfo.Edition)" -ForegroundColor Gray
    Write-Host -Object "  Platform: $($psInfo.Platform)" -ForegroundColor Gray
    Write-Host -Object "  Path: $($psInfo.Path)" -ForegroundColor Gray
}

function Get-PVMRootDirectory {
    return (Resolve-Path -Path "$PSScriptRoot\..\..").Path
}

function Get-Tests-Files {
    param ($testsNames = $null)

    $root = Get-PVMRootDirectory
    $allTests = Get-ChildItem -Path "$root\tests\*.tests.ps1" -Recurse -File

    if (-not $testsNames) {
        return $allTests
    }

    return $allTests | Where-Object {
        $testsNames -contains ($_.Name -replace '\.tests\.ps1$', '')
    }
}

function Get-All-Test-Names {
    param ($exclude = $null)

    $root = Get-PVMRootDirectory

    return Get-ChildItem -Path "$root\tests\*.tests.ps1" -Recurse -File | Where-Object {
        $name = $_.Name -replace '\.tests\.ps1$', ''
        -not ($exclude -contains $name)
    } | ForEach-Object {
        $_.Name -replace '\.tests\.ps1$', ''
    }
}

function Get-Covered-Source-File {
    param ($testFile, $root)

    $testsMap = Get-Tests-Map -root $root

    return $testsMap[$testFile.FullName]
}

function Get-Tests-Map {
    param ($root)

    $testsMap = @{}
    Get-ChildItem -Path "$root\src" -Recurse -Filter '*.ps1' | ForEach-Object {
        $testFile = $_.FullName -replace [regex]::Escape("$root\src"), "$root\tests"
        $testFile = $testFile -replace '.ps1', '.tests.ps1'
        $testsMap += @{ $testFile = $_ }
    }

    return $testsMap
}

function Build-Pester-Config {
    param ($options)

    $config = New-PesterConfiguration
    $config.Output.Verbosity = $options.verbosity

    if ($null -ne $options.tag) {
        $config.Filter.Tag = $options.tag
    }

    return $config
}

function Set-Coverage-Config {
    param ($config, $testFile, $options, $root)

    $covered = Get-Covered-Source-File -testFile $testFile -root $root

    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = $covered.FullName
    $outputPath = $covered.FullName -replace [regex]::Escape("$root\src"), ''
    $config.CodeCoverage.OutputPath = "$root\storage\coverage\$outputPath.xml"
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputEncoding = 'UTF8'
    $config.CodeCoverage.CoveragePercentTarget = $options.target

    return @{ covered = $covered; config = $config }
}

function Get-Separator-Width {
    param ($tests, $root)

    $maxLen = ($tests | ForEach-Object { ("$($_.Name) | $($_.FullName)").Length } | Measure-Object -Maximum).Maximum

    return $maxLen + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 5 / 2)
}

function Write-Test-Header {
    param ($file, $coveredFile, $separatorWidth)

    Write-Host -Object "`n`n$('-' * $separatorWidth)" -ForegroundColor Cyan
    Write-Host -Object "- Running test: $($file.Name) | $($file.FullName)" -ForegroundColor Cyan
    if ($coveredFile) {
        Write-Host -Object "- Covered file: $($coveredFile.Name) | $($coveredFile.FullName)" -ForegroundColor Cyan
    }
    Write-Host -Object ('-' * $separatorWidth) -ForegroundColor Cyan
}

function Format-Test-Result-Message {
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

function Run-Test-File {
    param ($config, $file, $options = $null, $separatorWidth = 60)

    $testResultData = @{ passedCount = 0; failedCount = 0; duration = 0; coverageRaw = $null }
    $root = Get-PVMRootDirectory
    $relativeFilePath = $file.FullName -replace [regex]::Escape("$root\tests\"), ''

    if (Is-File-Not-Exists -path $file.FullName) {
        return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; Message = 'File not found!'; testResultData = $testResultData }
    }

    if (-not $options) {
        $options = @{ coverage = $false; target = 75 }
    }

    $coveredFile = $null
    if ($options.coverage) {
        $coverageConfig = Set-Coverage-Config -config $config -testFile $file -options $options -root $root
        $coveredFile = $coverageConfig.covered
        $config = $coverageConfig.config
    }

    Write-Test-Header -file $file -coveredFile $coveredFile -separatorWidth $separatorWidth

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
        $message = Format-Test-Result-Message -testResult $testResult -rawDuration $rawDuration -coverageRaw $coverageRaw

        $testResultData.passedCount = $testResult.PassedCount
        $testResultData.failedCount = $testResult.FailedCount
        $testResultData.duration = $rawDuration
        $testResultData.coverageRaw = $coverageRaw

        if ($LASTEXITCODE -ne 0) {
            $code = -1
        } else {
            $code = 0
        }

        return @{ code = $code; Name = $file.Name; relativeFilePath = $relativeFilePath; Message = $message; testResultData = $testResultData }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"; exception = $_ }
        return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; Message = 'Failed to run test, check log.'; testResultData = $testResultData }
    }
}

function Prepare-Tests {
    param ($testsNames = $null, $options = $null, $exclude = $null)

    if ($null -ne $exclude) {
        $testsNames = Get-All-Test-Names -exclude $exclude
    }

    $tests = Get-Tests-Files -testsNames $testsNames

    return Run-Tests -tests $tests -options $options
}

function Write-Tests-Summary {
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
    Write-Host -Object "$content`n" -ForegroundColor $color

    $sorted = SortBy -data $testSummary -sortByColumn $options.sortBy
    $sorted | ForEach-Object {
        $label = "  - $($_.relativeFilePath) "
        $line = $label.PadRight($maxLineLength, '.') + " $($_.Message)"
        $color = 'DarkYellow'
        if ($_.code -eq 0) {
            if ($null -ne $_.testResultData.coverageRaw -and $_.testResultData.coverageRaw -lt $options.target) {
                $color = 'DarkGray'
            } else {
                $color = 'DarkGreen'
            }
        }
        Write-Host -Object $line -ForegroundColor $color
    }

    if ($totalFailedTests -gt 0) {
        return -1
    } else {
        return 0
    }
}

function Run-Tests {
    param ($tests = $null, $options = $null)

    try {
        if (-not $options) {
            $options = @{ verbosity = 'Normal'; coverage = $false; tag = $null; target = 75 }
        }

        $verbosityOptions = @('None', 'Normal', 'Detailed', 'Diagnostic')
        if ($verbosityOptions -notcontains $options.verbosity) {
            Write-Host -Object "`nInvalid verbosity option. Allowed values are: $($verbosityOptions -join ', ')" -ForegroundColor DarkYellow
            return -1
        }

        $config = Build-Pester-Config -options $options
        $separatorWidth = Get-Separator-Width -tests $tests

        Write-PowerShell-Info
        Write-Host -Object "`nRunning tests with verbosity: $($options.verbosity)" -ForegroundColor Cyan

        $testSummary = $tests | ForEach-Object {
            Run-Test-File -config $config -file $_ -options $options -separatorWidth $separatorWidth
        }

        $maxLineLength = ($testSummary.relativeFilePath | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 3)

        Write-Host -Object "`n----------------------------------------------------------------"
        Write-Host -Object "`n`nTest Results Summary:"
        Write-Host -Object " Coverage : $($options.target)% | Verbosity: $($options.verbosity)`n"

        if ($testSummary.Count -eq 0) {
            Write-Host -Object 'No tests found.' -ForegroundColor DarkYellow
            return -1
        }

        return Write-Tests-Summary -testSummary $testSummary -options $options -maxLineLength $maxLineLength
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run tests"; exception = $_ }
        Write-Host -Object "`nFailed to run tests, check log: $($PVMConfig.paths.logError)" -ForegroundColor DarkYellow
        return -1
    }
}

function SortBy {
    param ($data, $sortByColumn = $null)

    if ($null -ne $sortByColumn) {
        $direction = $sortByColumn -match '^-'
        $sortByColumn = $sortByColumn -replace '-', ''
    }

    switch ($sortByColumn) {
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
            return $data | Sort-Object @{ Expression = { [string]$_.relativeFilePath }; Descending = $direction }
        }
    }

    return $data
}
