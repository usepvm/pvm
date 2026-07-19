
BeforeAll {
    Mock Write-Host {}
    # Create a mock registry to simulate environment variables
    $script:MockRegistry = @{
        Machine = @{
            'Path' = 'C:\Windows\System32;C:\Program Files\Git\bin;C:\CustomApp;C:\Program Files\Java\bin'
            'JAVA_HOME' = 'C:\Program Files\Java'
            'GIT_HOME' = 'C:\Program Files\Git\bin'
            'CUSTOM_APP' = 'C:\CustomApp'
            'WINDOWS_DIR' = 'C:\Windows'
            'SYSTEM32_DIR' = 'C:\Windows\System32'
            'REGULAR_VAR' = 'SomeValue'
        }
    }

    # Setup test environment
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\io-drive"
    $script:STORAGE_PATH = $PVMConfig.paths.storage = "$TEST_DRIVE\storage"
    $PVMConfig.paths.logError = "$TEST_DRIVE\logs\error.log"
    $PVMConfig.paths.pathVarBackup = "$TEST_DRIVE\logs\path_backup.log"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path "$STORAGE_PATH\php\8.1" -Force | Out-Null
    New-Item -ItemType Directory -Path "$STORAGE_PATH\php\8.2" -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-All-Subdirectories" {
    Context "When path is valid" {
        It "Returns subdirectories for an existing path" {
            $result = Get-All-Subdirectories -path $STORAGE_PATH
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }
    }

    Context "When path is invalid" {
        It "Returns null for empty path" {
            $result = Get-All-Subdirectories -path ''
            $result | Should -Be $null
        }

        It "Returns null for whitespace path" {
            $result = Get-All-Subdirectories -path '   '
            $result | Should -Be $null
        }

        It "Returns null for non-existent path" {
            $result = Get-All-Subdirectories -path "$TEST_DRIVE\Nonexistent\Path"
            $result | Should -Be $null
        }

        It "Returns null when an exception occurs" {
            # Simulate an exception by passing a path that causes an error
            Mock Get-ChildItem { throw 'Simulated exception' }
            $result = Get-All-Subdirectories -path $STORAGE_PATH
            $result | Should -Be $null
        }
    }
}

Describe "Test-Directory-Exists" {
    Context "When checking directory existence" {
        It "Returns true for existing directory" {
            $result = Test-Directory-Exists -path $STORAGE_PATH
            $result | Should -Be $true
        }

        It "Returns false for non-existent directory" {
            $result = Test-Directory-Exists -path "$TEST_DRIVE\Nonexistent\Path"
            $result | Should -Be $false
        }

        It "Returns false for empty path" {
            $result = Test-Directory-Exists -path ''
            $result | Should -Be $false
        }

        It "Returns false for whitespace path" {
            $result = Test-Directory-Exists -path '   '
            $result | Should -Be $false
        }

        It "Handles exceptions gracefully" {
            Mock Test-Path { throw 'Error' }

            $result = Test-Directory-Exists -path "$TEST_DRIVE\Nonexistent\Path"
            $result | Should -Be $false
        }
    }
}

Describe "Test-Directory-Not-Exists" {
    It "Returns true for non-existent directory" {
        Mock Test-Directory-Exists { return $false }

        $result = Test-Directory-Not-Exists -path "$TEST_DRIVE\Nonexistent\Path"
        $result | Should -Be $true
    }

    It "Returns false for existing directory" {
        Mock Test-Directory-Exists { return $true }

        $result = Test-Directory-Not-Exists -path 'C:\Directory\Exists'
        $result | Should -Be $false
    }
}

Describe "Test-File-Exists" {
    Context "When checking file existence" {
        It "Returns true for an existing file" {
            $filePath = "$TEST_DRIVE\existing_file_exists.txt"
            New-Item -Path $filePath -ItemType File -Force | Out-Null

            $result = Test-File-Exists -path $filePath
            $result | Should -Be $true

            Remove-Item -Path $filePath -Force
        }

        It "Returns false for non-existent file" {
            $result = Test-File-Exists -path "$TEST_DRIVE\Nonexistent\file.txt"
            $result | Should -Be $false
        }

        It "Returns false for empty path" {
            $result = Test-File-Exists -path ''
            $result | Should -Be $false
        }

        It "Returns false for whitespace path" {
            $result = Test-File-Exists -path '   '
            $result | Should -Be $false
        }

        It "Handles exceptions gracefully" {
            Mock Test-Path { throw 'Error' }

            $result = Test-File-Exists -path "$TEST_DRIVE\Nonexistent\file.txt"
            $result | Should -Be $false
        }
    }
}

