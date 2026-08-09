
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\cache-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:CACHE_PATH = $PVMConfig.paths.cache
    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.paths.cache -Force | Out-Null

    Mock Show-Error {}
    Mock Show-Info {}
    Mock Write-Gray {}
    Mock Show-Message {}
    Mock Show-Success {}
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-CacheFiles Tests" {
    It "Should return a list of cache files" {
        Mock Get-ChildItem {
            return @(
                @{ Name = 'cache1.json'; FullName = "$CACHE_PATH\cache1.json" }
                @{ Name = 'cache2.json'; FullName = "$CACHE_PATH\cache2.json" }
            )
        }

        $result = Get-CacheFiles
        $result.Count | Should -Be 2
    }

    It "Should return null when cache directory does not exist" {
        Mock Test-DirectoryNotExists { return $true }

        $result = Get-CacheFiles
        $result | Should -Be $null
    }

    It "Should handle exceptions gracefully when cache cannot be listed" {
        Mock Get-ChildItem { throw 'Error' }

        $result = Get-CacheFiles
        $result | Should -Be $null
    }
}

Describe "Show-CacheFiles Tests" {
    BeforeEach {
        # Clean slate for each test
        Remove-ItemWrapper -path "$CACHE_PATH\*" -Force -ErrorAction SilentlyContinue

        Mock Add-LogEntry { return 0 }
    }

    It "Should return -1 when cache directory does not exist" {
        Mock Test-DirectoryNotExists { return $true }

        $result = Show-CacheFiles
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match 'No cache directory found'
        } -Exactly 1
    }

    It "Should return -1 when cache directory is empty" {
        # Directory exists but has no .json files
        $result = Show-CacheFiles
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match 'No cache files found'
        } -Exactly 1
    }

    It "Should list all available cache files" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"
        '{}' | Set-Content -Path "$CACHE_PATH\versions.json"

        $result = Show-CacheFiles
        $result | Should -Be 0

        Should -Invoke Show-Message -ParameterFilter { $message -match 'releases' }
        Should -Invoke Show-Message -ParameterFilter { $message -match 'versions' }
    }

    It "Should return 0 and display header when at least one file exists" {
        '{}' | Set-Content -Path "$CACHE_PATH\data.json"

        $result = Show-CacheFiles
        $result | Should -Be 0

        Should -Invoke Show-Info -ParameterFilter {
            $message -match 'Available Cache Files'
        } -Exactly 1
    }

    It "Should not list non-json files" {
        '{}' | Set-Content -Path "$CACHE_PATH\data.json"
        'text' | Set-Content -Path "$CACHE_PATH\readme.txt"

        $result = Show-CacheFiles
        $result | Should -Be 0

        Should -Invoke Show-Info -ParameterFilter { $message -match 'readme' } -Exactly 0
    }

    It "Should return -1 and log error when Get-CacheFiles throws" {
        Mock Get-CacheFiles { throw 'Access denied' }

        $result = Show-CacheFiles
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match 'Failed to list cache files'
        } -Exactly 1

        Should -Invoke Add-LogEntry -Exactly 1
    }
}

Describe "Show-CachedData Tests" {
    BeforeEach {
        Remove-ItemWrapper -path "$CACHE_PATH\*" -Force -ErrorAction SilentlyContinue

        Mock Add-LogEntry { return 0 }
    }

    It "Should return -1 when cache file does not exist" {
        $result = Show-CachedData -cacheName 'nonexistent'
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match "Cache file 'nonexistent' not found"
        } -Exactly 1

        Should -Invoke Show-Message -ParameterFilter {
            $message -match "Use 'pvm cache list' to see available cache files"
        } -Exactly 1
    }

    It "Should return -1 when cache file exists but contains no data" {
        # Get-DataFromCache returns null / empty
        Mock Get-DataFromCache { return $null }
        Mock Test-FileNotExists { return $false }

        $result = Show-CachedData -cacheName 'empty'
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match "No data found in cache file 'empty'"
        } -Exactly 1
    }

    It "Should return -1 when cache data is an empty collection" {
        Mock Get-DataFromCache { return @() }
        Mock Test-FileNotExists { return $false }

        $result = Show-CachedData -cacheName 'emptycol'
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match "No data found in cache file 'emptycol'"
        } -Exactly 1
    }

    It "Should return 0 and display data when cache file has content" {
        $cacheContent = @{ version = '8.2.0'; url = 'https://example.com' }
        $cacheContent | ConvertTo-Json -Depth 5 | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Get-DataFromCache { return $cacheContent }
        Mock Test-FileNotExists { return $false }

        $result = Show-CachedData -cacheName 'releases'
        $result | Should -Be 0

        Should -Invoke Show-Info -ParameterFilter {
            $message -match "Cache Data for 'releases'"
        } -Exactly 1
    }

    It "Should display the separator line" {
        $cacheContent = @{ key = 'value' }
        Mock Get-DataFromCache { return $cacheContent }
        Mock Test-FileNotExists { return $false }

        $result = Show-CachedData -cacheName 'info'
        $result | Should -Be 0

        Should -Invoke Write-Gray -ParameterFilter {
            $message -match '---'
        } -Exactly 1
    }

    It "Should return -1 and log error when an exception occurs" {
        Mock Test-FileNotExists { return $false }
        Mock Get-DataFromCache { throw 'Unexpected error' }

        $result = Show-CachedData -cacheName 'broken'
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match 'Failed to show cache data'
        } -Exactly 1

        Should -Invoke Add-LogEntry -Exactly 1
    }
}

