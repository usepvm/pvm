
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:STORAGE_PATH = $Global:PVMConfig.paths.directories.storage

    $null = New-Directory -path "$script:STORAGE_PATH\php\8.1"
    $null = New-Directory -path "$script:STORAGE_PATH\php\8.2"

    Mock Add-LogEntry { return 0 }
}

Describe "Get-AllSubdirectories" {
    Context "When path is valid" {
        It "Returns subdirectories for an existing path" {
            $result = Get-AllSubdirectories -path $script:STORAGE_PATH
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -BeGreaterThan 0
        }
    }

    Context "When path is invalid" {
        It "Returns null for empty path" {
            $result = Get-AllSubdirectories -path ''
            $result | Should -Be $null
        }

        It "Returns null for whitespace path" {
            $result = Get-AllSubdirectories -path '   '
            $result | Should -Be $null
        }

        It "Returns null for non-existent path" {
            $result = Get-AllSubdirectories -path "$script:TEST_DRIVE\Nonexistent\Path"
            $result | Should -Be $null
        }

        It "Returns null when an exception occurs" {
            Mock Get-ChildItemWrapper { throw 'Simulated exception' }
            $result = Get-AllSubdirectories -path $script:STORAGE_PATH
            $result | Should -Be $null
        }
    }
}

Describe "Test-DirectoryExists" {
    Context "When checking directory existence" {
        It "Returns true for existing directory" {
            $result = Test-DirectoryExists -path $script:STORAGE_PATH
            $result | Should -Be $true
        }

        It "Returns false for non-existent directory" {
            $result = Test-DirectoryExists -path "$script:TEST_DRIVE\Nonexistent\Path"
            $result | Should -Be $false
        }

        It "Returns false for empty path" {
            $result = Test-DirectoryExists -path ''
            $result | Should -Be $false
        }

        It "Returns false for whitespace path" {
            $result = Test-DirectoryExists -path '   '
            $result | Should -Be $false
        }

        It "Handles exceptions gracefully" {
            Mock Test-PathWrapper { throw 'Error' }

            $result = Test-DirectoryExists -path "$script:TEST_DRIVE\Nonexistent\Path"
            $result | Should -Be $false
        }
    }
}

Describe "Test-DirectoryNotExists" {
    It "Returns true for non-existent directory" {
        Mock Test-DirectoryExists { return $false }

        $result = Test-DirectoryNotExists -path "$script:TEST_DRIVE\Nonexistent\Path"
        $result | Should -Be $true
    }

    It "Returns false for existing directory" {
        Mock Test-DirectoryExists { return $true }

        $result = Test-DirectoryNotExists -path 'C:\Directory\Exists'
        $result | Should -Be $false
    }
}

Describe "Test-FileExists" {
    Context "When checking file existence" {
        It "Returns true for an existing file" {
            $filePath = "$script:TEST_DRIVE\existing_file_exists.txt"
            New-Item -Path $filePath -ItemType File -Force | Out-Null

            $result = Test-FileExists -path $filePath
            $result | Should -Be $true

            Remove-ItemWrapper -path $filePath
        }

        It "Returns false for non-existent file" {
            $result = Test-FileExists -path "$script:TEST_DRIVE\Nonexistent\file.txt"
            $result | Should -Be $false
        }

        It "Returns false for empty path" {
            $result = Test-FileExists -path ''
            $result | Should -Be $false
        }

        It "Returns false for whitespace path" {
            $result = Test-FileExists -path '   '
            $result | Should -Be $false
        }

        It "Handles exceptions gracefully" {
            Mock Test-PathWrapper { throw 'Error' }

            $result = Test-FileExists -path "$script:TEST_DRIVE\Nonexistent\file.txt"
            $result | Should -Be $false
        }
    }
}

Describe "Test-FileNotExists" {
    It "Returns true for non-existent file" {
        Mock Test-FileExists { return $false }

        $result = Test-FileNotExists -path "$script:TEST_DRIVE\Nonexistent\file.txt"
        $result | Should -Be $true
    }

    It "Returns false for existing file" {
        Mock Test-FileExists { return $true }

        $result = Test-FileNotExists -path 'C:\File\Exists.txt'
        $result | Should -Be $false
    }
}