Describe "Test-File-Not-Exists" {
    It "Returns true for non-existent file" {
        Mock Test-File-Exists { return $false }

        $result = Test-File-Not-Exists -path "$TEST_DRIVE\Nonexistent\file.txt"
        $result | Should -Be $true
    }

    It "Returns false for existing file" {
        Mock Test-File-Exists { return $true }

        $result = Test-File-Not-Exists -path 'C:\File\Exists.txt'
        $result | Should -Be $false
    }
}

Describe "New-Directory" {
    Context "When creating directories" {
        It "Creates a new directory successfully" {
            $newDir = "$TEST_DRIVE\new_dir"
            $result = New-Directory -path $newDir
            $result | Should -Be 0
            Test-Path $newDir | Should -Be $true
        }

        It "Returns 0 for existing directory" {
            $result = New-Directory -path $STORAGE_PATH
            $result | Should -Be 0
        }

        It "Returns -1 for empty path" {
            $result = New-Directory -path ''
            $result | Should -Be -1
        }

        It "Returns -1 when exception is thrown" {
            Mock Test-Directory-Not-Exists { return $true }
            Mock New-Item { throw 'Error' }
            $result = New-Directory -path "$TEST_DRIVE\new_dir"
            $result | Should -Be -1
        }
    }
}

