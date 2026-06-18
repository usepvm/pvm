
function Get-Tests-Files {
    param ($testsNames = $null)

    $PVMRootDirectory = (Resolve-Path -Path "$PSScriptRoot\..\..").Path

    $allTests = Get-ChildItem -Path "$PVMRootDirectory\tests\*.tests.ps1" -Recurse -File
    $tests = $allTests

    if ($testsNames) {
        $tests = $allTests | Where-Object {
            $fileTestName = $_.Name -replace '.tests.ps1', ''
            return ($testsNames -contains $fileTestName)
        }
    }

    return $tests
}

function Run-Test-File {
    param ($config, $file, $options = $null)

    try {
        $testResultData = @{
            passedCount = 0
            failedCount = 0
            duration    = 0
            coverageRaw = $null
        }

        $PVMRootDirectory = (Resolve-Path -Path "$PSScriptRoot\..\..").Path
        $relativeFilePath = $file.FullName -replace [regex]::Escape("$PVMRootDirectory\tests\"), ''

        if (Is-File-Not-Exists -path $file.FullName) {
            return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; Message = 'File not found!'; testResultData = $testResultData }
        }

        if (-not $options) {
            $options = @{ coverage = $false; target = 75 }
        }

        $coveredFile = $null
        if ($options.coverage) {
            $PVMRootDirectory = (Resolve-Path -Path "$PSScriptRoot\..\..").Path
            $covered = Get-ChildItem -Path "$PVMRootDirectory\src" -Recurse -Filter '*.ps1'
            $covered = Get-ChildItem -Path "$PVMRootDirectory\src" -Recurse -Filter '*.ps1' | Where-Object {
                $testFile = $file.FullName -replace [regex]::Escape("$PVMRootDirectory\tests"), ''
                $testFile = $testFile -replace '.tests.ps1', ''
                $fileToCover = $_.FullName -replace [regex]::Escape("$PVMRootDirectory\src"), ''
                $fileToCover = $fileToCover -replace '.ps1', ''

                return $fileToCover -eq $testFile
            }

            $config.CodeCoverage.Enabled = $true
            $config.CodeCoverage.Path = $covered.FullName
            $config.CodeCoverage.OutputPath = "$PVMRootDirectory\storage\coverage\$($file.Name).xml"
            $config.CodeCoverage.OutputFormat = 'JaCoCo' # 'CoverageGutters'
            $config.CodeCoverage.OutputEncoding = 'UTF8'
            $config.CodeCoverage.CoveragePercentTarget = $options.target
            $coveredFile = "$($covered.Name) | $($covered.FullName)"
        }

        $separatorWidth = [Math]::Max($file.Name.Length + $file.FullName.Length, $coveredFile.Length) + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 5 / 2)

        Write-Host -Object "`n`n$('-' * $separatorWidth)" -ForegroundColor Cyan
        Write-Host -Object "- Running test: $($file.Name) | $($file.FullName)" -ForegroundColor Cyan
        if ($coveredFile) {
            Write-Host -Object "- Covered file: $coveredFile" -ForegroundColor Cyan
        }
        Write-Host ('-' * $separatorWidth) -ForegroundColor Cyan

        $config.Run.Path = $file.FullName
        $config.Run.PassThru = $true
        $testResult = Invoke-Pester -Configuration $config
        $coverageRaw = $null
        $coverageText = '-'
        if ($options.coverage) {
            $coverageRaw = [double]$testResult.CodeCoverage.CoveragePercent
            $coverageText = '{0,6:00.00}%' -f $coverageRaw
        }
        $durationText = '-'
        $rawDuration = $testResult.Duration.TotalSeconds
        $duration = Format-Seconds -totalSeconds $rawDuration
        if ($duration -ne -1) {
            $durationText = '{0,5:0.0}' -f $duration
        }
        $message = (
            'Passed : {0,-4} | Failed : {1,-3} | Duration : {2,-5}' -f
            $testResult.PassedCount,
            $testResult.FailedCount,
            $durationText
        )
        if ($null -ne $coverageRaw) {
            $message = (
                'Passed : {0,-4} | Failed : {1,-3} | Duration : {2,-5} | Coverage : {3,-7}' -f
                $testResult.PassedCount,
                $testResult.FailedCount,
                $durationText,
                $coverageText
            )
        }

        $testResultData.passedCount = $testResult.PassedCount
        $testResultData.failedCount = $testResult.FailedCount
        $testResultData.duration = $rawDuration
        $testResultData.coverageRaw = $coverageRaw

        if ($LASTEXITCODE -ne 0) {
            return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; Message = $message; testResultData = $testResultData }
        }

        return @{ code = 0; Name = $file.Name; relativeFilePath = $relativeFilePath; Message = $message; testResultData = $testResultData }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"; exception = $_ }
        return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; Message = 'Failed to run test, check log.'; testResultData = $testResultData }
    }
}

