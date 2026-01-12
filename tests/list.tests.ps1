# PHP Version Management Tests
# Load required modules and functions
. "$PSScriptRoot\..\src\actions\list.ps1"

BeforeAll {
    # Mock global variables that would be defined in the main script
    $global:DATA_PATH = "$PSScriptRoot\storage\data"
    $global:LOG_ERROR_PATH = "$PSScriptRoot\storage\logs\error.log"
    
    Mock Write-Host { }
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
            'releases' = $PHP_WIN_RELEASES_URL
            'archives' = $PHP_WIN_ARCHIVES_URL
        }
    }
    Mock Get-Current-PHP-Version { return @{ version = "8.2.0" } }
    Mock Get-Installed-PHP-Versions { return @("php8.2.0", "php8.1.5", "php7.4.33") }
}

AfterAll {
    Remove-Item -Path "$PSScriptRoot\storage" -Recurse -Force -ErrorAction SilentlyContinue
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
        
        Mock Cache-Data { }
        
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
        
        Mock Cache-Data { }
        
        $result = Get-From-Source
        
        $allVersions = $result['Archives'] + $result['Releases']
        $allVersions | Should -Contain 'php-8.2.0-Win32-x86.zip'
        $allVersions | Should -Not -Contain 'php-8.2.0-Win32-x64.zip'
    }
    
    It "Should return empty list" {
        Mock Invoke-WebRequest {
            return @{ Links = @() }
        }
        Mock Cache-Data { }
        
        $result = Get-From-Source
        
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }
    
    It "Should handle web request failure" {
        Mock Invoke-WebRequest { throw "Network error" }
        Mock Log-Data { return "Logged error" }
        
        $result = Get-From-Source
        
        $result | Should -BeOfType [hashtable]
        $result.Keys.Count | Should -Be 0
    }
}

Describe "Get-PHP-List-To-Install" {
    
    It "Should read from cache" {
        Mock Test-Path { return $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
        Mock Get-Item { @{ LastWriteTime = $timeWithinLastWeek } }
        Mock Get-Data-From-Cache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        $result = Get-PHP-List-To-Install
        
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'Archives'
        $result.Keys | Should -Contain 'Releases'
        Assert-MockCalled Get-Data-From-Cache -Exactly 1
    }
    
    It "Should fetch from source when cache is empty" {
        Mock Test-Path { $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
        Mock Get-Item { @{ LastWriteTime = $timeWithinLastWeek } }
        Mock Get-Data-From-Cache { return @{} }
        Mock Get-From-Source {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        $result = Get-PHP-List-To-Install
        
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'Archives'
        $result.Keys | Should -Contain 'Releases'
        Assert-MockCalled Get-Data-From-Cache -Exactly 1
        Assert-MockCalled Get-From-Source -Exactly 1
    }
    
    It "Should fetch from source" {
        Mock Test-Path { return $false }
        Mock Get-From-Source {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        $result = Get-PHP-List-To-Install
        
        $result | Should -Not -BeNullOrEmpty
        $result.Keys | Should -Contain 'Archives'
        $result.Keys | Should -Contain 'Releases'
        Assert-MockCalled Get-From-Source -Exactly 1
    }
    
    It "Handles exceptions gracefully" {
        Mock Test-Path { throw "Cache error" }
        $result = Get-PHP-List-To-Install
        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-Available-PHP-Versions" {
    BeforeEach {
        Mock Write-Host { }
    }
    
    It "Should read from cache by default" {
        Mock Get-Data-From-Cache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        Mock Test-Path { return $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
        Mock Get-Item { @{ LastWriteTime = $timeWithinLastWeek } }
        
        $code = Get-Available-PHP-Versions
        
        $code | Should -Be 0
        Should -Invoke Get-Data-From-Cache -Exactly 1
    }
    
    It "Display available versions matching filter" {
        $code = Get-Available-PHP-Versions -term "7.1"
        $code | Should -Be 0
    }
    
    It "Return -1 when no available versions matching filter" {
        $code = Get-Available-PHP-Versions -term "9.1"
        $code | Should -Be -1
    }
    
    It "Return -1 when no installed versions matching filter" {
        Mock Get-Installed-PHP-Versions { return @("8.2.0", "8.2.0", "8.1.5") }
        $code = Display-Installed-PHP-Versions -term "9.1"
        $code | Should -Be -1
    }
    
    It "Should fetch from source when cache is empty" {
        Mock Test-Path { $true }
        Mock Get-Item { @{ LastWriteTime = (Get-Date) } }
        Mock Get-Data-From-Cache { return @{} }
        Mock Get-From-Source {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        $code = Get-Available-PHP-Versions
        
        $code | Should -Be 0
        Should -Invoke Get-Data-From-Cache -Exactly 1
        Should -Invoke Get-From-Source -Exactly 1
    }
    
    It "Should force fetch from source when cache not exists" {
        Mock Test-Path { return $false }
        Mock Get-Data-From-Cache { }  # Remove return value since it won't be called
        Mock Get-From-Source {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        
        $code = Get-Available-PHP-Versions
        
        $code | Should -Be 0
        Should -Not -Invoke Get-Data-From-Cache
        Should -Invoke Get-From-Source -Exactly 1
    }
    
    It "Should display versions in correct format" {
        Mock Get-Data-From-Cache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        Mock Test-Path { return $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString("yyyy-MM-ddTHH:mm:ss.fffffffK")
        Mock Get-Item { @{ LastWriteTime = $timeWithinLastWeek } }
        
        
        $code = Get-Available-PHP-Versions
        
        $code | Should -Be 0
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Available Versions*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Archives*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*Releases*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.1.0*" }
        Should -Invoke Write-Host -ParameterFilter { $Object -like "*8.2.0*" }
    }
    
    It "Returns -1 on empty list" {
        Mock Get-PHP-List-To-Install { return @{} }
        
        $result = Get-Available-PHP-Versions
        
        $result | Should -Be -1
    }
    
    It "Should handle exceptions gracefully" {
        Mock Get-PHP-List-To-Install { return @{
            'Archives' = @('php-8.1.0-Win32-x64.zip')
            'Releases' = @('php-8.2.0-Win32-x64.zip')
        }}
        Mock ForEach-Object { throw "Cache error" }
        Mock Log-Data { return "Logged error" }
        
        $result = Get-Available-PHP-Versions
        
        $result | Should -Be -1
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
    
    It "Display installed versions matching filter" {
        Mock Get-Installed-PHP-Versions { return @("8.2.0", "8.2.0", "8.1.5") }
        $code = Display-Installed-PHP-Versions -term "8.2"
        $code | Should -Be 0
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

Describe "Get-PHP-Versions-List" {
    It "Displays available versions" {
        Mock Get-Available-PHP-Versions { return 0 }
        
        $result = Get-PHP-Versions-List -available $true
        
        $result | Should -Be 0
        Assert-MockCalled Get-Available-PHP-Versions -Exactly 1
    }
    
    It "Displays installed versions" {
        Mock Display-Installed-PHP-Versions { return 0 }
        
        $result = Get-PHP-Versions-List
        
        $result | Should -Be 0
        Assert-MockCalled Display-Installed-PHP-Versions -Exactly 1
    }
}