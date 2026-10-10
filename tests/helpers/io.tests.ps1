
BeforeAll {
    if (-not $Global:CurrentTestDrive) {
        $currentFileName = Split-Path -Path $PSCommandPath -Leaf
        $msg = "`nTest Drive is not set for '$currentFileName'"
        $line = "`n$('=' * $msg.Length)"
        $errorMessage = $line + $msg + $line
        throw " `n$errorMessage"
    }

    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:STORAGE_PATH = $Global:PVMConfig.paths.directories.storage

    $null = New-Item -ItemType Directory -Path "$script:STORAGE_PATH\php\8.1" -Force
    $null = New-Item -ItemType Directory -Path "$script:STORAGE_PATH\php\8.2" -Force

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

            Remove-Item -Path $filePath -Force -Recurse -ErrorAction SilentlyContinue
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
        $newFile = "$script:TEST_DRIVE\new_file.txt"

        $result = New-File -path $newFile

        $result | Should -Be 0
        Should -Invoke New-ItemWrapper -ParameterFilter {
            $type -eq 'File' -and $path -eq $newFile
        }
    }

    It "Returns 0 for existing file" {
        $existingFile = "$script:TEST_DRIVE\existing_file.txt"
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
        $newFile = "$script:TEST_DRIVE\new_file.txt"

        $result = New-File -path $newFile

        $result | Should -Be -1
    }

    It "Returns -1 when exception is thrown" {
        Mock Test-FileNotExists { return $true }
        Mock New-ItemWrapper { throw 'Error' }

        $result = New-File -path "$script:TEST_DRIVE\new_file.txt"

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

            $result = New-SymbolicLink -link $linkPath -target $targetPath -disallowOutsideRoot

            $result.code | Should -Be 0
            $result.message | Should -Match 'Created symbolic link'
            $result.color | Should -Be 'DarkGreen'
            Should -Invoke New-ItemWrapper -ParameterFilter {
                $type -eq 'SymbolicLink' -and
                $path -eq $linkPath -and
                $target -eq $targetPath -and
                $disallowOutsideRoot -eq $true
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
            Remove-Item -Path $existingPath -Force -Recurse -ErrorAction SilentlyContinue
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
                    Remove-Item -Path $testDir -Force -Recurse -ErrorAction SilentlyContinue
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
            'test content' | Set-Content -Path $testFile -Encoding UTF8

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
                Remove-Item -Path $testDir -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "Expand-Zip" {
    BeforeEach {
        Mock Expand-ZipCore { }
        Mock Remove-ItemWrapper { }
        Mock Add-LogEntry { return 0 }
    }

    It "Should extract zip without errors" {
        $result = Expand-Zip -zipPath 'test.zip' -extractPath 'testdir'

        $result | Should -Be 0
        Should -Invoke Expand-ZipCore -Times 1
    }

    It "Should delete zip after extraction" {
        $result = Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' -deleteZipAfter $true

        $result | Should -Be 0
        Should -Invoke Remove-ItemWrapper -Times 1 -ParameterFilter { $path -eq 'test.zip' }
    }

    It "Should not delete zip if deleteZipAfter is false" {
        $result = Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' -deleteZipAfter $false

        $result | Should -Be 0
        Should -Invoke Remove-ItemWrapper -Times 0
    }

    It "Validates path when disallowOutsideRoot is passed" {
        Mock Test-PathInvalidOrNotUnderProjectRoot { return $true }
        Mock Add-LogEntry { return 0 }

        $result = Expand-Zip -zipPath 'test.zip' -extractPath 'testdir' -disallowOutsideRoot

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
    }

    It "Should call Add-LogEntry on extraction failure" {
        Mock Expand-ZipCore { throw "Extraction failed" }

        $result = Expand-Zip -zipPath 'bad.zip' -extractPath 'testdir'

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
    }
}

Describe "Get-FreeDiskSpaceBytes" {
    It "Returns available free space for an existing path" {
        $result = Get-FreeDiskSpaceBytes -path $script:STORAGE_PATH

        $result | Should -BeGreaterThan 0
    }

    It "Returns -1 for an empty path" {
        $result = Get-FreeDiskSpaceBytes -path ''

        $result | Should -Be -1
    }

    It "Returns -1 when the path has no drive root" {
        $result = Get-FreeDiskSpaceBytes -path 'relative\path'

        $result | Should -Be -1
    }
}

Describe "Test-FreeDiskSpaceSufficient" {
    It "Returns true when available space is greater than the minimum" {
        Mock Get-FreeDiskSpaceBytes { return ([int64]200MB) }

        $result = Test-FreeDiskSpaceSufficient -path 'C:\path' -minimumMegabytes 100

        $result | Should -BeTrue
    }

    It "Returns true when available space equals the minimum" {
        Mock Get-FreeDiskSpaceBytes { return ([int64]100MB) }

        $result = Test-FreeDiskSpaceSufficient -path 'C:\path' -minimumMegabytes 100

        $result | Should -BeTrue
    }

    It "Returns false when available space is below the minimum" {
        Mock Get-FreeDiskSpaceBytes { return ([int64]99MB) }

        $result = Test-FreeDiskSpaceSufficient -path 'C:\path' -minimumMegabytes 100

        $result | Should -BeFalse
    }

    It "Returns false when free space cannot be determined" {
        Mock Get-FreeDiskSpaceBytes { return -1 }

        $result = Test-FreeDiskSpaceSufficient -path 'C:\path' -minimumMegabytes 100

        $result | Should -BeFalse
    }

    It "Handles exception gracefully" {
        Mock Get-FreeDiskSpaceBytes { throw 'Error' }

        $result = Test-FreeDiskSpaceSufficient -path 'C:\path' -minimumMegabytes 100

        $result | Should -BeFalse
    }
}

Describe "Test-FreeDiskSpaceInsufficient" {
    It "Returns true when available space is below the minimum" {
        Mock Test-FreeDiskSpaceSufficient { return $false }

        $result = Test-FreeDiskSpaceInsufficient -path 'C:\path' -minimumMegabytes 100

        $result | Should -BeTrue
    }

    It "Returns false when available space is sufficient" {
        Mock Test-FreeDiskSpaceSufficient { return $true }

        $result = Test-FreeDiskSpaceInsufficient -path 'C:\path' -minimumMegabytes 100

        $result | Should -BeFalse
    }
}

Describe "Test-DownloadPrerequisites" {
    It "Returns error message when disk space is insufficient" {
        Mock Test-FreeDiskSpaceInsufficient { return $true }

        $result = Test-DownloadPrerequisites -uri 'https://example.com/file.zip' -minimumFreeSpaceMB 100

        $result.message | Should -BeLike '*Insufficient disk space for installation. At least 100 MB is required*'
    }

    It "Returns error message when remote file size cannot be determined" {
        Mock Test-FreeDiskSpaceInsufficient { return $false }
        Mock Get-RemoteFileSize { return ([int64]0) }

        $result = Test-DownloadPrerequisites -uri 'https://example.com/file.zip' -minimumFreeSpaceMB 100

        $result.message | Should -BeLike '*Failed to get remote file size or invalid size. Cannot proceed with download*'
    }

    It "Returns error message when remote file size exceeds available disk space" {
        Mock Test-FreeDiskSpaceInsufficient { return $false }
        Mock Get-RemoteFileSize { return ([int64]200MB) }
        Mock Convert-BytesToMegabytes { return 200 }
        Mock Get-FreeDiskSpaceBytes { return [int64]100MB }

        $result = Test-DownloadPrerequisites -uri 'https://example.com/file.zip' -minimumFreeSpaceMB 100

        $result.message | Should -BeLike 'Insufficient disk space for download. Required: 200 MB'
        $result.temporaryDirectory | Should -BeNullOrEmpty
    }

    It "Returns error message when temporary directory cannot be created" {
        Mock Test-FreeDiskSpaceInsufficient { return $false }
        Mock Get-RemoteFileSize { return ([int64]200MB) }
        Mock Convert-BytesToMegabytes { return 200 }
        Mock Get-TemporaryDirectory { return "$script:TEST_DRIVE\temp" }
        Mock New-Directory { return -1 }

        $result = Test-DownloadPrerequisites -uri 'https://example.com/file.zip' -minimumFreeSpaceMB 100

        $result.message | Should -BeLike "*Failed to create temporary directory '$script:TEST_DRIVE\temp'*"
        $result.temporaryDirectory | Should -BeNullOrEmpty
    }

    It "Returns success when all prerequisites are met" {
        Mock Test-FreeDiskSpaceInsufficient { return $false }
        Mock Get-RemoteFileSize { return ([int64]200MB) }
        Mock Convert-BytesToMegabytes { return 200 }
        Mock Get-TemporaryDirectory { return "$script:TEST_DRIVE\temp" }
        Mock New-Directory { return 0 }

        $result = Test-DownloadPrerequisites -uri 'https://example.com/file.zip' -minimumFreeSpaceMB 100

        $result.temporaryDirectory | Should -Be "$script:TEST_DRIVE\temp"
        $result.sizeMB | Should -Be 200
    }
}

Describe "Get-RemoteFile" {
    BeforeEach {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
    }

    It "Returns destination path for valid URI and destination" {
        $destinationPath = "$script:TEST_DRIVE\file.zip"
        Mock Invoke-WebRequestWrapper { return $destinationPath }

        $result = Get-RemoteFile -uri 'https://example.com/file.zip' -destinationPath $destinationPath

        $result | Should -Be $destinationPath
    }

    It "Returns null when exception occurs during download" {
        $destinationPath = "$script:TEST_DRIVE\file.zip"
        Mock Invoke-WebRequestWrapper { throw 'Network error' }

        $result = Get-RemoteFile -uri 'https://example.com/file.zip' -destinationPath $destinationPath

        $result | Should -Be $null
    }
}

Describe "Get-RemoteFileSize" {
    BeforeEach {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
    }

    It "Returns file size for valid URI" {
        Mock Invoke-WebRequestWrapper {
            return @{
                Headers = @{ 'Content-Length' = @('1024') }
            }
        }

        $result = Get-RemoteFileSize -uri 'https://example.com/file.zip'

        $result | Should -Be 1024
    }

    It "Returns -1 for empty URI" {
        $result = Get-RemoteFileSize -uri ''

        $result | Should -Be -1
    }

    It "Returns -1 for whitespace URI" {
        $result = Get-RemoteFileSize -uri '   '

        $result | Should -Be -1
    }

    It "Returns -1 when response is null" {
        Mock Invoke-WebRequestWrapper { return $null }

        $result = Get-RemoteFileSize -uri 'https://example.com/file.zip'

        $result | Should -Be -1
    }

    It "Returns -1 when headers are null" {
        Mock Invoke-WebRequestWrapper { return @{ Headers = $null } }

        $result = Get-RemoteFileSize -uri 'https://example.com/file.zip'

        $result | Should -Be -1
    }

    It "Returns -1 when Content-Length is missing" {
        Mock Invoke-WebRequestWrapper {
            return @{ Headers = @{} }
        }

        $result = Get-RemoteFileSize -uri 'https://example.com/file.zip'

        $result | Should -Be -1
    }

    It "Returns -1 when Content-Length is null or whitespaced" {
        Mock Invoke-WebRequestWrapper {
            return @{ Headers = @{ 'Content-Length' = @('') } }
        }

        $result = Get-RemoteFileSize -uri 'https://example.com/file.zip'

        $result | Should -Be -1
    }

    It "Handles exceptions gracefully" {
        Mock Invoke-WebRequestWrapper { throw 'Network error' }

        $result = Get-RemoteFileSize -uri 'https://example.com/file.zip'

        $result | Should -Be -1
    }
}

Describe "Test-RemoteFileDiskSpaceSufficient" {
    It "Returns true when remote file fits in available space" {
        Mock Get-RemoteFileSize { return ([int64]100MB) }
        Mock Get-FreeDiskSpaceBytes { return ([int64]200MB) }

        $result = Test-RemoteFileDiskSpaceSufficient -uri 'https://example.com/file.zip' -downloadPath 'C:\Downloads'

        $result | Should -BeTrue
    }

    It "Returns true when remote file size equals available space" {
        Mock Get-RemoteFileSize { return ([int64]100MB) }
        Mock Get-FreeDiskSpaceBytes { return ([int64]100MB) }

        $result = Test-RemoteFileDiskSpaceSufficient -uri 'https://example.com/file.zip' -downloadPath 'C:\Downloads'

        $result | Should -BeTrue
    }

    It "Returns false when remote file size exceeds available space" {
        Mock Get-RemoteFileSize { return ([int64]200MB) }
        Mock Get-FreeDiskSpaceBytes { return ([int64]100MB) }

        $result = Test-RemoteFileDiskSpaceSufficient -uri 'https://example.com/file.zip' -downloadPath 'C:\Downloads'

        $result | Should -BeFalse
    }

    It "Returns false when remote file size is invalid" {
        Mock Get-RemoteFileSize { return -1 }

        $result = Test-RemoteFileDiskSpaceSufficient -uri 'https://example.com/file.zip' -downloadPath 'C:\Downloads'

        $result | Should -BeFalse
    }

    It "Returns false when available space is invalid" {
        Mock Get-RemoteFileSize { return ([int64]100MB) }
        Mock Get-FreeDiskSpaceBytes { return -1 }

        $result = Test-RemoteFileDiskSpaceSufficient -uri 'https://example.com/file.zip' -downloadPath 'C:\Downloads'

        $result | Should -BeFalse
    }

    It "Handles exceptions gracefully" {
        Mock Get-RemoteFileSize { throw 'Error' }

        $result = Test-RemoteFileDiskSpaceSufficient -uri 'https://example.com/file.zip' -downloadPath 'C:\Downloads'

        $result | Should -BeFalse
    }
}

Describe "Test-RemoteFileDiskSpaceInsufficient" {
    It "Returns true when remote file exceeds available space" {
        Mock Test-RemoteFileDiskSpaceSufficient { return $false }

        $result = Test-RemoteFileDiskSpaceInsufficient -uri 'https://example.com/file.zip' -downloadPath 'C:\Downloads'

        $result | Should -BeTrue
    }

    It "Returns false when remote file fits in available space" {
        Mock Test-RemoteFileDiskSpaceSufficient { return $true }

        $result = Test-RemoteFileDiskSpaceInsufficient -uri 'https://example.com/file.zip' -downloadPath 'C:\Downloads'

        $result | Should -BeFalse
    }
}

Describe "Test-ValidDrivePath" {
    Context "When validating drive paths" {
        It "Returns true for valid drive path with backslash" {
            $result = Test-ValidDrivePath -path 'C:\Test'
            $result | Should -Be $true
        }

        It "Returns true for valid drive path with double backslash" {
            $result = Test-ValidDrivePath -path 'D:\\Test'
            $result | Should -Be $true
        }

        It "Returns false for null path" {
            $result = Test-ValidDrivePath -path $null
            $result | Should -Be $false
        }

        It "Returns false for empty path" {
            $result = Test-ValidDrivePath -path ''
            $result | Should -Be $false
        }

        It "Returns false for whitespace path" {
            $result = Test-ValidDrivePath -path '   '
            $result | Should -Be $false
        }

        It "Returns false for path without drive letter" {
            $result = Test-ValidDrivePath -path '\Test\Path'
            $result | Should -Be $false
        }

        It "Returns false for path with invalid characters" {
            $result = Test-ValidDrivePath -path 'C:\Test|Invalid'
            $result | Should -Be $false
        }

        It "Returns false for relative path" {
            $result = Test-ValidDrivePath -path 'relative\path'
            $result | Should -Be $false
        }

        It "Returns false for UNC path" {
            $result = Test-ValidDrivePath -path '\\server\share'
            $result | Should -Be $false
        }

        It "Returns false for non-existent drive when drive check is enabled" {
            $result = Test-ValidDrivePath -path 'Z:\Test'
            $result | Should -Be $false
        }
    }
}

Describe "Test-InvalidDrivePath" {
    It "Return true for invalid path" {
        Mock Test-ValidDrivePath { return $false }

        $result = Test-InvalidDrivePath -path 'some-path'

        $result | Should -BeTrue
    }

    It "Return false for valid path" {
        Mock Test-ValidDrivePath { return $true }

        $result = Test-InvalidDrivePath -path 'C:\some-path'

        $result | Should -BeFalse
    }
}
Describe "Test-PathUnderRoot" {
    Context "When path is under root" {
        It "Returns true for direct child" {
            $result = Test-PathUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'
            $result | Should -BeTrue
        }

        It "Returns true for nested child" {
            $result = Test-PathUnderRoot -path 'C:\Root\A\B\C' -rootPath 'C:\Root'
            $result | Should -BeTrue
        }

        It "Is case-insensitive" {
            $result = Test-PathUnderRoot -path 'c:\root\child' -rootPath 'C:\ROOT'
            $result | Should -BeTrue
        }

        It "Handles trailing backslashes on path and root" {
            $result = Test-PathUnderRoot -path 'C:\Root\Child\' -rootPath 'C:\Root\'
            $result | Should -BeTrue
        }

        It "Trims whitespace from path and root" {
            $result = Test-PathUnderRoot -path '  C:\Root\Child  ' -rootPath '  C:\Root  '
            $result | Should -BeTrue
        }

        It "Normalizes parent traversal that stays under root" {
            $result = Test-PathUnderRoot -path 'C:\Root\A\..\B' -rootPath 'C:\Root'
            $result | Should -BeTrue
        }
    }

    Context "When path is not under root" {
        It "Returns false when path equals root" {
            $result = Test-PathUnderRoot -path 'C:\Root' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false when path equals root with trailing backslash" {
            $result = Test-PathUnderRoot -path 'C:\Root\' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false for sibling sharing the root prefix" {
            $result = Test-PathUnderRoot -path 'C:\RootOther\Child' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false for unrelated path" {
            $result = Test-PathUnderRoot -path 'C:\Other\Child' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false for parent of root" {
            $result = Test-PathUnderRoot -path 'C:\' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false for different drive" {
            $result = Test-PathUnderRoot -path 'D:\Root\Child' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false for parent traversal escaping root" {
            $result = Test-PathUnderRoot -path 'C:\Root\..\Other' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }
    }

    Context "When inputs are invalid" {
        It "Returns false for null path" {
            $result = Test-PathUnderRoot -path $null -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false for empty path" {
            $result = Test-PathUnderRoot -path '' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false for whitespace path" {
            $result = Test-PathUnderRoot -path '   ' -rootPath 'C:\Root'
            $result | Should -BeFalse
        }

        It "Returns false for null root" {
            $result = Test-PathUnderRoot -path 'C:\Root\Child' -rootPath $null
            $result | Should -BeFalse
        }

        It "Returns false for empty root" {
            $result = Test-PathUnderRoot -path 'C:\Root\Child' -rootPath ''
            $result | Should -BeFalse
        }

        It "Returns false for whitespace root" {
            $result = Test-PathUnderRoot -path 'C:\Root\Child' -rootPath '   '
            $result | Should -BeFalse
        }
    }
}

Describe "Test-PathNotUnderRoot" {
    It "Returns true when path is not under root" {
        Mock Test-PathUnderRoot { return $false }

        $result = Test-PathNotUnderRoot -path 'C:\Other' -rootPath 'C:\Root'

        $result | Should -BeTrue
    }

    It "Returns false when path is under root" {
        Mock Test-PathUnderRoot { return $true }

        $result = Test-PathNotUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        $result | Should -BeFalse
    }

    It "Passes path and root to Test-PathUnderRoot" {
        Mock Test-PathUnderRoot { return $true }

        $null = Test-PathNotUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        Should -Invoke Test-PathUnderRoot -Times 1 -ParameterFilter {
            $path -eq 'C:\Root\Child' -and $rootPath -eq 'C:\Root'
        }
    }
}

Describe "Test-PathValidAndUnderRoot" {
    It "Returns true when path is valid and under root" {
        Mock Test-ValidDrivePath { return $true }
        Mock Test-PathUnderRoot { return $true }

        $result = Test-PathValidAndUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        $result | Should -BeTrue
    }

    It "Returns false when path is invalid" {
        Mock Test-ValidDrivePath { return $false }
        Mock Test-PathUnderRoot { return $true }

        $result = Test-PathValidAndUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        $result | Should -BeFalse
    }

    It "Returns false when path is not under root" {
        Mock Test-ValidDrivePath { return $true }
        Mock Test-PathUnderRoot { return $false }

        $result = Test-PathValidAndUnderRoot -path 'C:\Other' -rootPath 'C:\Root'

        $result | Should -BeFalse
    }

    It "Does not check root containment when path is invalid" {
        Mock Test-ValidDrivePath { return $false }
        Mock Test-PathUnderRoot { return $true }

        $null = Test-PathValidAndUnderRoot -path 'bad' -rootPath 'C:\Root'

        Should -Invoke Test-PathUnderRoot -Times 0
    }

    It "Passes path and root to the underlying checks" {
        Mock Test-ValidDrivePath { return $true }
        Mock Test-PathUnderRoot { return $true }

        $null = Test-PathValidAndUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        Should -Invoke Test-ValidDrivePath -Times 1 -ParameterFilter { $path -eq 'C:\Root\Child' }
        Should -Invoke Test-PathUnderRoot -Times 1 -ParameterFilter {
            $path -eq 'C:\Root\Child' -and $rootPath -eq 'C:\Root'
        }
    }

    It "Returns false and logs when an exception occurs" {
        Mock Test-ValidDrivePath { throw 'Error' }

        $result = Test-PathValidAndUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        $result | Should -BeFalse
        Should -Invoke Add-LogEntry -Times 1
    }

    It "Returns false and logs when Test-PathUnderRoot throws" {
        Mock Test-ValidDrivePath { return $true }
        Mock Test-PathUnderRoot { throw 'Error' }

        $result = Test-PathValidAndUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        $result | Should -BeFalse
        Should -Invoke Add-LogEntry -Times 1
    }
}

Describe "Test-PathInvalidOrNotUnderRoot" {
    It "Returns true when path is invalid or not under root" {
        Mock Test-PathValidAndUnderRoot { return $false }

        $result = Test-PathInvalidOrNotUnderRoot -path 'C:\Other' -rootPath 'C:\Root'

        $result | Should -BeTrue
    }

    It "Returns false when path is valid and under root" {
        Mock Test-PathValidAndUnderRoot { return $true }

        $result = Test-PathInvalidOrNotUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        $result | Should -BeFalse
    }

    It "Passes path and root to Test-PathValidAndUnderRoot" {
        Mock Test-PathValidAndUnderRoot { return $true }

        $null = Test-PathInvalidOrNotUnderRoot -path 'C:\Root\Child' -rootPath 'C:\Root'

        Should -Invoke Test-PathValidAndUnderRoot -Times 1 -ParameterFilter {
            $path -eq 'C:\Root\Child' -and $rootPath -eq 'C:\Root'
        }
    }
}

Describe "Test-PathValidUnderProjectRoot" {
    BeforeEach {
        $script:ORIGINAL_PVM_CONFIG = $Global:PVMConfig
    }

    AfterEach {
        $Global:PVMConfig = $script:ORIGINAL_PVM_CONFIG
    }

    It "Returns false when PVMConfig is null" {
        $Global:PVMConfig = $null
        Mock Test-PathValidAndUnderRoot { return $true }

        $result = Test-PathValidUnderProjectRoot -path 'C:\Root\Child'

        $result | Should -BeFalse
        Should -Invoke Test-PathValidAndUnderRoot -Times 0
    }

    It "Returns false when rootPath is null" {
        $Global:PVMConfig = @{ rootPath = $null }
        Mock Test-PathValidAndUnderRoot { return $true }

        $result = Test-PathValidUnderProjectRoot -path 'C:\Root\Child'

        $result | Should -BeFalse
        Should -Invoke Test-PathValidAndUnderRoot -Times 0
    }

    It "Returns true when path is valid and under project root" {
        $Global:PVMConfig = @{ rootPath = 'C:\Root' }
        Mock Test-PathValidAndUnderRoot { return $true }

        $result = Test-PathValidUnderProjectRoot -path 'C:\Root\Child'

        $result | Should -BeTrue
    }

    It "Returns false when path is not valid or not under project root" {
        $Global:PVMConfig = @{ rootPath = 'C:\Root' }
        Mock Test-PathValidAndUnderRoot { return $false }

        $result = Test-PathValidUnderProjectRoot -path 'C:\Other'

        $result | Should -BeFalse
    }

    It "Passes path and project root to Test-PathValidAndUnderRoot" {
        $Global:PVMConfig = @{ rootPath = 'C:\Root' }
        Mock Test-PathValidAndUnderRoot { return $true }

        $null = Test-PathValidUnderProjectRoot -path 'C:\Root\Child'

        Should -Invoke Test-PathValidAndUnderRoot -Times 1 -ParameterFilter {
            $path -eq 'C:\Root\Child' -and $rootPath -eq 'C:\Root'
        }
    }
}

Describe "Test-PathInvalidOrNotUnderProjectRoot" {
    It "Returns true when path is not valid under project root" {
        Mock Test-PathValidUnderProjectRoot { return $false }

        $result = Test-PathInvalidOrNotUnderProjectRoot -path 'C:\Other'

        $result | Should -BeTrue
    }

    It "Returns false when path is valid under project root" {
        Mock Test-PathValidUnderProjectRoot { return $true }

        $result = Test-PathInvalidOrNotUnderProjectRoot -path 'C:\Root\Child'

        $result | Should -BeFalse
    }

    It "Passes path to Test-PathValidUnderProjectRoot" {
        Mock Test-PathValidUnderProjectRoot { return $true }

        $null = Test-PathInvalidOrNotUnderProjectRoot -path 'C:\Root\Child'

        Should -Invoke Test-PathValidUnderProjectRoot -Times 1 -ParameterFilter {
            $path -eq 'C:\Root\Child'
        }
    }
}

Describe "Get-TemporaryDirectory" {
    It "Returns null or empty for null root path" {
        $result = Get-TemporaryDirectory -root '  '

        $result | Should -BeNullOrEmpty
    }

    It "Returns null or empty for empty root path" {
        $result = Get-TemporaryDirectory -root ''

        $result | Should -BeNullOrEmpty
    }

    It "Returns null or empty for whitespace root path" {
        $result = Get-TemporaryDirectory -root '   '

        $result | Should -BeNullOrEmpty
    }

    It "Returns a valid temporary directory path for a valid root" {
        $rootPath = "$script:TEST_DRIVE\temp"
        New-Directory -path $rootPath | Out-Null

        $result = Get-TemporaryDirectory -root $rootPath

        $result | Should -Not -BeNullOrEmpty
        $result | Should -Match ('^' + [regex]::Escape($rootPath) + '\\temp_[0-9a-fA-F]{32}$')
    }
}

Describe "Get-SHA256HashFromFile" {
    It "Returns null for non-existent file" {
        $result = Get-SHA256HashFromFile -filePath 'C:\nonexistent\file.txt'

        $result | Should -BeNullOrEmpty
    }

    It "Returns null for null or empty file path" {
        $result = Get-SHA256HashFromFile -filePath ''

        $result | Should -BeNullOrEmpty
    }

    It "Returns correct SHA256 hash for a file" {
        $testFile = "$script:TEST_DRIVE\test-sha256.txt"
        $testContent = "test content"
        Set-Content -Path $testFile -Value $testContent -Encoding UTF8

        $result = Get-SHA256HashFromFile -filePath $testFile

        $result | Should -Not -BeNullOrEmpty
        $result.Length | Should -Be 64
        $result | Should -Match '^[a-f0-9]{64}$'
    }

    It "Returns lowercase hash" {
        $testFile = "$script:TEST_DRIVE\test-sha256-lower.txt"
        Set-Content -Path $testFile -Value "test" -Encoding UTF8

        $result = Get-SHA256HashFromFile -filePath $testFile

        $result | Should -Be $result.ToLower()
    }

    It "Handle exception gracefully" {
        Mock Test-FileNotExists { throw 'Error' }

        $result = Get-SHA256HashFromFile -filePath 'C:\nonexistent\file.txt'

        $result | Should -BeNullOrEmpty
        Should -Invoke Add-LogEntry -Times 1
    }
}

Describe "Get-SHA256HashesFromRemote" {
    BeforeEach {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
    }

    It "Returns empty hashtable for null or empty URL" {
        $result = Get-SHA256HashesFromRemote -url ''

        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It "Returns empty hashtable when response is null" {
        Mock Invoke-WebRequestWrapper { return $null }

        $result = Get-SHA256HashesFromRemote -url 'https://example.com/sha256sum.txt'

        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It "Parses SHA256 sum format correctly" {
        $mockContent = @(
            'a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890 *php-8.2.0-Win32-vs16-x64.zip'
            'f6e5d4c3b2a19876fedcba9876543210fedcba9876543210fedcba9876543210 *php-8.2.0-nts-Win32-vs16-x64.zip'
        ) -join "`n"
        $mockResponse = [PSCustomObject]@{ Content = $mockContent }
        Mock Invoke-WebRequestWrapper { return $mockResponse }

        $result = Get-SHA256HashesFromRemote -url 'https://example.com/sha256sum.txt'

        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 2
    }

    It "Handles multiple lines with empty lines" {
        $mockContent = @(
            '6df2a5f59f10f08022bede47a26d61c3c16756c54d86aad58503dc8a9d3c25ad *php-8.2.34-Win32-vs16-x64.zip'
            ''
            'e37e7daf7ffe68df06bfccecf2950a6afc1a827e2b74cfaaa36ebe1574344cbd *php-8.2.34-Win32-vs16-x86.zip'
        ) -join "`n"
        $mockResponse = [PSCustomObject]@{ Content = $mockContent }
        Mock Invoke-WebRequestWrapper { return $mockResponse }

        $result = Get-SHA256HashesFromRemote -url 'https://example.com/sha256sum.txt'

        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 2
    }

    It "Converts hash to lowercase" {
        $mockContent = "A1B2C3D4E5F67890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890 *test.zip"
        $mockResponse = [PSCustomObject]@{ Content = $mockContent }
        Mock Invoke-WebRequestWrapper { return $mockResponse }

        $result = Get-SHA256HashesFromRemote -url 'https://example.com/sha256sum.txt'

        $result['test.zip'] | Should -Be $result['test.zip'].ToLower()
    }

    It "Handle exception gracefully" {
        Mock Show-SpinnerWhileJob { throw 'Error' }

        $result = Get-SHA256HashesFromRemote -url 'https://example.com/sha256sum.txt'

        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
        Should -Invoke Add-LogEntry -Times 1
    }
}

Describe "Test-SHA256HashValid" {
    It "Returns false for non-existent file" {
        Mock Test-FileNotExists { return $true }

        $result = Test-SHA256HashValid -filePath 'C:\nonexistent\file.txt' -expectedHash 'a1b2c3d4'

        $result | Should -Be $false
    }

    It "Returns false for null or empty expected hash" {
        Mock Test-FileNotExists { return $false }

        $result = Test-SHA256HashValid -filePath 'C:\some\file.txt' -expectedHash ''

        $result | Should -Be $false
    }

    It "Returns true when hashes match" {
        Mock Test-FileNotExists { return $false }
        Mock Get-SHA256HashFromFile { return 'a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890' }

        $result = Test-SHA256HashValid -filePath 'C:\some\file.txt' -expectedHash 'a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890'

        $result | Should -Be $true
    }

    It "Returns false when hashes do not match" {
        Mock Test-FileNotExists { return $false }
        Mock Get-SHA256HashFromFile { return 'a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890' }

        $result = Test-SHA256HashValid -filePath 'C:\some\file.txt' -expectedHash 'f6e5d4c3b2a19876fedcba9876543210fedcba9876543210fedcba9876543210'

        $result | Should -Be $false
    }

    It "Performs case-insensitive comparison" {
        Mock Test-FileNotExists { return $false }
        Mock Get-SHA256HashFromFile { return 'a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890' }

        $result = Test-SHA256HashValid -filePath 'C:\some\file.txt' -expectedHash 'A1B2C3D4E5F67890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890'

        $result | Should -Be $true
    }

    It "Returns false when Get-SHA256HashFromFile returns null" {
        Mock Test-FileNotExists { return $false }
        Mock Get-SHA256HashFromFile { return $null }

        $result = Test-SHA256HashValid -filePath 'C:\some\file.txt' -expectedHash 'a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890'

        $result | Should -Be $false
    }

    It "Handles exception gracefully" {
        Mock Test-FileNotExists { return $false }
        Mock Get-SHA256HashFromFile { throw 'Error' }

        $result = Test-SHA256HashValid -filePath 'C:\some\file.txt' -expectedHash 'a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890'

        $result | Should -Be $false
        Should -Invoke Add-LogEntry -Times 1
    }
}
