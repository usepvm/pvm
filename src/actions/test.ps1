

function Run-Tests {
    param ($verbosity = "Normal")
    
    try {
        $config = New-PesterConfiguration
        $config.Output.Verbosity = $verbosity

        $tests = Get-ChildItem "$PVMRoot\tests\*.tests.ps1"
        $tests | ForEach-Object { 
            try {
                Write-Host "`n----------------------------------------------------------------"
                Write-Host "- Running test: $($_.Name)"
                Write-Host "----------------------------------------------------------------"
                $fileName = $_.FullName
                $config.Run.Path = $fileName
                Invoke-Pester -Configuration $config
            } catch {
                $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Run-Tests: Failed to run test: $fileName" -data $_.Exception.Message
                Write-Host "`n- Failed to run test: $fileName"
            }
            Write-Host "`n"
        }
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Run-Tests: Failed to run tests" -data $_.Exception.Message
        Write-Host "`nFailed to run tests."
    }
    
}


