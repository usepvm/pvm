
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:ROOT_PATH = $Global:PVMConfig.rootPath
    $script:TEST_DRIVE_PATH = $Global:PVMConfig.paths.directories.testDrive

    Mock New-Line { }
    Mock Show-Info { }
    Mock Write-Color { }
    Mock Write-Cyan { }
    Mock Write-White { }
    Mock Write-DarkGray { }
    Mock Show-Error { }
    Mock Show-Message { }
    Mock Write-Gray { }
}

Describe "Show-Scripts" {
    It "Displays the available scripts and commands" {
        Mock Get-Scripts {
            return [ordered]@{
                build = @('test --filter build', 'test --filter unit')
                lint  = @('test --filter lint')
            }
        }

        Show-Scripts

        Should -Invoke Write-Cyan -Times 1 -Exactly -ParameterFilter {
            $message -eq "`nAvailable scripts:"
        }
        Should -Invoke Write-White -Times 2 -Exactly -ParameterFilter {
            $message -in @("`n  build", "`n  lint")
        }
        Should -Invoke Write-DarkGray -Times 3 -Exactly -ParameterFilter {
            $message -in @("   - test --filter build", "   - test --filter unit", "   - test --filter lint")
        }
    }

    It "Displays no script entries when no scripts are available" {
        Mock Get-Scripts { return @{} }

        Show-Scripts

        Should -Invoke Write-Cyan -Times 1 -Exactly
        Should -Not -Invoke Write-White
        Should -Not -Invoke Write-DarkGray
    }
}

Describe "Clear-TestDrive" {
    It "Clears the fake storage path if valid" {
        Mock Test-ValidDrivePath { return $true }
        Mock Remove-ItemWrapper { }

        Clear-TestDrive

        Should -Invoke Remove-ItemWrapper -ParameterFilter { $path -eq "$script:TEST_DRIVE_PATH\*" }
    }

    It "Does not attempt to clear when test drive path is null" {
        Mock Remove-ItemWrapper { }
        $Global:PVMConfig.paths.directories.testDrive = $null

        Clear-TestDrive

        Should -Not -Invoke Remove-ItemWrapper
    }

    It "Does not attempt to clear when test drive path is invalid" {
        Mock Test-ValidDrivePath { return $false }
        Mock Remove-ItemWrapper { }
        $Global:PVMConfig.paths.directories.testDrive = "invalid\path\without\drive"

        Clear-TestDrive

        Should -Not -Invoke Remove-ItemWrapper
    }

    It "Does not attempt to clear when test drive path is empty" {
        Mock Test-ValidDrivePath { return $false }
        Mock Remove-ItemWrapper { }
        $Global:PVMConfig.paths.directories.testDrive = ""

        Clear-TestDrive

        Should -Not -Invoke Remove-ItemWrapper
    }
}

Describe "Use-PesterVersion" {
    BeforeEach {
        Mock Find-PesterVersion { return @{ Version = [version]'5.0.0' } }
        Mock Import-PesterVersion { return @{ Version = [version]'5.0.0' } }
    }

    It "Returns false when no Pester module is found" {
        Mock Get-Module { return $null }

        $result = Use-PesterVersion -version '5.0.0'

        $result | Should -Be $false
        Should -Invoke Show-Error -Times 1 -Exactly
    }

    It "Returns false when specified version is not found" {
        Mock Get-Module { return @(@{ Version = [version]'5.0.0' }) }
        Mock Find-PesterVersion { return $null }

        $result = Use-PesterVersion -version '6.0.0'

        $result | Should -Be $false
        Should -Invoke Show-Error -Times 1 -Exactly
    }

    It "Returns imported Pester version when found" {
        Mock Get-Module { return @(@{ Version = [version]'5.0.0' }) }

        $result = Use-PesterVersion -version '5.0.0'

        $result | Should -Not -Be $false
        Should -Invoke Import-PesterVersion -Times 1 -Exactly
    }
}

Describe "Use-LatestPesterVersion" {
    BeforeEach {
        Mock Find-PesterVersion { return @{ Version = [version]'5.0.0' } }
        Mock Import-PesterVersion { return @{ Version = [version]'5.0.0' } }
    }

    It "Uses latest Pester version" {
        Mock Get-Module { return @(@{ Version = [version]'5.0.0' }) }

        $result = Use-LatestPesterVersion

        $result | Should -Not -Be $false
        Should -Invoke Find-PesterVersion -Times 1 -Exactly -ParameterFilter {
            $version -eq 'latest'
        }
        Should -Invoke Import-PesterVersion -Times 1 -Exactly
    }
}