Describe "New-Symbolic-Link" {
    Context "When creating symbolic links" {
        It "Creates a symbolic link successfully when running as admin" {
            # Mock Test-Admin to return true
            Mock Test-Admin { return $true }

            # Mock New-Item to simulate successful symbolic link creation
            Mock New-Item {
                param ($ItemType, $Path, $Target)

                return @{ FullName = $Path }
            }

            $linkPath = "$TEST_DRIVE\test_link"
            $targetPath = "$STORAGE_PATH\php\8.1"

            $result = New-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be 0
            $result.message | Should -Match 'Created symbolic link'
            $result.color | Should -Be 'DarkGreen'

            # Verify New-Item was called with correct parameters
            Should -Invoke New-Item -ParameterFilter {
                $ItemType -eq 'SymbolicLink' -and
                $Path -eq $linkPath -and
                $Target -eq $targetPath
            }
        }

        It "Returns -1 if fails to create symbolic link" {
            Mock Test-Not-Admin { return $true }
            Mock Invoke-PS-Command { return -1 }
            $linkPath = "$TEST_DRIVE\test_link_fail"
            $targetPath = "$STORAGE_PATH\php\8.1"
            $result = New-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be -1
            $result.message | Should -Be "Failed to create symbolic link '$linkPath' -> '$targetPath'"
            $result.color | Should -Be 'DarkYellow'
        }

        It "Creates a symbolic link successfully using elevated command" {
            Mock Test-Not-Admin { return $true }
            Mock Invoke-PS-Command { return 0 }

            $linkPath = "$TEST_DRIVE\test_link_2"
            $targetPath = "$STORAGE_PATH\php\8.1"

            $result = New-Symbolic-Link -link $linkPath -target $targetPath

            $result.code | Should -Be 0
            $result.message | Should -Match 'Created symbolic link'
            $result.color | Should -Be 'DarkGreen'

            Should -Invoke Invoke-PS-Command -ParameterFilter {
                $command -like '*New-Item -ItemType SymbolicLink*' -and
                $command -like "*$linkPath*" -and
                $command -like "*$targetPath*"
            }
        }

        It "Returns -1 if target directory does not exist" {
            $result = New-Symbolic-Link -link "$TEST_DRIVE\link" -target "$TEST_DRIVE\Nonexistent\Target"
            $result.code | Should -Be -1
            $result.message | Should -Match "Target directory "$TEST_DRIVE\\Nonexistent\\Target" does not exist!"
            $result.color | Should -Be 'DarkYellow'
        }

        It "Returns -1 if link already exists and is not a symbolic link" {
            # Create a regular file to simulate existing non-link
            $existingPath = "$TEST_DRIVE\existing_file"
            New-Item -Path $existingPath -ItemType File -Force | Out-Null

            $result = New-Symbolic-Link -link $existingPath -target "$STORAGE_PATH\php\8.1"
            $result.code | Should -Be -1
            $result.message | Should -Be "Link '$existingPath' is not a symbolic link!"
            $result.color | Should -Be 'DarkYellow'

            # Cleanup
            Remove-Item -Path $existingPath -Force
        }

        It "Deletes existing symbolic link and creates new one" {
            # Use project storage path for testing
            $STORAGE_PATH_TEMP = (Resolve-Path -Path $STORAGE_PATH).ProviderPath
            $testDir = "$STORAGE_PATH_TEMP\tests\symlink_test"
            $linkPath = "$testDir\test_link"
            $targetPath = "$testDir\php\8.1"

            try {
                Mock Test-Admin { return $true }
                Mock New-Directory { return 0 }
                Mock Get-Item { return @{ Attributes = 'ReparsePoint' } }

                New-Item -ItemType Directory -Path $testDir -Force | Out-Null
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null

                # # Create a directory at the link path to simulate an existing item
                New-Item -ItemType Directory -Path $linkPath -Force | Out-Null

                $result = New-Symbolic-Link -link $linkPath -target $targetPath

                $result.code | Should -Be 0
                $result.message | Should -Match "Created symbolic link"
            } finally {
                # Cleanup
                if (Test-Path $testDir) {
                    Remove-Item -Path $testDir -Recurse -Force
                }
            }
        }

        It "Handles exceptions gracefully" {
            Mock Test-Directory-Exists { throw 'Simulated exception' }
            $result = New-Symbolic-Link -link "$TEST_DRIVE\link" -target "$TEST_DRIVE\target"
            $result.code | Should -Be -1
        }

        It "Returns -1 for empty link path" {
            $result = New-Symbolic-Link -link '' -target "$TEST_DRIVE\target"
            $result.code | Should -Be -1
        }

        It "Returns -1 for empty target path" {
            $result = New-Symbolic-Link -link "$TEST_DRIVE\link" -target ''
            $result.code | Should -Be -1
        }
    }

    Context "When link directory does not exist" {
        It "Creates a symbolic link successfully" {
            $linkPath = "$TEST_DRIVE\test_parent\test_link"
            $targetPath = "$STORAGE_PATH\php\8.1"
            $parent = Split-Path -Path $linkPath

            Mock Test-Directory-Not-Exists -ParameterFilter { $path -eq $targetPath } -MockWith { return $false }
            Mock Test-Directory-Not-Exists -ParameterFilter { $path -eq $parent } -MockWith { return $true }
            Mock Test-Not-Admin { return $false }
            Mock New-Directory -MockWith { return 0 }
            Mock Test-Path { return $false }
            Mock New-Item {
                param ($ItemType, $Path, $Target)

                return @{ FullName = $Path }
            }

            $result = New-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be 0
        }

        It "Returns -1 when symbolic link parent directory fails to create" {
            $linkPath = "$TEST_DRIVE\test_parent\test_link"
            $targetPath = "$STORAGE_PATH\php\8.1"
            Mock Test-Directory-Not-Exists -ParameterFilter { $path -eq "$TEST_DRIVE\test_parent" } -MockWith { return $true }
            Mock Test-Directory-Not-Exists -ParameterFilter { $path -eq $targetPath } -MockWith { return $false }
            Mock New-Directory -MockWith { return -1 }
            $result = New-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be -1
        }
    }
}

