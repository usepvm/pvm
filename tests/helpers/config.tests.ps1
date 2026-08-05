
BeforeAll {
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\config-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:TEMPLATES_PATH = $PVMConfig.paths.templates
    $script:ALIASES_LIST_PATH = $PVMConfig.paths.aliasesList
    $script:SCRIPTS_LIST_PATH = $PVMConfig.paths.scriptsList

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Set-AliasesList" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $TEMPLATES_PATH | Out-Null
        $script:DEFAULT_ALIASES = $PVMConfig.defaults.aliases
    }

    It "Creates aliases.json" {
        $result = Set-AliasesList
        $result | Should -Be 0

        $result = Get-Aliases
        $result.Count | Should -Be $DEFAULT_ALIASES.Count
    }

    It "Returns -1 when exception is thrown" {
        Mock Set-Content { throw 'Test exception' }
        $result = Set-AliasesList
        $result | Should -Be -1
    }
}

Describe "Get-Aliases" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $TEMPLATES_PATH | Out-Null
        $testContent = [ordered]@{'?' = 'help'; 'i' = 'install'; 'init' = 'setup'}
        $testContent | ConvertTo-Json -Depth 10 | Set-Content -Path $ALIASES_LIST_PATH
        $script:DEFAULT_ALIASES = $PVMConfig.defaults.aliases
    }

    It "Returns aliases from aliases.json or PVMConfig.defaults.aliases" {
        $result = Get-Aliases
        $result.Count | Should -Be 3
        $result['?'] | Should -Be 'help'
        $result['i'] | Should -Be 'install'
        $result['init'] | Should -Be 'setup'
    }

    It "Falls back to DEFAULT_ALIASES value" {
        Remove-Item -Path "$TEMPLATES_PATH\aliases.json"
        $result = Get-Aliases
        $result.Count | Should -Be $DEFAULT_ALIASES.Count
    }

    It "Returns default value when exception is thrown" {
        Mock Test-FileExists { return $true }
        Mock Get-Content { throw 'Test exception' }
        $result = Get-Aliases
        $result.Count | Should -Be $DEFAULT_ALIASES.Count
    }
}

Describe "Get-FlagMap" {
    It "Returns PVMConfig.defaults.flags" {
        $result = Get-FlagMap
        $result.Count | Should -Be $PVMConfig.defaults.flags.Count
    }
}

Describe "Set-Scripts-List" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $TEMPLATES_PATH | Out-Null
        $script:DEFAULT_SCRIPTS = $PVMConfig.defaults.scripts
    }

    It "Creates scripts.json" {
        $result = Set-ScriptsList
        $result | Should -Be 0

        $result = Get-Scripts
        $result.Count | Should -Be $DEFAULT_SCRIPTS.Count
    }

    It "Returns -1 when exception is thrown" {
        Mock Set-Content { throw 'Test exception' }
        $result = Set-ScriptsList
        $result | Should -Be -1
    }
}

Describe "Get-Scripts" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $TEMPLATES_PATH | Out-Null
        $testContent = [ordered]@{'test:quiet' = 'test --verbosity=None'; 'test:cov' = 'test --coverage=75'}
        $testContent | ConvertTo-Json -Depth 10 | Set-Content -Path $SCRIPTS_LIST_PATH
        $script:DEFAULT_SCRIPTS = $PVMConfig.defaults.scripts
    }

    It "Returns scripts from scripts.json or PVMConfig.defaults.scripts" {
        $result = Get-Scripts
        $result.Count | Should -Be 2
        $result['test:quiet'] | Should -Be 'test --verbosity=None'
        $result['test:cov'] | Should -Be 'test --coverage=75'
    }

    It "Falls back to DEFAULT_SCRIPTS value" {
        Remove-Item -Path "$script:TEMPLATES_PATH\scripts.json"
        $result = Get-Scripts
        $result.Count | Should -Be $DEFAULT_SCRIPTS.Count
    }

    It "Returns default value when exception is thrown" {
        Mock Test-FileExists { return $true }
        Mock Get-Content { throw 'Test exception' }
        $result = Get-Scripts
        $result.Count | Should -Be $DEFAULT_SCRIPTS.Count
    }
}

