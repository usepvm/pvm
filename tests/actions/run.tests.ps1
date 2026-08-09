
BeforeAll {
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\run-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    Mock Write-Color {}
    Mock Show-Message {}
    Mock Write-Yellow {}
    Mock Write-Cyan {}
    Mock Write-Gray {}
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe 'Show-SubProcessOutput' {
    It 'Handles string output that is valid JSON array' {
        Mock Write-Color {}
        Mock Show-Message {}

        $jsonOutput = '[{"message":"test","color":"red","noNewLine":false}]'
        Show-SubProcessOutput -output $jsonOutput

        Should -Invoke Write-Color -Times 1 -Exactly
        Should -Not -Invoke Show-Message
    }

    It 'Handles string output that is invalid JSON' {
        Mock Write-Color {}
        Mock Show-Message {}

        $invalidJson = 'not json'
        Show-SubProcessOutput -output $invalidJson

        Should -Not -Invoke Write-Color
        Should -Invoke Show-Message -Times 1 -Exactly
    }

    It 'Handles non-string output' {
        Mock Write-Color {}
        Mock Show-Message {}

        $arrayOutput = @('line1', 'line2')
        Show-SubProcessOutput -output $arrayOutput

        Should -Not -Invoke Write-Color
        Should -Invoke Show-Message -Times 2 -Exactly
    }
}

Describe 'Invoke-RunScripts' {
    BeforeEach {
        Mock Write-Yellow {}
        Mock Show-Scripts {}
        Mock Get-Scripts { @{} }
        Mock Write-Cyan {}
        Mock Write-Gray {}
        Mock Invoke-PVMSubprocess { @{ code = 0; output = '' } }
        Mock Get-Actions { @{} }
        Mock Show-SubProcessOutput {}
        Mock New-Lines {}
        Mock Add-LogEntry {}
        Mock Invoke-Sound {}
    }

    It 'Returns -1 when scriptName is null or whitespace' {
        $result = Invoke-RunScripts -scriptName $null

        $result | Should -Be -1
        Should -Invoke Write-Yellow -Times 1 -Exactly
        Should -Invoke Show-Scripts -Times 1 -Exactly
    }

    It 'Returns -1 when scriptName is empty string' {
        $result = Invoke-RunScripts -scriptName ''

        $result | Should -Be -1
        Should -Invoke Write-Yellow -Times 1 -Exactly
        Should -Invoke Show-Scripts -Times 1 -Exactly
    }

    It 'Returns 0 and shows scripts when scriptName is list' {
        $result = Invoke-RunScripts -scriptName 'list'

        $result | Should -Be 0
        Should -Invoke Show-Scripts -Times 1 -Exactly
        Should -Not -Invoke Get-Scripts
    }

    It 'Returns -1 when script is not found' {
        Mock Get-Scripts { @{'existing' = @()} }

        $result = Invoke-RunScripts -scriptName 'nonexistent'

        $result | Should -Be -1
        Should -Invoke Write-Yellow -Times 1 -Exactly
        Should -Invoke Show-Scripts -Times 1 -Exactly
    }

    It 'Returns -1 when command is not test' {
        Mock Get-Scripts { @{'testscript' = @('invalid command')} }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be -1
        Should -Invoke Write-Yellow -ParameterFilter { $message -like '*Invalid command*' } -Times 1 -Exactly
    }

    It "Runs single command in subprocess and returns result with no arguments" {
        Mock Get-Scripts { @{'testscript' = @('test')} }
        Mock Get-Actions { @{ 'test' = @{ data = @{ action = { return 0 } } } } }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be 0
        Should -Invoke Get-Actions -Times 1 -Exactly
        Should -Not -Invoke Invoke-PVMSubprocess
    }

    It 'Runs single command directly and returns result' {
        Mock Get-Scripts { @{'testscript' = @('test arg1')} }
        Mock Get-Actions { @{ 'test' = @{ data = @{ action = { return 0 } } } } }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be 0
        Should -Invoke Get-Actions -Times 1 -Exactly
        Should -Not -Invoke Invoke-PVMSubprocess
    }

    It 'Runs multiple commands in subprocess' {
        Mock Get-Scripts { @{'testscript' = @('test arg1', 'test arg2')} }
        Mock Invoke-PVMSubprocess { @{ code = 0; output = '' } }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be 0
        Should -Invoke Invoke-PVMSubprocess -Times 2 -Exactly
        Should -Invoke Show-SubProcessOutput -Times 2 -Exactly
    }

    It 'Returns -1 when any subprocess command fails' {
        Mock Get-Scripts { @{'testscript' = @('test arg1', 'test arg2')} }
        Mock Invoke-PVMSubprocess { @{ code = -1; output = '' } }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be -1
    }

    It 'Returns -1 on exception' {
        Mock Get-Scripts { throw 'Test exception' }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1 -Exactly
    }

    It 'Handles mixed success and failure in subprocess' {
        Mock Get-Scripts { @{'testscript' = @('test arg1', 'test arg2')} }
        Mock Invoke-PVMSubprocess {
            param ($command, $arguments)
            if ($arguments -eq 'arg1') { return @{ code = 0; output = '' } }
            return @{ code = -1; output = '' }
        }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be -1
    }

    It "Handles exception in subprocess" {
        $scripts =@('test arg1', 'test arg2')
        Mock Get-Scripts { @{'testscript' = $scripts } }
        Mock Invoke-PVMSubprocess { throw 'Test exception' }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be -1
        Should -Invoke Write-Yellow -Times $scripts.Count -Exactly
        Should -Invoke Add-LogEntry -Times $scripts.Count -Exactly
    }

    It "Returns -1 when multi-command script has invalid verbosity" {
        Mock Get-Scripts { @{'testscript' = @('test arg1 --verbosity=None', 'test arg2 --verbosity=Normal')} }
        Mock Invoke-PVMSubprocess { @{ code = 0; output = '' } }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be -1
        Should -Invoke Write-Yellow -ParameterFilter {
            $message -like "*Invalid verbosity in multi-command script 'testscript': 'test arg2 --verbosity=Normal' (only --verbosity=None is allowed when a script has more than one command)*"
        } -Exactly 1
    }

    It "Runs scripts with custom files" {
        Mock Get-Scripts { @{'testscript' = @('test arg1 --verbosity=None', 'test arg2 --pester=5.7 --verbosity=None')} }
        Mock Invoke-PVMSubprocess { @{ code = 0; output = '' } }

        $result = Invoke-RunScripts -scriptName 'testscript' -files @('file1.ps1', 'file2.ps1')

        $result | Should -Be 0
        Should -Invoke Invoke-PVMSubprocess -Times 1 -ParameterFilter {
            $command -eq 'test' -and
            $arguments -join ' | ' -eq 'arg1 | --verbosity=None | file1.ps1 | file2.ps1'
        }
        Should -Invoke Invoke-PVMSubprocess -Times 1 -ParameterFilter {
            $command -eq 'test' -and
            $arguments -join ' | ' -eq 'arg2 | --pester=5.7 | --verbosity=None | file1.ps1 | file2.ps1'
        }
    }
}
