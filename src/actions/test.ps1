
function Use-Pester-Version {
    param ($version)

    Write-Host "`nChecking for Pester version: $version" -ForegroundColor Yellow

    $availableVersions = Get-Module -Name Pester -ListAvailable

    if (-not $availableVersions) {
        Write-Host "No Pester module found. Please install Pester first." -ForegroundColor Red
        return $false
    }

    $targetVersion = Find-Pester-Version -version $version -availableVersions $availableVersions

    if (-not $targetVersion) {
        $availableList = $availableVersions.Version -join ', '
        Write-Host "Pester version '$version' not found. Available versions: $availableList" -ForegroundColor Red
        return $false
    }

    return Import-Pester-Version -targetVersion $targetVersion
}

function Use-Latest-Pester-Version {
    Write-Host "`nChecking for latest Pester version" -ForegroundColor Yellow

    $availableVersions = Get-Module -Name Pester -ListAvailable
    $targetVersion = Find-Pester-Version -version 'latest' -availableVersions $availableVersions

    return Import-Pester-Version -targetVersion $targetVersion
}

function Find-Pester-Version {
    param ($version, $availableVersions)

    if ([string]::IsNullOrWhiteSpace($version) -or $version -eq 'latest') {
        return $availableVersions | Sort-Object Version -Descending | Select-Object -First 1
    }

    switch -Regex ($version) {
        '^\d+\.\d+\.\d+$' {
            return $availableVersions | Where-Object { $_.Version -eq $version }
        }
        '^\d+\.\d+$' {
            return $availableVersions | Where-Object { $_.Version -like "$version.*" } | Sort-Object Version -Descending | Select-Object -First 1
        }
        '^\d+$' {
            return $availableVersions | Where-Object { $_.Version.Major -eq [int]$version } | Sort-Object Version -Descending | Select-Object -First 1
        }
        default {
            return $availableVersions | Where-Object { $_.Version -le $version } | Sort-Object Version -Descending | Select-Object -First 1
        }
    }
}

function Import-Pester-Version {
    param ($targetVersion)

    Import-Module Pester -RequiredVersion $targetVersion.Version -Force
    $pesterVersion = Get-Module -Name Pester
    Write-Host "Using Pester version: $($pesterVersion.Version)" -ForegroundColor Green

    Write-Host -Object "`nPester Info:" -ForegroundColor Cyan
    Write-Host -Object "  Version: $($pesterVersion.Version)" -ForegroundColor Gray
    Write-Host -Object "  Path: $($pesterVersion.Path)" -ForegroundColor Gray

    return $pesterVersion
}