Describe "Test-PathExists" {
    It "Returns false for non-existent path" {
        Mock Test-DirectoryExists { return $false }
        Mock Test-FileExists { return $false }

        $result = Test-PathExists -path "$script:TEST_DRIVE\Nonexistent\Path"
        $result | Should -Be $false
    }

    It "Returns true for existing directory" {
        Mock Test-DirectoryExists { return $true }
        Mock Test-FileExists { return $false }

        $result = Test-PathExists -path 'C:\Directory\Exists'
        $result | Should -Be $true
    }

    It "Returns true for existing file" {
        Mock Test-DirectoryExists { return $false }
        Mock Test-FileExists { return $true }

        $result = Test-PathExists -path 'C:\File\Exists.txt'
        $result | Should -Be $true
    }
}

Describe "Test-PathNotExists" {
    It "Returns true for non-existent path" {
        Mock Test-PathExists { return $false }

        $result = Test-PathNotExists -path "$script:TEST_DRIVE\Nonexistent\Path"
        $result | Should -Be $true
    }

    It "Returns false for existing path" {
        Mock Test-PathExists { return $true }

        $result = Test-PathNotExists -path 'C:\Directory\Exists'
        $result | Should -Be $false
    }
}

Describe "Test-SymlinkExists" {
    It "Returns false for null path" {
        $result = Test-SymlinkExists -path $null

        $result | Should -Be $false
    }

    It "Returns false for empty path" {
        $result = Test-SymlinkExists -path ''

        $result | Should -Be $false
    }

    It "Returns false for whitespace path" {
        $result = Test-SymlinkExists -path '   '

        $result | Should -Be $false
    }

    It "Handles exceptions gracefully" {
        Mock Get-ItemWrapper { throw 'Error' }

        $result = Test-SymlinkExists -path "$script:TEST_DRIVE\Nonexistent\Path"
        $result | Should -Be $false
    }

    It "Returns true for existing symlink" {
        Mock Get-ItemWrapper { return @{ Attributes = 'ReparsePoint' } }

        $result = Test-SymlinkExists -path "$script:TEST_DRIVE\pvm\php"

        $result | Should -Be $true
    }
}

Describe "Test-SymlinkNotExists" {
    It "Returns false for existing symlink" {
        Mock Test-SymlinkExists { return $true }

        $result = Test-SymlinkNotExists -path "$script:TEST_DRIVE\pvm\php"

        $result | Should -Be $false
    }

    It "Returns true for non-existent symlink" {
        Mock Test-SymlinkExists { return $false }

        $result = Test-SymlinkNotExists -path "$script:TEST_DRIVE\Nonexistent\Path"

        $result | Should -Be $true
    }
}

Describe "New-Directory" {
    Context "When creating directories" {
        It "Creates a new directory successfully" {
            Mock New-ItemWrapper { return @{ Name = 'test_link' } }
            $newDir = "$script:TEST_DRIVE\new_dir"

            $result = New-Directory -path $newDir

            $result | Should -Be 0
            Should -Invoke New-ItemWrapper -ParameterFilter {
                $type -eq 'Directory' -and $path -eq $newDir
            }
        }

        It "Returns 0 for existing directory" {
            Mock New-ItemWrapper { return @{ FullName = $script:STORAGE_PATH } }

            $result = New-Directory -path $script:STORAGE_PATH

            $result | Should -Be 0
        }

        It "Returns -1 for empty path" {
            $result = New-Directory -path ''

            $result | Should -Be -1
        }

        It "Returns -1 when creating directory fails" {
            Mock New-ItemWrapper { return $null }
            $newDir = "$script:TEST_DRIVE\new_dir"

            $result = New-Directory -path $newDir

            $result | Should -Be -1
        }

        It "Returns -1 when exception is thrown" {
            Mock Test-DirectoryNotExists { return $true }
            Mock New-ItemWrapper { throw 'Error' }

            $result = New-Directory -path "$script:TEST_DRIVE\new_dir"

            $result | Should -Be -1
        }
    }
}

