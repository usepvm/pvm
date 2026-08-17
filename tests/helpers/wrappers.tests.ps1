

BeforeAll {
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\wrappers-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Write-HostWrapper" {
    BeforeEach {
        $script:currentPVMSubprocess = @{ enabled = $Global:PVMSubprocess.enabled; structuredOutput = $Global:PVMSubprocess.structuredOutput }
    }

    AfterEach {
        $Global:PVMSubprocess = $script:currentPVMSubprocess
    }

    It "Calls Write-Host with the correct parameters" {
        $Global:PVMSubprocess.enabled = $false
        Mock Write-Host { }

        $object = "Test message"
        $foregroundColor = "Green"
        $noNewLine = $false

        Write-HostWrapper -object $object -foregroundColor $foregroundColor -noNewLine:$noNewLine

        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq $object -and
            $ForegroundColor -eq $foregroundColor -and
            $NoNewline -eq $noNewLine
        }
    }

    It "Stores structured output when subprocess mode is enabled" {
        $Global:PVMSubprocess.structuredOutput = @()
        $Global:PVMSubprocess.enabled = $true
        Mock Write-Host {}

        Write-HostWrapper -object 'Test message' -foregroundColor 'Red'

        Should -Invoke Write-Host -Exactly 0
        $Global:PVMSubprocess.structuredOutput.Count | Should -Be 1
        $Global:PVMSubprocess.structuredOutput[0].message | Should -Be 'Test message'
        $Global:PVMSubprocess.structuredOutput[0].color | Should -Be 'Red'
        $Global:PVMSubprocess.structuredOutput[0].noNewLine | Should -Be $false
    }
}

Describe "Read-HostWrapper" {
    It "Calls Read-Host with no parameters" {
        Mock Read-Host { }

        $result = Read-HostWrapper

        $result | Should -BeNullOrEmpty
        Should -Invoke Read-Host -Times 1 -ParameterFilter {
            $Prompt -eq $null
        }
    }

    It "Calls Read-Host with the correct parameters" {
        Mock Read-Host { return 'Test response' }

        $prompt = "Test prompt"

        $result = Read-HostWrapper -prompt $prompt

        $result | Should -Be 'Test response'
        Should -Invoke Read-Host -Times 1 -ParameterFilter {
            $Prompt -eq $prompt
        }
    }

    It "Returns null when Read-Host returns empty string" {
        Mock Read-Host { return '' }

        $result = Read-HostWrapper -prompt "Test prompt"

        $result | Should -BeNullOrEmpty
    }

    It "Returns null when Read-Host returns null" {
        Mock Read-Host { return $null }

        $result = Read-HostWrapper -prompt "Test prompt"

        $result | Should -BeNullOrEmpty
    }

    It "Returns null when Read-Host returns whitespace only" {
        Mock Read-Host { return '   ' }

        $result = Read-HostWrapper -prompt "Test prompt"

        $result | Should -BeNullOrEmpty
    }

    It "Returns trimmed value when Read-Host returns whitespace" {
        Mock Read-Host { return ' Test response  ' }

        $result = Read-HostWrapper -prompt "Test prompt"

        $result | Should -Be 'Test response'
    }

    It "Throws when Read-Host throws" {
        Mock Read-Host { throw 'Test error' }

        { Read-HostWrapper -prompt "Test prompt" } | Should -Throw 'Test error'
    }
}

Describe "Add-ContentWrapper" {
    It "Calls Add-Content with the correct parameters and UTF8 encoding" {
        Mock Add-Content {}

        $path = "$TEST_DRIVE\test.txt"
        $content = "Test content"

        Add-ContentWrapper -path $path -value $content

        Should -Invoke Add-Content -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $Value -eq $content -and
            ($Encoding -eq 'UTF8') -or ($Encoding.WebName -eq 'utf-8')
        }
    }

    It "Throws when Add-Content throws" {
        Mock Add-Content { throw 'Test error' }

        $path = "$TEST_DRIVE\test.txt"
        $content = "Test content"

        { Add-ContentWrapper -path $path -value $content } | Should -Throw 'Test error'
    }
}