Describe "Find-PesterVersion" {
    It "Returns latest version when version is null" {
        $availableVersions = @(
            @{ Version = [version]'5.0.0' }
            @{ Version = [version]'5.1.0' }
            @{ Version = [version]'5.2.0' }
        )

        $result = Find-PesterVersion -version $null -availableVersions $availableVersions

        $result.Version | Should -Be '5.2.0'
    }

    It "Returns latest version when version is 'latest'" {
        $availableVersions = @(
            @{ Version = [version]'5.0.0' }
            @{ Version = [version]'5.1.0' }
            @{ Version = [version]'5.2.0' }
        )

        $result = Find-PesterVersion -version 'latest' -availableVersions $availableVersions

        $result.Version | Should -Be '5.2.0'
    }

    It "Returns exact version when version matches exactly" {
        $availableVersions = @(
            @{ Version = [version]'5.0.0' }
            @{ Version = [version]'5.1.0' }
            @{ Version = [version]'5.2.0' }
        )

        $result = Find-PesterVersion -version '5.1.0' -availableVersions $availableVersions

        $result.Version | Should -Be '5.1.0'
    }

    It "Returns latest minor version when version is major.minor" {
        $availableVersions = @(
            @{ Version = [version]'5.0.0' }
            @{ Version = [version]'5.1.0' }
            @{ Version = [version]'5.1.5' }
            @{ Version = [version]'5.2.0' }
        )

        $result = Find-PesterVersion -version '5.1' -availableVersions $availableVersions

        $result.Version | Should -Be '5.1.5'
    }

    It "Returns latest major version when version is major only" {
        $availableVersions = @(
            @{ Version = [version]'4.0.0' }
            @{ Version = [version]'5.0.0' }
            @{ Version = [version]'5.1.0' }
            @{ Version = [version]'6.0.0' }
        )

        $result = Find-PesterVersion -version '5' -availableVersions $availableVersions

        $result.Version | Should -Be '5.1.0'
    }

    It "Returns null when exact version is not found" {
        $availableVersions = @(
            @{ Version = [version]'5.0.0' }
            @{ Version = [version]'5.1.0' }
        )

        $result = Find-PesterVersion -version '5.5.0' -availableVersions $availableVersions

        $result | Should -Be $null
    }

    It "Uses default case for version string not matching patterns" {
        $availableVersions = @(
            @{ Version = [version]'5.0.0' }
            @{ Version = [version]'5.1.0' }
            @{ Version = [version]'5.2.0' }
        )

        # Use a version string with build number that doesn't match the patterns
        # but can still be converted to version for comparison
        $result = Find-PesterVersion -version '5.1.0.1' -availableVersions $availableVersions

        # This should trigger the default case and return the highest version <= 5.1.0.1
        $result | Should -Not -Be $null
        $result.Version | Should -Be '5.1.0'
    }
}

Describe "Import-PesterVersion" {
    It "Imports Pester module with specified version" {
        Mock Import-Module { }
        Mock Get-Module { return @{ Version = [version]'5.0.0'; Path = 'C:\Modules\Pester' } }

        $targetVersion = @{ Version = [version]'5.0.0' }

        $null = Import-PesterVersion -targetVersion $targetVersion

        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Pester' -and $RequiredVersion -eq [version]'5.0.0'
        }
        Should -Invoke Get-Module -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'Pester'
        }
    }
}

Describe "Show-PesterVersion" {
    It "Shows Pester version information" {
        $pesterVersion = @{
            Version = [version]'5.0.0'
            Path    = 'C:\Modules\Pester'
        }

        Show-PesterVersion -pesterVersion $pesterVersion

        Should -Invoke Show-Message -Times 3 -Exactly
    }
}

Describe "Show-PesterVersionShort" {
    It "Shows short Pester version information" {
        $pesterVersion = @{
            Version = [version]'5.0.0'
        }

        Show-PesterVersionShort -pesterVersion $pesterVersion

        Should -Invoke Show-Message -Times 1 -Exactly -ParameterFilter {
            $message -like '*Pester Version*'
        }
    }
}

