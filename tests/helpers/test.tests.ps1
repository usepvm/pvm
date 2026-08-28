
Describe "Test-IsNotQuiet" {
    It "Returns false when verbosity is None" {
        $result = Test-IsNotQuiet -verbosity 'None'

        $result | Should -Be $false
    }

    It "Returns true when verbosity is not None" {
        $result = Test-IsNotQuiet -verbosity 'Normal'

        $result | Should -Be $true
    }
}

Describe "Show-Scripts" {
    BeforeEach {
        Mock Write-Cyan {}
        Mock Write-White {}
        Mock Write-DarkGray {}
    }

    It "Displays the available scripts and commands" {
        Mock Get-Scripts {
            [ordered]@{
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
        Mock Get-Scripts { @{} }

        Show-Scripts

        Should -Invoke Write-Cyan -Times 1 -Exactly
        Should -Not -Invoke Write-White
        Should -Not -Invoke Write-DarkGray
    }
}