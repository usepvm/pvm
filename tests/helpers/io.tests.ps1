
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
    $script:STORAGE_PATH = $PVMConfig.paths.storage = 'TestDrive:\storage'
    $PVMConfig.paths.logError = 'TestDrive:\logs\error.log'
    $PVMConfig.paths.pathVarBackup = 'TestDrive:\logs\path_backup.log'

    New-Item -ItemType Directory -Path "$STORAGE_PATH\php\8.1" -Force | Out-Null
    New-Item -ItemType Directory -Path "$STORAGE_PATH\php\8.2" -Force | Out-Null
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
            $result = Get-All-Subdirectories -path 'TestDrive:\Nonexistent\Path'
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

Describe "Is-Directory-Exists" {
    Context "When checking directory existence" {
        It "Returns true for existing directory" {
            $result = Is-Directory-Exists -path $STORAGE_PATH
            $result | Should -Be $true
        }

        It "Returns false for non-existent directory" {
            $result = Is-Directory-Exists -path 'TestDrive:\Nonexistent\Path'
            $result | Should -Be $false
        }

        It "Returns false for empty path" {
            $result = Is-Directory-Exists -path ''
            $result | Should -Be $false
        }

        It "Returns false for whitespace path" {
            $result = Is-Directory-Exists -path '   '
            $result | Should -Be $false
        }

        It "Handles exceptions gracefully" {
            Mock Test-Path { throw 'Error' }

            $result = Is-Directory-Exists -path 'TestDrive:\Nonexistent\Path'
            $result | Should -Be $false
        }
    }
}

Describe "Is-Directory-Not-Exists" {
    It "Returns true for non-existent directory" {
        Mock Is-Directory-Exists { return $false }

        $result = Is-Directory-Not-Exists -path 'TestDrive:\Nonexistent\Path'
        $result | Should -Be $true
    }

    It "Returns false for existing directory" {
        Mock Is-Directory-Exists { return $true }

        $result = Is-Directory-Not-Exists -path 'C:\Directory\Exists'
        $result | Should -Be $false
    }
}

Describe "Is-File-Exists" {
    Context "When checking file existence" {
        It "Returns true for an existing file" {
            $filePath = 'TestDrive:\existing_file_exists.txt'
            New-Item -Path $filePath -ItemType File -Force | Out-Null

            $result = Is-File-Exists -path $filePath
            $result | Should -Be $true

            Remove-Item -Path $filePath -Force
        }

        It "Returns false for non-existent file" {
            $result = Is-File-Exists -path 'TestDrive:\Nonexistent\file.txt'
            $result | Should -Be $false
        }

        It "Returns false for empty path" {
            $result = Is-File-Exists -path ''
            $result | Should -Be $false
        }

        It "Returns false for whitespace path" {
            $result = Is-File-Exists -path '   '
            $result | Should -Be $false
        }

        It "Handles exceptions gracefully" {
            Mock Test-Path { throw 'Error' }

            $result = Is-File-Exists -path 'TestDrive:\Nonexistent\file.txt'
            $result | Should -Be $false
        }
    }
}

Describe "Is-File-Not-Exists" {
    It "Returns true for non-existent file" {
        Mock Is-File-Exists { return $false }

        $result = Is-File-Not-Exists -path 'TestDrive:\Nonexistent\file.txt'
        $result | Should -Be $true
    }

    It "Returns false for existing file" {
        Mock Is-File-Exists { return $true }

        $result = Is-File-Not-Exists -path 'C:\File\Exists.txt'
        $result | Should -Be $false
    }
}

Describe "Make-Directory" {
    Context "When creating directories" {
        It "Creates a new directory successfully" {
            $newDir = 'TestDrive:\new_dir'
            $result = Make-Directory -path $newDir
            $result | Should -Be 0
            Test-Path $newDir | Should -Be $true
        }

        It "Returns 0 for existing directory" {
            $result = Make-Directory -path $STORAGE_PATH
            $result | Should -Be 0
        }

        It "Returns -1 for empty path" {
            $result = Make-Directory -path ''
            $result | Should -Be -1
        }

        It "Returns -1 when exception is thrown" {
            Mock Is-Directory-Not-Exists { return $true }
            Mock New-Item { throw 'Error' }
            $result = Make-Directory -path 'TestDrive:\new_dir'
            $result | Should -Be -1
        }
    }
}

