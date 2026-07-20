
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\config-drive"
    $script:TEMPLATES_PATH = $PVMConfig.paths.templates = "$TEST_DRIVE\templates"
    $script:ALIASES_LIST_PATH = $PVMConfig.paths.aliasesList = "$TEMPLATES_PATH\aliases.json"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
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

Describe "Set-Aliases-List" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $TEMPLATES_PATH | Out-Null
        $script:DEFAULT_ALIASES = $PVMConfig.defaults.aliases
    }

    It "Creates aliases.json" {
        $result = Set-Aliases-List
        $result | Should -Be 0

        $result = Get-Aliases
        $result.Count | Should -Be $DEFAULT_ALIASES.Count
    }

    It "Returns -1 when exception is thrown" {
        Mock Set-Content { throw 'Test exception' }
        $result = Set-Aliases-List
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
        Mock Test-File-Exists { return $true }
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
        $script:TEMPLATES_PATH = $PVMConfig.paths.templates = 'TestDrive:\\storage\data\templates'
        $PVMConfig.paths.scriptsList = "$TEMPLATES_PATH\scripts.json"
        New-Item -ItemType Directory -Force -Path $script:TEMPLATES_PATH | Out-Null
        $script:DEFAULT_SCRIPTS = $PVMConfig.defaults.scripts
    }

    It "Creates scripts.json" {
        $result = Set-Scripts-List
        $result | Should -Be 0

        $result = Get-Scripts
        $result.Count | Should -Be $DEFAULT_SCRIPTS.Count
    }

    It "Returns -1 when exception is thrown" {
        Mock Set-Content { throw 'Test exception' }
        $result = Set-Scripts-List
        $result | Should -Be -1
    }
}

Describe "Get-Scripts" {
    BeforeAll {
        $script:TEMPLATES_PATH = $PVMConfig.paths.templates = 'TestDrive:\\storage\data\templates'
        $script:SCRIPTS_LIST_PATH = $PVMConfig.paths.scriptsList = "$TEMPLATES_PATH\scripts.json"
        New-Item -ItemType Directory -Path $script:TEMPLATES_PATH | Out-Null
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
        Mock Test-File-Exists { return $true }
        Mock Get-Content { throw 'Test exception' }
        $result = Get-Scripts
        $result.Count | Should -Be $DEFAULT_SCRIPTS.Count
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
}