Describe "Get-EnvBool" {
    It 'returns $true for "true" (any case)' {
        Get-EnvBool 'true' | Should -BeTrue
        Get-EnvBool 'True' | Should -BeTrue
        Get-EnvBool 'TRUE' | Should -BeTrue
    }

    It 'returns $false for "false" (any case)' {
        Get-EnvBool 'false' | Should -BeFalse
        Get-EnvBool 'False' | Should -BeFalse
        Get-EnvBool 'FALSE' | Should -BeFalse
    }

    It 'returns the default when value is $null' {
        Get-EnvBool $null $true | Should -BeTrue
        Get-EnvBool $null $false | Should -BeFalse
    }

    It 'returns the default when value is empty string' {
        Get-EnvBool '' $true | Should -BeTrue
    }

    It 'returns the default when value is whitespace only' {
        Get-EnvBool '   ' $true | Should -BeTrue
    }

    It 'returns the default when value is unparsable garbage' {
        Get-EnvBool 'yes' $true | Should -BeTrue
        Get-EnvBool '1' $false | Should -BeFalse
        Get-EnvBool 'not-a-bool' $true | Should -BeTrue
    }

    It 'defaults to $false when no default is supplied and value is invalid' {
        Get-EnvBool 'garbage' | Should -BeFalse
    }

    It 'trims surrounding whitespace around a valid value' {
        Get-EnvBool '  true  ' | Should -BeTrue
    }

    It 'does not throw on any input' {
        { Get-EnvBool $null } | Should -Not -Throw
        { Get-EnvBool '' } | Should -Not -Throw
        { Get-EnvBool 'nonsense' } | Should -Not -Throw
    }
}

Describe "Get-EnvInt" {
    It 'parses a valid positive integer' {
        Get-EnvInt '42' | Should -Be 42
    }

    It 'parses a valid negative integer' {
        Get-EnvInt '-5' | Should -Be -5
    }

    It 'parses zero' {
        Get-EnvInt '0' | Should -Be 0
    }

    It 'returns the default when value is $null' {
        Get-EnvInt $null 24 | Should -Be 24
    }

    It 'returns the default when value is empty string' {
        Get-EnvInt '' 24 | Should -Be 24
    }

    It 'returns the default when value is whitespace only' {
        Get-EnvInt '   ' 10 | Should -Be 10
    }

    It 'returns the default when value is non-numeric' {
        Get-EnvInt 'abc' 10 | Should -Be 10
    }

    It 'returns the default when value is a decimal (not a valid int)' {
        Get-EnvInt '3.14' 10 | Should -Be 10
    }

    It 'defaults to 0 when no default is supplied and value is invalid' {
        Get-EnvInt 'garbage' | Should -Be 0
    }

    It 'trims surrounding whitespace around a valid value' {
        Get-EnvInt '  42  ' | Should -Be 42
    }

    It 'does not throw on any input' {
        { Get-EnvInt $null } | Should -Not -Throw
        { Get-EnvInt '' } | Should -Not -Throw
        { Get-EnvInt 'nonsense' } | Should -Not -Throw
    }

    It 'handles values exceeding Int32 range by falling back to default' {
        Get-EnvInt '99999999999999999999' 5 | Should -Be 5
    }
}

