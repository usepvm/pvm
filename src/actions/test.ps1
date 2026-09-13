
function Initialize-PVMTestEnvironment {
    param ($driveName)

    $environment = @{
        PVMConfigBackup = Copy-ObjectDeep -object $Global:PVMConfig
        TestDrive       = "$($Global:PVMConfig.paths.directories.fakeStorage)\$driveName-drive"
    }

    Clear-PVMTestStorage
    $Global:PVMConfig.test.setFakePaths.Invoke($environment.TestDrive)

    New-Directory -path $environment.TestDrive

    return $environment
}

function Restore-PVMTestEnvironment {
    param ($environment)

    Remove-ItemWrapper -path $environment.TestDrive
    $Global:PVMConfig   = $environment.PVMConfigBackup
}

function Get-PowerShellInfo {
    $psInfo = @{
        Version = $PSVersionTable.PSVersion
        Edition = $PSVersionTable.PSEdition
        Platform = if ($PSVersionTable.Platform) { $PSVersionTable.Platform } else { 'Windows' }
        Path = $PSHome
    }

    $psInfo.Name = if ($PSVersionTable.PSVersion.Major -ge 6) { 'PowerShell Core (pwsh)' } else { 'Windows PowerShell (powershell)' }

    return $psInfo
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

function Invoke-TestFile {
    param ($config, $file = $null, $options = $null, $separatorWidth = 60, $testsMap = $null)

    $testResultData = @{ passedCount = 0; failedCount = 0; duration = 0; coverageRaw = $null }
    $relativeFilePath = $file.FullName -replace [regex]::Escape("$($PVMConfig.rootPath)\tests\"), ''
    $sortedName = if ($options -and $options.groupBy -and $options.groupBy -eq 'folder') { $file.Name } else { $relativeFilePath }

    if (Test-FileNotExists -path $file.FullName) {
        $testResultData.failedCount = 1
        return @{ code = -1; name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; message = @{ content = 'File not found!'; color = 'DarkYellow' }; testResultData = $testResultData }
    }

    if (-not $options) {
        $options = @{ coverage = $PVMConfig.test.coverage.enabled; target = $PVMConfig.test.coverage.default }
    }

    $coveredFile = $null
    if ($options.coverage) {
        $coverageConfig = Set-CoverageConfig -config $config -testFile $file -options $options -testsMap $testsMap
        $coveredFile = $coverageConfig.covered
        $config = $coverageConfig.config
    }

    if (Test-IsNotQuiet -verbosity $options.verbosity) {
        Write-TestHeader -file $file -coveredFile $coveredFile -separatorWidth $separatorWidth
    }

    try {
        $config.Run.Path = $file.FullName
        $config.Run.PassThru = $true
        $testResult = Invoke-Pester -Configuration $config

        $rawDuration = $testResult.Duration.TotalSeconds

        $coverageRaw = if ($options.coverage) { [double]$testResult.CodeCoverage.CoveragePercent } else { $null }

        $testResultData.passedCount = $testResult.PassedCount
        $testResultData.failedCount = $testResult.FailedCount
        $testResultData.totalCount = $testResult.TotalCount
        $testResultData.duration = $rawDuration
        $testResultData.coverageRaw = $coverageRaw
        $testResultData.CodeCoverage = $testResult.CodeCoverage

        $code = if ($testResult.FailedCount -gt 0) { -1 } else { 0 }

        if ($testResult.FailedCount -gt 0) {
            $color = 'DarkYellow'
        } elseif ($null -ne $coverageRaw -and $coverageRaw -lt $options.target) {
            $color = 'DarkGray'
        } else { $color = 'DarkGreen' }

        $message = @{
            content = Format-TestResultMessage -testResult $testResult -rawDuration $rawDuration -coverageRaw $coverageRaw
            color = $color
        }

        return @{ code = $code; name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; message = $message; testResultData = $testResultData }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"; exception = $_ }
        return @{ code = -1; name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; message = @{ content = 'Failed to run test, check log.'; color = 'DarkYellow' }; testResultData = $testResultData }
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

function Invoke-Tests {
    param ($tests = $null, $options = $null, $pesterVersion = $null)

    try {
        $pesterInfo = if ($pesterVersion) { Use-PesterVersion -version $pesterVersion } else { Use-LatestPesterVersion }

        if (-not $pesterInfo) {
            Show-Error -message "`nNo Pester module found. Please install Pester first."
            return -1
        }

        if (-not $options) {
            $options = @{
                verbosity = $PVMConfig.test.verbosity.default;
                coverage = $PVMConfig.test.coverage.enabled;
                target = $PVMConfig.test.coverage.default;
                tag = $null;
                groupBy = $null
            }
        }

        $verbosityOptions = $PVMConfig.test.verbosity.options
        if ($verbosityOptions -notcontains $options.verbosity) {
            Show-Error -message "`nInvalid verbosity option. Allowed values are: $($verbosityOptions -join ', ')"
            return -1
        }

        $psInfo = Get-PowerShellInfo
        if (Test-IsNotQuiet -verbosity $options.verbosity) {
            Show-PesterVersion -pesterVersion $pesterInfo
            Show-PowerShellInfo -psInfo $psInfo
        } else {
            Show-PesterVersionShort -pesterVersion $pesterInfo
            Show-PowerShellInfoShort -psInfo $psInfo
        }

        $config = Initialize-PesterConfig -options $options
        $separatorWidth = Get-SeparatorWidth -tests $tests
        $testsMap = if ($options.coverage) { Get-TestsMap } else { $null }

        Show-Info -message "`nRunning tests with verbosity: $($options.verbosity)"

        $testSummary = $tests | ForEach-Object -Process {
            Invoke-TestFile -config $config -file $_ -options $options -separatorWidth $separatorWidth -testsMap $testsMap
        }

        $maxLineLength = ($testSummary.relativeFilePath | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 3)

        Show-Message -message "`n----------------------------------------------------------------"
        Show-Message -message "`n`nTests Settings:"
        Show-Message -message " PowerShell Engine ..... $($psInfo.Name)"
        Show-Message -message " PowerShell ............ $($psInfo.Version)"
        Show-Message -message " Pester ................ $($pesterInfo.Version)"
        Show-Message -message " Coverage .............. $($options.target)%"
        Show-Message -message " Verbosity ............. $($options.verbosity)`n"

        if ($testSummary.Length -eq 0) {
            Show-Error -message 'No tests found.'
            return -1
        }

        $totalAnalyzed = 0
        $totalExecuted = 0
        $testSummary | ForEach-Object -Process {
            $totalAnalyzed += [double]$_.testResultData.CodeCoverage.CommandsAnalyzedCount
            $totalExecuted += [double]$_.testResultData.CodeCoverage.CommandsExecutedCount
        }
        $totalCoverage = if ($totalAnalyzed -gt 0) { [math]::Round(($totalExecuted / $totalAnalyzed) * 100, 2) } else { 0 }

        $testData = @{
            testSummary = $testSummary
            totalFailedTests = $testSummary | ForEach-Object -Process { $_.testResultData.failedCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            totalPassedTests = $testSummary | ForEach-Object -Process { $_.testResultData.passedCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            totalTests = $testSummary | ForEach-Object -Process { $_.testResultData.totalCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            totalDuration = $testSummary | ForEach-Object -Process { $_.testResultData.duration } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            totalCoverage = $totalCoverage
        }

        $totalDurationFormatted = Format-Seconds -totalSeconds $testData.totalDuration

        Show-Message -message "Test Results Summary:"
        Show-Message -message " Files tested ........... $($testData.testSummary.Length)"
        Show-Message -message " Total tests ............ $($testData.totalTests)"
        Show-Message -message " Total passed ........... $($testData.totalPassedTests)"
        Show-Message -message " Total failed ........... $($testData.totalFailedTests)"
        Show-Message -message " Total coverage ......... $($testData.totalCoverage)%"
        if ($totalDurationFormatted -ne -1) {
            Show-Message -message " Total duration ......... $totalDurationFormatted"
        }

        Write-TestsSummary -testData $testData -options $options -maxLineLength $maxLineLength

        if ($testData.totalFailedTests -gt 0) {
            Invoke-ErrorSound -wait
            return -1
        }

        Invoke-SuccessSound -wait
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run tests"; exception = $_ }
        Show-Error -message "`nFailed to run tests, check log: $($PVMConfig.paths.files.logError)"
        return -1
    }
}