Describe "Remove-CacheFile Tests" {
    BeforeEach {
        Remove-ItemWrapper -path "$CACHE_PATH\*" -Force -ErrorAction SilentlyContinue

        Mock Add-LogEntry { return 0 }
    }

    It "Should return -1 when cache file does not exist" {
        $result = Remove-CacheFile -cacheName 'nonexistent'
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match "Cache file 'nonexistent' not found"
        } -Exactly 1

        Should -Invoke Show-Message -ParameterFilter {
            $message -match "Use 'pvm cache list' to see available cache files"
        } -Exactly 1
    }

    It "Should return -1 when user cancels with 'n'" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'n' }

        $result = Remove-CacheFile -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $true

        Should -Invoke Write-Gray -ParameterFilter {
            $message -match 'Deletion cancelled'
        } -Exactly 1
    }

    It "Should return -1 when user cancels with empty response" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return '' }

        $result = Remove-CacheFile -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $true

        Should -Invoke Write-Gray -ParameterFilter {
            $message -match 'Deletion cancelled'
        } -Exactly 1
    }

    It "Should return -1 when user cancels with 'no'" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'no' }

        $result = Remove-CacheFile -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should return -1 when user cancels with 'yes' (not just 'y')" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'yes' }

        $result = Remove-CacheFile -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should successfully delete file when user confirms with 'y'" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'y' }

        $result = Remove-CacheFile -cacheName 'releases'
        $result | Should -Be 0

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $false

        Should -Invoke Show-Success -ParameterFilter {
            $message -match "Cache file 'releases' deleted successfully"
        } -Exactly 1
    }

    It "Should successfully delete file when user confirms with 'Y'" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'Y' }

        $result = Remove-CacheFile -cacheName 'releases'
        $result | Should -Be 0

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $false
    }

    It "Should display the correct confirmation prompt including cache name" {
        '{}' | Set-Content -Path "$CACHE_PATH\mydata.json"

        Mock Read-HostWrapper { return 'y' }

        $result = Remove-CacheFile -cacheName 'mydata'
        $result | Should -Be 0

        Should -Invoke Read-HostWrapper -ParameterFilter {
            $prompt -match "Are you sure you want to delete cache file 'mydata'" -and
            $prompt -match '\(y/n\)'
        } -Exactly 1
    }

    It "Should not display the confirmation prompt when skipConfirmation is true" {
        '{}' | Set-Content -Path "$CACHE_PATH\mydata.json"
        Mock Read-HostWrapper { }

        $result = Remove-CacheFile -cacheName 'mydata' -skipConfirmation $true
        $result | Should -Be 0
        Should -Invoke Read-HostWrapper -Exactly 0
        Test-Path "$CACHE_PATH\mydata.json" | Should -Be $false
    }

    It "Should return -1 and log error when Remove-ItemWrapper throws" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'y' }
        Mock Remove-ItemWrapper { throw 'Access denied' }

        $result = Remove-CacheFile -cacheName 'releases'
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match 'Failed to delete cache file'
        } -Exactly 1

        Should -Invoke Add-LogEntry -Exactly 1
    }

    It "Should handle cache file with complex name" {
        '{}' | Set-Content -Path "$CACHE_PATH\php-releases_8x.json"

        Mock Read-HostWrapper { return 'y' }

        $result = Remove-CacheFile -cacheName 'php-releases_8x'
        $result | Should -Be 0

        Test-Path "$CACHE_PATH\php-releases_8x.json" | Should -Be $false

        Should -Invoke Show-Success -ParameterFilter {
            $message -match "Cache file 'php-releases_8x' deleted successfully"
        } -Exactly 1
    }
}

