
function Get-Tests-Files {
    param ($tests = $null)
    
    if ($tests) {
        $tests = $tests | ForEach-Object {
            return @{
                Name = "$_.tests.ps1"
                FullName = "$PVMRoot\tests\$_.tests.ps1"
            }
        }
    } else {
        $tests = Get-ChildItem "$PVMRoot\tests\*.tests.ps1" | ForEach-Object {
            return @{
                Name = $_.Name
                FullName = $_.FullName
            }
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
            duration = 0
            coverageRaw = $null
        }
        
        if (-not (Test-Path $file.FullName)) {
            return @{ code = -1; Name = $file.Name; Message = "File not found!"; testResultData = $testResultData }
        }
        
        if (-not $options) {
            $options = @{ coverage = $false; target = 75 }
        }

        $coveredFile = ""
        if ($options.coverage) {
            $PVMRootDirectory = (Resolve-Path "$PSScriptRoot\..\..").Path
            $covered = Get-ChildItem -Path "$PVMRootDirectory\src" -Recurse -Filter "*.ps1"
            $covered = $covered | Where-Object {
                return ($_.Name -replace '.ps1','') -eq ($file.Name -replace '.tests.ps1','')
            }
                
            $config.CodeCoverage.Enabled = $true
            $config.CodeCoverage.Path = $covered.FullName
            $config.CodeCoverage.OutputPath = "$PVMRootDirectory\storage\coverage\$($file.Name).xml"
            $config.CodeCoverage.OutputFormat = 'JaCoCo' # 'CoverageGutters'
            $config.CodeCoverage.OutputEncoding = 'UTF8'
            $config.CodeCoverage.CoveragePercentTarget = $options.target
            $coveredFile = "(covers: $($covered.Name))"
        }
        
        Write-Host "`n----------------------------------------------------------------"
        Write-Host "- Running test: $($file.Name) $coveredFile"
        Write-Host "----------------------------------------------------------------"


        $config.Run.Path = $file.FullName
        $config.Run.PassThru = $true
        $testResult = Invoke-Pester -Configuration $config
        $coverageRaw = $null
        $coverageText = "-"
        if ($testResult.CodeCoverage.CoveragePercent) {
            $coverageRaw = [double]$testResult.CodeCoverage.CoveragePercent
            $coverageText = '{0,6:00.00}%' -f $coverageRaw
        }
        $durationText = "-"
        $rawDuration = $testResult.Duration.TotalSeconds
        $duration = Format-Seconds -totalSeconds $rawDuration
        if ($duration -ne -1) {
            $durationText = $duration
        }
        $message = (
            'Passed : {0,-4} | Failed : {1,-4} | Duration : {2,-6}' -f
            $testResult.PassedCount,
            $testResult.FailedCount,
            $durationText
        )
        if ($coverageRaw) {
            $message = (
                'Passed : {0,-4} | Failed : {1,-4} | Duration : {2,-6} | Coverage : {3,-7}' -f
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
            return @{ code = -1; Name = $file.Name; Message = $message; testResultData = $testResultData }
        }
        
        return @{ code = 0; Name = $file.Name; Message = $message; testResultData = $testResultData }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"
            exception = $_
        }
        return @{ code = -1; Name = $file.Name; Message = "Failed to run test, check log."; testResultData = $testResultData }
    }
}

function Run-Tests {
    param ($tests = $null, $options = $null)
    
    try {
        if (-not $options) {
            $options = @{ verbosity = "Normal"; coverage = $false; tag = $null; target = 75 }
        }
        
        $verbosityOptions = @('None', 'Normal', 'Detailed', 'Diagnostic')
        if ($verbosityOptions -notcontains $options.verbosity) {
            Write-Host "`nInvalid verbosity option. Allowed values are: $($verbosityOptions -join ', ')" -ForegroundColor DarkYellow
            return -1
        }

        $config = New-PesterConfiguration
        $config.Output.Verbosity = $options.verbosity
        
        $tests = Get-Tests-Files -tests $tests
        
        if ($null -ne $options.tag) {
            $config.Filter.Tag = $options.tag
        }
        
        $testSummary = @()
        Write-Host "`nRunning tests with verbosity: $($options.verbosity)" -ForegroundColor Cyan
        $tests | ForEach-Object { 
            $testResult = Run-Test-File -config $config -file $_ -options $options
            $testSummary += $testResult
        }
        
        Write-Host "`n----------------------------------------------------------------"
        Write-Host "`n`nTest Results Summary: (Coverage : $($options.target)%)`n"
        $code = 0
        if ($testSummary.Count -gt 0) {
            $totalFailedTests = $testSummary | Where-Object { $_.code -ne 0 } | ForEach-Object { $_.testResultData.failedCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            $totalDuration = $testSummary | ForEach-Object { $_.testResultData.duration } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            $totalDurationFormatted = Format-Seconds -totalSeconds $totalDuration
            if ($totalFailedTests -gt 0) { $code = -1; $color = "DarkYellow" } else { $code = 0; $color = "DarkGreen" }
            $content = " Files tested : $($testSummary.Count) | Total failed tests: $totalFailedTests"
            if ($totalDurationFormatted -ne -1) {
                $content += " | Total duration: $totalDurationFormatted"
            }
            $content += "`n"
            Write-Host $content -ForegroundColor $color
            
            $maxFileNameLength = ($testSummary.Name | Measure-Object -Maximum Length).Maximum
            $maxLineLength = $maxFileNameLength + 20  # padding
            
            $testSummary = SortBy -data $testSummary -sortByColumn $options.sortBy
            $testSummary | ForEach-Object {
                $label = "  - $($_.Name) "
                $line = $label.PadRight($maxLineLength, '.') + " $($_.Message)"
                $color = "DarkYellow"
                if ($_.code -eq 0) {
                    $color = "DarkGreen"
                    if ($null -ne $_.testResultData.coverageRaw -and $_.testResultData.coverageRaw -lt $options.target) {
                        $color = "DarkGray"
                    }
                }
                Write-Host $line -ForegroundColor $color
            }
        } else {
            $code = -1
            Write-Host "No tests found." -ForegroundColor DarkYellow
        }
        return $code
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to run tests"
            exception = $_
        }
        Write-Host "`nFailed to run tests, check log: $LOG_ERROR_PATH" -ForegroundColor DarkYellow

        return -1
    }
}

function SortBy {
    param ($data, $sortByColumn = $null)
    
    if ($sortByColumn -ne $null) {
        $direction = $sortByColumn -match "^-"
        $sortByColumn = $sortByColumn -replace '-', ''
    }
    
    switch ($sortByColumn) {
        "duration" {
            return $data | Sort-Object `
                @{ Expression = {
                        if ($null -eq $_.testResultData.duration) {
                            [double]::PositiveInfinity
                        } else {
                            [double]$_.testResultData.duration
                        }
                }; Descending = $direction }
        }
        "coverage" {
            return $data | Sort-Object `
                @{ Expression = {
                        if ($null -eq $_.testResultData.coverageRaw) {
                            [double]::PositiveInfinity
                        } else {
                            [double]$_.testResultData.coverageRaw
                        }
                }; Descending = $direction }
        }
        "file" {
            return $data | Sort-Object @{ Expression = { [string]$_.Name }; Descending = $direction }
        }
    }
    
    return $data;
}

