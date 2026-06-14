BeforeAll {
    # Mock global variables
    $global:CACHE_PATH = 'TestDrive:\\cache'
    $CACHE_PATH = $global:CACHE_PATH

    # Create test cache directory
    New-Item -ItemType Directory -Path $global:CACHE_PATH -Force | Out-Null
}

Describe "List-Cache-Files Tests" {
    BeforeEach {
        # Clean slate for each test
        Remove-Item -Path "$global:CACHE_PATH\*" -Force -ErrorAction SilentlyContinue

        Mock Write-Host {}
        Mock Log-Data { return 0 }
    }

    It "Should return -1 when cache directory does not exist" {
        Mock Is-Directory-Not-Exists { return $true }

        $result = List-Cache-Files
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'No cache directory found'
        } -Exactly 1
    }

    It "Should return -1 when cache directory is empty" {
        # Directory exists but has no .json files
        $result = List-Cache-Files
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'No cache files found'
        } -Exactly 1
    }

    It "Should list all available cache files" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"
        '{}' | Set-Content -Path "$global:CACHE_PATH\versions.json"

        $result = List-Cache-Files
        $result | Should -Be 0

        Assert-MockCalled Write-Host -ParameterFilter { $Object -match 'releases' }
        Assert-MockCalled Write-Host -ParameterFilter { $Object -match 'versions' }
    }

    It "Should return 0 and display header when at least one file exists" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\data.json"

        $result = List-Cache-Files
        $result | Should -Be 0

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Available Cache Files'
        } -Exactly 1
    }

    It "Should not list non-json files" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\data.json"
        'text' | Set-Content -Path "$global:CACHE_PATH\readme.txt"

        $result = List-Cache-Files
        $result | Should -Be 0

        Assert-MockCalled Write-Host -ParameterFilter { $Object -match 'readme' } -Exactly 0
    }

    It "Should return -1 and log error when Get-ChildItem throws" {
        Mock Get-ChildItem { throw 'Access denied' }

        $result = List-Cache-Files
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Failed to list cache files'
        } -Exactly 1

        Assert-MockCalled Log-Data -Exactly 1
    }
}

Describe "Show-Cache-Data Tests" {
    BeforeEach {
        Remove-Item -Path "$global:CACHE_PATH\*" -Force -ErrorAction SilentlyContinue

        Mock Write-Host {}
        Mock Log-Data { return 0 }
    }

    It "Should return -1 when cache file does not exist" {
        $result = Show-Cache-Data -cacheName 'nonexistent'
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "Cache file 'nonexistent' not found"
        } -Exactly 1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "Use 'pvm cache list' to see available cache files"
        } -Exactly 1
    }

    It "Should return -1 when cache file exists but contains no data" {
        # Get-Data-From-Cache returns null / empty
        Mock Get-Data-From-Cache { return $null }
        Mock Is-File-Not-Exists { return $false }

        $result = Show-Cache-Data -cacheName 'empty'
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "No data found in cache file 'empty'"
        } -Exactly 1
    }

    It "Should return -1 when cache data is an empty collection" {
        Mock Get-Data-From-Cache { return @() }
        Mock Is-File-Not-Exists { return $false }

        $result = Show-Cache-Data -cacheName 'emptycol'
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "No data found in cache file 'emptycol'"
        } -Exactly 1
    }

    It "Should return 0 and display data when cache file has content" {
        $cacheContent = @{ version = '8.2.0'; url = 'https://example.com' }
        $cacheContent | ConvertTo-Json -Depth 5 | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Get-Data-From-Cache { return $cacheContent }
        Mock Is-File-Not-Exists { return $false }

        $result = Show-Cache-Data -cacheName 'releases'
        $result | Should -Be 0

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "Cache Data for 'releases'"
        } -Exactly 1
    }

    It "Should display the separator line" {
        $cacheContent = @{ key = 'value' }
        Mock Get-Data-From-Cache { return $cacheContent }
        Mock Is-File-Not-Exists { return $false }

        $result = Show-Cache-Data -cacheName 'info'
        $result | Should -Be 0

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match '---'
        } -Exactly 1
    }

    It "Should return -1 and log error when an exception occurs" {
        Mock Is-File-Not-Exists { return $false }
        Mock Get-Data-From-Cache { throw 'Unexpected error' }

        $result = Show-Cache-Data -cacheName 'broken'
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Failed to show cache data'
        } -Exactly 1

        Assert-MockCalled Log-Data -Exactly 1
    }
}