function Get-PowerShell-Info {
    $psInfo = @{
        Version = $PSVersionTable.PSVersion
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
    param ($psInfo)

    Write-Host -Object "`nPowerShell Info:" -ForegroundColor Cyan
    Write-Host -Object "  Engine: $($psInfo.Name)" -ForegroundColor Gray
    Write-Host -Object "  Version: $($psInfo.Version)" -ForegroundColor Gray
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
    param ($testFile, $testsMap)

    return $testsMap[$testFile.FullName]
}

function Get-Tests-Map {
    param ($root)

    $testsMap = @{}
    Get-ChildItem -Path "$root\src" -Recurse -Filter '*.ps1' | ForEach-Object {
        $testFile = $_.FullName -replace [regex]::Escape("$root\src"), "$root\tests"
        $testFile = $testFile -replace '.ps1', '.tests.ps1'
        $testsMap[$testFile] = $_
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
    param ($config, $testFile, $options, $root, $testsMap)

    $covered = Get-Covered-Source-File -testFile $testFile -testsMap $testsMap

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
    param ($config, $file, $options = $null, $separatorWidth = 60, $testsMap = $null)

    $testResultData = @{ passedCount = 0; failedCount = 0; duration = 0; coverageRaw = $null }
    $root = Get-PVMRootDirectory
    $relativeFilePath = $file.FullName -replace [regex]::Escape("$root\tests\"), ''
    $sortedName = if ($options -and $options.groupBy) { $file.Name } else { $relativeFilePath }

    if (Is-File-Not-Exists -path $file.FullName) {
        return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; Message = 'File not found!'; testResultData = $testResultData }
    }

    if (-not $options) {
        $options = @{ coverage = $false; target = 75 }
    }

    $coveredFile = $null
    if ($options.coverage) {
        $coverageConfig = Set-Coverage-Config -config $config -testFile $file -options $options -root $root -testsMap $testsMap
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

        $code = if ($testResult.FailedCount -gt 0) { -1 } else { 0 }

        return @{ code = $code; Name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; Message = $message; testResultData = $testResultData }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to run test: $($file.FullName)"; exception = $_ }
        return @{ code = -1; Name = $file.Name; relativeFilePath = $relativeFilePath; sortedName = $sortedName; Message = 'Failed to run test, check log.'; testResultData = $testResultData }
    }
}

function Prepare-Tests {
    param ($testsNames = $null, $options = $null, $exclude = $null, $pesterVersion = $null)

    if ($null -ne $exclude) {
        $testsNames = Get-All-Test-Names -exclude $exclude
    }

    $tests = Get-Tests-Files -testsNames $testsNames

    return Run-Tests -tests $tests -options $options -pesterVersion $pesterVersion
}

function Get-Coverage-Group-Name {
    param ($coverageRaw)

    if ($null -eq $coverageRaw) {
        return 'n/a'
    }

    if ($coverageRaw -ge 100) {
        return '100%'
    }

    if ($coverageRaw -ge 90) {
        return '90%+'
    }

    if ($coverageRaw -ge 80) {
        return '80%+'
    }

    if ($coverageRaw -ge 70) {
        return '70%+'
    }

    if ($coverageRaw -ge 60) {
        return '60%+'
    }

    if ($coverageRaw -ge 50) {
        return '50%+'
    }

    return '<50%'
}

function Get-Folder-Group-Name {
    param ($relativeFilePath)

    $parent = Split-Path -Path $relativeFilePath -Parent

    if (-not $parent) {
        return '(root)'
    }

    return ($parent -replace '\\', '/')
}

function Get-Result-Color {
    param ($item, $target)

    if ($item.code -ne 0) { return 'DarkYellow' }

    if ($null -ne $item.testResultData.coverageRaw -and $item.testResultData.coverageRaw -lt $target) { return 'DarkGray' }

    return 'DarkGreen'
}

function Get-Coverage-Group-Rank {
    param ($groupName)

    $order = @('<50%', '50%+', '60%+', '70%+', '80%+', '90%+', '100%', 'n/a')
    $rank = [array]::IndexOf($order, $groupName)

    if ($rank -eq -1) { return 999 }

    return $rank
}

function Write-Grouped-Results {
    param ($sorted, $groupExpr, $maxLineLength, $target, $groupBy = $null)

    $grouped = if ($groupExpr) { $sorted | Group-Object -Property $groupExpr } else { @(@{ Name = $null; Group = $sorted }) }

    if ($groupBy -eq 'coverage') {
        $grouped = $grouped | Sort-Object { Get-Coverage-Group-Rank -groupName $_.Name }
    } elseif ($groupBy -eq 'folder') {
        $grouped = $grouped | Sort-Object { $_.Name }
    }

    foreach ($group in $grouped) {
        if ($group.Name) { Write-Host -Object "`n  [$($group.Name)]" -ForegroundColor DarkCyan }

        $group.Group | ForEach-Object {
            $label = "    - $($_.sortedName) "
            $line = $label.PadRight($maxLineLength, '.') + " $($_.Message)"
            Write-Host -Object $line -ForegroundColor (Get-Result-Color -item $_ -target $target)
        }
    }
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

    $groupExpr = switch ($options.groupBy) {
        'coverage' { { Get-Coverage-Group-Name -coverageRaw $_.testResultData.coverageRaw } }
        'folder'   { { Get-Folder-Group-Name -relativeFilePath $_.relativeFilePath } }
        default    { $null }
    }

    Write-Grouped-Results -sorted $sorted -groupExpr $groupExpr -maxLineLength $maxLineLength -target $options.target -groupBy $options.groupBy

    if ($totalFailedTests -gt 0) {
        return -1
    } else {
        return 0
    }
}

function Run-Tests {
    param ($tests = $null, $options = $null, $pesterVersion = $null)

    try {
        if ($pesterVersion) {
            $pesterInfo = Use-Pester-Version -version $pesterVersion
        } else {
            $pesterInfo = Use-Latest-Pester-Version
        }

        if (-not $pesterInfo) {
            Write-Host -Object "`nNo Pester module found. Please install Pester first." -ForegroundColor DarkYellow
            return -1
        }

        if (-not $options) {
            $options = @{ verbosity = 'Normal'; coverage = $false; tag = $null; target = 75; groupBy = $null }
        }

        $verbosityOptions = @('None', 'Normal', 'Detailed', 'Diagnostic')
        if ($verbosityOptions -notcontains $options.verbosity) {
            Write-Host -Object "`nInvalid verbosity option. Allowed values are: $($verbosityOptions -join ', ')" -ForegroundColor DarkYellow
            return -1
        }

        $config = Build-Pester-Config -options $options
        $separatorWidth = Get-Separator-Width -tests $tests
        $root = Get-PVMRootDirectory
        $testsMap = if ($options.coverage) { Get-Tests-Map -root $root } else { $null }

        $psInfo = Get-PowerShell-Info
        Write-PowerShell-Info -psInfo $psInfo
        Write-Host -Object "`nRunning tests with verbosity: $($options.verbosity)" -ForegroundColor Cyan

        $testSummary = $tests | ForEach-Object {
            Run-Test-File -config $config -file $_ -options $options -separatorWidth $separatorWidth -testsMap $testsMap
        }

        $maxLineLength = ($testSummary.relativeFilePath | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 3)

        Write-Host -Object "`n----------------------------------------------------------------"
        Write-Host -Object "`n`nTests Settings:"
        Write-Host -Object " PowerShell Engine ..... $($psInfo.Name)"
        Write-Host -Object " PowerShell ............ $($psInfo.Version)"
        Write-Host -Object " Pester ................ $($pesterInfo.Version)"
        Write-Host -Object "`nTest Results Summary:"
        Write-Host -Object " Coverage .............. $($options.target)%"
        Write-Host -Object " Verbosity ............. $($options.verbosity)`n"

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
            return $data | Sort-Object @{ Expression = { [string]$_.sortedName }; Descending = $direction }
        }
    }

    return $data
}