function Prepare-Tests {
    param ($testsNames = $null, $options = $null, $exclude = $null)

    if ($null -ne $exclude) {
        $PVMRootDirectory = (Resolve-Path -Path "$PSScriptRoot\..\..").Path

        $testsNames = Get-ChildItem -Path "$PVMRootDirectory\tests\*.tests.ps1" -Recurse -File | Where-Object {
            return -not ($exclude -contains ($_.Name -replace '.tests.ps1', ''))
        } | ForEach-Object {
            return $_.Name -replace '.tests.ps1', ''
        }
    }

    $tests = Get-Tests-Files -testsNames $testsNames

    return Run-Tests -tests $tests -options $options
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

        $config = New-PesterConfiguration
        $config.Output.Verbosity = $options.verbosity

        if ($null -ne $options.tag) {
            $config.Filter.Tag = $options.tag
        }

        $testSummary = @()
        Write-Host -Object "`nRunning tests with verbosity: $($options.verbosity)" -ForegroundColor Cyan
        $tests | ForEach-Object {
            $testSummary += Run-Test-File -config $config -file $_ -options $options
        }

        Write-Host -Object "`n----------------------------------------------------------------"
        Write-Host -Object "`n`nTest Results Summary:"
        Write-Host -Object " Coverage : $($options.target)% | Verbosity: $($options.verbosity)`n"
        $code = 0
        if ($testSummary.Count -gt 0) {
            $totalFailedTests = $testSummary | Where-Object { $_.code -ne 0 } | ForEach-Object { $_.testResultData.failedCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            $totalDuration = $testSummary | ForEach-Object { $_.testResultData.duration } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            $totalDurationFormatted = Format-Seconds -totalSeconds $totalDuration
            if ($totalFailedTests -gt 0) { $code = -1; $color = 'DarkYellow' } else { $code = 0; $color = 'DarkGreen' }
            $content = " Files tested : $($testSummary.Count) | Total failed tests: $totalFailedTests"
            if ($totalDurationFormatted -ne -1) {
                $content += " | Total duration: $totalDurationFormatted"
            }
            $content += "`n"
            Write-Host -Object $content -ForegroundColor $color

            $maxLineLength = ($testSummary.relativeFilePath | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 3)

            $testSummary = SortBy -data $testSummary -sortByColumn $options.sortBy
            $testSummary | ForEach-Object {
                $label = "  - $($_.relativeFilePath) "
                $line = $label.PadRight($maxLineLength, '.') + " $($_.Message)"
                $color = 'DarkYellow'
                if ($_.code -eq 0) {
                    $color = 'DarkGreen'
                    if ($null -ne $_.testResultData.coverageRaw -and $_.testResultData.coverageRaw -lt $options.target) {
                        $color = 'DarkGray'
                    }
                }
                Write-Host -Object $line -ForegroundColor $color
            }
        } else {
            $code = -1
            Write-Host -Object 'No tests found.' -ForegroundColor DarkYellow
        }
        return $code
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
            return $data | Sort-Object `
            @{ Expression     = {
                    if ($null -eq $_.testResultData.duration) {
                        [double]::PositiveInfinity
                    } else {
                        [double]$_.testResultData.duration
                    }
                }; Descending = $direction
            }
        }
        'coverage' {
            return $data | Sort-Object `
            @{ Expression     = {
                    if ($null -eq $_.testResultData.coverageRaw) {
                        [double]::PositiveInfinity
                    } else {
                        [double]$_.testResultData.coverageRaw
                    }
                }; Descending = $direction
            }
        }
        'file' {
            return $data | Sort-Object @{ Expression = { [string]$_.relativeFilePath }; Descending = $direction }
        }
    }

    return $data;
}
