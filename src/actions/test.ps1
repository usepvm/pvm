
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
        if (-not (Test-Path $file.FullName)) {
            return @{ code = -1; Name = $file.Name; FailedCount = 1; Message = "File not found!" }
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
        $coveragePercent = $null
        if ($testResult.CodeCoverage.CoveragePercent) {
            $coveragePercent = $testResult.CodeCoverage.CoveragePercent.ToString('00.00')
            $message = "| Coverage: $coveragePercent%"
        }
        if ($LASTEXITCODE -ne 0) {
            return @{ code = -1; Name = $file.Name; FailedCount = $($testResult.FailedCount); Message = "Failed: $($testResult.FailedCount) $message"; coverage = $coveragePercent }
        }
        
        return @{ code = 0; Name = $file.Name; FailedCount = 0; Message = "Failed: $($testResult.FailedCount) $message"; coverage = $coveragePercent }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"
            exception = $_
        }
        return @{ code = -1; Name = $file.Name; FailedCount = 1; Message = "Failed to run test, check log." }
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
        
        $messages = @(@{ content = "`n----------------------------------------------------------------" })
        $messages += @(@{ content = "`n`nTest Results Summary: (Target : $($options.target)%)`n" })
        $code = 0
        if ($testSummary.Count -gt 0) {
            $totalFailedTests = $testSummary | Where-Object { $_.code -ne 0 } | ForEach-Object { $_.FailedCount } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
            if ($totalFailedTests -gt 0) { $code = -1; $color = "DarkYellow" } else { $code = 0; $color = "DarkGreen" }
            $messages += @{ content = " Files tested : $($testSummary.Count) | Total failed tests: $totalFailedTests`n"; color = $color }
            
            $maxFileNameLength = ($testSummary.Name | Measure-Object -Maximum Length).Maximum
            $maxLineLength = $maxFileNameLength + 10  # padding
            
            $testSummary | ForEach-Object {
                $dotsCount = $maxLineLength - $_.Name.Length
                if ($dotsCount -lt 0) { $dotsCount = 0 }
                $dots = '.' * $dotsCount
                $color = "DarkYellow"
                if ($_.code -eq 0) {
                    $color = "DarkGreen"
                    if ($null -ne $_.coverage -and [double]$_.coverage -lt $options.target) {
                        $color = "DarkGray"
                    }
                }
                $messages += @{ content = "  - $($_.Name) $dots $($_.Message)"; color = $color }
            }
        } else {
            $code = -1
            $messages += @{ content = "No tests found."; color = "DarkYellow" }
        }
        $result = @{ code = $code; messages = $messages }
        return $result
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to run tests"
            exception = $_
        }
        return @{ code = -1; message = "Failed to run tests."; color = "DarkYellow" }
    }
}