Describe "Get-EnvConfig" {
    BeforeEach {
        $script:envRoot = "$TEST_DRIVE\envconfig"
        New-Item -ItemType Directory -Path $script:envRoot -Force | Out-Null
    }

    Context "When .env file is missing" {
        It "Copies .env.example to .env" {
            Set-Content -Path "$envRoot\.env.example" -Value 'KEY=value'
            Get-EnvConfig -rootPath $envRoot

            $result = Get-Content -Path "$envRoot\.env"
            $result | Should -Be 'KEY=value'
        }
    }

    Context "When .env file exists" {
        It "Writes a verbose message with the env file path" {
            Set-Content -Path "$envRoot\.env" -Value 'KEY=value'
            Mock Write-Verbose {}

            Get-EnvConfig -rootPath $envRoot -Verbose

            Should -Invoke Write-Verbose -ParameterFilter {
                $Message -eq "Using .env from: $envRoot\.env"
            } -Times 1 -Exactly
        }

        It "Returns a hashtable of parsed key=value pairs" {
            @'
PHP_CURRENT_VERSION_PATH=C:\pvm\php
CACHE_MAX_HOURS=168
DEFAULT_LOG_PAGE_SIZE=5
'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 3
            $result['PHP_CURRENT_VERSION_PATH'] | Should -Be 'C:\pvm\php'
            $result['CACHE_MAX_HOURS'] | Should -Be '168'
            $result['DEFAULT_LOG_PAGE_SIZE'] | Should -Be '5'
        }

        It "Skips empty lines and comment lines" {
            @'

# Top-level comment
   # Indented comment

KEY=value

'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result.Count | Should -Be 1
            $result['KEY'] | Should -Be 'value'
        }

        It "Trims whitespace around keys and values" {
            '  KEY  =  value  ' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['KEY'] | Should -Be 'value'
        }

        It "Removes matching double quotes from values" {
            'QUOTED="hello world"' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['QUOTED'] | Should -Be 'hello world'
        }

        It "Removes matching single quotes from values" {
            "QUOTED='hello world'" | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['QUOTED'] | Should -Be 'hello world'
        }

        It "Keeps unquoted values unchanged" {
            'PLAIN=hello world' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['PLAIN'] | Should -Be 'hello world'
        }

        It "Keeps values with mismatched or unclosed quotes unchanged" {
            @'
MISMATCHED="value'
UNCLOSED="value
'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['MISMATCHED'] | Should -Be '"value'''
            $result['UNCLOSED'] | Should -Be '"value'
        }

        It "Ignores lines that are not key=value pairs" {
            @'
NOT_A_PAIR
ALSO NOT VALID
VALID=yes
'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result.Count | Should -Be 1
            $result['VALID'] | Should -Be 'yes'
        }

        It "Parses empty values" {
            'EMPTY=' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['EMPTY'] | Should -Be ''
        }

        It "Preserves inline comments as part of the value" {
            'CACHE_MAX_HOURS=168 # Cached available versions expiration in hours' | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result['CACHE_MAX_HOURS'] | Should -Be '168 # Cached available versions expiration in hours'
        }

        It "Returns an empty hashtable when the file has only comments and blank lines" {
            @'
# comment only

'@ | Set-Content -Path "$envRoot\.env"

            $result = Get-EnvConfig -rootPath $envRoot

            $result | Should -BeOfType [hashtable]
            $result.Count | Should -Be 0
        }
    }
}

