
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\store-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)
    $script:CACHE_PATH = $PVMConfig.paths.cache

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null
    Mock Show-Error {}
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-DataFromCache" {
    It "Returns data from cache file" {
        Mock Test-FileNotExists { return $false }
        Mock Get-ContentWrapper { return @'
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
        $list = Get-DataFromCache -cacheFileName 'test.json'
        $list.Releases[0] | Should -Be '/downloads/releases/php-7.4.33-Win32-vc15-x64.zip'
        $list.Archives[0] | Should -Be '/downloads/releases/archives/php-5.5.0-Win32-VC11-x64.zip'
    }

    It "Returns empty list when cache file name is null or empty" {
        Mock Test-FileNotExists { return $false }
        $list = Get-DataFromCache -cacheFileName ''
        $list.Count | Should -Be 0

        $list = Get-DataFromCache -cacheFileName $null
        $list.Count | Should -Be 0
    }

    It "Returns empty list when cache file doesn't exist" {
        Mock Test-FileNotExists { return $true }

        $list = Get-DataFromCache -cacheFileName 'test.json'
        $list.Count | Should -Be 0
    }

    It "Returns empty list when cache file content returns null" {
        Mock Test-FileNotExists { return $false }
        Mock Get-ContentWrapper { return $null }
        $list = Get-DataFromCache -cacheFileName 'test.json'
        $list.Count | Should -Be 0
    }

    It "Returns empty list when cache file is empty" {
        Mock Test-FileNotExists { return $false }
        Mock Get-ContentWrapper { return '' }
        $list = Get-DataFromCache -cacheFileName 'test.json'
        $list.Count | Should -Be 0
    }

    It "Handles exceptions gracefully" {
        Mock Test-FileNotExists { return $false }
        Mock Get-ContentWrapper { throw 'Simulated exception' }
        $list = Get-DataFromCache -cacheFileName 'test.json'
        $list.Count | Should -Be 0
    }
}

Describe "Test-CanUseCache" {
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
            Set-ContentWrapper -path "$CACHE_PATH\$cacheFile" -value '{"test": "data"}'

            $result = Test-CanUseCache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }

        It "Returns false when cache file is older than max age" {
            $cacheFileName = 'old_cache'
            $cacheFile = "$cacheFileName.json"

            # Create a cache file with old timestamp (older than CACHE_MAX_HOURS)
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-ContentWrapper -path "$CACHE_PATH\$cacheFile" -value '{"test": "data"}'

            # Set file modification time to be older than CACHE_MAX_HOURS (168 hours)
            $oldTime = (Get-Date).AddHours(-200)
            (Get-ItemWrapper -path "$CACHE_PATH\$cacheFile").LastWriteTime = $oldTime

            $result = Test-CanUseCache -cacheFileName $cacheFileName
            $result | Should -Be $false
        }

        It "Returns false when cache file is exactly at max age boundary" {
            $cacheFileName = 'boundary_cache'
            $cacheFile = "$cacheFileName.json"

            # Create a cache file
            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-ContentWrapper -path "$CACHE_PATH\$cacheFile" -value '{"test": "data"}'

            # Set file modification time to be exactly at CACHE_MAX_HOURS
            $boundaryTime = (Get-Date).AddHours(-$CACHE_MAX_HOURS)
            (Get-ItemWrapper -path "$CACHE_PATH\$cacheFile").LastWriteTime = $boundaryTime

            $result = Test-CanUseCache -cacheFileName $cacheFileName
            # Since the function uses -lt (less than), equality should return false
            $result | Should -Be $false
        }
    }

    Context "When cache file does not exist" {
        It "Returns false when cache file does not exist" {
            $cacheFileName = 'nonexistent_cache'

            $result = Test-CanUseCache -cacheFileName $cacheFileName
            $result | Should -Be $false
        }
    }

    Context "With edge cases" {
        It "Returns false for empty cache file name" {
            $result = Test-CanUseCache -cacheFileName ''
            $result | Should -Be $false
        }

        It "Returns false for null cache file name" {
            $result = Test-CanUseCache -cacheFileName $null
            $result | Should -Be $false
        }

        It "Handles exceptions gracefully" {
            Mock Test-FileExists { return $true }
            Mock New-TimeSpan { throw 'Error' }
            { Test-CanUseCache -cacheFileName 'test' } | Should -Not -Throw
            $result = Test-CanUseCache -cacheFileName 'test'
            $result | Should -Be $false
        }
    }

    Context "With special file names" {
        It "Works with file names containing special characters" {
            $cacheFileName = 'cache-with_special.chars'
            $cacheFile = "$cacheFileName.json"

            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-ContentWrapper -path "$CACHE_PATH\$cacheFile" -value '{"test": "data"}'

            $result = Test-CanUseCache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }

        It "Works with file names containing numbers" {
            $cacheFileName = 'cache123available_versions456'
            $cacheFile = "$cacheFileName.json"

            New-Item -Path "$CACHE_PATH\$cacheFile" -ItemType File -Force | Out-Null
            Set-ContentWrapper -path "$CACHE_PATH\$cacheFile" -value '{"test": "data"}'

            $result = Test-CanUseCache -cacheFileName $cacheFileName
            $result | Should -Be $true
        }
    }

    It "Handles exceptions gracefully" {
        Mock Get-CacheFilePath { throw 'Error' }
        $result = Test-CanUseCache -cacheFileName 'test'
        $result | Should -Be $false
    }
}