Describe "Expand-Zip-Core Tests" {
    It "Loads System.IO.Compression.FileSystem assembly and extracts zip" {
        # Use project storage path for testing
        $STORAGE_PATH_TEMP = (Resolve-Path -Path $STORAGE_PATH).ProviderPath
        $testDir = "$STORAGE_PATH_TEMP\tests\zip_test"
        $zipPath = "$testDir\test.zip"
        $extractPath = "$testDir\extract"
        $testFile = "$testDir\source\test.txt"

        try {
            # Create source directory and file
            New-Item -ItemType Directory -Path (Split-Path $testFile) -Force | Out-Null
            'test content' | Set-Content -Path $testFile

            # Create zip file using PowerShell's Compress-Archive
            Compress-Archive -Path $testFile -DestinationPath $zipPath -Force

            # Create extraction directory
            New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

            # Call Expand-Zip-Core
            { Expand-Zip-Core -zipPath $zipPath -extractPath $extractPath } | Should -Not -Throw

            # Verify extraction worked
            $extractedFile = "$extractPath\test.txt"
            Test-Path $extractedFile | Should -Be $true
            Get-Content $extractedFile | Should -Be 'test content'
        } finally {
            # Cleanup
            if (Test-Path $testDir) {
                Remove-Item -Path $testDir -Recurse -Force
            }
        }
    }
}

Describe "Expand-Zip Tests" {
    BeforeEach {
        Mock Expand-Zip-Core { }
        Mock Remove-Item { }
        Mock Write-Host { }
        Mock Add-LogEntry { }
    }

    It "Should extract zip without errors" {
        # This is a basic test since we're mocking the zip extraction
        { Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' } | Should -Not -Throw
        Should -Invoke Expand-Zip-Core -Times 1
    }

    It "Should delete zip after extraction" {
        { Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' -deleteZipAfter $true } | Should -Not -Throw
        Should -Invoke Remove-Item -Times 1 -ParameterFilter { $Path -eq 'test.zip' }
    }

    It "Should not delete zip if deleteZipAfter is false" {
        { Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' -deleteZipAfter $false } | Should -Not -Throw
        Should -Invoke Remove-Item -Times 0
    }

    It "Should call Add-LogEntry on extraction failure" {
        Mock Expand-Zip-Core { throw "Extraction failed" }
        { Expand-Zip -zipPath 'bad.zip' -extractPath 'testdir' } | Should -Not -Throw
        Should -Invoke Add-LogEntry -Times 1
    }
}

Describe "Get-Web-Response Tests" {
    Context "When making web requests" {
        It "Calls Invoke-WebRequest with UseBasicParsing" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Get-Web-Response -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com' -and
                $UseBasicParsing -eq $true
            }
        }

        It "Calls Invoke-WebRequest with OutFile parameter when provided" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }
            $outFile = "$TEST_DRIVE\output.txt"

            $null = Get-Web-Response -uri 'https://example.com' -outFile $outFile

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com' -and
                $UseBasicParsing -eq $true -and
                $OutFile -eq $outFile
            }
        }

        It "Returns the result from Invoke-WebRequest" {
            $mockResponse = @{ StatusCode = 200; Content = 'test content' }
            Mock Invoke-WebRequest { return $mockResponse }

            $result = Get-Web-Response -uri 'https://example.com'

            $result.StatusCode | Should -Be 200
            $result.Content | Should -Be 'test content'
        }

        It "Does not include OutFile parameter when not provided" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Get-Web-Response -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $PSBoundParameters.ContainsKey('OutFile') -eq $false
            }
        }
    }

    Context "Error handling" {
        It "Throws when Invoke-WebRequest throws" {
            Mock Invoke-WebRequest { throw 'Network error' }

            { Get-Web-Response -uri 'https://example.com' } | Should -Throw
        }

        It "Handles invalid URI format" {
            Mock Invoke-WebRequest { throw 'Invalid URI format' }

            { Get-Web-Response -uri 'not-a-valid-uri' } | Should -Throw
        }
    }

    Context "Parameter validation" {
        It "Trims whitespace from URI" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            Get-Web-Response -uri '   https://example.com   '

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com'
            }
        }

        It "Passes trimmed empty string to Invoke-WebRequest" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            Get-Web-Response -uri '   '

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq ''
            }
        }
    }

    Context "With different URI schemes" {
        It "Handles HTTPS URIs" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Get-Web-Response -uri 'https://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://example.com'
            }
        }

        It "Handles HTTP URIs" {
            Mock Invoke-WebRequest { return @{ StatusCode = 200 } }

            $null = Get-Web-Response -uri 'http://example.com'

            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'http://example.com'
            }
        }
    }
}