Describe "New-File" {
    It "Creates a new file successfully" {
        Mock New-ItemWrapper { return @{ Name = 'new_file.txt' } }
        $newFile = 'TestDrive:\new_file.txt'

        $result = New-File -path $newFile

        $result | Should -Be 0
        Should -Invoke New-ItemWrapper -ParameterFilter {
            $type -eq 'File' -and $path -eq $newFile
        }
    }

    It "Returns 0 for existing file" {
        $existingFile = 'TestDrive:\existing_file.txt'
        Mock New-ItemWrapper { return @{ FullName = $existingFile } }

        $result = New-File -path $existingFile

        $result | Should -Be 0
    }

    It "Returns -1 for empty path" {
        $result = New-File -path ''

        $result | Should -Be -1
    }

    It "Returns -1 when creating file fails" {
        Mock New-ItemWrapper { return $null }
        $newFile = 'TestDrive:\new_file.txt'

        $result = New-File -path $newFile

        $result | Should -Be -1
    }

    It "Returns -1 when exception is thrown" {
        Mock Test-FileNotExists { return $true }
        Mock New-ItemWrapper { throw 'Error' }

        $result = New-File -path 'TestDrive:\new_file.txt'

        $result | Should -Be -1
    }
}

Describe "New-SymbolicLink" {
    Context "When creating symbolic links" {
        It "Creates a symbolic link successfully when running as admin" {
            Mock Test-Admin { return $true }
            Mock New-ItemWrapper {
                param ($type, $path, $target)

                return @{ FullName = $path }
            }
            $linkPath = "$script:TEST_DRIVE\test_link"
            $targetPath = "$script:STORAGE_PATH\php\8.1"

            $result = New-SymbolicLink -link $linkPath -target $targetPath

            $result.code | Should -Be 0
            $result.message | Should -Match 'Created symbolic link'
            $result.color | Should -Be 'DarkGreen'
            Should -Invoke New-ItemWrapper -ParameterFilter {
                $type -eq 'SymbolicLink' -and
                $path -eq $linkPath -and
                $target -eq $targetPath
            }
        }

        It "Returns -1 if fails to create symbolic link" {
            Mock Test-NotAdmin { return $true }
            Mock Invoke-PSCommand { return -1 }
            $linkPath = "$script:TEST_DRIVE\test_link_fail"
            $targetPath = "$script:STORAGE_PATH\php\8.1"

            $result = New-SymbolicLink -link $linkPath -target $targetPath

            $result.code | Should -Be -1
            $result.message | Should -Be "Failed to create symbolic link '$linkPath' -> '$targetPath'"
            $result.color | Should -Be 'DarkYellow'
        }

        It "Creates a symbolic link successfully using elevated command" {
            Mock Test-NotAdmin { return $true }
            Mock Invoke-PSCommand { return 0 }
            $linkPath = "$script:TEST_DRIVE\test_link_2"
            $targetPath = "$script:STORAGE_PATH\php\8.1"

            $result = New-SymbolicLink -link $linkPath -target $targetPath

            $result.code | Should -Be 0
            $result.message | Should -Match 'Created symbolic link'
            $result.color | Should -Be 'DarkGreen'
            Should -Invoke Invoke-PSCommand -ParameterFilter {
                $command -like '*New-Item -ItemType SymbolicLink*' -and
                $command -like "*$linkPath*" -and
                $command -like "*$targetPath*"
            }
        }

        It "Returns -1 if target directory does not exist" {
            $result = New-SymbolicLink -link "$script:TEST_DRIVE\link" -target "$script:TEST_DRIVE\Nonexistent\Target"

            $result.code | Should -Be -1
            $result.message | Should -Match "Target directory "$script:TEST_DRIVE\\Nonexistent\\Target" does not exist!"
            $result.color | Should -Be 'DarkYellow'
        }

        It "Returns -1 if link already exists and is not a symbolic link" {
            # Create a regular file to simulate existing non-link
            $existingPath = "$script:TEST_DRIVE\existing_file"
            New-Item -Path $existingPath -ItemType File -Force | Out-Null

            $result = New-SymbolicLink -link $existingPath -target "$script:STORAGE_PATH\php\8.1"

            $result.code | Should -Be -1
            $result.message | Should -Be "Link '$existingPath' is not a symbolic link!"
            $result.color | Should -Be 'DarkYellow'

            # Cleanup
            Remove-ItemWrapper -path $existingPath
        }

        It "Deletes existing symbolic link and creates new one" {
            $script:STORAGE_PATH_TEMP = (Resolve-Path -Path $script:STORAGE_PATH).ProviderPath
            $testDir = "$script:STORAGE_PATH_TEMP\tests\symlink_test"
            $linkPath = "$testDir\test_link"
            $targetPath = "$testDir\php\8.1"

            try {
                Mock Test-NotAdmin { return $false }
                Mock New-ItemWrapper { return @{ Name = 'test_link'; FullName = $linkPath } }
                Mock New-Directory { return 0 }
                Mock Get-ItemWrapper { return @{ Attributes = 'ReparsePoint' } }

                New-Item -ItemType Directory -Path $testDir -Force | Out-Null
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                # Create a directory at the link path to simulate an existing item
                New-Item -ItemType Directory -Path $linkPath -Force | Out-Null

                $result = New-SymbolicLink -link $linkPath -target $targetPath

                $result.code | Should -Be 0
                $result.message | Should -Match "Created symbolic link"
            } finally {
                # Cleanup
                if (Test-Path $testDir) {
                    Remove-ItemWrapper -path $testDir
                }
            }
        }

        It "Returns -1 when creating symlink fails" {
            Mock Test-DirectoryNotExists { return $false }
            Mock Test-SymlinkExists { return $false }
            Mock Test-PathExists { return $false }
            Mock Test-NotAdmin { return $false }
            Mock New-ItemWrapper { return $null }
            $linkPath = "$script:STORAGE_PATH\test_link"
            $targetPath = "$script:STORAGE_PATH\php\8.1"

            $result = New-SymbolicLink -link $linkPath -target $targetPath

            $result.code | Should -Be -1
        }

        It "Handles exceptions gracefully" {
            Mock Test-DirectoryExists { throw 'Simulated exception' }

            $result = New-SymbolicLink -link "$script:TEST_DRIVE\link" -target "$script:TEST_DRIVE\target"

            $result.code | Should -Be -1
        }

        It "Returns -1 for empty link path" {
            $result = New-SymbolicLink -link '' -target "$script:TEST_DRIVE\target"

            $result.code | Should -Be -1
        }

        It "Returns -1 for empty target path" {
            $result = New-SymbolicLink -link "$script:TEST_DRIVE\link" -target ''

            $result.code | Should -Be -1
        }
    }

    Context "When link directory does not exist" {
        It "Creates a symbolic link successfully" {
            $linkPath = "$script:TEST_DRIVE\test_parent\test_link"
            $targetPath = "$script:STORAGE_PATH\php\8.1"
            $parent = Split-Path -Path $linkPath

            Mock Test-DirectoryNotExists -ParameterFilter { $path -eq $targetPath } -MockWith { return $false }
            Mock Test-DirectoryNotExists -ParameterFilter { $path -eq $parent } -MockWith { return $true }
            Mock Test-NotAdmin { return $false }
            Mock New-Directory { return 0 }
            Mock Test-PathExists { return $false }
            Mock New-ItemWrapper {
                param ($type, $path, $target)

                return @{ FullName = $path }
            }

            $result = New-SymbolicLink -link $linkPath -target $targetPath
            $result.code | Should -Be 0
        }

        It "Returns -1 when symbolic link parent directory fails to create" {
            $linkPath = "$script:TEST_DRIVE\test_parent\test_link"
            $targetPath = "$script:STORAGE_PATH\php\8.1"
            Mock Test-DirectoryNotExists -ParameterFilter { $path -eq "$script:TEST_DRIVE\test_parent" } -MockWith { return $true }
            Mock Test-DirectoryNotExists -ParameterFilter { $path -eq $targetPath } -MockWith { return $false }
            Mock New-Directory { return -1 }
            $result = New-SymbolicLink -link $linkPath -target $targetPath
            $result.code | Should -Be -1
        }
    }
}