Describe "Save-CachedData" {
    It "Caches data successfully" {
        Mock ConvertTo-Json { return '{"Releases":["php-8.4.12.zip"],"Archives":["php-5.5.0.zip"]}' }
        Mock New-Directory { return 0 }
        Mock Set-ContentWrapper { }
        $code = Save-CachedData -cacheFileName 'test' -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be 0
    }

    It "Fails to creade cache directory" {
        Mock ConvertTo-Json { return '{"Releases":["php-8.4.12.zip"],"Archives":["php-5.5.0.zip"]}' }
        Mock New-Directory { return -1 }
        Mock Set-ContentWrapper { }
        $code = Save-CachedData -cacheFileName 'test' -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be -1
    }

    It "Handles null data gracefully" {
        $code = Save-CachedData -cacheFileName $null -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be -1
    }

    It "Handles empty cache file name gracefully" {
        $code = Save-CachedData -cacheFileName '' -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be -1
    }

    It "Handles whitespace cache file name gracefully" {
        $code = Save-CachedData -cacheFileName '   ' -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be -1
    }

    It "Handles null data gracefully" {
        $code = Save-CachedData -cacheFileName 'test' -data $null
        $code | Should -Be -1
    }

    It "Handles exceptions gracefully" {
        Mock ConvertTo-Json { throw 'Simulated exception' }
        $code = Save-CachedData -cacheFileName 'test' -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $code | Should -Be -1
    }
}

