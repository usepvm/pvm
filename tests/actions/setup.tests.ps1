
BeforeAll {
    if (-not $Global:CurrentTestDrive) {
        $currentFileName = Split-Path -Path $PSCommandPath -Leaf
        $msg = "`nTest Drive is not set for '$currentFileName'"
        $line = "`n$('=' * $msg.Length)"
        $errorMessage = $line + $msg + $line
        throw " `n$errorMessage"
    }

    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:ROOT_PATH = $Global:PVMConfig.rootPath
    $script:PHP_CURRENT_VERSION_PATH = $Global:PVMConfig.env.PHP_CURRENT_VERSION_PATH
    $script:PVM_ENV_VAR_NAME = $Global:PVMConfig.env.PVM_ENV_VAR_NAME

    Mock Show-Success { }
    Mock Show-Error { }
    Mock Show-LabelledSuccess { }
    Mock Show-LabelledError { }
    Mock Show-LabelledInfo {}
    Mock Show-LabelledWarning {}
    Mock Write-White { }
    Mock Write-Cyan { }
    Mock Add-LogEntry { return 0 }
}

Describe "Initialize-PVM" {
    BeforeAll {
        $script:MockRegistryThrowException = $false
        $script:MockRegistryException = 'Registry access denied'
        $script:MockRegistry = @{
            Machine = @{
                'Path' = 'C:\Windows\System32'
                'PHP' = $null
                'pvm' = $null
            }
        }

        Mock Add-LogEntry { return 0 }

        Mock Test-NotAdmin { return $false }

        Mock Get-EnvVarByNameCore {
            param ($name)

            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            return $script:MockRegistry.Machine[$name]
        }

        Mock Set-EnvVarCore {
            param ($name, $value)

            if ($script:MockRegistryThrowException) {
                throw $script:MockRegistryException
            }

            if ($null -eq $value) {
                $script:MockRegistry.Machine.Remove($name)
            } else {
                $script:MockRegistry.Machine[$name] = $value
            }
        }
    }

    BeforeEach {
        $script:MockRegistry = @{
            Machine = @{
                'Path' = 'C:\Windows\System32'
                'pvm' = $null
            }
        }

        Mock Get-EnvVarByName { return $null }
        Mock Set-EnvVar { return 0 }
        Mock Test-DirectoryExists { return $false }
        Mock New-Directory { return 0 }
        Mock Add-LogEntry { return 0 }
        Mock Optimize-SystemPath { }
    }

    Context "When Path environment variable is empty" {
        It "Should add both PVM and PHP paths when neither exists" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith { return $null }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$script:ROOT_PATH;$script:PHP_CURRENT_VERSION_PATH"
            }

            $result = Initialize-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -ParameterFilter { $message -eq 'PVM environment has been set up.' }
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$script:PVM_ENV_VAR_NAME*" } -Exactly 1
        }
    }

    Context "When Path environment variable has existing entries" {
        It "Should only add missing paths" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;C:\Program Files\PowerShell'
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$script:ROOT_PATH;$script:PHP_CURRENT_VERSION_PATH"
            }

            $result = Initialize-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -ParameterFilter { $message -eq 'PVM environment has been set up.' }
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$script:PVM_ENV_VAR_NAME*" } -Exactly 1
        }

        It "Should not add paths that already exist" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;%PVM%'
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$script:ROOT_PATH;$script:PHP_CURRENT_VERSION_PATH"
            }

            $result = Initialize-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -ParameterFilter { $message -eq 'PVM environment has been set up.' }
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' } -Exactly 0
        }

        It "Should recognize existing paths in different cases" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;%pvm%'
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$($script:ROOT_PATH.ToLower());$($script:PHP_CURRENT_VERSION_PATH.ToLower())"
            }

            $result = Initialize-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -ParameterFilter { $message -eq 'PVM environment has been set up.' }
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' } -Exactly 0
        }
    }

    Context "When PVM is not properly set up" {
        It "Should set up PVM environment" {
            Mock Get-EnvVarByName { return '' }

            $result = Initialize-PVM

            $result | Should -Be 0
            Should -Invoke Set-EnvVar -Times 1 -ParameterFilter {
                $name -eq $script:PVM_ENV_VAR_NAME -and
                $value -eq "$script:ROOT_PATH;$script:PHP_CURRENT_VERSION_PATH"
            }
            Should -Invoke Set-EnvVar -Times 1 -ParameterFilter {
                $name -eq 'Path'
                $value -eq ";%$($script:PVM_ENV_VAR_NAME)%"
            }
        }
    }

    Context "When errors occur" {
        It "Should handle exceptions and log them" {
            Mock Get-EnvVarByName { throw 'Test exception' }

            $result = Initialize-PVM

            $result.code | Should -Be -1
            $result.message | Should -Be 'Failed to set up PVM environment.'
            Should -Invoke Add-LogEntry -Exactly 1
        }

        It "Returns error code when New-Directory fails" {
            Mock Get-EnvVarByName { return $null }
            Mock New-Directory { return -1 }

            $result = Initialize-PVM

            $result | Should -Be -1
            Should -Invoke Show-Error -ParameterFilter { $message -eq 'Failed to create directory for PHP version.' }
        }

        It "Returns error code when Set-EnvVar fails" {
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'Path' } -MockWith {
                return 'C:\Windows\System32;C:\Program Files\PowerShell'
            }
            Mock Get-EnvVarByName -ParameterFilter { $name -eq 'PVM' } -MockWith {
                return "$script:ROOT_PATH;$script:PHP_CURRENT_VERSION_PATH"
            }
            Mock Set-EnvVar { return -1 }

            $result = Initialize-PVM

            $result | Should -Be -1
            Should -Invoke Show-Error -ParameterFilter { $message -eq 'Failed to set Path environment variable.' }
            Should -Invoke Set-EnvVar -ParameterFilter { $name -eq 'Path' -and $value -like "*$script:PVM_ENV_VAR_NAME*" } -Exactly 1
        }
    }
}