Describe "Delete-Cache-File Tests" {
    BeforeEach {
        Remove-Item -Path "$global:CACHE_PATH\*" -Force -ErrorAction SilentlyContinue

        Mock Write-Host {}
        Mock Log-Data { return 0 }
    }

    It "Should return -1 when cache file does not exist" {
        $result = Delete-Cache-File -cacheName 'nonexistent'
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "Cache file 'nonexistent' not found"
        } -Exactly 1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "Use 'pvm cache list' to see available cache files"
        } -Exactly 1
    }

    It "Should return -1 when user cancels with 'n'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'n' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Deletion cancelled'
        } -Exactly 1
    }

    It "Should return -1 when user cancels with empty response" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return '' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Deletion cancelled'
        } -Exactly 1
    }

    It "Should return -1 when user cancels with 'no'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'no' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should return -1 when user cancels with 'yes' (not just 'y')" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'yes' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should successfully delete file when user confirms with 'y'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'y' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be 0

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $false

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "Cache file 'releases' deleted successfully"
        } -Exactly 1
    }

    It "Should successfully delete file when user confirms with 'Y'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'Y' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be 0

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $false
    }

    It "Should trim whitespace from user response and delete when 'y'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return '  y  ' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be 0

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $false
    }

    It "Should trim whitespace and cancel when response is '  n  '" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return '  n  ' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should display the correct confirmation prompt including cache name" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\mydata.json"

        Mock Read-Host { return 'y' }

        $result = Delete-Cache-File -cacheName 'mydata'
        $result | Should -Be 0

        Assert-MockCalled Read-Host -ParameterFilter {
            $Prompt -match "Are you sure you want to delete cache file 'mydata'" -and
            $Prompt -match '\(y/n\)'
        } -Exactly 1
    }

    It "Should return -1 and log error when Remove-Item throws" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'y' }
        Mock Remove-Item { throw 'Access denied' }

        $result = Delete-Cache-File -cacheName 'releases'
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Failed to delete cache file'
        } -Exactly 1

        Assert-MockCalled Log-Data -Exactly 1
    }

    It "Should handle cache file with complex name" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\php-releases_8x.json"

        Mock Read-Host { return 'y' }

        $result = Delete-Cache-File -cacheName 'php-releases_8x'
        $result | Should -Be 0

        Test-Path "$global:CACHE_PATH\php-releases_8x.json" | Should -Be $false

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match "Cache file 'php-releases_8x' deleted successfully"
        } -Exactly 1
    }
}

Describe "Clear-Cache-Files Tests" {
    BeforeEach {
        Remove-Item -Path "$global:CACHE_PATH\*" -Force -ErrorAction SilentlyContinue

        Mock Write-Host {}
        Mock Log-Data { return 0 }
    }

    It "Should return -1 when no cache files exist" {
        $result = Clear-Cache-Files
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'No cache files found'
        } -Exactly 1
    }

    It "Should return -1 when user cancels with 'n'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"
        '{}' | Set-Content -Path "$global:CACHE_PATH\versions.json"

        Mock Read-Host { return 'n' }

        $result = Clear-Cache-Files
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true
        Test-Path "$global:CACHE_PATH\versions.json" | Should -Be $true

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Deletion cancelled'
        } -Exactly 1
    }

    It "Should return -1 when user cancels with empty response" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return '' }

        $result = Clear-Cache-Files
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should return -1 when user cancels with 'no'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'no' }

        $result = Clear-Cache-Files
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should return -1 when user cancels with 'yes' (not just 'y')" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'yes' }

        $result = Clear-Cache-Files
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should delete all cache files when user confirms with 'y'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"
        '{}' | Set-Content -Path "$global:CACHE_PATH\versions.json"
        '{}' | Set-Content -Path "$global:CACHE_PATH\metadata.json"

        Mock Read-Host { return 'y' }

        $result = Clear-Cache-Files
        $result | Should -Be 0

        Test-Path "$global:CACHE_PATH\releases.json"  | Should -Be $false
        Test-Path "$global:CACHE_PATH\versions.json"  | Should -Be $false
        Test-Path "$global:CACHE_PATH\metadata.json"  | Should -Be $false

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'All cache files deleted successfully'
        } -Exactly 1
    }

    It "Should delete all cache files when user confirms with 'Y'" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"
        '{}' | Set-Content -Path "$global:CACHE_PATH\versions.json"

        Mock Read-Host { return 'Y' }

        $result = Clear-Cache-Files
        $result | Should -Be 0

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $false
        Test-Path "$global:CACHE_PATH\versions.json" | Should -Be $false
    }

    It "Should trim whitespace and delete all files when response is '  y  '" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return '  y  ' }

        $result = Clear-Cache-Files
        $result | Should -Be 0

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $false
    }

    It "Should trim whitespace and cancel when response is '  n  '" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return '  n  ' }

        $result = Clear-Cache-Files
        $result | Should -Be -1

        Test-Path "$global:CACHE_PATH\releases.json" | Should -Be $true
    }

    It "Should display correct confirmation prompt" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'y' }

        $result = Clear-Cache-Files
        $result | Should -Be 0

        Assert-MockCalled Read-Host -ParameterFilter {
            $Prompt -match 'Are you sure you want to delete all cache files' -and
            $Prompt -match '\(y/n\)'
        } -Exactly 1
    }

    It "Should work correctly with a single cache file" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\single.json"

        Mock Read-Host { return 'y' }

        $result = Clear-Cache-Files
        $result | Should -Be 0

        Test-Path "$global:CACHE_PATH\single.json" | Should -Be $false
    }

    It "Should return -1 and log error when an exception occurs during deletion" {
        '{}' | Set-Content -Path "$global:CACHE_PATH\releases.json"

        Mock Read-Host { return 'y' }
        Mock Remove-Item { throw 'Access denied' }

        $result = Clear-Cache-Files
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Failed to clear cache files'
        } -Exactly 1

        Assert-MockCalled Log-Data -Exactly 1
    }

    It "Should return -1 and log error when Get-ChildItem throws" {
        Mock Get-ChildItem { throw 'Disk error' }

        $result = Clear-Cache-Files
        $result | Should -Be -1

        Assert-MockCalled Write-Host -ParameterFilter {
            $Object -match 'Failed to clear cache files'
        } -Exactly 1

        Assert-MockCalled Log-Data -Exactly 1
    }
}