Describe "Expand-ZipCore" {
    It "Loads System.IO.Compression.FileSystem assembly and extracts zip" {
        $script:STORAGE_PATH_TEMP = (Resolve-Path -Path $script:STORAGE_PATH).ProviderPath
        $testDir = "$script:STORAGE_PATH_TEMP\tests\zip_test"
        $zipPath = "$testDir\test.zip"
        $extractPath = "$testDir\extract"
        $testFile = "$testDir\source\test.txt"

        try {
            # Create source directory and file
            New-Item -ItemType Directory -Path (Split-Path $testFile) -Force | Out-Null
            'test content' | Set-ContentWrapper -path $testFile

            # Create zip file using PowerShell's Compress-Archive
            Compress-Archive -Path $testFile -DestinationPath $zipPath -Force

            # Create extraction directory
            New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

            # Call Expand-ZipCore
            { Expand-ZipCore -zipPath $zipPath -extractPath $extractPath } | Should -Not -Throw

            # Verify extraction worked
            $extractedFile = "$extractPath\test.txt"
            Test-Path $extractedFile | Should -Be $true
            Get-ContentWrapper -path $extractedFile | Should -Be 'test content'
        } finally {
            # Cleanup
            if (Test-Path $testDir) {
                Remove-ItemWrapper -path $testDir
            }
        }
    }
}