Describe "Show-PowerShellInfo" {
    It "Shows PowerShell information" {
        $psInfo = @{
            Name     = 'PowerShell Core (pwsh)'
            Version  = [version]'7.0.0'
            Edition  = 'Core'
            Platform = 'Unix'
            Path     = '/usr/bin/pwsh'
        }

        Show-PowerShellInfo -psInfo $psInfo

        Should -Invoke Show-Message -Times 6 -Exactly
    }
}

Describe "Show-PowerShellInfoShort" {
    It "Shows short PowerShell information" {
        $psInfo = @{
            Version = [version]'7.0.0'
        }

        Show-PowerShellInfoShort -psInfo $psInfo

        Should -Invoke Show-Message -Times 1 -Exactly -ParameterFilter {
            $message -like '*PowerShell Version*'
        }
    }
}

Describe "Get-TestsFiles" {
    It "Returns all test files when no specific names provided" {
        Mock Get-ChildItemWrapper {
            return @(
                @{ Name = 'test1.tests.ps1'; FullName = "$script:TEST_DRIVE\tests\test1.tests.ps1" }
                @{ Name = 'test2.tests.ps1'; FullName = "$script:TEST_DRIVE\tests\test2.tests.ps1" }
            )
        }

        $result = Get-TestsFiles

        $result.Count | Should -Be 2
    }

    It "Returns specific test files when names are provided" {
        Mock Get-ChildItemWrapper {
            return @(
                @{ Name = 'test1.tests.ps1'; FullName = "$script:TEST_DRIVE\tests\test1.tests.ps1" }
                @{ Name = 'test2.tests.ps1'; FullName = "$script:TEST_DRIVE\tests\test2.tests.ps1" }
            )
        }

        $result = @(Get-TestsFiles -testsNames @('test1'))

        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'test1.tests.ps1'
    }

    It "Includes placeholder for missing test files" {
        Mock Get-ChildItemWrapper {
            return @(
                @{ Name = 'test1.tests.ps1'; FullName = "$script:TEST_DRIVE\tests\test1.tests.ps1" }
            )
        }

        $result = Get-TestsFiles -testsNames @('test1', 'test2')

        $result.Count | Should -Be 2
        $result[1].Name | Should -Be 'test2.tests.ps1'
    }
}

Describe "Get-AllTestNames" {
    It "Returns all test names without exclusions" {
        Mock Get-ChildItemWrapper {
            return @(
                @{ BaseName = 'test1.tests'; FullName = "$script:TEST_DRIVE\tests\test1.tests.ps1" }
                @{ BaseName = 'test2.tests'; FullName = "$script:TEST_DRIVE\tests\test2.tests.ps1" }
            )
        }

        $result = Get-AllTestNames

        $result.Count | Should -Be 2
    }

    It "Excludes specified test names" {
        Mock Get-ChildItemWrapper {
            return @(
                @{ BaseName = 'test1.tests'; FullName = "$script:TEST_DRIVE\tests\test1.tests.ps1" }
                @{ BaseName = 'test2.tests'; FullName = "$script:TEST_DRIVE\tests\test2.tests.ps1" }
            )
        }

        $result = Get-AllTestNames -exclude @('test1')

        $result.Count | Should -Be 1
        $result | Should -Not -Contain 'test1'
    }
}

Describe "Get-CoveredSourceFile" {
    It "Returns the source file for a given test file" {
        $testsMap = @{
            "$script:TEST_DRIVE\tests\file.tests.ps1" = @{ Name = 'file.ps1'; FullName = "$script:TEST_DRIVE\src\file.ps1" }
        }

        $testFile = @{ FullName = "$script:TEST_DRIVE\tests\file.tests.ps1" }

        $result = Get-CoveredSourceFile -testFile $testFile -testsMap $testsMap

        $result.FullName | Should -Be "$script:TEST_DRIVE\src\file.ps1"
    }
}

Describe "Get-TestsMap" {
    It "Creates a mapping from test files to source files" {
        New-Item -Path "$script:ROOT_PATH\src\helpers" -ItemType Directory -Force | Out-Null
        New-Item -Path "$script:ROOT_PATH\src\helpers\other.ps1" -ItemType File -Force | Out-Null
        New-Item -Path "$script:ROOT_PATH\src\helpers\other2.ps1" -ItemType File -Force | Out-Null

        $result = Get-TestsMap

        $result.Count | Should -BeGreaterOrEqual 2
        # The function maps test file paths to source file objects
        $result.Values.Count | Should -BeGreaterOrEqual 2
    }
}

