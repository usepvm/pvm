
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:TEMPLATES_PATH = $Global:PVMConfig.paths.directories.templates
    $script:ALIASES_LIST_PATH = $Global:PVMConfig.paths.files.aliasesList
    $script:SCRIPTS_LIST_PATH = $Global:PVMConfig.paths.files.scriptsList
    $script:DEFAULT_ALIASES = $Global:PVMConfig.defaults.aliases
    $script:DEFAULT_SCRIPTS = $Global:PVMConfig.defaults.scripts
    $script:DEFAULT_FLAGS = $Global:PVMConfig.defaults.flags
}

Describe "Set-AliasesList" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $script:TEMPLATES_PATH | Out-Null
    }

    It "Creates aliases.json" {
        $result = Set-AliasesList
        $result | Should -Be 0

        $result = Get-Aliases
        $result.Count | Should -Be $script:DEFAULT_ALIASES.Count
    }

    It "Returns -1 when exception is thrown" {
        Mock Set-ContentWrapper { throw 'Test exception' }
        $result = Set-AliasesList
        $result | Should -Be -1
    }
}

Describe "Get-Aliases" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $script:TEMPLATES_PATH | Out-Null
        $testContent = [ordered]@{'?' = 'help'; 'i' = 'install'; 'init' = 'setup'}
        $testContent | ConvertTo-Json -Depth 10 | Set-ContentWrapper -path $script:ALIASES_LIST_PATH
    }

    It "Returns aliases from aliases.json or PVMConfig.defaults.aliases" {
        $result = Get-Aliases
        $result.Count | Should -Be 3
        $result['?'] | Should -Be 'help'
        $result['i'] | Should -Be 'install'
        $result['init'] | Should -Be 'setup'
    }

    It "Falls back to DEFAULT_ALIASES value" {
        Remove-ItemWrapper -path "$script:TEMPLATES_PATH\aliases.json"
        $result = Get-Aliases
        $result.Count | Should -Be $script:DEFAULT_ALIASES.Count
    }

    It "Returns default value when exception is thrown" {
        Mock Test-FileExists { return $true }
        Mock Get-ContentWrapper { throw 'Test exception' }
        $result = Get-Aliases
        $result.Count | Should -Be $script:DEFAULT_ALIASES.Count
    }
}

Describe "Get-FlagMap" {
    It "Returns PVMConfig.defaults.flags" {
        $result = Get-FlagMap
        $result.Count | Should -Be $script:DEFAULT_FLAGS.Count
    }
}

Describe "Set-Scripts-List" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $script:TEMPLATES_PATH | Out-Null
    }

    It "Creates scripts.json" {
        $result = Set-ScriptsList
        $result | Should -Be 0

        $result = Get-Scripts
        $result.Count | Should -Be $script:DEFAULT_SCRIPTS.Count
    }

    It "Returns -1 when exception is thrown" {
        Mock Set-ContentWrapper { throw 'Test exception' }
        $result = Set-ScriptsList
        $result | Should -Be -1
    }
}

Describe "Get-Scripts" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $script:TEMPLATES_PATH | Out-Null
        $testContent = [ordered]@{'test:quiet' = 'test --verbosity=None'; 'test:cov' = 'test --coverage=75'}
        $testContent | ConvertTo-Json -Depth 10 | Set-ContentWrapper -path $script:SCRIPTS_LIST_PATH
    }

    It "Returns scripts from scripts.json or PVMConfig.defaults.scripts" {
        $result = Get-Scripts
        $result.Count | Should -Be 2
        $result['test:quiet'] | Should -Be 'test --verbosity=None'
        $result['test:cov'] | Should -Be 'test --coverage=75'
    }

    It "Falls back to DEFAULT_SCRIPTS value" {
        Remove-ItemWrapper -path "$script:TEMPLATES_PATH\scripts.json"
        $result = Get-Scripts
        $result.Count | Should -Be $script:DEFAULT_SCRIPTS.Count
    }

    It "Returns default value when exception is thrown" {
        Mock Test-FileExists { return $true }
        Mock Get-ContentWrapper { throw 'Test exception' }
        $result = Get-Scripts
        $result.Count | Should -Be $script:DEFAULT_SCRIPTS.Count
    }
}