Describe "Clear-CacheFiles Tests" {
    BeforeEach {
        Remove-ItemWrapper -path "$CACHE_PATH\*" -Force -ErrorAction SilentlyContinue

        Mock Add-LogEntry { return 0 }
    }

    It "Should return -1 when no cache files exist" {
        $result = Clear-CacheFiles
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match 'No cache files found'
        } -Exactly 1
    }

    It "Should return -1 when user cancels with 'n'" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"
        '{}' | Set-Content -Path "$CACHE_PATH\versions.json"

        Mock Read-HostWrapper { return 'n' }

        $result = Clear-CacheFiles
        $result | Should -Be -1

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $true
        Test-Path "$CACHE_PATH\versions.json" | Should -Be $true

        Should -Invoke Write-Gray -ParameterFilter {
            $message -match 'Deletion cancelled'
        } -Exactly 1
    }

    It "Should return -1 when user cancels with empty response" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return '' }

        $result = Clear-CacheFiles
        $result | Should -Be -1

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should return -1 when user cancels with 'no'" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'no' }

        $result = Clear-CacheFiles
        $result | Should -Be -1

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should return -1 when user cancels with 'yes' (not just 'y')" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'yes' }

        $result = Clear-CacheFiles
        $result | Should -Be -1

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should delete all cache files when user confirms with 'y'" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"
        '{}' | Set-Content -Path "$CACHE_PATH\versions.json"
        '{}' | Set-Content -Path "$CACHE_PATH\metadata.json"

        Mock Read-HostWrapper { return 'y' }

        $result = Clear-CacheFiles
        $result | Should -Be 0

        Test-Path "$CACHE_PATH\releases.json"  | Should -Be $false
        Test-Path "$CACHE_PATH\versions.json"  | Should -Be $false
        Test-Path "$CACHE_PATH\metadata.json"  | Should -Be $false

        Should -Invoke Show-Success -ParameterFilter {
            $message -match 'All cache files deleted successfully'
        } -Exactly 1
    }

    It "Should delete all cache files when user confirms with 'Y'" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"
        '{}' | Set-Content -Path "$CACHE_PATH\versions.json"

        Mock Read-HostWrapper { return 'Y' }

        $result = Clear-CacheFiles
        $result | Should -Be 0

        Test-Path "$CACHE_PATH\releases.json" | Should -Be $false
        Test-Path "$CACHE_PATH\versions.json" | Should -Be $false
    }

    It "Should display correct confirmation prompt" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'y' }

        $result = Clear-CacheFiles
        $result | Should -Be 0

        Should -Invoke Read-HostWrapper -ParameterFilter {
            $prompt -match 'Are you sure you want to delete all cache files' -and
            $prompt -match '\(y/n\)'
        } -Exactly 1
    }

    It "Should work correctly with a single cache file" {
        '{}' | Set-Content -Path "$CACHE_PATH\single.json"

        Mock Read-HostWrapper { return 'y' }

        $result = Clear-CacheFiles
        $result | Should -Be 0

        Test-Path "$CACHE_PATH\single.json" | Should -Be $false
    }

    It "Should not display the confirmation prompt when skipConfirmation is true" {
        '{}' | Set-Content -Path "$CACHE_PATH\mydata.json"
        Mock Read-HostWrapper { }

        $result = Clear-CacheFiles -skipConfirmation $true
        $result | Should -Be 0
        Should -Invoke Read-HostWrapper -Exactly 0
        Test-Path "$CACHE_PATH\mydata.json" | Should -Be $false
    }

    It "Should return -1 and log error when an exception occurs during deletion" {
        '{}' | Set-Content -Path "$CACHE_PATH\releases.json"

        Mock Read-HostWrapper { return 'y' }
        Mock Remove-ItemWrapper { throw 'Access denied' }

        $result = Clear-CacheFiles
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match 'Failed to clear cache files'
        } -Exactly 1

        Should -Invoke Add-LogEntry -Exactly 1
    }

    It "Should return -1 and log error when Get-CacheFiles throws" {
        Mock Get-CacheFiles { throw 'Disk error' }

        $result = Clear-CacheFiles
        $result | Should -Be -1

        Should -Invoke Show-Error -ParameterFilter {
            $message -match 'Failed to clear cache files'
        } -Exactly 1

        Should -Invoke Add-LogEntry -Exactly 1
    }
}