Describe "Set-CoverageConfig" {
    It "Sets coverage configuration with all parameters" {
        New-Item -Path "$script:ROOT_PATH\src\helpers" -ItemType Directory -Force | Out-Null
        New-Item -Path "$script:ROOT_PATH\src\helpers\file.ps1" -ItemType File -Force | Out-Null
        New-Item -Path "$script:ROOT_PATH\storage\coverage\helpers" -ItemType Directory -Force | Out-Null

        $testsMap = @{
            "$script:ROOT_PATH\tests\helpers\file.tests.ps1" = @{ Name = 'file.ps1'; FullName = "$script:ROOT_PATH\src\helpers\file.ps1" }
        }

        $testFile = @{ FullName = "$script:ROOT_PATH\tests\helpers\file.tests.ps1" }

        $config = @{
            CodeCoverage = @{
                Enabled = $false
                Path = ''
                OutputPath = ''
                OutputFormat = ''
                OutputEncoding = ''
                CoveragePercentTarget = 75
            }
        }
        $options = @{
            target = 85
        }

        $result = Set-CoverageConfig -config $config -testFile $testFile -options $options -testsMap $testsMap

        $result.covered.FullName | Should -Be "$script:ROOT_PATH\src\helpers\file.ps1"
        $result.config.CodeCoverage.Enabled | Should -Be $true
        $result.config.CodeCoverage.CoveragePercentTarget | Should -Not -Be $null
    }
}

Describe "Get-SeparatorWidth" {
    It "Calculates separator width based on test names" {
        $tests = @(
            @{ Name = 'test1'; FullName = "$script:TEST_DRIVE\tests\test1.tests.ps1" }
            @{ Name = 'test2'; FullName = "$script:TEST_DRIVE\tests\test2.tests.ps1" }
        )

        $result = Get-SeparatorWidth -tests $tests

        $result | Should -BeGreaterThan 0
    }
}

Describe "Write-TestHeader" {
    It "Writes test header with covered file" {
        $file = @{ Name = 'file.tests.ps1'; FullName = "$script:TEST_DRIVE\tests\file.tests.ps1" }
        $coveredFile = @{ Name = 'file.ps1'; FullName = "$script:TEST_DRIVE\src\file.ps1" }
        $separatorWidth = 80

        Write-TestHeader -file $file -coveredFile $coveredFile -separatorWidth $separatorWidth

        Should -Invoke Show-Info -Times 4 -Exactly
    }

    It "Writes test header without covered file" {
        $file = @{ Name = 'file.tests.ps1'; FullName = "$script:TEST_DRIVE\tests\file.tests.ps1" }
        $separatorWidth = 80

        Write-TestHeader -file $file -coveredFile $null -separatorWidth $separatorWidth

        Should -Invoke Show-Info -Times 3 -Exactly
    }
}

Describe "Format-TestResultMessage" {
    It "Formats message with coverage" {
        $testResult = @{ PassedCount = 10; FailedCount = 2 }
        $rawDuration = 5.5
        $coverageRaw = 85.5

        $result = Format-TestResultMessage -testResult $testResult -rawDuration $rawDuration -coverageRaw $coverageRaw

        $result | Should -Match 'Passed : 10'
        $result | Should -Match 'Failed : 2'
        $result | Should -Match 'Duration'
        $result | Should -Match 'Coverage'
    }

    It "Formats message without coverage" {
        $testResult = @{ PassedCount = 10; FailedCount = 2 }
        $rawDuration = 5.5
        $coverageRaw = $null

        $result = Format-TestResultMessage -testResult $testResult -rawDuration $rawDuration -coverageRaw $coverageRaw

        $result | Should -Match 'Passed : 10'
        $result | Should -Match 'Failed : 2'
        $result | Should -Match 'Duration'
        $result | Should -Not -Match 'Coverage'
    }

    It "Shows 0s for invalid duration" {
        $testResult = @{ PassedCount = 10; FailedCount = 2 }
        $rawDuration = -1
        $coverageRaw = $null

        $result = Format-TestResultMessage -testResult $testResult -rawDuration $rawDuration -coverageRaw $coverageRaw

        $result | Should -Match 'Duration.*0s'
    }
}