Describe "Get-EnvBool" {
    It 'returns $true for "true" (any case)' {
        $code = Get-EnvBool -value 'true'
        $code | Should -BeTrue

        $code = Get-EnvBool -value 'True'
        $code | Should -BeTrue

        $code = Get-EnvBool -value 'TRUE'
        $code | Should -BeTrue
    }

    It 'returns $false for "false" (any case)' {
        $code = Get-EnvBool -value 'false'
        $code | Should -BeFalse

        $code = Get-EnvBool -value 'False'
        $code | Should -BeFalse

        $code = Get-EnvBool -value 'FALSE'
        $code | Should -BeFalse
    }

    It 'returns the default when value is $null' {
        $code = Get-EnvBool -value $null -default $true
        $code | Should -BeTrue

        $code = Get-EnvBool -value $null -default $false
        $code | Should -BeFalse
    }

    It 'returns the default when value is empty string' {
        $code = Get-EnvBool -value '' -default $true
        $code | Should -BeTrue
    }

    It 'returns the default when value is whitespace only' {
        $code = Get-EnvBool -value '   ' -default $true
        $code | Should -BeTrue
    }

    It 'returns the default when value is unparsable garbage' {
        $code = Get-EnvBool -value 'yes' -default $true
        $code | Should -BeTrue

        $code = Get-EnvBool -value '1' -default $false
        $code | Should -BeFalse

        $code = Get-EnvBool -value 'not-a-bool' -default $true
        $code | Should -BeTrue
    }

    It 'defaults to $false when no default is supplied and value is invalid' {
        $code = Get-EnvBool -value 'garbage'
        $code | Should -BeFalse
    }

    It 'trims surrounding whitespace around a valid value' {
        $code = Get-EnvBool -value '  true  '
        $code | Should -BeTrue
    }

    It 'does not throw on any input' {
        { Get-EnvBool -value $null } | Should -Not -Throw
        { Get-EnvBool -value '' } | Should -Not -Throw
        { Get-EnvBool -value 'nonsense' } | Should -Not -Throw
    }
}

Describe "Get-EnvInt" {
    It 'parses a valid positive integer' {
        $code = Get-EnvInt -value '42'
        $code | Should -Be 42
    }

    It 'parses a valid negative integer' {
        $code = Get-EnvInt -value '-5'
        $code | Should -Be -5
    }

    It 'parses zero' {
        $code = Get-EnvInt -value '0'
        $code | Should -Be 0
    }

    It 'returns the default when value is $null' {
        $code = Get-EnvInt -value $null -default 24
        $code | Should -Be 24
    }

    It 'returns the default when value is empty string' {
        $code = Get-EnvInt -value '' -default 24
        $code | Should -Be 24
    }

    It 'returns the default when value is whitespace only' {
        $code = Get-EnvInt -value '   ' -default 10
        $code | Should -Be 10
    }

    It 'returns the default when value is non-numeric' {
        $code = Get-EnvInt -value 'abc' -default 10
        $code | Should -Be 10
    }

    It 'returns the default when value is a decimal (not a valid int)' {
        $code = Get-EnvInt -value '3.14' -default 10
        $code | Should -Be 10
    }

    It 'defaults to 0 when no default is supplied and value is invalid' {
        $code = Get-EnvInt -value 'garbage'
        $code | Should -Be 0
    }

    It 'trims surrounding whitespace around a valid value' {
        $code = Get-EnvInt -value '  42  '
        $code | Should -Be 42
    }

    It 'does not throw on any input' {
        { Get-EnvInt -value $null } | Should -Not -Throw
        { Get-EnvInt -value '' } | Should -Not -Throw
        { Get-EnvInt -value 'nonsense' } | Should -Not -Throw
    }

    It 'handles values exceeding Int32 range by falling back to default' {
        $code = Get-EnvInt -value '99999999999999999999' -default 5
        $code | Should -Be 5
    }
}

Describe "Get-EnvPath" {
    Context "When value is valid" {
        BeforeEach {
            Mock Test-InvalidDrivePath { return $false }
        }

        It 'returns the value for a valid drive-rooted path' {
            $code = Get-EnvPath -value 'C:\storage\tests'
            $code | Should -Be 'C:\storage\tests'
        }

        It 'accepts any drive letter' {
            $code = Get-EnvPath -value 'D:\foo\bar'
            $code | Should -Be 'D:\foo\bar'

            $code = Get-EnvPath -value 'z:\foo\bar'
            $code | Should -Be 'z:\foo\bar'
        }

        It 'accepts a bare drive root' {
            $code = Get-EnvPath -value 'C:'
            $code | Should -Be 'C:'
        }

        It 'trims surrounding whitespace around a valid value' {
            $code = Get-EnvPath -value '  C:\storage\tests  '
            $code | Should -Be 'C:\storage\tests'
        }
    }

    Context "When value is invalid" {
        BeforeEach {
            Mock Test-InvalidDrivePath { return $true }
        }

        It 'returns the default when value is empty string' {
            $code = Get-EnvPath -value '' -default 'C:\default'
            $code | Should -Be 'C:\default'
        }

        It 'returns the default when value is whitespace only' {
            $code = Get-EnvPath -value '   ' -default 'C:\default'
            $code | Should -Be 'C:\default'
        }

        It 'returns the default when value has no drive prefix' {
            $code = Get-EnvPath -value 'storage\tests' -default 'C:\default'
            $code | Should -Be 'C:\default'

            $code = Get-EnvPath -value '\storage\tests' -default 'C:\default'
            $code | Should -Be 'C:\default'
        }

        It 'returns the default for a UNC path' {
            $code = Get-EnvPath -value '\\server\share' -default 'C:\default'
            $code | Should -Be 'C:\default'
        }

        It 'returns the default when value contains invalid path characters' {
            $code = Get-EnvPath -value "C:\storage\test`0dir" -default 'C:\default'
            $code | Should -Be 'C:\default'
        }

        It 'returns the default when value is $null' {
            $code = Get-EnvPath -value $null -default 'C:\default'
            $code | Should -Be 'C:\default'
        }
    }

    It 'defaults to $null when no default is supplied and value is invalid' {
        $code = Get-EnvPath -value 'garbage'
        $code | Should -BeNullOrEmpty
    }

    It 'does not throw on any input' {
        { Get-EnvPath -value $null } | Should -Not -Throw
        { Get-EnvPath -value '' } | Should -Not -Throw
        { Get-EnvPath -value 'nonsense' } | Should -Not -Throw
    }
}