Describe "Make-Symbolic-Link" {
    Context "When creating symbolic links" {
        It "Creates a symbolic link successfully when running as admin" {
            # Mock Is-Admin to return true
            Mock Is-Admin { return $true }

            # Mock New-Item to simulate successful symbolic link creation
            Mock New-Item {
                param ($ItemType, $Path, $Target)
                if ($ItemType -eq 'SymbolicLink') {
                    # Create a dummy file to simulate the link
                    New-Item -Path $Path -ItemType File -Force | Out-Null
                    return @{ FullName = $Path }
                }
            } -ParameterFilter { $ItemType -eq 'SymbolicLink' }

            $linkPath = 'TestDrive:\test_link'
            $targetPath = "$STORAGE_PATH\php\8.1"

            $result = Make-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be 0
            $result.message | Should -Match 'Created symbolic link'
            $result.color | Should -Be 'DarkGreen'

            # Verify New-Item was called with correct parameters
            Assert-MockCalled New-Item -ParameterFilter {
                $ItemType -eq 'SymbolicLink' -and
                $Path -eq $linkPath -and
                $Target -eq $targetPath
            }
        }

        It "Returns -1 if fails to create symbolic link" {
            Mock Is-Not-Admin { return $true }
            Mock Run-Ps-Command { return -1 }
            $linkPath = 'TestDrive:\test_link_fail'
            $targetPath = "$STORAGE_PATH\php\8.1"
            $result = Make-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be -1
            $result.message | Should -Be "Failed to make symbolic link '$linkPath' -> '$targetPath'"
            $result.color | Should -Be 'DarkYellow'
        }

        It "Creates a symbolic link successfully using elevated command" {
            Mock Is-Not-Admin { return $true }
            Mock Run-Ps-Command { return 0 }

            $linkPath = 'TestDrive:\test_link_2'
            $targetPath = "$STORAGE_PATH\php\8.1"

            $result = Make-Symbolic-Link -link $linkPath -target $targetPath

            $result.code | Should -Be 0
            $result.message | Should -Match 'Created symbolic link'
            $result.color | Should -Be 'DarkGreen'

            Assert-MockCalled Run-Ps-Command -ParameterFilter {
                $command -like '*New-Item -ItemType SymbolicLink*' -and
                $command -like "*$linkPath*" -and
                $command -like "*$targetPath*"
            }
        }

        It "Returns -1 if target directory does not exist" {
            $result = Make-Symbolic-Link -link 'TestDrive:\link' -target 'TestDrive:\Nonexistent\Target'
            $result.code | Should -Be -1
            $result.message | Should -Match "Target directory 'TestDrive:\\Nonexistent\\Target' does not exist!"
            $result.color | Should -Be 'DarkYellow'
        }

        It "Returns -1 if link already exists and is not a symbolic link" {
            # Create a regular file to simulate existing non-link
            $existingPath = 'TestDrive:\existing_file'
            New-Item -Path $existingPath -ItemType File -Force | Out-Null

            $result = Make-Symbolic-Link -link $existingPath -target "$STORAGE_PATH\php\8.1"
            $result.code | Should -Be -1
            $result.message | Should -Be "Link '$existingPath' is not a symbolic link!"
            $result.color | Should -Be 'DarkYellow'

            # Cleanup
            Remove-Item -Path $existingPath -Force
        }

        It "Handles exceptions gracefully" {
            Mock Is-Directory-Exists { throw 'Simulated exception' }
            $result = Make-Symbolic-Link -link 'TestDrive:\link' -target 'TestDrive:\target'
            $result.code | Should -Be -1
        }

        It "Returns -1 for empty link path" {
            $result = Make-Symbolic-Link -link '' -target 'TestDrive:\target'
            $result.code | Should -Be -1
        }

        It "Returns -1 for empty target path" {
            $result = Make-Symbolic-Link -link 'TestDrive:\link' -target ''
            $result.code | Should -Be -1
        }
    }

    Context "When link directory does not exist" {
        It "Creates a symbolic link successfully" {
            $linkPath = 'TestDrive:\test_parent\test_link'
            $targetPath = "$STORAGE_PATH\php\8.1"
            $parent = Split-Path -Path $linkPath

            Mock Is-Directory-Not-Exists -ParameterFilter { $path -eq $targetPath } -MockWith { return $false }
            Mock Is-Directory-Not-Exists -ParameterFilter { $path -eq $parent } -MockWith { return $true }
            Mock Is-Not-Admin { return $false }
            Mock Make-Directory -MockWith { return 0 }

            $result = Make-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be 0
        }

        It "Returns -1 when symbolic link parent directory fails to create" {
            Mock Is-Directory-Not-Exists -ParameterFilter { $path -eq 'TestDrive:\test_parent' } -MockWith { return $true }
            Mock Make-Directory -MockWith { return -1 }
            $linkPath = 'TestDrive:\test_parent\test_link'
            $targetPath = "$STORAGE_PATH\php\8.1"
            $result = Make-Symbolic-Link -link $linkPath -target $targetPath
            $result.code | Should -Be -1
        }
    }
}

Describe "Extract-Zip Tests" {
    BeforeEach {
        Mock Extract-Zip-Core { }
        Mock Remove-Item { }
        Mock Write-Host { }
        Mock Log-Data { }
    }

    It "Should extract zip without errors" {
        # This is a basic test since we're mocking the zip extraction
        { Extract-Zip -zipPath 'test.zip' -extractPath 'testdir' } | Should -Not -Throw
        Assert-MockCalled Extract-Zip-Core -Times 1
    }

    It "Should delete zip after extraction" {
        { Extract-Zip -zipPath 'test.zip' -extractPath 'testdir' -deleteZipAfter $true } | Should -Not -Throw
        Assert-MockCalled Remove-Item -Times 1 -ParameterFilter { $Path -eq 'test.zip' }
    }

    It "Should not delete zip if deleteZipAfter is false" {
        { Extract-Zip -zipPath 'test.zip' -extractPath 'testdir' -deleteZipAfter $false } | Should -Not -Throw
        Assert-MockCalled Remove-Item -Times 0
    }

    It "Should call Log-Data on extraction failure" {
        Mock Extract-Zip-Core { throw "Extraction failed" }
        { Extract-Zip -zipPath 'bad.zip' -extractPath 'testdir' } | Should -Not -Throw
        Assert-MockCalled Log-Data -Times 1
    }
}