Describe "Get-Config" {
    Context "When .env file exists" {
        BeforeAll {
            $script:testRoot = "$TEST_DRIVE\pvm"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
            @'
PHP_CURRENT_VERSION_PATH=C:\pvm\php
PVM_ENV_VAR_NAME=PVM
CACHE_MAX_HOURS=168
DEFAULT_LOG_PAGE_SIZE=5
DEFAULT_PARTIAL_LIST_SIZE=10
MIN_PAD_RIGHT_LENGTH=20
MIN_LINE_LENGTH=50
'@ | Set-Content -Path "$testRoot\.env"
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
            $result.version | Should -Be '2.6'
        }

        It "Sets paths correctly" {
            $result = Get-Config -rootPath $testRoot
            $result.paths.storage | Should -Be "$testRoot\storage"
            $result.paths.php | Should -Be "$testRoot\storage\php"
            $result.paths.data | Should -Be "$testRoot\storage\data"
            $result.paths.templates | Should -Be "$testRoot\storage\data\templates"
            $result.paths.cache | Should -Be "$testRoot\storage\data\cache"
            $result.paths.profiles | Should -Be "$testRoot\storage\data\profiles"
            $result.paths.log | Should -Be "$testRoot\storage\logs"
            $result.paths.logError | Should -Be "$testRoot\storage\logs\error.log"
        }

        It "Uses TEST_DRIVE from .env for fake storage when provided" {
            $customRoot = "$TEST_DRIVE\custom-env"
            New-Item -ItemType Directory -Path $customRoot -Force | Out-Null
            @'
PHP_CURRENT_VERSION_PATH=C:\pvm\php
PVM_ENV_VAR_NAME=PVM
CACHE_MAX_HOURS=168
DEFAULT_LOG_PAGE_SIZE=5
DEFAULT_PARTIAL_LIST_SIZE=10
MIN_PAD_RIGHT_LENGTH=20
MIN_LINE_LENGTH=50
TEST_DRIVE=C:\fake-storage
'@ | Set-Content -Path "$customRoot\.env"

            $result = Get-Config -rootPath $customRoot

            $result.paths.fakeStorage | Should -Be 'C:\fake-storage'
        }

        It "Falls back to storage/tests when TEST_DRIVE is not set" {
            $fallbackRoot = "$TEST_DRIVE\fallback-env"
            New-Item -ItemType Directory -Path $fallbackRoot -Force | Out-Null
            @'
PHP_CURRENT_VERSION_PATH=C:\pvm\php
PVM_ENV_VAR_NAME=PVM
CACHE_MAX_HOURS=168
DEFAULT_LOG_PAGE_SIZE=5
DEFAULT_PARTIAL_LIST_SIZE=10
MIN_PAD_RIGHT_LENGTH=20
MIN_LINE_LENGTH=50
'@ | Set-Content -Path "$fallbackRoot\.env"

            $result = Get-Config -rootPath $fallbackRoot

            $result.paths.fakeStorage | Should -Be "$fallbackRoot\storage\tests"
        }

        It "Falls back to storage/tests when TEST_DRIVE is not a valid path" {
            $invalidRoot = "$TEST_DRIVE\invalid-env"
            New-Item -ItemType Directory -Path $invalidRoot -Force | Out-Null
            @'
PHP_CURRENT_VERSION_PATH=C:\pvm\php
PVM_ENV_VAR_NAME=PVM
CACHE_MAX_HOURS=168
DEFAULT_LOG_PAGE_SIZE=5
DEFAULT_PARTIAL_LIST_SIZE=10
MIN_PAD_RIGHT_LENGTH=20
MIN_LINE_LENGTH=50
TEST_DRIVE=bad<path
'@ | Set-Content -Path "$invalidRoot\.env"

            $result = Get-Config -rootPath $invalidRoot

            $result.paths.fakeStorage | Should -Be "$invalidRoot\storage\tests"
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

    Context "Get-Config -> test.setFakePaths" {
        BeforeAll {
            $script:testRoot = "$TEST_DRIVE\pvm"
            New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
            @'
PHP_CURRENT_VERSION_PATH=C:\pvm\php
PVM_ENV_VAR_NAME=PVM
CACHE_MAX_HOURS=168
DEFAULT_LOG_PAGE_SIZE=5
DEFAULT_PARTIAL_LIST_SIZE=10
MIN_PAD_RIGHT_LENGTH=20
MIN_LINE_LENGTH=50
'@ | Set-Content -Path "$testRoot\.env"
        }

        BeforeEach {
            $PVMConfig = Get-Config -rootPath $testRoot
        }

        AfterEach {
            Remove-Variable -Name PVMConfig -Scope Global -ErrorAction SilentlyContinue
        }

        It "Is a scriptblock" {
            $PVMConfig.test.setFakePaths | Should -BeOfType [scriptblock]
        }

        It "Rewrites PVMConfig.paths. under the given root" {
            $fakeRoot = "$TEST_DRIVE\fake-root"
            $PVMConfig.test.setFakePaths.Invoke($fakeRoot)

            $PVMConfig.paths.pvmRoot | Should -Be $fakeRoot
            $PVMConfig.paths.storage | Should -Be "$fakeRoot\storage"

            $PVMConfig.paths.fakeStorage | Should -Be "$fakeRoot\storage"

            $PVMConfig.paths.php | Should -Be "$fakeRoot\storage\php"
            $PVMConfig.paths.data | Should -Be "$fakeRoot\storage\data"
            $PVMConfig.paths.cache | Should -Be "$fakeRoot\storage\data\cache"
            $PVMConfig.paths.templates | Should -Be "$fakeRoot\storage\data\templates"
            $PVMConfig.paths.profiles | Should -Be "$fakeRoot\storage\data\profiles"

            $PVMConfig.paths.profileExample | Should -Be "$fakeRoot\storage\data\profiles\profile-example.json"
            $PVMConfig.paths.profileTemplate | Should -Be "$fakeRoot\storage\data\templates\profile-template.json"
            $PVMConfig.paths.zendExtensionsList | Should -Be "$fakeRoot\storage\data\templates\zend_extensions.json"
            $PVMConfig.paths.aliasesList | Should -Be "$fakeRoot\storage\data\templates\aliases.json"
            $PVMConfig.paths.scriptsList | Should -Be "$fakeRoot\storage\data\templates\scripts.json"

            $PVMConfig.paths.log | Should -Be "$fakeRoot\storage\logs"
            $PVMConfig.paths.logError | Should -Be "$fakeRoot\storage\logs\error.log"
            $PVMConfig.paths.pathVarBackup | Should -Be "$fakeRoot\storage\logs\path.bak.log"

            $PVMConfig.paths.assets | Should -Be "$fakeRoot\assets"
        }

        It "Rewrites env.PHP_CURRENT_VERSION_PATH under the given root" {
            $fakeRoot = "$TEST_DRIVE\fake-root"
            $PVMConfig.test.setFakePaths.Invoke($fakeRoot)

            $PVMConfig.env.PHP_CURRENT_VERSION_PATH | Should -Be "$fakeRoot\pvm\php"
        }

        It "Does not touch unrelated config sections" {
            $fakeRoot = "$TEST_DRIVE\fake-root"
            $originalVersion = $PVMConfig.version
            $originalLinks = [ordered]@{}
            $PVMConfig.links.GetEnumerator() | ForEach-Object {
                $originalLinks[$_.Key] = $_.Value  
            }

            $PVMConfig.test.setFakePaths.Invoke($fakeRoot)

            $PVMConfig.version | Should -Be $originalVersion
            $PVMConfig.links.GetEnumerator() | ForEach-Object {
                $PVMConfig.links[$_.Key] | Should -Be $originalLinks[$_.Key]
            }
        }

        It "Overwrites previously-set fake paths when called again with a new root" {
            $firstRoot = "$TEST_DRIVE\fake-root-1"
            $secondRoot = "$TEST_DRIVE\fake-root-2"

            $PVMConfig.test.setFakePaths.Invoke($firstRoot)
            $PVMConfig.test.setFakePaths.Invoke($secondRoot)

            $PVMConfig.paths.pvmRoot | Should -Be $secondRoot
            $PVMConfig.paths.storage | Should -Be "$secondRoot\storage"
            $PVMConfig.env.PHP_CURRENT_VERSION_PATH | Should -Be "$secondRoot\pvm\php"
        }
    }
}

Describe "Copy-ObjectDeep" {
    It "Returns null when input is null" {
        $result = Copy-ObjectDeep -object $null
        $result | Should -Be $null
    }

    It "Returns primitive value as-is" {
        $result = Copy-ObjectDeep -object 42
        $result | Should -Be 42

        $result = Copy-ObjectDeep -object "test string"
        $result | Should -Be "test string"

        $result = Copy-ObjectDeep -object $true
        $result | Should -Be $true
    }

    It "Deep copies ordered dictionary" {
        $original = [ordered]@{
            key1 = "value1"
            key2 = 42
            key3 = $false
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.GetType().Name | Should -Be "OrderedDictionary"
        $copy.key1 | Should -Be "value1"
        $copy.key2 | Should -Be 42
        $copy.key3 | Should -Be $false

        # Verify it's a deep copy, not a reference
        $copy.key1 = "modified"
        $original.key1 | Should -Be "value1"
    }

    It "Deep copies hashtable" {
        $original = @{
            name = "test"
            count = 10
            active = $true
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.GetType().Name | Should -Be "Hashtable"
        $copy.name | Should -Be "test"
        $copy.count | Should -Be 10
        $copy.active | Should -Be $true

        # Verify it's a deep copy, not a reference
        $copy.name = "modified"
        $original.name | Should -Be "test"
    }

    It "Deep copies array" {
        $original = @(1, 2, 3, "four", $false)

        $copy = Copy-ObjectDeep -object $original

        $copy.Count | Should -Be 5
        $copy[0] | Should -Be 1
        $copy[1] | Should -Be 2
        $copy[2] | Should -Be 3
        $copy[3] | Should -Be "four"
        $copy[4] | Should -Be $false

        # Verify it's a deep copy, not a reference
        $copy[0] = 99
        $original[0] | Should -Be 1
    }

    It "Deep copies nested ordered dictionary" {
        $original = [ordered]@{
            level1 = [ordered]@{
                level2 = [ordered]@{
                    value = "deep"
                }
            }
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.level1.level2.value | Should -Be "deep"

        # Verify it's a deep copy
        $copy.level1.level2.value = "modified"
        $original.level1.level2.value | Should -Be "deep"
    }

    It "Deep copies nested hashtable" {
        $original = @{
            outer = @{
                inner = @{
                    data = "nested"
                }
            }
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.outer.inner.data | Should -Be "nested"

        # Verify it's a deep copy
        $copy.outer.inner.data = "modified"
        $original.outer.inner.data | Should -Be "nested"
    }

    It "Deep copies array of hashtables" {
        $original = @(
            @{ name = "first"; value = 1 },
            @{ name = "second"; value = 2 }
        )

        $copy = Copy-ObjectDeep -object $original

        $copy.Count | Should -Be 2
        $copy[0].name | Should -Be "first"
        $copy[1].value | Should -Be 2

        # Verify it's a deep copy
        $copy[0].name = "modified"
        $original[0].name | Should -Be "first"
    }

    It "Deep copies ordered dictionary containing arrays" {
        $original = [ordered]@{
            items = @(1, 2, 3)
            names = @("alice", "bob")
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.items.Count | Should -Be 3
        $copy.names.Count | Should -Be 2

        # Verify it's a deep copy
        $copy.items[0] = 99
        $original.items[0] | Should -Be 1
    }

    It "Recreates scriptblock as new instance" {
        $original = { Write-Host "test" }

        $copy = Copy-ObjectDeep -object $original

        $copy.GetType().Name | Should -Be "ScriptBlock"
        $copy.ToString() | Should -Be $original.ToString()

        # Verify it's a new instance
        $copy = { Write-Host "modified" }
        $original.ToString() | Should -Not -Be "modified"
    }

    It "Handles complex nested structure" {
        $original = [ordered]@{
            data = @{
                items = @(
                    [ordered]@{ name = "item1"; values = @(1, 2, 3) },
                    [ordered]@{ name = "item2"; values = @(4, 5, 6) }
                )
                config = [ordered]@{
                    enabled = $true
                    options = @("opt1", "opt2")
                }
            }
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.data.items.Count | Should -Be 2
        $copy.data.items[0].name | Should -Be "item1"
        $copy.data.items[0].values[1] | Should -Be 2
        $copy.data.config.enabled | Should -Be $true
        $copy.data.config.options[0] | Should -Be "opt1"

        # Verify deep copy
        $copy.data.items[0].values[0] = 999
        $original.data.items[0].values[0] | Should -Be 1
    }

    It "Handles empty collections" {
        $emptyOrdered = [ordered]@{}
        $emptyHashtable = @{}
        $emptyArray = @()

        $copyOrdered = Copy-ObjectDeep -object $emptyOrdered
        $copyHashtable = Copy-ObjectDeep -object $emptyHashtable
        $copyArray = Copy-ObjectDeep -object $emptyArray

        $copyOrdered.Count | Should -Be 0
        $copyHashtable.Count | Should -Be 0
        $copyArray.Count | Should -Be 0
    }
}