Describe "Get-CoverageGroupName" {
    It "Returns 'n/a' for null coverage" {
        $result = Get-CoverageGroupName -coverageRaw $null

        $result | Should -Be 'n/a'
    }

    It "Returns '100%' for 100 or more" {
        $result = Get-CoverageGroupName -coverageRaw 100

        $result | Should -Be '100%'
    }

    It "Returns '90%+' for 90-99.99" {
        $result = Get-CoverageGroupName -coverageRaw 95

        $result | Should -Be '90%+'
    }

    It "Returns '80%+' for 80-89.99" {
        $result = Get-CoverageGroupName -coverageRaw 85

        $result | Should -Be '80%+'
    }

    It "Returns '70%+' for 70-79.99" {
        $result = Get-CoverageGroupName -coverageRaw 75

        $result | Should -Be '70%+'
    }

    It "Returns '60%+' for 60-69.99" {
        $result = Get-CoverageGroupName -coverageRaw 65

        $result | Should -Be '60%+'
    }

    It "Returns '50%+' for 50-59.99" {
        $result = Get-CoverageGroupName -coverageRaw 55

        $result | Should -Be '50%+'
    }

    It "Returns '<50%' for less than 50" {
        $result = Get-CoverageGroupName -coverageRaw 45

        $result | Should -Be '<50%'
    }
}

Describe "Get-FolderGroupName" {
    It "Returns 'n/a' for file not found message" {
        $item = @{ Message = 'File not found!' }

        $result = Get-FolderGroupName -item $item

        $result | Should -Be 'n/a'
    }

    It "Returns '(root)' for root level file" {
        $item = @{ Message = 'Test'; relativeFilePath = 'file.ps1' }

        $result = Get-FolderGroupName -item $item

        $result | Should -Be '(root)'
    }

    It "Returns folder name for nested file" {
        $item = @{ Message = 'Test'; relativeFilePath = 'helpers\file.ps1' }

        $result = Get-FolderGroupName -item $item

        $result | Should -Be 'helpers'
    }

    It "Normalizes backslashes to forward slashes" {
        $item = @{ Message = 'Test'; relativeFilePath = 'src\helpers\file.ps1' }

        $result = Get-FolderGroupName -item $item

        $result | Should -Be 'src/helpers'
    }
}

Describe "Get-CoverageGroupRank" {
    It "Returns correct rank for each group" {
        $groups = @('<50%', '50%+', '60%+', '70%+', '80%+', '90%+', '100%', 'n/a')

        $ranks = foreach ($group in $groups) {
            Get-CoverageGroupRank -groupName $group
        }

        $ranks | Should -Be @(0, 1, 2, 3, 4, 5, 6, 7)
    }

    It "Returns 999 for unknown group" {
        $result = Get-CoverageGroupRank -groupName 'unknown'

        $result | Should -Be 999
    }
}

Describe "Write-TestsSummary" {
    It "Writes tests summary with default options" {
        $testData = @{
            testSummary = @(
                @{
                    sortedName = 'test1'
                    message   = @{ content = 'PASS'; color = 'Green' }
                    testResultData = @{ duration = 1; coverageRaw = 80 }
                }
            )
        }

        $options = @{
            sortBy  = $null
            groupBy = $null
        }

        Write-TestsSummary -testData $testData -options $options -maxLineLength 80

        Should -Invoke New-Line -Times 1 -Exactly
    }

    It "Writes tests summary grouped by coverage" {
        $testData = @{
            testSummary = @(
                @{
                    sortedName = 'test1'
                    message   = @{ content = 'PASS'; color = 'Green' }
                    testResultData = @{ duration = 1; coverageRaw = 80 }
                }
            )
        }

        $options = @{
            sortBy  = $null
            groupBy = 'coverage'
        }

        Write-TestsSummary -testData $testData -options $options -maxLineLength 80

        Should -Invoke Show-Info -Times 1 -Exactly
    }

    It "Writes tests summary grouped by folder" {
        $testItem = @{
            sortedName = 'test1'
            message   = @{ content = 'PASS'; color = 'Green' }
            testResultData = @{ duration = 1; coverageRaw = 80 }
            relativeFilePath = 'helpers\file.ps1'
        }
        $testItem | Add-Member -MemberType NoteProperty -Name 'Message' -Value 'Some message' -Force

        $testData = @{
            testSummary = @($testItem)
        }

        $options = @{
            sortBy  = $null
            groupBy = 'folder'
        }

        Write-TestsSummary -testData $testData -options $options -maxLineLength 80

        Should -Invoke Show-Info -Times 1 -Exactly
    }
}