Describe "Set-ContentWrapper Tests" {
    It "Calls Set-Content with the correct parameters and UTF8 encoding" {
        Mock Set-Content {}

        $path = "$TEST_DRIVE\test.txt"
        $content = "Test content"

        Set-ContentWrapper -path $path -value $content

        Should -Invoke Set-Content -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $Value -eq $content -and
            ($Encoding -eq 'UTF8') -or ($Encoding.WebName -eq 'utf-8')
        }
    }

    It "Throws when Set-Content throws" {
        Mock Set-Content { throw 'Test error' }

        $path = "$TEST_DRIVE\test.txt"
        $content = "Test content"

        { Set-ContentWrapper -path $path -value $content } | Should -Throw 'Test error'
    }
}

Describe "Invoke-WebRequestWrapper Tests" {
    Context "When making web requests" {
        It "Calls Invoke-WebRequest with UseBasicParsing" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Invoke-WebRequestWrapper -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com' -and
                $UseBasicParsing -eq $true
            }
        }

        It "Calls Invoke-WebRequest with OutFile parameter when provided" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }
            $outFile = "$TEST_DRIVE\output.txt"

            $null = Invoke-WebRequestWrapper -uri 'https://example.com' -outFile $outFile

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com' -and
                $UseBasicParsing -eq $true -and
                $OutFile -eq $outFile
            }
        }

        It "Returns the result from Invoke-WebRequest" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200; Content = 'test content' } }

            $result = Invoke-WebRequestWrapper -uri 'https://example.com'

            $result.StatusCode | Should -Be 200
            $result.Content | Should -Be 'test content'
        }

        It "Does not include OutFile parameter when not provided" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Invoke-WebRequestWrapper -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $PSBoundParameters.ContainsKey('OutFile') -eq $false
            }
        }
    }

    Context "Error handling" {
        It "Throws when Invoke-WebRequest throws" {
            Mock Invoke-WebRequest { throw 'Network error' }

            { Invoke-WebRequestWrapper -uri 'https://example.com' } | Should -Throw
        }

        It "Handles invalid URI format" {
            Mock Invoke-WebRequest { throw 'Invalid URI format' }

            { Invoke-WebRequestWrapper -uri 'not-a-valid-uri' } | Should -Throw
        }
    }

    Context "Parameter validation" {
        It "Trims whitespace from URI" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            Invoke-WebRequestWrapper -uri '   https://example.com   '

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com'
            }
        }

        It "Passes trimmed empty string to Invoke-WebRequest" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            Invoke-WebRequestWrapper -uri '   '

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq ''
            }
        }
    }

    Context "With different URI schemes" {
        It "Handles HTTPS URIs" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Invoke-WebRequestWrapper -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com'
            }
        }

        It "Handles HTTP URIs" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Invoke-WebRequestWrapper -uri 'http://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'http://example.com'
            }
        }
    }
}

Describe "Move-ItemWrapper Tests" {
    It "Calls Move-Item with the correct parameters" {
        Mock Move-Item { }

        $source = "$TEST_DRIVE\source"
        $destination = "$TEST_DRIVE\destination"

        $null = Move-ItemWrapper -path $source -destination $destination

        Should -Invoke Move-Item -Times 1 -ParameterFilter {
            $Path -eq $source -and
            $Destination -eq $destination
        }
    }

    It "Throws when Move-Item throws" {
        Mock Move-Item { throw 'Test error' }

        $source = "$TEST_DRIVE\source"
        $destination = "$TEST_DRIVE\destination"

        { Move-ItemWrapper -path $source -destination $destination } | Should -Throw
    }
}

Describe "Copy-ItemWrapper Tests" {
    It "Calls Copy-Item with the correct parameters" {
        Mock Copy-Item { }

        $source = "$TEST_DRIVE\source"
        $destination = "$TEST_DRIVE\destination"

        $null = Copy-ItemWrapper -path $source -destination $destination

        Should -Invoke Copy-Item -Times 1 -ParameterFilter {
            $Path -eq $source -and
            $Destination -eq $destination
        }
    }

    It "Throws when Copy-Item throws" {
        Mock Copy-Item { throw 'Test error' }

        $source = "$TEST_DRIVE\source"
        $destination = "$TEST_DRIVE\destination"

        { Copy-ItemWrapper -path $source -destination $destination } | Should -Throw
    }
}

