

BeforeAll {
    Mock Write-Host {}

    # Setup test environment
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\wrappers-drive"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Read-Host-Wrapper" {
    It "Calls Read-Host with no parameters" {
        Mock Read-Host { }

        $result = Read-Host-Wrapper

        $result | Should -BeNullOrEmpty
        Should -Invoke Read-Host -Times 1 -ParameterFilter {
            $Prompt -eq $null
        }
    }

    It "Calls Read-Host with the correct parameters" {
        Mock Read-Host { return 'Test response' }

        $prompt = "Test prompt"

        $result = Read-Host-Wrapper -prompt $prompt

        $result | Should -Be 'Test response'
        Should -Invoke Read-Host -Times 1 -ParameterFilter {
            $Prompt -eq $prompt
        }
    }

    It "Returns null when Read-Host returns empty string" {
        Mock Read-Host { return '' }

        $result = Read-Host-Wrapper -prompt "Test prompt"

        $result | Should -BeNullOrEmpty
    }

    It "Returns null when Read-Host returns null" {
        Mock Read-Host { return $null }

        $result = Read-Host-Wrapper -prompt "Test prompt"

        $result | Should -BeNullOrEmpty
    }

    It "Returns null when Read-Host returns whitespace only" {
        Mock Read-Host { return '   ' }

        $result = Read-Host-Wrapper -prompt "Test prompt"

        $result | Should -BeNullOrEmpty
    }

    It "Returns trimmed value when Read-Host returns whitespace" {
        Mock Read-Host { return ' Test response  ' }

        $result = Read-Host-Wrapper -prompt "Test prompt"

        $result | Should -Be 'Test response'
    }

    It "Throws when Read-Host throws" {
        Mock Read-Host { throw 'Test error' }

        { Read-Host-Wrapper -prompt "Test prompt" } | Should -Throw 'Test error'
    }
}

Describe "Add-Content-Wrapper" {
    It "Calls Add-Content with the correct parameters and UTF8 encoding" {
        Mock Add-Content {}

        $path = "$TEST_DRIVE\test.txt"
        $content = "Test content"

        Add-Content-Wrapper -path $path -value $content

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

        { Add-Content-Wrapper -path $path -value $content } | Should -Throw 'Test error'
    }
}

Describe "Set-Content-Wrapper Tests" {
    It "Calls Set-Content with the correct parameters and UTF8 encoding" {
        Mock Set-Content {}

        $path = "$TEST_DRIVE\test.txt"
        $content = "Test content"

        Set-Content-Wrapper -path $path -value $content

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

        { Set-Content-Wrapper -path $path -value $content } | Should -Throw 'Test error'
    }
}

Describe "Get-WebResponse Tests" {
    Context "When making web requests" {
        It "Calls Invoke-WebRequest with UseBasicParsing" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Get-WebResponse -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com' -and
                $UseBasicParsing -eq $true
            }
        }

        It "Calls Invoke-WebRequest with OutFile parameter when provided" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }
            $outFile = "$TEST_DRIVE\output.txt"

            $null = Get-WebResponse -uri 'https://example.com' -outFile $outFile

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com' -and
                $UseBasicParsing -eq $true -and
                $OutFile -eq $outFile
            }
        }

        It "Returns the result from Invoke-WebRequest" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200; Content = 'test content' } }

            $result = Get-WebResponse -uri 'https://example.com'

            $result.StatusCode | Should -Be 200
            $result.Content | Should -Be 'test content'
        }

        It "Does not include OutFile parameter when not provided" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Get-WebResponse -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $PSBoundParameters.ContainsKey('OutFile') -eq $false
            }
        }
    }

    Context "Error handling" {
        It "Throws when Invoke-WebRequest throws" {
            Mock Invoke-WebRequest { throw 'Network error' }

            { Get-WebResponse -uri 'https://example.com' } | Should -Throw
        }

        It "Handles invalid URI format" {
            Mock Invoke-WebRequest { throw 'Invalid URI format' }

            { Get-WebResponse -uri 'not-a-valid-uri' } | Should -Throw
        }
    }

    Context "Parameter validation" {
        It "Trims whitespace from URI" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            Get-WebResponse -uri '   https://example.com   '

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com'
            }
        }

        It "Passes trimmed empty string to Invoke-WebRequest" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            Get-WebResponse -uri '   '

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq ''
            }
        }
    }

    Context "With different URI schemes" {
        It "Handles HTTPS URIs" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Get-WebResponse -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com'
            }
        }

        It "Handles HTTP URIs" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Get-WebResponse -uri 'http://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'http://example.com'
            }
        }
    }
}