Describe "Get-EnvConfig" {
    BeforeEach {
        $script:envRoot = "$script:TEST_DRIVE\envconfig"
        New-Item -ItemType Directory -Path $script:envRoot -Force | Out-Null
    }

    Context "When .env file is missing" {
        It "Copies .env.example to .env" {
            Set-ContentWrapper -path "$envRoot\.env.example" -value 'KEY=value'
            Get-EnvConfig -rootPath $envRoot

            $result = Get-ContentWrapper -path "$envRoot\.env"
            $result | Should -Be 'KEY=value'
        }
    }

    Context "When .env file exists" {
        It "Writes a verbose message with the env file path" {
            Set-ContentWrapper -path "$envRoot\.env" -value 'KEY=value'
            Mock Write-Verbose { }

            Get-EnvConfig -rootPath $envRoot

            Should -Invoke Write-Verbose -ParameterFilter {
                $message -eq "Using .env from: $envRoot\.env"
            } -Times 1 -Exactly
        }

        It "Returns a hashtable of parsed key=value pairs" {
            @(
                'PHP_CURRENT_VERSION_PATH=C:\pvm\php'
                'CACHE_MAX_HOURS=168'
                'DEFAULT_LOG_PAGE_SIZE=5'
            ) -join "`n" | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 3
            $result['PHP_CURRENT_VERSION_PATH'] | Should -Be 'C:\pvm\php'
            $result['CACHE_MAX_HOURS'] | Should -Be '168'
            $result['DEFAULT_LOG_PAGE_SIZE'] | Should -Be '5'
        }

        It "Skips empty lines and comment lines" {
            @(
                ''
                '# Top-level comment'
                '   # Indented comment'
                ''
                'KEY=value'
                ''
            ) -join "`n" | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result.Count | Should -Be 1
            $result['KEY'] | Should -Be 'value'
        }

        It "Trims whitespace around keys and values" {
            '  KEY  =  value  ' | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['KEY'] | Should -Be 'value'
        }

        It "Removes matching double quotes from values" {
            'QUOTED="hello world"' | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['QUOTED'] | Should -Be 'hello world'
        }

        It "Removes matching single quotes from values" {
            "QUOTED='hello world'" | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['QUOTED'] | Should -Be 'hello world'
        }

        It "Keeps unquoted values unchanged" {
            'PLAIN=hello world' | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['PLAIN'] | Should -Be 'hello world'
        }

        It "Keeps values with mismatched or unclosed quotes unchanged" {
            @(
                "MISMATCHED=`"value'"
                'UNCLOSED="value'
            ) -join "`n" | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['MISMATCHED'] | Should -Be '"value'''
            $result['UNCLOSED'] | Should -Be '"value'
        }

        It "Ignores lines that are not key=value pairs" {
            @(
                'NOT_A_PAIR'
                'ALSO NOT VALID'
                'VALID=yes'
            ) -join "`n" | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result.Count | Should -Be 1
            $result['VALID'] | Should -Be 'yes'
        }

        It "Parses empty values" {
            'EMPTY=' | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['EMPTY'] | Should -Be ''
        }

        It "Preserves inline comments as part of the value" {
            'CACHE_MAX_HOURS=168 # Cached available versions expiration in hours' | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['CACHE_MAX_HOURS'] | Should -Be '168 # Cached available versions expiration in hours'
        }

        It "Returns an empty hashtable when the file has only comments and blank lines" {
            @(
                '# comment only'
                ''
            ) -join "`n" | Set-ContentWrapper -path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 0
        }
    }
}