Describe "Get-PVMDirectoryItems" {
    BeforeEach {
        $script:created = @()
        Mock New-Directory { param ($path) $script:created += $path; return 0 }
    }

    It "Returns one item per directory" {
        @(Get-PVMDirectoryItems).Count | Should -Be 10
    }

    It "Uses the configured paths as labels" {
        $dirs = $Global:PVMConfig.paths.directories
        $root = [regex]::Escape("$($Global:PVMConfig.rootPath)\")

        (Get-PVMDirectoryItems).Label | Should -Be @(
            $dirs.storage, $dirs.testDrive, $dirs.php, $dirs.data, $dirs.templates,
            $dirs.cache, $dirs.profiles, $dirs.log, $dirs.state, $dirs.temp
        ).ForEach({ $_ -replace $root, '' })
    }

    It "Each action creates its own directory" {
        foreach ($item in Get-PVMDirectoryItems) {
            $splat = $item.Args
            & $item.Action @splat
        }

        Should -Invoke New-Directory -Times 10 -Exactly
        $script:created | Should -Contain $Global:PVMConfig.paths.directories.php
        $script:created | Should -Be ((Get-PVMDirectoryItems) | ForEach-Object { $_.Args.path })
    }
}

Describe "Get-PVMFileItems" {
    BeforeEach {
        Mock New-ProfileExample { return 0 }
        Mock New-ProfileTemplate { return 0 }
        Mock Set-ZendExtensionsList { return 0 }
        Mock Set-AliasesList { return 0 }
        Mock Set-ScriptsList { return 0 }
    }

    It "Returns one item per file" {
        @(Get-PVMFileItems).Count | Should -Be 5
    }

    It "Uses the configured paths as labels, in order" {
        $files = $Global:PVMConfig.paths.files
        $root  = [regex]::Escape("$($Global:PVMConfig.rootPath)\")

        (Get-PVMFileItems).Label | Should -Be @(
            $files.profileExample, $files.profileTemplate, $files.zendExtensionsList,
            $files.aliasesList, $files.scriptsList
        ).ForEach({ $_ -replace $root, '' })
    }

    It "Each action calls its creator once" {
        foreach ($item in Get-PVMFileItems) {
            $splat = $item.Args
            & $item.Action @splat
        }

        Should -Invoke New-ProfileExample -Times 1 -Exactly
        Should -Invoke New-ProfileTemplate -Times 1 -Exactly
        Should -Invoke Set-ZendExtensionsList -Times 1 -Exactly
        Should -Invoke Set-AliasesList -Times 1 -Exactly
        Should -Invoke Set-ScriptsList -Times 1 -Exactly
    }
}

Describe "Invoke-PVMSection" {
    BeforeEach {
        $script:items = @(
            [pscustomobject]@{ Label = 'ok';     Action = { 0 } }
            [pscustomobject]@{ Label = 'broken'; Action = { -1 } }
        )
    }

    It "Writes the title" {
        $null = Invoke-PVMSection -title 'Title' -items $items -width 20

        Should -Invoke Write-Cyan -Times 1 -Exactly -ParameterFilter { $message -eq 'Title' }
    }

    It "Returns the codes of all actions" {
        $result = @(Invoke-PVMSection -title 'Title' -items $items -width 20)

        $result | Should -Be @(0, -1)
    }

    It "Shows success for 0 and error otherwise" {
        $null = Invoke-PVMSection -title 'Title' -items $items -width 20

        Should -Invoke Show-Success -Times 1 -Exactly
        Should -Invoke Show-Error -Times 1 -Exactly
    }

    It "Pads every line to the same width with dots" {
        $null = Invoke-PVMSection -title 'Title' -items $items -width 20

        Should -Invoke Write-White -Times 2 -Exactly -ParameterFilter { $message.Length -eq 21 }
        Should -Invoke Write-White -Times 1 -Exactly -ParameterFilter {
            $message -eq ('- ok ' + ('.' * 15) + ' ')
        }
    }
}

Describe "Initialize-EnvironmentDirectoriesAndFiles" {
    BeforeEach {
        Mock Get-PVMDirectoryItems { [pscustomobject]@{ Label = 'dir'; Action = { 0 } } }
        Mock Get-PVMFileItems { [pscustomobject]@{ Label = 'a-longer-file-label'; Action = { 0 } } }
    }

    It "Returns 0 when all directories and files are created" {
        Mock Invoke-PVMSection { return @(0, 0) }

        Initialize-EnvironmentDirectoriesAndFiles | Should -Be 0
    }

    It "Returns -1 when a directory creation fails" {
        Mock Invoke-PVMSection { return @(0, -1) } -ParameterFilter { $title -like '*directories*' }
        Mock Invoke-PVMSection { return @(0, 0) } -ParameterFilter { $title -like '*files*' }

        Initialize-EnvironmentDirectoriesAndFiles | Should -Be -1
    }

    It "Returns -1 when a file creation fails" {
        Mock Invoke-PVMSection { return @(0, 0) } -ParameterFilter { $title -like '*directories*' }
        Mock Invoke-PVMSection { return @(0, -1) } -ParameterFilter { $title -like '*files*' }

        Initialize-EnvironmentDirectoriesAndFiles | Should -Be -1
    }

    It "Passes the same width, based on the longest label, to both sections" {
        Mock Invoke-PVMSection { return @(0) }

        $null = Initialize-EnvironmentDirectoriesAndFiles

        # 'a-longer-file-label'.Length + 3 + (MIN_PAD_RIGHT_LENGTH * 2)
        Should -Invoke Invoke-PVMSection -Times 2 -Exactly -ParameterFilter {
            $width -eq ('a-longer-file-label'.Length + 3 + ($Global:PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2))
        }
    }

    It "Shows the storage path" {
        Mock Invoke-PVMSection { return @(0) }

        $null = Initialize-EnvironmentDirectoriesAndFiles

        Should -Invoke Show-LabelledInfo -Times 1 -Exactly -ParameterFilter {
            $message.Contains($Global:PVMConfig.paths.directories.storage)
        }
    }
}

Describe "New-EnvFile" {
    BeforeAll {
        Mock Copy-ItemWrapper { return 0 }
    }

    It "Returns -1 when the .env.example file is not found" {
        Mock Test-FileNotExists { return $true }

        $result = New-EnvFile

        $result | Should -Be -1
        Should -Invoke Copy-ItemWrapper -Times 0
        Should -Invoke Show-LabelledError -Times 1 -ParameterFilter {
            $message -like '*Failed to find .env.example file.*'
        }
    }

    It "Returns 0 when the user does not want to overwrite the .env file" {
        Mock Test-FileNotExists { return $false }
        New-Item -ItemType File -Path "$script:ROOT_PATH\.env" -Force | Out-Null
        Mock Read-HostWrapper { return 'n' }

        $result = New-EnvFile

        $result | Should -Be -1
        Should -Invoke Copy-ItemWrapper -Times 0
    }

    It "Returns 0 when the user wants to overwrite the .env file" {
        Mock Test-FileNotExists { return $false }
        New-Item -ItemType File -Path "$script:ROOT_PATH\.env" -Force | Out-Null
        Mock Read-HostWrapper { return 'y' }

        $result = New-EnvFile

        $result | Should -Be 0
        Should -Invoke Copy-ItemWrapper -Times 1
        Should -Invoke Show-LabelledSuccess -Times 1 -ParameterFilter {
            $message -like '*Created .env file.*'
        }
    }

    It "Returns 0 when the .env is created" {
        Mock Test-FileNotExists -ParameterFilter { $path -eq "$script:ROOT_PATH\.env.example"} { return $false }
        Mock Test-FileExists -ParameterFilter { $path -eq "$script:ROOT_PATH\.env"} { return $false }
        Mock Read-HostWrapper { }

        $result = New-EnvFile

        $result | Should -Be 0
        Should -Invoke Read-HostWrapper -Times 0
        Should -Invoke Copy-ItemWrapper -Times 1
        Should -Invoke Show-LabelledSuccess -Times 1 -ParameterFilter {
            $message -like '*Created .env file.*'
        }
    }

    It "Returns -1 when copy .env fails" {
        Mock Test-FileNotExists -ParameterFilter { $path -eq "$script:ROOT_PATH\.env.example"} { return $false }
        Mock Test-FileExists -ParameterFilter { $path -eq "$script:ROOT_PATH\.env"} { return $false }
        Mock Copy-ItemWrapper { return -1 }

        $result = New-EnvFile

        $result | Should -Be -1
        Should -Invoke Copy-ItemWrapper -Times 1
        Should -Invoke Show-LabelledError -Times 1 -ParameterFilter { $message -like '*Failed to create .env file*' }
    }

    It "Returns -1 when the .env is not created" {
        Mock Test-FileNotExists -ParameterFilter { $path -eq "$script:ROOT_PATH\.env.example"} { return $false }
        Mock Test-FileExists -ParameterFilter { $path -eq "$script:ROOT_PATH\.env"} { return $false }
        Mock Read-HostWrapper { }
        Mock Copy-ItemWrapper { throw 'Access denied' }

        $result = New-EnvFile

        $result | Should -Be -1
        Should -Invoke Read-HostWrapper -Times 0
        Should -Invoke Copy-ItemWrapper -Times 1
    }
}

Describe "Wait-ForEnvEdit" {
    It "Should prompt the user to edit the .env file" {
        Mock Read-HostWrapper { return '' }
        Mock Get-Config { return @{} }

        Wait-ForEnvEdit

        Should -Invoke Read-HostWrapper -Times 1
        Should -Invoke Show-LabelledWarning -Times 1 -ParameterFilter {
            $label -eq 'TODO' -and
            $message -like "*Edit '$script:ROOT_PATH\.env' now if you want custom settings*"
        }
    }
}
