

function Run-Tests {
    param ($verbosity = "Normal", $tests = $null, $tag = $null)
    
    try {
        $config = New-PesterConfiguration
        $config.Output.Verbosity = $verbosity
        
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
        
        if (($tests.Length -eq 1) -and ($null -ne $tag)) {
            $config.Filter.Tag = $tag
        }
        
        $result = @{ code = 0; message = "Tests completed successfully."; color = "DarkGreen" }
        $testFailedDetails = @()
        Write-Host "`nRunning tests with verbosity: $verbosity" -ForegroundColor Cyan
        $tests | ForEach-Object { 
            try {
                Write-Host "`n----------------------------------------------------------------"
                Write-Host "- Running test: $($_.Name)"
                Write-Host "----------------------------------------------------------------"
                $fileName = $_.FullName
                if (-not (Test-Path $fileName)) {
                    $msg = "- $fileName does not exist."
                    Write-Host "`n$msg" -ForegroundColor DarkYellow
                    throw $msg
                }
                $config.Run.Path = $fileName
                $config.Run.PassThru = $true
                $testResult = Invoke-Pester -Configuration $config
                if ($LASTEXITCODE -ne 0) {
                    $testFailedDetails += @{ Name = $_.Name; Count = $($testResult.FailedCount) }
                }
            } catch {
                $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Run-Tests: Failed to run test: $fileName" -data $_.Exception.Message
                Write-Host "`n- Failed to run test: $fileName" -ForegroundColor DarkYellow
                $result = @{ code = 1; message = "Some tests failed to run!"; color = "DarkYellow" }
            }
            Write-Host "`n"
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
                $message += "`n  - $($_.Name) $dots $($_.Count) tests"
            }
            $result = @{ code = 1; message = $message; color = "DarkGray" }
        }
        
        $message = "Test Results Summary:"
        $message += "`n=======================`n`n"
        $result.message = $message + $result.message
        
        return $result
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Run-Tests: Failed to run tests" -data $_.Exception.Message
        Write-Host "`nFailed to run tests."
        return @{ code = 1; message = "Failed to run tests."; color = "DarkYellow" }
    }
}