Describe "Get-SortedTests" {
    It "Returns unsorted data when by is null" {
        $data = @(
            @{ sortedName = 'test1'; testResultData = @{ duration = 1; coverageRaw = 50 } }
            @{ sortedName = 'test2'; testResultData = @{ duration = 2; coverageRaw = 60 } }
        )

        $result = Get-SortedTests -data $data -by $null

        $result.Count | Should -Be 2
    }

    It "Sorts by duration ascending" {
        $data = @(
            @{ sortedName = 'test1'; testResultData = @{ duration = 2; coverageRaw = 50 } }
            @{ sortedName = 'test2'; testResultData = @{ duration = 1; coverageRaw = 60 } }
        )

        $result = Get-SortedTests -data $data -by 'duration'

        $result[0].sortedName | Should -Be 'test2'
        $result[1].sortedName | Should -Be 'test1'
    }

    It "Sorts by duration descending" {
        $data = @(
            @{ sortedName = 'test1'; testResultData = @{ duration = 1; coverageRaw = 50 } }
            @{ sortedName = 'test2'; testResultData = @{ duration = 2; coverageRaw = 60 } }
        )

        $result = Get-SortedTests -data $data -by '-duration'

        $result[0].sortedName | Should -Be 'test2'
        $result[1].sortedName | Should -Be 'test1'
    }

    It "Sorts by coverage ascending" {
        $data = @(
            @{ sortedName = 'test1'; testResultData = @{ duration = 1; coverageRaw = 60 } }
            @{ sortedName = 'test2'; testResultData = @{ duration = 2; coverageRaw = 50 } }
        )

        $result = Get-SortedTests -data $data -by 'coverage'

        $result[0].sortedName | Should -Be 'test2'
        $result[1].sortedName | Should -Be 'test1'
    }

    It "Sorts by coverage descending" {
        $data = @(
            @{ sortedName = 'test1'; testResultData = @{ duration = 1; coverageRaw = 50 } }
            @{ sortedName = 'test2'; testResultData = @{ duration = 2; coverageRaw = 60 } }
        )

        $result = Get-SortedTests -data $data -by '-coverage'

        $result[0].sortedName | Should -Be 'test2'
        $result[1].sortedName | Should -Be 'test1'
    }

    It "Sorts by file name ascending" {
        $data = @(
            @{ sortedName = 'test2'; testResultData = @{ duration = 1; coverageRaw = 50 } }
            @{ sortedName = 'test1'; testResultData = @{ duration = 2; coverageRaw = 60 } }
        )

        $result = Get-SortedTests -data $data -by 'file'

        $result[0].sortedName | Should -Be 'test1'
        $result[1].sortedName | Should -Be 'test2'
    }

    It "Handles null duration in sorting" {
        $data = @(
            @{ sortedName = 'test1'; testResultData = @{ duration = $null; coverageRaw = 50 } }
            @{ sortedName = 'test2'; testResultData = @{ duration = 1; coverageRaw = 60 } }
        )

        $result = Get-SortedTests -data $data -by 'duration'

        $result[0].sortedName | Should -Be 'test2'
        $result[1].sortedName | Should -Be 'test1'
    }

    It "Handles null coverage in sorting" {
        $data = @(
            @{ sortedName = 'test1'; testResultData = @{ duration = 1; coverageRaw = $null } }
            @{ sortedName = 'test2'; testResultData = @{ duration = 2; coverageRaw = 60 } }
        )

        $result = Get-SortedTests -data $data -by 'coverage'

        $result[0].sortedName | Should -Be 'test2'
        $result[1].sortedName | Should -Be 'test1'
    }
}

