
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
}

AfterAll {
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Resolve-Alias Tests" {
    $testCases = @(
        @{ Command = '?'; Expected = 'help' }
        @{ Command = 'h'; Expected = 'help' }
        @{ Command = 'H'; Expected = 'help' }
        @{ Command = 'INIT'; Expected = 'setup' }
        @{ Command = 'CUR'; Expected = 'current' }
        @{ Command = 'ACTive'; Expected = 'current' }
        @{ Command = 'ls'; Expected = 'list' }
        @{ Command = 'list'; Expected = 'list' }
        @{ Command = 'u'; Expected = 'uninstall' }
        @{ Command = 'U'; Expected = 'uninstall' }
        @{ Command = 'uninstall'; Expected = 'uninstall' }
        @{ Command = 'I'; Expected = 'install' }
        @{ Command = 'install'; Expected = 'install' }
        @{ Command = 'SWITCH'; Expected = 'use' }
        @{ Command = 'ON'; Expected = 'enable' }
        @{ Command = 'OFF'; Expected = 'disable' }
        @{ Command = 'A'; Expected = 'add' }
        @{ Command = '+'; Expected = 'add' }
        @{ Command = 'rm'; Expected = 'remove' }
        @{ Command = '-'; Expected = 'remove' }
        @{ Command = 'i'; Expected = 'install' }
        @{ Command = 'LS'; Expected = 'list' }
        @{ Command = 'RM'; Expected = 'remove' }
        @{ Command = 'DEL'; Expected = 'delete' }
        @{ Command = 'CLS'; Expected = 'clear' }
        @{ Command = 'unknown'; Expected = 'unknown' }
        @{ Command = ''; Expected = $null }
        @{ Command = '    '; Expected = $null }
        @{ Command = $null; Expected = $null }
    )

    It "Returns '<Expected>' when '<Command>' is passed" -TestCases $testCases {
        param ($Command, $Expected)
        $result = Resolve-Alias -alias $Command
        $result | Should -Be $Expected
    }
}

Describe "Resolve-FlagCommand" {
    $testCases = @(
        @{ Command = '--version'; Expected = 'version' }
        @{ Command = '-v'; Expected = 'version' }
        @{ Command = '--help'; Expected = 'help' }
        @{ Command = '-h'; Expected = 'help' }
        @{ Command = 'unknown'; Expected = $null }
        @{ Command = ''; Expected = $null }
        @{ Command = '    '; Expected = $null }
    )

    It "Returns '<Expected>' when '<Command>' is passed" -TestCases $testCases {
        param ($Command, $Expected)
        $result = Resolve-FlagCommand -arguments @($Command)
        $result | Should -Be $Expected
    }
}

Describe "Resolve-BuildType" {
    Context "When searching in arguments" {
        It "Returns nts when nts is in arguments" {
            $arguments = @('some_arg', 'nts', 'another_arg')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'nts'
        }

        It "Returns ts when ts is in arguments" {
            $arguments = @('some_arg', 'ts', 'another_arg')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'ts'
        }

        It "Returns first matching architecture when multiple are present" {
            $arguments = @('ts', 'nts', 'other')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'ts'
        }

        It "Returns null when no matching architecture in arguments" {
            $arguments = @('some_arg', 'another_arg', 'third_arg')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Case insensitivity" {
        It "Returns lowercase nts when uppercase NTS provided" {
            $arguments = @('NTS')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'nts'
        }

        It "Returns lowercase TS when mixed case TS provided" {
            $arguments = @('TS')
            $result = Resolve-BuildType -arguments $arguments
            $result | Should -Be 'TS'
        }
    }

    Context "With default choice" {
        It "Returns ts as default when choseDefault is true" {
            $arguments = @('some_arg', 'other_arg')

            $result = Resolve-BuildType -arguments $arguments -choseDefault $true
            $result | Should -Be 'ts'
        }

        It "Returns argument arch even when choseDefault is true" {
            $arguments = @('nts', 'some_arg')

            $result = Resolve-BuildType -arguments $arguments -choseDefault $true
            $result | Should -Be 'nts'
        }
    }

    Context "With empty or null inputs" {
        It "Returns null when arguments array is empty and choseDefault is false" {
            $arguments = @()
            $result = Resolve-BuildType -arguments $arguments -choseDefault $false
            $result | Should -BeNullOrEmpty
        }

        It "Returns default when arguments array is empty and choseDefault is true" {
            $arguments = @()

            $result = Resolve-BuildType -arguments $arguments -choseDefault $true
            $result | Should -Be 'ts'
        }

        It "Returns null when arguments is null" {
            $result = Resolve-BuildType -arguments $null
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Resolve-Arch" {
    Context "When searching in arguments" {
        It "Returns x86 when x86 is in arguments" {
            $arguments = @('some_arg', 'x86', 'another_arg')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x86'
        }

        It "Returns x64 when x64 is in arguments" {
            $arguments = @('some_arg', 'x64', 'another_arg')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x64'
        }

        It "Returns first matching architecture when multiple are present" {
            $arguments = @('x86', 'x64', 'other')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x86'
        }

        It "Returns null when no matching architecture in arguments" {
            $arguments = @('some_arg', 'another_arg', 'third_arg')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Case insensitivity" {
        It "Returns lowercase x86 when uppercase X86 provided" {
            $arguments = @('X86')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x86'
        }

        It "Returns lowercase x64 when mixed case X64 provided" {
            $arguments = @('X64')
            $result = Resolve-Arch -arguments $arguments
            $result | Should -Be 'x64'
        }
    }

    Context "With default choice" {
        It "Returns x64 as default when 64-bit OS and choseDefault is true" {
            Mock Is-OS-64Bit { return $true }
            $arguments = @('some_arg', 'other_arg')

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x64'
        }

        It "Returns x86 as default when 32-bit OS and choseDefault is true" {
            Mock Is-OS-64Bit { return $false }
            $arguments = @('some_arg', 'other_arg')

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x86'
        }

        It "Returns argument arch even when choseDefault is true" {
            Mock Is-OS-64Bit { return $true }
            $arguments = @('x86', 'some_arg')

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x86'
        }
    }

    Context "With empty or null inputs" {
        It "Returns null when arguments array is empty and choseDefault is false" {
            $arguments = @()
            $result = Resolve-Arch -arguments $arguments -choseDefault $false
            $result | Should -BeNullOrEmpty
        }

        It "Returns default when arguments array is empty and choseDefault is true" {
            Mock Is-OS-64Bit { return $true }
            $arguments = @()

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x64'
        }

        It "Returns null when arguments is null" {
            $result = Resolve-Arch -arguments $null
            $result | Should -BeNullOrEmpty
        }
    }
}
