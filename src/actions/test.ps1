
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
        $tests = Get-ChildItem "$PVMRoot\tests\*.tests.ps1"
    }
    
    return $tests
} 

function Run-Test-File {
    param ($config, $file, $verbosity)
    
    if (-not (Test-Path $file.FullName)) {
        return @{ Name = $file.Name; Count = 1; Message = "File not found!" }
    }
    
    $config.Run.Path = $file.FullName
    $config.Run.PassThru = $true
    $testResult = Invoke-Pester -Configuration $config
    if ($LASTEXITCODE -ne 0) {
        return @{ Name = $file.Name; Count = $($testResult.FailedCount); Message = "$($testResult.FailedCount) tests" }
    }
    
    return $null
}

function Run-Tests {
    param ($verbosity = "Normal", $tests = $null, $tag = $null)
    
    try {
        $config = New-PesterConfiguration
        $config.Output.Verbosity = $verbosity
        
        $tests = Get-Tests-Files -tests $tests
        
        if (($tests.Length -eq 1) -and ($null -ne $tag)) {
            $config.Filter.Tag = $tag
        }
        
        $result = @{ code = 0; message = "Tests completed successfully."; color = "DarkGreen" }
        $testFailedDetails = @()
        Write-Host "`nRunning tests with verbosity: $verbosity" -ForegroundColor Cyan
        $tests | ForEach-Object { 
            try {
                $file = $_
                Write-Host "`n----------------------------------------------------------------"
                Write-Host "- Running test: $($file.Name)"
                Write-Host "----------------------------------------------------------------"
                $testResult = Run-Test-File -config $config -file $file -verbosity $verbosity
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