Describe "Set-TestDrive" {
    BeforeAll {
        $script:testRoot = "$script:TEST_DRIVE\pvm"
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        @(
            'PHP_CURRENT_VERSION_PATH=C:\pvm\php'
            'PVM_ENV_VAR_NAME=PVM'
            'CACHE_MAX_HOURS=168'
            'DEFAULT_LOG_PAGE_SIZE=5'
            'DEFAULT_PARTIAL_LIST_SIZE=10'
            'MIN_PAD_RIGHT_LENGTH=20'
            'MIN_LINE_LENGTH=50'
        ) -join "`n" | Set-ContentWrapper -path "$testRoot\.env"
    }

    BeforeEach {
        $Global:PVMConfig = Get-Config -rootPath $testRoot
    }

    AfterEach {
        Remove-Variable -Name PVMConfig -Scope Global -ErrorAction SilentlyContinue
    }

    It "Rewrites PVMConfig.paths. under the given root" {
        $fakeRoot = "$script:TEST_DRIVE\fake-root"

        Set-TestDrive -path $fakeRoot

        $Global:PVMConfig.rootPath | Should -Be $fakeRoot
        $Global:PVMConfig.paths.directories.root | Should -Be $fakeRoot
        $Global:PVMConfig.paths.directories.storage | Should -Be "$fakeRoot\storage"

        $Global:PVMConfig.paths.directories.testDrive | Should -Be $fakeRoot

        $Global:PVMConfig.paths.directories.php | Should -Be "$fakeRoot\storage\php"
        $Global:PVMConfig.paths.directories.data | Should -Be "$fakeRoot\storage\data"
        $Global:PVMConfig.paths.directories.cache | Should -Be "$fakeRoot\storage\data\cache"
        $Global:PVMConfig.paths.directories.templates | Should -Be "$fakeRoot\storage\data\templates"
        $Global:PVMConfig.paths.directories.profiles | Should -Be "$fakeRoot\storage\data\profiles"
        $Global:PVMConfig.paths.directories.log | Should -Be "$fakeRoot\storage\logs"
        $Global:PVMConfig.paths.directories.assets | Should -Be "$fakeRoot\assets"

        $Global:PVMConfig.paths.files.profileExample | Should -Be "$fakeRoot\storage\data\profiles\profile-example.json"
        $Global:PVMConfig.paths.files.profileTemplate | Should -Be "$fakeRoot\storage\data\templates\profile-template.json"
        $Global:PVMConfig.paths.files.zendExtensionsList | Should -Be "$fakeRoot\storage\data\templates\zend_extensions.json"
        $Global:PVMConfig.paths.files.aliasesList | Should -Be "$fakeRoot\storage\data\templates\aliases.json"
        $Global:PVMConfig.paths.files.scriptsList | Should -Be "$fakeRoot\storage\data\templates\scripts.json"
        $Global:PVMConfig.paths.files.logError | Should -Be "$fakeRoot\storage\logs\error.log"
        $Global:PVMConfig.paths.files.pathVarBackup | Should -Be "$fakeRoot\storage\data\state\path.bak.log"
        $Global:PVMConfig.paths.files.lastUpdateCheck | Should -Be "$fakeRoot\storage\data\state\last_update_check.txt"
    }

    It "Rewrites env.PHP_CURRENT_VERSION_PATH under the given root" {
        $fakeRoot = "$script:TEST_DRIVE\fake-root"

        Set-TestDrive -path $fakeRoot

        $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH | Should -Be "$fakeRoot\pvm\php"
    }

    It "Does not touch unrelated config sections" {
        $fakeRoot = "$script:TEST_DRIVE\fake-root"
        $originalVersion = $Global:PVMConfig.version
        $originalLinks = [ordered]@{}
        $Global:PVMConfig.links.GetEnumerator() | ForEach-Object -Process {
            $originalLinks[$_.Key] = $_.Value
        }

        Set-TestDrive -path $fakeRoot

        $Global:PVMConfig.version | Should -Be $originalVersion
        $Global:PVMConfig.links.GetEnumerator() | ForEach-Object -Process {
            $Global:PVMConfig.links[$_.Key] | Should -Be $originalLinks[$_.Key]
        }
    }

    It "Overwrites previously-set fake paths when called again with a new root" {
        $firstRoot = "$script:TEST_DRIVE\fake-root-1"
        $secondRoot = "$script:TEST_DRIVE\fake-root-2"

        Set-TestDrive -path $firstRoot
        Set-TestDrive -path $secondRoot

        $Global:PVMConfig.rootPath | Should -Be $secondRoot
        $Global:PVMConfig.paths.directories.root | Should -Be $secondRoot
        $Global:PVMConfig.paths.directories.storage | Should -Be "$secondRoot\storage"
        $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH | Should -Be "$secondRoot\pvm\php"
    }
}