Describe "Get-EnvDefaults" {
    It "returns a hashtable" {
        (Get-EnvDefaults) | Should -BeOfType [hashtable]
    }

    It "has the expected keys" {
        $keys = (Get-EnvDefaults).Keys
        $keys | Should -Contain 'PHP_CURRENT_VERSION_PATH'
        $keys | Should -Contain 'PVM_ENV_VAR_NAME'
        $keys | Should -Contain 'CACHE_MAX_HOURS'
        $keys | Should -Contain 'DEFAULT_LOG_PAGE_SIZE'
        $keys | Should -Contain 'DEFAULT_PARTIAL_LIST_SIZE'
        $keys | Should -Contain 'MIN_PAD_RIGHT_LENGTH'
        $keys | Should -Contain 'MIN_LINE_LENGTH'
        $keys | Should -Contain 'ENABLE_UPDATE_CHECK'
        $keys | Should -Contain 'UPDATE_CHECK_INTERVAL_HOURS'
        $keys | Should -Contain 'SOUNDS_DISABLED'
    }

    It "has correct default values" {
        $defaults = Get-EnvDefaults
        $defaults.PHP_CURRENT_VERSION_PATH    | Should -Be 'C:\pvm\php'
        $defaults.CACHE_MAX_HOURS             | Should -Be 168
        $defaults.DEFAULT_LOG_PAGE_SIZE       | Should -Be 5
        $defaults.DEFAULT_PARTIAL_LIST_SIZE   | Should -Be 10
        $defaults.MIN_PAD_RIGHT_LENGTH        | Should -Be 10
        $defaults.MIN_LINE_LENGTH             | Should -Be 50
        $defaults.ENABLE_UPDATE_CHECK         | Should -Be $true
        $defaults.UPDATE_CHECK_INTERVAL_HOURS | Should -Be 24
        $defaults.SOUNDS_DISABLED             | Should -Be $false
    }

    It "returns a fresh hashtable on each call (no shared mutable state)" {
        $d1 = Get-EnvDefaults
        $d1.CACHE_MAX_HOURS = 999
        $d2 = Get-EnvDefaults
        $d2.CACHE_MAX_HOURS | Should -Be 168
    }
}

Describe "Get-Config" {
    Context "When .env file exists" {
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

        It "Returns a hashtable with all expected sections" {
            $result = Get-Config -rootPath $testRoot

            $result | Should -BeOfType [hashtable]
            $result.ContainsKey('version') | Should -Be $true
            $result.ContainsKey('paths') | Should -Be $true
            $result.ContainsKey('links') | Should -Be $true
            $result.ContainsKey('env') | Should -Be $true
            $result.ContainsKey('defaults') | Should -Be $true
        }

        It "Sets the correct version" {
            $result = Get-Config -rootPath $testRoot
            $result.version | Should -Be '2.7'
        }

        It "Sets paths correctly" {
            $result = Get-Config -rootPath $testRoot
            $result.paths.directories.storage | Should -Be "$testRoot\storage"
            $result.paths.directories.php | Should -Be "$testRoot\storage\php"
            $result.paths.directories.data | Should -Be "$testRoot\storage\data"
            $result.paths.directories.templates | Should -Be "$testRoot\storage\data\templates"
            $result.paths.directories.cache | Should -Be "$testRoot\storage\data\cache"
            $result.paths.directories.profiles | Should -Be "$testRoot\storage\data\profiles"
            $result.paths.directories.log | Should -Be "$testRoot\storage\logs"
            $result.paths.files.logError | Should -Be "$testRoot\storage\logs\error.log"
        }

        It "Sets env variables from .env file" {
            $result = Get-Config -rootPath $testRoot
            $result.env.PHP_CURRENT_VERSION_PATH | Should -Be 'C:\pvm\php'
            $result.env.PVM_ENV_VAR_NAME | Should -Be 'PVM'
            $result.env.CACHE_MAX_HOURS | Should -Be 168
            $result.env.DEFAULT_LOG_PAGE_SIZE | Should -Be 5
        }

        It "Sets default zend extensions" {
            $result = Get-Config -rootPath $testRoot
            $result.defaults.zendExtensions | Should -Be @('opcache', 'xdebug')
        }

        It "Sets default extensions list" {
            $result = Get-Config -rootPath $testRoot
            $result.defaults.extensions | Should -Contain 'curl'
            $result.defaults.extensions | Should -Contain 'mbstring'
            $result.defaults.extensions | Should -Contain 'opcache'
        }

        It "Sets aliases dictionary" {
            $result = Get-Config -rootPath $testRoot
            $result.defaults.aliases['?'] | Should -Be 'help'
            $result.defaults.aliases['i'] | Should -Be 'install'
            $result.defaults.aliases['ls'] | Should -Be 'list'
        }
    }
}
