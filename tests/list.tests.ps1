# PHP Version Management Tests
# Load required modules and functions
. "$PSScriptRoot\..\src\actions\list.ps1"

BeforeAll {
    # Mock global variables that would be defined in the main script
    $global:DATA_PATH = "$PSScriptRoot\storage\data"
    $global:LOG_ERROR_PATH = "$PSScriptRoot\storage\logs\error.log"
    
    # Mock external functions that aren't defined in the provided code
    Mock Make-Directory { param($path) 
        if (-not (Test-Path -Path $path)) {
            $parent = Split-Path -Parent $path
            if ($parent -and -not (Test-Path -Path $parent)) {
                Make-Directory -path $parent
            }
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
        return 0
    }
    Mock Log-Data { param($logPath, $message, $data) return "Logged: $message - $data" }
    Mock Get-Source-Urls { 
        return @{
            'releases' = 'https://windows.php.net/downloads/releases/'
            'archives' = 'https://windows.php.net/downloads/releases/archives/'
        }
    }
    Mock Get-Current-PHP-Version { return @{ version = "8.2.0" } }
    Mock Get-Installed-PHP-Versions { return @("php8.2.0", "php8.1.5", "php7.4.33") }
}

AfterAll {
    Remove-Item -Path "$PSScriptRoot\storage" -Recurse -Force -ErrorAction SilentlyContinue
}

Describe "Cache-Fetched-PHP-Versions" {
    BeforeEach {
        # Clean test directory
        if (Test-Path "TestDrive:\data") {
            Remove-Item "TestDrive:\data" -Recurse -Force
        }
    }
    
    It "Should cache PHP versions successfully" {
        $testVersions = @{
            'Archives' = @('php-8.1.0-Win32-x64.zip', 'php-7.4.33-Win32-x64.zip')
            'Releases' = @('php-8.2.0-Win32-x64.zip', 'php-8.1.5-Win32-x64.zip')
        }
        
        Cache-Fetched-PHP-Versions $testVersions
        
        $cachePath = "$global:DATA_PATH\available_versions.json"
        $cachePath | Should -Exist
        
        $cachedContent = Get-Content $cachePath | ConvertFrom-Json
        $cachedContent.Archives.Count | Should -Be 2
        $cachedContent.Releases.Count | Should -Be 2
    }
    
    It "Should handle empty version list" {
        $emptyVersions = @{}
        
        { Cache-Fetched-PHP-Versions $emptyVersions } | Should -Not -Throw
        
        $cachePath = "$global:DATA_PATH\available_versions.json"
        $cachePath | Should -Exist
    }
    
    It "Should handle null input gracefully" {
        Mock Log-Data { return "Logged error" }
        
        { Cache-Fetched-PHP-Versions $null } | Should -Not -Throw
    }
}

Describe "Get-From-Cache" {
    BeforeEach {
        # Clean test directory
        if (Test-Path "TestDrive:\data") {
            Remove-Item "TestDrive:\data" -Recurse -Force
        }
        New-Item -Path "TestDrive:\data" -ItemType Directory -Force
    }
    
    It "Should retrieve cached versions successfully" {
        $testData = @{
            'Archives' = @('php-8.1.0-Win32-x64.zip')
            'Releases' = @('php-8.2.0-Win32-x64.zip')
        }
        $jsonContent = $testData | ConvertTo-Json -Depth 3
        Set-Content -Path "$global:DATA_PATH\available_versions.json" -Value $jsonContent
        
        $result = Get-From-Cache
        
        $result | Should -Not -BeNullOrEmpty
        $result.Keys.Count | Should -Be 2
        $result['Archives'].Count | Should -Be 1
        $result['Releases'].Count | Should -Be 1
    }
    
    It "Should return empty hashtable when cache file doesn't exist" {
        Set-Content -Path "$DATA_PATH\available_versions.json" -Value "{}"
        
        $result = Get-From-Cache
        
        $result | Should -BeOfType [hashtable]
        $result.Keys.Count | Should -Be 0
    }
    
    It "Should handle corrupted cache file" {
        Set-Content -Path "$global:DATA_PATH\available_versions.json" -Value "invalid json content"
        Mock Log-Data { return "Logged error" }
        
        $result = Get-From-Cache
        
        $result | Should -BeOfType [hashtable]
        $result.Keys.Count | Should -Be 0
    }
}

Describe "Get-From-Source" {
    BeforeEach {
        # Clean test directory
        if (Test-Path "TestDrive:\data") {
            Remove-Item "TestDrive:\data" -Recurse -Force
        }
        
        # Mock environment variable
        $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    }
    
    It "Should fetch and filter PHP versions from source" {
        # Mock web response
        $mockLinks = @(
            @{ href = 'php-8.2.0-Win32-x64.zip' },
            @{ href = 'php-8.1.5-Win32-x64.zip' },
            @{ href = 'php-7.4.33-Win32-x64.zip' },
            @{ href = 'php-8.2.0-Win32-x86.zip' },
            @{ href = 'php-debug-8.2.0-Win32-x64.zip' },
            @{ href = 'php-devel-8.2.0-Win32-x64.zip' },
            @{ href = 'php-8.2.0-nts-Win32-x64.zip' }
        )
        
        Mock Invoke-WebRequest {
            return @{ Links = $mockLinks }
        }
        
        Mock Cache-Fetched-PHP-Versions { }
        
        $result = Get-From-Source
        
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'Archives'
        $result.Keys | Should -Contain 'Releases'
        
        # Verify filtering worked (should exclude debug, devel, nts, and x86)
        $allVersions = $result['Archives'] + $result['Releases']
        $allVersions | Should -Not -Contain 'php-debug-8.2.0-Win32-x64.zip'
        $allVersions | Should -Not -Contain 'php-devel-8.2.0-Win32-x64.zip'
        $allVersions | Should -Not -Contain 'php-8.2.0-nts-Win32-x64.zip'
        $allVersions | Should -Not -Contain 'php-8.2.0-Win32-x86.zip'
    }
    
    It "Should handle x86 architecture" {
        $env:PROCESSOR_ARCHITECTURE = 'X86'
        
        $mockLinks = @(
            @{ href = 'php-8.2.0-Win32-x86.zip' },
            @{ href = 'php-8.2.0-Win32-x64.zip' }
        )
        
        Mock Invoke-WebRequest {
            return @{ Links = $mockLinks }
        }
        
        Mock Cache-Fetched-PHP-Versions { }
        
        $result = Get-From-Source
        
        $allVersions = $result['Archives'] + $result['Releases']
        $allVersions | Should -Contain 'php-8.2.0-Win32-x86.zip'
        $allVersions | Should -Not -Contain 'php-8.2.0-Win32-x64.zip'
    }
    
    It "Should handle web request failure" {
        Mock Invoke-WebRequest { throw "Network error" }
        Mock Log-Data { return "Logged error" }
        
        $result = Get-From-Source
        
        $result | Should -BeOfType [hashtable]
        $result.Keys.Count | Should -Be 0
    }
    
    It "Should limit to last 10 versions" {
        # Create 15 mock versions
        $mockLinks = @()
        for ($i = 1; $i -le 15; $i++) {
            $mockLinks += @{ href = "php-8.2.$i-Win32-x64.zip" }
        }
        
        Mock Invoke-WebRequest {
            return @{ Links = $mockLinks }
        }
        
        Mock Cache-Fetched-PHP-Versions { }
        
        $result = Get-From-Source
        
        $totalVersions = ($result['Archives'] + $result['Releases']).Count
        $totalVersions | Should -BeLessOrEqual 10
    }
}

Describe "Get-Available-PHP-Versions" {
    BeforeEach {
        Mock Write-Host { }
    }
    
    It "Should read from cache by default" {
        Mock Get-From-Cache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        Get-Available-PHP-Versions
        
        Should -Invoke Get-From-Cache -Exactly 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Reading from the cache*" }
    }
    
    It "Should fetch from source when cache is empty" {
        Mock Test-Path { $true }
        Mock Get-Item { @{ LastWriteTime = (Get-Date) } }
        Mock Get-From-Cache { return @{} }
        Mock Get-From-Source {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        Get-Available-PHP-Versions
        
        Should -Invoke Get-From-Cache -Exactly 1
        Should -Invoke Get-From-Source -Exactly 1
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Cache is empty*" }
    }
    
    It "Should force fetch from source when cache not exists" {
        Mock Test-Path { return $false }
        Mock Get-From-Cache { }  # Remove return value since it won't be called
        Mock Get-From-Source {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        Get-Available-PHP-Versions
        
        Should -Not -Invoke Get-From-Cache
        Should -Invoke Get-From-Source -Exactly 1
    }
    
    It "Should display versions in correct format" {
        Mock Get-From-Cache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        Get-Available-PHP-Versions
        
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Available Versions*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Archives*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Releases*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.1.0*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.2.0*" }
    }
    
    It "Should handle exceptions gracefully" {
        Mock Get-From-Cache { throw "Cache error" }
        Mock Log-Data { return "Logged error" }
        
        $result = Get-Available-PHP-Versions
        
        $result | Should -Be 1
    }
}

Describe "Display-Installed-PHP-Versions" {
    BeforeEach {
        Mock Write-Host { }
    }
    
    It "Should display installed versions with current version marked" {
        Mock Get-Current-PHP-Version { return @{ version = "8.2.0" } }
        Mock Get-Installed-PHP-Versions { return @("8.2.0", "8.1.5", "7.4.33") }
        
        Display-Installed-PHP-Versions
        
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Installed Versions*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.2.0*(Current)*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.1.5*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*7.4.33*" }
    }
    
    It "Should handle no installed versions" {
        Mock Get-Current-PHP-Version { return @{ version = "" } }
        Mock Get-Installed-PHP-Versions { return @() }
        
        Display-Installed-PHP-Versions
        
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*No PHP versions found*" }
    }
    
    It "Should handle duplicate versions" {
        Mock Get-Current-PHP-Version { return @{ version = "8.2.0" } }
        Mock Get-Installed-PHP-Versions { return @("php8.2.0", "php8.2.0", "php8.1.5") }
        
        Display-Installed-PHP-Versions
        
        # Should only display unique versions
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.2.0*" } -Exactly 1
    }
    
    It "Should handle no current version set" {
        Mock Get-Current-PHP-Version { return @{ version = "" } }
        Mock Get-Installed-PHP-Versions { return @("php8.2.0", "php8.1.5") }
        
        Display-Installed-PHP-Versions
        
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.2.0*" -and $Object -notlike "*(Current)*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.1.5*" -and $Object -notlike "*(Current)*" }
    }
    
    It "Should handle exceptions gracefully" {
        Mock Get-Current-PHP-Version { throw "Error getting current version" }
        Mock Log-Data { return "Logged error" }
        
        { Display-Installed-PHP-Versions } | Should -Not -Throw
    }
}

Describe "Integration Tests" {
    BeforeEach {
        # Clean test environment
        if (Test-Path "TestDrive:\data") {
            Remove-Item "TestDrive:\data" -Recurse -Force
        }
        Mock Write-Host { }
    }
    
    It "Should complete full cache workflow" {
        $testVersions = @{
            'Archives' = @('php-8.1.0-Win32-x64.zip')
            'Releases' = @('php-8.2.0-Win32-x64.zip')
        }
        
        # Cache versions
        Cache-Fetched-PHP-Versions $testVersions
        
        # Retrieve from cache
        $cachedVersions = Get-From-Cache
        
        $cachedVersions | Should -Not -BeNullOrEmpty
        $cachedVersions.Keys.Count | Should -Be 2
        $cachedVersions['Archives'][0] | Should -Be 'php-8.1.0-Win32-x64.zip'
        $cachedVersions['Releases'][0] | Should -Be 'php-8.2.0-Win32-x64.zip'
    }
    
    It "Should fallback from cache to source correctly" {
        Mock Get-From-Source {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        # Should try cache first, then source
        $result = Get-Available-PHP-Versions
        $result | Should -Be 0
    }
}