Describe "Expand-Zip" {
    BeforeEach {
        Mock Expand-ZipCore { }
        Mock Remove-ItemWrapper { }
        Mock Add-LogEntry { }
    }

    It "Should extract zip without errors" {
        { Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' } | Should -Not -Throw
        Should -Invoke Expand-ZipCore -Times 1
    }

    It "Should delete zip after extraction" {
        { Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' -deleteZipAfter $true } | Should -Not -Throw
        Should -Invoke Remove-ItemWrapper -Times 1 -ParameterFilter { $path -eq 'test.zip' }
    }

    It "Should not delete zip if deleteZipAfter is false" {
        { Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' -deleteZipAfter $false } | Should -Not -Throw
        Should -Invoke Remove-ItemWrapper -Times 0
    }

    It "Should call Add-LogEntry on extraction failure" {
        Mock Expand-ZipCore { throw "Extraction failed" }
        { Expand-Zip -zipPath 'bad.zip' -extractPath 'testdir' } | Should -Not -Throw
        Should -Invoke Add-LogEntry -Times 1
    }
}

Describe "Test-YesResponse" {
    It "Should return true for 'y' and 'Y' responses" {
        Test-YesResponse -response 'y' | Should -Be $true
        Test-YesResponse -response 'Y' | Should -Be $true
    }

    It "Should return false for other responses" {
        Test-YesResponse -response 'n' | Should -Be $false
        Test-YesResponse -response 'N' | Should -Be $false
    }
}

Describe "Test-NoResponse" {
    It "Should return true for 'n' and 'N' responses" {
        Test-NoResponse -response 'n' | Should -Be $true
        Test-NoResponse -response 'N' | Should -Be $true
    }

    It "Should return false for other responses" {
        Test-NoResponse -response 'y' | Should -Be $false
        Test-NoResponse -response 'Y' | Should -Be $false
    }
}

Describe "Get-BaseUrl" {
    It "Should return the expected base URL" {
        $result = Get-BaseUrl -url 'https://example.com/test'
        $result | Should -Be 'example.com'
    }

    It "Should return an empty string for an invalid URL" {
        $result = Get-BaseUrl -url 'invalid-url'
        $result | Should -Be $null
    }

    It "Should return an empty string for an empty URL" {
        $result = Get-BaseUrl -url ''
        $result | Should -Be $null
    }

    It "Should return an empty string for a null URL" {
        $result = Get-BaseUrl -url $null
        $result | Should -Be $null
    }
}