Describe "Remove-ItemWrapper Tests" {
    It "Calls Remove-Item with the correct parameters" {
        Mock Remove-Item { }

        $path = "$TEST_DRIVE\path"

        $null = Remove-ItemWrapper -path $path

        Should -Invoke Remove-Item -Times 1 -ParameterFilter {
            $Path -eq $path
        }
    }

    It "Throws when Remove-Item throws" {
        Mock Remove-Item { throw 'Test error' }

        $path = "$TEST_DRIVE\path"

        { Remove-ItemWrapper -path $path } | Should -Throw
    }
}

Describe "Get-ItemWrapper Tests" {
    It "Calls Get-Item with the correct parameters" {
        Mock Get-Item { }

        $path = "$TEST_DRIVE\path"

        $null = Get-ItemWrapper -path $path

        Should -Invoke Get-Item -Times 1 -ParameterFilter {
            $Path -eq $path
        }
    }

    It "Throws when Get-Item throws" {
        Mock Get-Item { throw 'Test error' }

        $path = "$TEST_DRIVE\path"

        { Get-ItemWrapper -path $path } | Should -Throw
    }
}

Describe "Get-ChildItemWrapper Tests" {
    It "Calls Get-ChildItem with the correct parameters" {
        Mock Get-ChildItem { }

        $path = "$TEST_DRIVE\path"

        $null = Get-ChildItemWrapper -path $path

        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Path -eq $path
        }
    }

    It "Calls Get-ChildItem with the correct parameters with recurse" {
        Mock Get-ChildItem { }

        $path = "$TEST_DRIVE\path"

        $null = Get-ChildItemWrapper -path $path -recurse -force

        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $Recurse -and
            $Force
        }
    }

    It "Calls Get-ChildItem with the correct parameters with filter" {
        Mock Get-ChildItem { }

        $path = "$TEST_DRIVE\path"

        $null = Get-ChildItemWrapper -path $path -filter '*.txt'

        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $Filter -eq '*.txt'
        }
    }

    It "Calls Get-ChildItem with the correct parameters with file" {
        Mock Get-ChildItem { }

        $path = "$TEST_DRIVE\path"

        $null = Get-ChildItemWrapper -path $path -file

        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $File
        }
    }

    It "Calls Get-ChildItem with the correct parameters with directory" {
        Mock Get-ChildItem { }

        $path = "$TEST_DRIVE\path"

        $null = Get-ChildItemWrapper -path $path -directory

        Should -Invoke Get-ChildItem -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $Directory
        }
    }

    It "Throws when Get-ChildItem throws" {
        Mock Get-ChildItem { throw 'Test error' }

        $path = "$TEST_DRIVE\path"

        { Get-ChildItemWrapper -path $path } | Should -Throw
    }
}

Describe "Get-ContentWrapper Tests" {
    It "Calls Get-Content with the correct parameters" {
        Mock Get-Content { }

        $path = "$TEST_DRIVE\path"

        $null = Get-ContentWrapper -path $path -raw

        Should -Invoke Get-Content -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $Raw
        }
    }

    It "Throws when Get-Content throws" {
        Mock Get-Content { throw 'Test error' }

        $path = "$TEST_DRIVE\path"

        { Get-ContentWrapper -path $path } | Should -Throw
    }
}

Describe "New-ItemWrapper Tests" {
    It "Calls New-Item with the correct parameters - type File" {
        Mock New-Item { }

        $path = "$TEST_DRIVE\path\file.txt"

        $null = New-File -path $path

        Should -Invoke New-Item -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $ItemType -eq 'File'
        }
    }

    It "Calls New-Item with the correct parameters - type Directory" {
        Mock New-Item { }

        $path = "$TEST_DRIVE\path"

        $null = New-Directory -path $path

        Should -Invoke New-Item -Times 1 -ParameterFilter {
            $Path -eq $path -and
            $ItemType -eq 'Directory'
        }
    }

    It "Calls New-Item with the correct parameters - type SymbolicLink" {
        Mock New-Item { }

        $path = "$TEST_DRIVE\path"
        $target = "$TEST_DRIVE\target"

        $null = New-ItemWrapper -type SymbolicLink -path $path -target $target

        Should -Invoke New-Item -Times 1 -ParameterFilter {
            $path -eq $path -and
            $ItemType -eq 'SymbolicLink' -and
            $target -eq $target
        }
    }

    It "Throws when New-Item throws" {
        Mock New-Item { throw 'Test error' }

        $path = "$TEST_DRIVE\path"

        { New-ItemWrapper -path $path } | Should -Throw
    }
}