Describe "Test-HasData" {
    It "Returns false for null data" {
        $result = Test-HasData -data $null
        $result | Should -Be $false
    }

    It "Returns true for non-empty hashtable" {
        $result = Test-HasData -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $result | Should -Be $true
    }

    It "Returns false for empty hashtable" {
        $result = Test-HasData -data @{}
        $result | Should -Be $false
    }

    It "Returns true for non-empty array" {
        $result = Test-HasData -data @('php-8.4.12.zip', 'php-5.5.0.zip')
        $result | Should -Be $true
    }

    It "Returns false for empty array" {
        $result = Test-HasData -data @()
        $result | Should -Be $false
    }

    It "Returns true for non-empty pscustomobject" {
        $result = Test-HasData -data ([pscustomobject] @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')})
        $result | Should -Be $true
    }

    It "Returns false for empty pscustomobject" {
        $result = Test-HasData -data ([pscustomobject] @{})
        $result | Should -Be $false
    }
}

Describe "Test-HasNoData" {
    It "Returns true for null data" {
        Mock Test-HasData { return $false }

        $result = Test-HasNoData -data $null
        $result | Should -Be $true
    }

    It "Returns false for non-empty data" {
        Mock Test-HasData { return $true }

        $result = Test-HasNoData -data @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')}
        $result | Should -Be $false
    }

    It "Returns true for empty data" {
        Mock Test-HasData { return $false }

        $result = Test-HasNoData -data @{}
        $result | Should -Be $true
    }

    It "Returns false for non-empty array" {
        Mock Test-HasData { return $true }

        $result = Test-HasNoData -data @('php-8.4.12.zip', 'php-5.5.0.zip')
        $result | Should -Be $false
    }

    It "Returns true for empty array" {
        Mock Test-HasData { return $false }

        $result = Test-HasNoData -data @()
        $result | Should -Be $true
    }

    It "Returns false for non-empty pscustomobject" {
        Mock Test-HasData { return $true }

        $result = Test-HasNoData -data ([pscustomobject] @{'Releases' = @('php-8.4.12.zip'); 'Archives' = @('php-5.5.0.zip')})
        $result | Should -Be $false
    }

    It "Returns true for empty pscustomobject" {
        Mock Test-HasData { return $false }

        $result = Test-HasNoData -data ([pscustomobject] @{})
        $result | Should -Be $true
    }

    It "Throws when Test-HasData throws" {
        Mock Test-HasData { throw 'Error' }

        { Test-HasNoData -data @() } | Should -Throw 'Error'
    }
}

Describe "Get-OrUpdateCache" {
    BeforeAll {
        function Get-Example { return @{} }
    }

    It "Reads from cache first" {
        Mock Get-Example { return @{} }
        Mock Test-CanUseCache { return $true }
        Mock Save-CachedData { return 0 }
        Mock Get-DataFromCache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }

        $null = Get-OrUpdateCache -cacheFileName 'file.json' -compute {
            Get-Example
        }

        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-Example -Exactly 0
        Should -Invoke Save-CachedData -Exactly 0
    }

    It "Runs the passed command when can't read from cache" {
        Mock Get-Example {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        Mock Save-CachedData { return 0 }
        Mock Test-CanUseCache { return $false }

        $null = Get-OrUpdateCache -cacheFileName 'file.json' -compute {
            Get-Example
        }

        Should -Invoke Get-Example -Exactly 1
        Should -Invoke Save-CachedData -Exactly 1
    }

    It "Runs the passed command when cache is empty" {
        Mock Test-CanUseCache { return $true }
        Mock Get-DataFromCache { return $null }
        Mock Get-Example { return $null }

        $null = Get-OrUpdateCache -cacheFileName 'file.json' -compute {
            Get-Example
        }

        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-Example -Exactly 1
    }

    It "Does not run the passed command when cache has pscustomobject data" {
        Mock Test-CanUseCache { return $true }
        Mock Get-Example { return $null }
        Mock Get-DataFromCache {
            return [pscustomobject] @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }

        $null = Get-OrUpdateCache -cacheFileName 'file.json' -compute {
            Get-Example
        }

        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-Example -Exactly 0
    }

    It "Checks for data type 'array' before saving to cache" {
        Mock Get-Example {
            return @(
                @('php-8.1.0-Win32-x64.zip')
                @('php-8.2.0-Win32-x64.zip')
            )
        }
        Mock Save-CachedData { return 0 }
        Mock Test-CanUseCache { return $false }

        $null = Get-OrUpdateCache -cacheFileName 'file.json' -compute {
            Get-Example
        }

        Should -Invoke Get-Example -Exactly 1
        Should -Invoke Save-CachedData -Exactly 1
    }

    It "Checks for data type 'pscustomobject' before saving to cache" {
        Mock Get-Example {
            return [pscustomobject] @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        Mock Save-CachedData { return 0 }
        Mock Test-CanUseCache { return $false }

        $null = Get-OrUpdateCache -cacheFileName 'file.json' -compute {
            Get-Example
        }

        Should -Invoke Get-Example -Exactly 1
        Should -Invoke Save-CachedData -Exactly 1
    }
}
