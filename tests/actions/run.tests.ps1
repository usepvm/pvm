
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\run-drive"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
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
        Mock Get-Actions { @{ 'test' = @{ action = { return 0 } } } }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be 0
        Should -Invoke Get-Actions -Times 1 -Exactly
        Should -Not -Invoke Invoke-PVMSubprocess
    }

    It 'Runs single command directly and returns result' {
        Mock Get-Scripts { @{'testscript' = @('test arg1')} }
        Mock Get-Actions { @{ 'test' = @{ action = { return 0 } } } }

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
        Mock Invoke-PVMSubprocess { @{ code = 1; output = '' } }

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
            param($command, $arguments)
            if ($arguments -eq 'arg1') { return @{ code = 0; output = '' } }
            return @{ code = 1; output = '' }
        }

        $result = Invoke-RunScripts -scriptName 'testscript'

        $result | Should -Be -1
    }
}
