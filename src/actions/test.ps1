
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
    
    if (-not (Test-Path $file.FullName)) {
        return @{ code = -1; Name = $file.Name; FailedCount = 0; Message = "File not found!" }
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
    $message = ""
    if ($testResult.CodeCoverage.CoveragePercent) {
        $coveragePercent = $testResult.CodeCoverage.CoveragePercent.ToString('00.00')
        $message = "| Coverage: $coveragePercent%"
    }
    if ($LASTEXITCODE -ne 0) {
        return @{ code = -1; Name = $file.Name; FailedCount = $($testResult.FailedCount); Message = "Failed: $($testResult.FailedCount) $message" }
    }
    
    return @{ code = 0; Name = $file.Name; FailedCount = 0; Message = "Failed: $($testResult.FailedCount) $message" }
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
        
        $result = @{ code = 0; message = "Tests completed successfully."; color = "DarkGreen" }
        $testSummary = @()
        Write-Host "`nRunning tests with verbosity: $($options.verbosity)" -ForegroundColor Cyan
        $tests | ForEach-Object { 
            try {
                $file = $_
                $testResult = Run-Test-File -config $config -file $file -options $options
                $testSummary += $testResult
            } catch {
                $logged = Log-Data -data @{
                    header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"
                    exception = $_
                }
                Write-Host "`nFailed to run test: $($file.FullName)" -ForegroundColor DarkYellow
                $result = @{ code = 1; message = "Some tests failed to run!"; color = "DarkYellow" }
            }
        }
        
        $message = "`n`nTest Results Summary:`n"
        if ($testSummary.Count -gt 0) {
            $totalFailedTests = $testSummary | Where-Object { $_.code -ne 0 } | ForEach-Object { $_.FailedCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            $message += "`n Files tested : $($testSummary.Count)  |  Total failed tests: $totalFailedTests`n"
            $maxFileNameLength = ($testSummary.Name | Measure-Object -Maximum Length).Maximum
            $maxLineLength = $maxFileNameLength + 10  # padding
            
            $testSummary | ForEach-Object {
                $dotsCount = $maxLineLength - $_.Name.Length
                if ($dotsCount -lt 0) { $dotsCount = 0 }
                $dots = '.' * $dotsCount
                $message += "`n  - $($_.Name) $dots $($_.Message)"
            }
            $result = @{ code = 1; message = $message }
        }
        
        return $result
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to run tests"
            exception = $_
        }
        return @{ code = 1; message = "Failed to run tests."; color = "DarkYellow" }
    }
}


