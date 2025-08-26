
function Get-Tests-Files {
    param ($tests)
    
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
    param ($config, $file, $verbosity, $coverage = $false)
    
    if (-not (Test-Path $file.FullName)) {
        return @{ Name = $file.Name; Count = 1; Message = "File not found!" }
    }

    $coveredFile = ""
    if ($coverage) {
        $PVMRootDirectory = (Resolve-Path "$PSScriptRoot\..\..").Path
        $covered = Get-ChildItem -Path "$PVMRootDirectory\src" -Recurse -Filter "*.ps1"
        $covered = $covered | Where-Object {
            return ($_.Name -replace '.ps1','') -eq ($file.Name -replace '.tests.ps1','')
        }
            
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.Path = $covered.FullName
        $config.CodeCoverage.OutputPath = "$PVMRootDirectory\coverage\$($file.Name).xml"
        $config.CodeCoverage.OutputFormat = 'JaCoCo' # 'CoverageGutters'
        $config.CodeCoverage.OutputEncoding = 'UTF8'
        $coveredFile = "(covers: $($covered.Name))"
    }
    
    Write-Host "`n----------------------------------------------------------------"
    Write-Host "- Running test: $($file.Name) $coveredFile"
    Write-Host "----------------------------------------------------------------"


    $config.Run.Path = $file.FullName
    $config.Run.PassThru = $true
    $testResult = Invoke-Pester -Configuration $config
    if ($LASTEXITCODE -ne 0) {
        return @{ Name = $file.Name; Count = $($testResult.FailedCount); Message = "$($testResult.FailedCount) tests" }
    }
    
    return $null
}

function Run-Tests {
    param ($verbosity = "Normal", $tests = $null, $tag = $null, $coverage = $false)
    
    try {
        $verbosityOptions = @('None', 'Normal', 'Detailed', 'Diagnostic')
        if ($verbosityOptions -notcontains $verbosity) {
            Write-Host "`nInvalid verbosity option. Allowed values are: $($verbosityOptions -join ', ')" -ForegroundColor DarkYellow
            return -1
        }

        $config = New-PesterConfiguration
        $config.Output.Verbosity = $verbosity
        
        $tests = Get-Tests-Files -tests $tests
        
        if ($null -ne $tag) {
            $config.Filter.Tag = $tag
        }
        
        $result = @{ code = 0; message = "Tests completed successfully."; color = "DarkGreen" }
        $testFailedDetails = @()
        Write-Host "`nRunning tests with verbosity: $verbosity" -ForegroundColor Cyan
        $tests | ForEach-Object { 
            try {
                $file = $_
                $testResult = Run-Test-File -config $config -file $file -verbosity $verbosity -coverage $coverage
                if ($testResult -and $testResult.Count -gt 0) {
                    $testFailedDetails += $testResult
                }
            } catch {
                $logged = Log-Data -data @{
                    header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"
                    exception = $_
                }
                Write-Host "`nFailed to run test: $($file.FullName)" -ForegroundColor DarkYellow
                $result = @{ code = 1; message = "Some tests failed to run!"; color = "DarkYellow" }
            }
        }
        
        if ($testFailedDetails.Count -gt 0) {
            $totalFailedTests = $testFailedDetails | ForEach-Object { $_.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            $message = " Files failed to run: $($testFailedDetails.Count)  |  Total failed tests: $totalFailedTests"
            $maxFileNameLength = ($testFailedDetails.Name | Measure-Object -Maximum Length).Maximum
            $maxLineLength = $maxFileNameLength + 10  # padding
            
            $testFailedDetails | ForEach-Object {
                $dotsCount = $maxLineLength - $_.Name.Length
                if ($dotsCount -lt 0) { $dotsCount = 0 }
                $dots = '.' * $dotsCount
                $message += "`n  - $($_.Name) $dots $($_.Message)"
            }
            $result = @{ code = 1; message = $message; color = "DarkGray" }
        }
        
        $message = "`nTest Results Summary:"
        $message += "`n=======================`n`n"
        $result.message = $message + $result.message
        
        return $result
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to run tests"
            exception = $_
        }
        return @{ code = 1; message = "Failed to run tests."; color = "DarkYellow" }
    }
}


