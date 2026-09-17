
Describe "Resolve-Alias" {
    $testCases = @(
        @{ command = '?'; expected = 'help' }
        @{ command = 'h'; expected = 'help' }
        @{ command = 'H'; expected = 'help' }
        @{ command = 'INIT'; expected = 'setup' }
        @{ command = 'CUR'; expected = 'current' }
        @{ command = 'ACTive'; expected = 'current' }
        @{ command = 'ls'; expected = 'list' }
        @{ command = 'list'; expected = 'list' }
        @{ command = 'u'; expected = 'uninstall' }
        @{ command = 'U'; expected = 'uninstall' }
        @{ command = 'uninstall'; expected = 'uninstall' }
        @{ command = 'I'; expected = 'install' }
        @{ command = 'install'; expected = 'install' }
        @{ command = 'SWITCH'; expected = 'use' }
        @{ command = 'ON'; expected = 'enable' }
        @{ command = 'OFF'; expected = 'disable' }
        @{ command = 'A'; expected = 'add' }
        @{ command = '+'; expected = 'add' }
        @{ command = 'rm'; expected = 'remove' }
        @{ command = '-'; expected = 'remove' }
        @{ command = 'i'; expected = 'install' }
        @{ command = 'LS'; expected = 'list' }
        @{ command = 'RM'; expected = 'remove' }
        @{ command = 'DEL'; expected = 'delete' }
        @{ command = 'CLS'; expected = 'clear' }
        @{ command = 'unknown'; expected = 'unknown' }
        @{ command = ''; expected = $null }
        @{ command = '    '; expected = $null }
        @{ command = $null; expected = $null }
    )

    It "Returns '<Expected>' when '<Command>' is passed" -TestCases $testCases {
        param ($command, $expected)
        $result = Resolve-Alias -alias $command
        $result | Should -Be $expected
    }

    It "Returns the alias itself when Get-Aliases returns null" {
        Mock Get-Aliases { return $null }

        $result = Resolve-Alias -alias 'ls'
        $result | Should -Be 'ls'
    }

    It "Returns the alias itself when Get-Aliases returns an empty hashtable" {
        Mock Get-Aliases { return @{} }

        $result = Resolve-Alias -alias 'ls'
        $result | Should -Be 'ls'
    }
}

Describe "Resolve-FlagCommand" {
    $testCases = @(
        @{ command = '--version'; expected = 'version' }
        @{ command = '-v'; expected = 'version' }
        @{ command = '--help'; expected = 'help' }
        @{ command = '-h'; expected = 'help' }
        @{ command = 'unknown'; expected = $null }
        @{ command = ''; expected = $null }
        @{ command = '    '; expected = $null }
    )

    It "Returns '<Expected>' when '<Command>' is passed" -TestCases $testCases {
        param ($command, $expected)
        $result = Resolve-FlagCommand -arguments @($command)
        $result | Should -Be $expected
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
            Mock Test-OS64Bit { return $true }
            $arguments = @('some_arg', 'other_arg')

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x64'
        }

        It "Returns x86 as default when 32-bit OS and choseDefault is true" {
            Mock Test-OS64Bit { return $false }
            $arguments = @('some_arg', 'other_arg')

            $result = Resolve-Arch -arguments $arguments -choseDefault $true
            $result | Should -Be 'x86'
        }

        It "Returns argument arch even when choseDefault is true" {
            Mock Test-OS64Bit { return $true }
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
            Mock Test-OS64Bit { return $true }
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

Describe "Resolve-VersionsFromArguments" {
    Context "Basic version extraction" {
        It "Returns single version when one version is provided" {
            $arguments = @('8.2.0')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2.0')
        }

        It "Returns multiple versions when multiple versions are provided" {
            $arguments = @('8.2.0', '8.3.0', '8.1.0')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2.0', '8.3.0', '8.1.0')
        }

        It "Returns empty array when no versions are provided" {
            $arguments = @('some', 'other', 'args')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -BeNullOrEmpty
        }

        It "Returns empty array when arguments array is empty" {
            $arguments = @()
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -BeNullOrEmpty
        }

        It "Returns null when arguments is null" {
            $result = Resolve-VersionsFromArguments -arguments $null
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Version format validation" {
        It "Extracts version with two parts (major.minor)" {
            $arguments = @('8.2')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2')
        }

        It "Extracts version with one part (major)" {
            $arguments = @('8')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8')
        }

        It "Extracts version with three parts (major.minor.patch)" {
            $arguments = @('8.2.15')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2.15')
        }

        It "Filters out non-version arguments" {
            $arguments = @('8.2.0', 'some-flag', '8.3.0', '--another-flag', '8.1.0')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2.0', '8.3.0', '8.1.0')
        }

        It "Filters out arguments with special characters" {
            $arguments = @('8.2.0', 'latest', 'auto', '--flag')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2.0')
        }

        It "Filters out arguments with letters" {
            $arguments = @('8.2.0', 'abc', '8.3.0', 'def')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2.0', '8.3.0')
        }

        It "Filters out arguments with dots and letters" {
            $arguments = @('8.2.0', '8.2.0rc1', '8.3.0beta')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2.0')
        }
    }

    Context "Mixed arguments" {
        It "Extracts versions from mixed valid and invalid arguments" {
            $arguments = @('--arch', 'x64', '8.2.0', '--build', 'ts', '8.3.0')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('8.2.0', '8.3.0')
        }

        It "Maintains order of versions as they appear in arguments" {
            $arguments = @('8.1.0', '8.2.0', '8.3.0')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result[0] | Should -Be '8.1.0'
            $result[1] | Should -Be '8.2.0'
            $result[2] | Should -Be '8.3.0'
        }

        It "Handles single digit versions" {
            $arguments = @('7', '8')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('7', '8')
        }

        It "Handles versions with leading zeros" {
            $arguments = @('08.02.00', '08.03.00')
            $result = Resolve-VersionsFromArguments -arguments $arguments
            $result | Should -Be @('08.02.00', '08.03.00')
        }
    }
}
