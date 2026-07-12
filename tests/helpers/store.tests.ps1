
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\store-drive"
    $script:CACHE_PATH = $PVMConfig.paths.cache = "$TEST_DRIVE\cache"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $script:CACHE_PATH -Force | Out-Null
    Mock Write-Host {}
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-Data-From-Cache" {
    It "Returns data from cache file" {
        Mock Is-File-Not-Exists { return $false }
        Mock Get-Content { return @'
            {
                'Releases': [
                    '/downloads/releases/php-7.4.33-Win32-vc15-x64.zip',
                    '/downloads/releases/php-8.0.30-Win32-vs16-x64.zip',
                    '/downloads/releases/php-8.4.12-Win32-vs17-x64.zip'
                ],
                'Archives': [
                    '/downloads/releases/archives/php-5.5.0-Win32-VC11-x64.zip',
                    '/downloads/releases/archives/php-5.5.1-Win32-VC11-x64.zip'
                ]
            }
'@
        }
        $list = Get-Data-From-Cache -cacheFileName 'test.json'
        $list.Releases[0] | Should -Be '/downloads/releases/php-7.4.33-Win32-vc15-x64.zip'
        $list.Archives[0] | Should -Be '/downloads/releases/archives/php-5.5.0-Win32-VC11-x64.zip'
    }

    It "Returns empty list when cache file name is null or empty" {
        Mock Is-File-Not-Exists { return $false }
        $list = Get-Data-From-Cache -cacheFileName ''
        $list.Count | Should -Be 0

        $list = Get-Data-From-Cache -cacheFileName $null
        $list.Count | Should -Be 0
    }

    It "Returns empty list when cache file doesn't exist" {
        Mock Is-File-Not-Exists { return $true }

        $list = Get-Data-From-Cache -cacheFileName 'test.json'
        $list.Count | Should -Be 0
    }

    It "Returns empty list when cache file content returns null" {
        Mock Is-File-Not-Exists { return $false }
        Mock Get-Content { return $null }
        $list = Get-Data-From-Cache -cacheFileName 'test.json'
        $list.Count | Should -Be 0
    }

    It "Returns empty list when cache file is empty" {
        Mock Is-File-Not-Exists { return $false }
        Mock Get-Content { return '' }
        $list = Get-Data-From-Cache -cacheFileName 'test.json'
        $list.Count | Should -Be 0
    }

    It "Handles exceptions gracefully" {
        Mock Is-File-Not-Exists { return $false }
        Mock Get-Content { throw 'Simulated exception' }
        $list = Get-Data-From-Cache -cacheFileName 'test.json'
        $list.Count | Should -Be 0
    }
}

Describe "Can-Use-Cache" {
    BeforeAll {
        $script:CACHE_MAX_HOURS = $PVMConfig.env.CACHE_MAX_HOURS = 168

        New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null
    }

    Context "When cache file exists" {
        It "Returns true when cache file is within max age" {
            $cacheFileName = 'test_cache'
            $cacheFile = "$cacheFileName.json"

            # Create a cache file with recent timestamp
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'

            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }

        It "Returns false when cache file is older than max age" {
            $cacheFileName = 'old_cache'
            $cacheFile = "$cacheFileName.json"

            # Create a cache file with old timestamp (older than CACHE_MAX_HOURS)
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'

            # Set file modification time to be older than CACHE_MAX_HOURS (168 hours)
            $oldTime = (Get-Date).AddHours(-200)
            (Get-Item -Path "$CACHE_PATH\$cacheFile").LastWriteTime = $oldTime

            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $false
        }

        It "Returns false when cache file is exactly at max age boundary" {
            $cacheFileName = 'boundary_cache'
            $cacheFile = "$cacheFileName.json"

            # Create a cache file
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'

            # Set file modification time to be exactly at CACHE_MAX_HOURS
            $boundaryTime = (Get-Date).AddHours(-$CACHE_MAX_HOURS)
            (Get-Item -Path "$CACHE_PATH\$cacheFile").LastWriteTime = $boundaryTime

            $result = Can-Use-Cache -cacheFileName $cacheFileName
            # Since the function uses -lt (less than), equality should return false
            $result | Should -Be $false
        }
    }

    Context "When cache file does not exist" {
        It "Returns false when cache file does not exist" {
            $cacheFileName = 'nonexistent_cache'

            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $false
        }
    }

    Context "With edge cases" {
        It "Returns false for empty cache file name" {
            $result = Can-Use-Cache -cacheFileName ''
            $result | Should -Be $false
        }

        It "Returns false for null cache file name" {
            $result = Can-Use-Cache -cacheFileName $null
            $result | Should -Be $false
        }

        It "Handles exceptions gracefully" {
            Mock Is-File-Exists { return $true }
            Mock New-TimeSpan { throw 'Error' }
            { Can-Use-Cache -cacheFileName 'test' } | Should -Not -Throw
            $result = Can-Use-Cache -cacheFileName 'test'
            $result | Should -Be $false
        }
    }

    Context "With special file names" {
        It "Works with file names containing special characters" {
            $cacheFileName = 'cache-with_special.chars'
            $cacheFile = "$cacheFileName.json"

            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'

            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }

        It "Works with file names containing numbers" {
            $cacheFileName = 'cache123available_versions456'
            $cacheFile = "$cacheFileName.json"

            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-Content -Path "$CACHE_PATH\$cacheFile" -Value '{"test": "data"}'

            $result = Can-Use-Cache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }
    }

    It "Handles exceptions gracefully" {
        Mock Get-Cache-FilePath { throw 'Error' }
        $result = Can-Use-Cache -cacheFileName 'test'
        $result | Should -Be $false
    }
}

Describe "Cache-Data" {
    It "Caches data successfully" {
        Mock ConvertTo-Json { return '{"Releases":["php-8.4.12.zip"],"Archives":["php-5.5.0.zip"]}' }
        Mock Make-Directory { return 0 }
        Mock Set-Content { }
        $code = Cache-Data -cacheFileName 'test' -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be 0
    }

    It "Fails to creade cache directory" {
        Mock ConvertTo-Json { return '{"Releases":["php-8.4.12.zip"],"Archives":["php-5.5.0.zip"]}' }
        Mock Make-Directory { return -1 }
        Mock Set-Content { }
        $code = Cache-Data -cacheFileName 'test' -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be -1
    }

    It "Handles exceptions gracefully" {
        Mock ConvertTo-Json { throw 'Simulated exception' }
        $code = Cache-Data -cacheFileName 'test' -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be -1
    }
}

Describe "Get-OrUpdateCache" {
    It "Reads from cache first" {
        function Example { return @{} }
        Mock Example { return @{} }
        Mock Can-Use-Cache { return $true }
        Mock Cache-Data { return 0 }
        Mock Get-Data-From-Cache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }

        $null = Get-OrUpdateCache -cacheFileName 'file.json' -compute {
            Example
        }

        Should -Invoke Get-Data-From-Cache -Exactly 1
        Should -Invoke Example -Exactly 0
        Should -Invoke Cache-Data -Exactly 0
    }

    It "Runs the passed command when can't read from cache" {
        function Example { return @{} }
        Mock Example {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        Mock Cache-Data { return 0 }
        Mock Can-Use-Cache { return $false }

        $null = Get-OrUpdateCache -cacheFileName 'file.json' -compute {
            Example
        }

        Should -Invoke Example -Exactly 1
        Should -Invoke Cache-Data -Exactly 1
    }
}
