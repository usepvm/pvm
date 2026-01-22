# Comprehensive Test Suite for PHP Installation Functions
# Load required modules and functions
. "$PSScriptRoot\..\src\actions\install.ps1"

BeforeAll {
    Mock Write-Host {}
    # Global test variables
    $global:LOG_ERROR_PATH = "TestDrive:\error.log"
    $global:STORAGE_PATH = "TestDrive:\storage"
    $global:PVMRoot = "TestDrive:\pvm"

    # Mock registry for testing environment variables
    $global:MockRegistry = @{
        Machine = @{
            "Path" = "C:\Windows\System32;C:\Program Files\Git\bin"
            "php8.1.0" = "C:\PHP\8.1.0"
            "php8.0.5" = "C:\PHP\8.0.5"
            "php7.4.30" = "C:\PHP\7.4.30"
        }
        Process = @{}
        User = @{}
    }

    $global:MockRegistryThrowException = $false
    $global:MockRegistryException = "Registry access denied"

    # Mock file system
    $global:MockFileSystem = @{
        Directories = @()
        Files = @{}
        WebResponses = @{}
        DownloadFails = $false
    }

    # Test helper functions
    function Reset-MockState {
        $global:MockRegistryThrowException = $false
        $global:MockFileSystem.DownloadFails = $false
        $global:MockFileSystem.WebResponses = @{}
        $global:MockFileSystem.Files = @{}
        $global:MockFileSystem.Directories = @()
        $global:MockRegistry = @{
            Machine = @{
                "Path" = "C:\Windows\System32;C:\Program Files\Git\bin"
                "php8.1.0" = "C:\PHP\8.1.0"
                "php8.0.5" = "C:\PHP\8.0.5"
                "php7.4.30" = "C:\PHP\7.4.30"
            }
            Process = @{}
            User = @{}
        }
    }

    function Set-MockWebResponse {
        param($url, $content, $links = @())
        $global:MockFileSystem.WebResponses[$url] = @{
            Content = $content
            Links = $links
        }
    }

    # Mock functions for testing
    function Log-Data {
        param($logPath, $message, $data)
        Write-Host "LOG: $message - $data"
        return $true
    }

    function Invoke-WebRequest {
        param($Uri, $OutFile = $null)
        
        if ($global:MockFileSystem.DownloadFails) {
            throw "Network error"
        }
        
        if ($global:MockFileSystem.WebResponses.ContainsKey($Uri)) {
            $response = $global:MockFileSystem.WebResponses[$Uri]
            if ($OutFile) {
                $global:MockFileSystem.Files[$OutFile] = "Downloaded content"
                return
            }
            return @{
                Content = $response.Content
                Links = $response.Links
            }
        }
        
        throw "URL not mocked: $Uri"
    }

    function Test-Path {
        param($Path, $PathType = $null)
        
        if ($PathType -eq "Container") {
            return $global:MockFileSystem.Directories -contains $Path
        }
        return $global:MockFileSystem.Files.ContainsKey($Path)
    }

    function Remove-Item {
        param($Path)
        if ($global:MockFileSystem.Files.ContainsKey($Path)) {
            $global:MockFileSystem.Files.Remove($Path)
        }
    }

    function Copy-Item {
        param($Path, $Destination)
        $global:MockFileSystem.Files[$Destination] = "Copied content"
    }

    function Get-Content {
        param($Path)
        if ($global:MockFileSystem.Files.ContainsKey($Path)) {
            $content = $global:MockFileSystem.Files[$Path]
            return $content -split "`n"
        }
        throw "File not found in mock system: $Path"
    }

    function Set-Content {
        param($Path, $Value, $Encoding = $null)
        $global:MockFileSystem.Files[$Path] = $Value -join "`n"
    }

    function Add-Content {
        param($Path, $Value)
        if ($global:MockFileSystem.Files.ContainsKey($Path)) {
            $global:MockFileSystem.Files[$Path] += "`n$Value"
        } else {
            $global:MockFileSystem.Files[$Path] = $Value
        }
    }

    function Add-Type {
        param($AssemblyName)
        # Mock for System.IO.Compression.FileSystem
    }


    function Read-Host {
        param($Prompt)
        return $global:MockUserInput
    }

    # Environment variable wrapper functions
    function Get-EnvironmentVariablesWrapper {
        param($target)
        
        if ($global:MockRegistryThrowException) {
            throw $global:MockRegistryException
        }
        
        switch ($target) {
            ([System.EnvironmentVariableTarget]::Machine) { 
                $result = @{}
                $global:MockRegistry.Machine.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                return $result
            }
            ([System.EnvironmentVariableTarget]::Process) { 
                $result = @{}
                $global:MockRegistry.Process.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                return $result
            }
            ([System.EnvironmentVariableTarget]::User) { 
                $result = @{}
                $global:MockRegistry.User.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
                return $result
            }
            default { return @{} }
        }
    }

    function Get-EnvironmentVariableWrapper {
        param($name, $target)
        
        if ($global:MockRegistryThrowException) {
            throw $global:MockRegistryException
        }
        
        switch ($target) {
            ([System.EnvironmentVariableTarget]::Machine) { return $global:MockRegistry.Machine[$name] }
            ([System.EnvironmentVariableTarget]::Process) { return $global:MockRegistry.Process[$name] }
            ([System.EnvironmentVariableTarget]::User) { return $global:MockRegistry.User[$name] }
            default { return $null }
        }
    }

    function Set-EnvironmentVariableWrapper {
        param($name, $value, $target)
        
        if ($global:MockRegistryThrowException) {
            throw $global:MockRegistryException
        }
        
        switch ($target) {
            ([System.EnvironmentVariableTarget]::Machine) { 
                if ($value -eq $null) {
                    $global:MockRegistry.Machine.Remove($name)
                } else {
                    $global:MockRegistry.Machine[$name] = $value
                }
            }
            ([System.EnvironmentVariableTarget]::Process) { 
                if ($value -eq $null) {
                    $global:MockRegistry.Process.Remove($name)
                } else {
                    $global:MockRegistry.Process[$name] = $value
                }
            }
            ([System.EnvironmentVariableTarget]::User) { 
                if ($value -eq $null) {
                    $global:MockRegistry.User.Remove($name)
                } else {
                    $global:MockRegistry.User[$name] = $value
                }
            }
        }
    }


    # Override the original environment functions to use wrappers
    function Get-All-EnvVars {
        try {
            return Get-EnvironmentVariablesWrapper -target ([System.EnvironmentVariableTarget]::Machine)
        } catch {
            $logged = Log-Data -data @{
                header = "Get-All-EnvVars: Failed to get all environment variables"
                exception = $_
            }
            return $null
        }
    }

    function Get-EnvVar-ByName {
        param ($name)
        try {
            if ([string]::IsNullOrWhiteSpace($name)) {
                return $null
            }
            $name = $name.Trim()
            return Get-EnvironmentVariableWrapper -name $name -target ([System.EnvironmentVariableTarget]::Machine)
        } catch {
            $logged = Log-Data -data @{
                header = "Get-EnvVar-ByName: Failed to get environment variable '$name'"
                exception = $_
            }
            return $null
        }
    }

    function Set-EnvVar {
        param ($name, $value)
        try {
            if ([string]::IsNullOrWhiteSpace($name)) {
                return -1
            }
            $name = $name.Trim()
            Set-EnvironmentVariableWrapper -name $name -value $value -target ([System.EnvironmentVariableTarget]::Machine)
            return 0
        } catch {
            $logged = Log-Data -data @{
                header = "Set-EnvVar: Failed to set environment variable '$name'"
                exception = $_
            }
            return -1
        }
    }

    function Is-PHP-Version-Installed {
        param($version)
        
        $envVars = Get-All-EnvVars
        return $envVars.ContainsKey("php$version")
    }
}

# Test Suites
Describe "Get-Source-Urls Tests" {
    Mock Write-Host {}
    It "Should return ordered hashtable with correct URLs" {
        $urls = Get-Source-Urls
        $urls | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $urls["Archives"] | Should -Be "https://windows.php.net/downloads/releases/archives"
        $urls["Releases"] | Should -Be "https://windows.php.net/downloads/releases"
    }
}


Describe "Get-PHP-Versions-From-Url Tests" {
    BeforeEach {
        Reset-MockState
    }
    
    It "Should parse PHP versions correctly" {
        $mockLinks = @(
            @{ href = "/downloads/releases/php-8.1.0-Win32-vs16-x64.zip" },
            @{ href = "/downloads/releases/php-8.1.1-Win32-vs16-x64.zip" },
            @{ href = "/downloads/releases/php-debug-8.1.0-Win32-vs16-x64.zip" },
            @{ href = "/downloads/releases/php-8.1.0-nts-Win32-vs16-x64.zip" }
        )
        Set-MockWebResponse -url "https://test.com" -links $mockLinks
        
        $result = Get-PHP-Versions-From-Url -url "https://test.com" -version "8.1"
        
        $result.Count | Should -Be 2
        $result[0].version | Should -Be "8.1.0"
        $result[1].version | Should -Be "8.1.1"
    }
    
    It "Should handle network errors gracefully" {
        $global:MockFileSystem.DownloadFails = $true
        
        $result = Get-PHP-Versions-From-Url -url "https://test.com" -version "8.1"
        
        $result | Should -Be @()
    }
    
    It "Should filter out debug and nts versions" {
        $mockLinks = @(
            @{ href = "/downloads/releases/php-8.1.0-Win32-vs16-x64.zip" },
            @{ href = "/downloads/releases/php-debug-8.1.0-Win32-vs16-x64.zip" },
            @{ href = "/downloads/releases/php-devel-8.1.0-Win32-vs16-x64.zip" },
            @{ href = "/downloads/releases/php-8.1.0-nts-Win32-vs16-x64.zip" }
        )
        Set-MockWebResponse -url "https://test.com" -links $mockLinks
        
        $result = Get-PHP-Versions-From-Url -url "https://test.com" -version "8.1"
        
        $result.Length | Should -Be 1
        $result.version | Should -Be "8.1.0"
    }
}

Describe "Get-PHP-Versions Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
    }
    
    It "Should return versions for x64 architecture" {
        $mockLinks = @(
            @{ href = "/downloads/releases/php-8.1.0-Win32-vs16-x64.zip" },
            @{ href = "/downloads/releases/php-8.1.0-Win32-vs16-x86.zip" }
        )
        
        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links $mockLinks
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links $mockLinks
        
        $result = Get-PHP-Versions -version "8.1"
        
        $result.Count | Should -BeGreaterThan 0
    }
    
    It "Should handle exception gracefully" {
        Mock Get-PHP-Versions-From-Url {
            return @(
                @{ version = "8.1.0"; fileName = "php-8.1.0-Win32-vs16-x64.zip" },
                @{ version = "8.1.1"; fileName = "php-8.1.1-Win32-vs16-x64.zip" }
            )
        }
        Mock Where-Object { throw "Test exception" }
        
        $result = Get-PHP-Versions -version "8.1"
        
        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }
}

Describe "Download-PHP" {
    BeforeAll {
        Mock Make-Directory { return 0 }
        Mock Download-PHP-From-Url { return "TestDrive:\php" }
    }
    
    It "Should download PHP successfully" {
        $result = Download-PHP -versionObject @{ fileName = "php-8.1.0-Win32-vs16-x64.zip"; version = "8.1.0" }
        $result | Should -Be "TestDrive:\php"
    }
    
    It "Returns null if directory creation fails" {
        Mock Make-Directory { return -1 }
        $result = Download-PHP -versionObject @{ fileName = "php-8.1.0-Win32-vs16-x64.zip"; version = "8.1.0" }
        $result | Should -BeNullOrEmpty
    }
    
    It "Handles exception gracefully" {
        Mock Get-Source-Urls { throw "Test exception" }
        $result = Download-PHP -versionObject @{ fileName = "php-8.1.0-Win32-vs16-x64.zip"; version = "8.1.0" }
        $result | Should -BeNullOrEmpty
    }
}

Describe "Download-PHP-From-Url Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
    }
    
    It "Should download file successfully" {
        $urls = Get-Source-Urls
        $versionObject = @{ fileName = "php-8.1.0-Win32-vs16-x64.zip"; version = "8.1.0" }
        
        # Mock the actual URL that will be called
        $expectedUrl = "$($urls["Archives"])/php-8.1.0-Win32-vs16-x64.zip"
        Set-MockWebResponse -url $expectedUrl -content "Downloaded content"
        
        $result = Download-PHP-From-Url -destination "TestDrive:\php" -url $expectedUrl -versionObject $versionObject
        
        $result | Should -Be "TestDrive:\php"
        $global:MockFileSystem.Files.ContainsKey("TestDrive:\php\php-8.1.0-Win32-vs16-x64.zip") | Should -Be $true
    }
    
    It "Should handle download failure" {
        $global:MockFileSystem.DownloadFails = $true
        $versionObject = @{ fileName = "php-8.1.0-Win32-vs16-x64.zip" }
        
        $result = Download-PHP-From-Url -destination "TestDrive:\php" -url "https://test.com/php.zip" -versionObject $versionObject
        
        $result | Should -Be $null
    }
}

Describe "Extract-Zip Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
    }
    
    It "Should extract zip without errors" {
        # This is a basic test since we're mocking the zip extraction
        { Extract-Zip -zipPath "test.zip" -extractPath "testdir" } | Should -Not -Throw
    }
}

Describe "Extract-And-Configure Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
        $global:MockFileSystem.Files["TestDrive:\php\php.ini-development"] = "development config"
    }
    
    It "Should extract and configure PHP" {
        { Extract-And-Configure -path "TestDrive:\php.zip" -fileNamePath "TestDrive:\php" } | Should -Not -Throw
        $global:MockFileSystem.Files.ContainsKey("TestDrive:\php\php.ini") | Should -Be $true
    }
    
    It "Should handle extraction failure" {
        Mock Remove-Item { throw "Test exception" }
        
        { Extract-And-Configure -path "TestDrive:\php.zip" -fileNamePath "TestDrive:\php" } | Should -Not -Throw
    }
}


Describe "Configure-Opcache Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
        $global:MockFileSystem.Files["TestDrive:\php\php.ini"] = @"
;extension_dir = "ext"
;zend_extension = opcache
;opcache.enable = 1
;opcache.enable_cli = 1
"@
    }
    
    It "Should enable Opcache successfully" {
        $code = Configure-Opcache -version "8.1" -phpPath "TestDrive:\php"
        
        $code | Should -Be 0
        $content = $global:MockFileSystem.Files["TestDrive:\php\php.ini"]
        $content | Should -Match "extension_dir = `"ext`""
        $content | Should -Match "zend_extension = opcache"
        $content | Should -Match "opcache\.enable = 1"
        $content | Should -Match "opcache\.enable_cli = 1"
    }
    
    It "Should handle missing php.ini" {
        $global:MockFileSystem.Files.Remove("TestDrive:\php\php.ini")
        
        $code = Configure-Opcache -version "8.1" -phpPath "TestDrive:\php"
        $code | Should -Be -1
    }
    
    It "Should handle exception gracefully" {
        Mock Get-Content { throw "Error reading file" }
        
        $code = Configure-Opcache -version "8.1" -phpPath "TestDrive:\php"
        $code | Should -Be -1
    }
}

Describe "Select-Version Tests" {
    BeforeEach {
        Reset-MockState
        $global:MockUserInput = ""
    }
    
    It "Should return single version when only one available" {
        Mock Write-Host { }
        $versions = @{
            "Archives" = @(@{ version = "8.1.0"; fileName = "php-8.1.0.zip" })
        }
        
        $result = Select-Version -matchingVersions $versions
        
        $result.version | Should -Be "8.1.0"
    }
    
    It "Should return null when user cancels" {
        Mock Write-Host { }
        $versions = @{
            "Archives" = @(
                @{ version = "8.1.0"; fileName = "php-8.1.0.zip" },
                @{ version = "8.1.1"; fileName = "php-8.1.1.zip" }
            )
        }
        $global:MockUserInput = ""
        
        $result = Select-Version -matchingVersions $versions
        
        $result | Should -Be $null
    }
    
    It "Returns null when user provides invalid input" {
        Mock Write-Host { }
        $versions = @{
            "Archives" = @(
                @{ version = "8.1.0"; fileName = "php-8.1.0.zip" },
                @{ version = "8.1.1"; fileName = "php-8.1.1.zip" }
            )
        }
        $global:MockUserInput = "invalid"
        
        $result = Select-Version -matchingVersions $versions
        
        $result | Should -Be $null
    }
    
    It "Should return selected version when user provides valid input" {
        Mock Write-Host { }
        $versions = @{
            "Archives" = @(
                @{ version = "8.1.0"; fileName = "php-8.1.0.zip" },
                @{ version = "8.1.1"; fileName = "php-8.1.1.zip" }
            )
        }
        $global:MockUserInput = "8.1.1"

        $result = Select-Version -matchingVersions $versions
        
        $result.version | Should -Be "8.1.1"
    }
}

Describe "Install-PHP Integration Tests" {
    BeforeEach {
        # Mock Write-Host { }
        Reset-MockState
        $global:MockUserInput = ""
        $global:MockFileSystem.Files["TestDrive:\pvm\pvm"] = "PVM executable"
        
        # Mock PHP versions response
        $mockLinks = @(
            @{ href = "/downloads/releases/php-8.1.15-Win32-vs16-x64.zip" }
        )
        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links $mockLinks
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links $mockLinks
    }
    
    It "Should install PHP successfully" {
        function Get-Matching-PHP-Versions { return $null }
        function Download-PHP-From-Url { return "TestDrive:\php"}
        
        $result = Install-PHP -version "8.1"
        
        $result.code | Should -Be 0
    }
    
    It "Should return -1 if version already installed" {
        $global:MockRegistry.Machine["php8.1"] = "C:\PHP\php-8.1"
        
        $result = Install-PHP -version "8.1"
        
        $result.code | Should -Be -1
    }
    
    It "Returns -1 when user declines family version install" {
        Mock Get-Current-PHP-Version { return @{ version = "7.4.9" } }
        Mock Get-Matching-PHP-Versions { return @("7.4.9", "8.0.9", "8.1.9", "8.1.12") }
        $global:MockUserInput = "n"
    
        $result = Install-PHP -version "8"
        
        $result.code | Should -Be -1
    }
    
    It "Installs PHP when user accepts family version install" {
        Mock Get-Matching-PHP-Versions { return $null }
        Mock Download-PHP-From-Url { return "TestDrive:\php"}
        Mock Get-Matching-PHP-Versions { return @("7.4.9", "8.0.9", "8.1.9", "8.1.12") }
        $global:MockUserInput = "y"
        
        $result = Install-PHP -version "8"
        
        $result.code | Should -Be 0
    }
    
    It "Returns -1 when user selection is null" {
        Mock Get-Matching-PHP-Versions { return $null }
        Mock Download-PHP-From-Url { return "TestDrive:\php"}
        Mock Select-Version { return $null }
        
        $result = Install-PHP -version "8.1"
        
        $result.code | Should -Be -1 
    }
    
    It "Returns -1 when user selection is already installed" {
        Mock Get-Matching-PHP-Versions { return $null }
        Mock Download-PHP-From-Url { return "TestDrive:\php"}
        Mock Select-Version { return @{ version = "8.1.15"; fileName = "php-8.1.15-Win32-vs16-x64.zip" } }
        Mock Is-PHP-Version-Installed -ParameterFilter { $version -eq "8.1.15" } -MockWith { return $true }
        
        $result = Install-PHP -version "8.1"
        
        $result.code | Should -Be -1 
    }
    
    It "Handles exception gracefully" {
        Mock Is-PHP-Version-Installed { return $false }
        Mock Get-Matching-PHP-Versions { return @("7.4.9", "8.0.9", "8.1.9", "8.1.12") }
        Mock Read-Host { throw "Test exception" }
        
        $result = Install-PHP -version "8.1"
        
        $result.code | Should -Be -1
    }
    
    It "Should handle no matching versions found" {
        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links @()
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links @()
        
        $result = Install-PHP -version "9.0"
        
        $result.code | Should -Be -1
    }
    
    It "Should handle download failure" {
        $global:MockFileSystem.DownloadFails = $true
        
        $result = Install-PHP -version "8.1"
        
        $result.code | Should -Be -1
    }
    
    It "Should prompt for family version when other versions exist" {
        $global:MockFileSystem.WebResponses = @{
            "$PHP_WIN_ARCHIVES_URL/php-8.1.15-Win32-vs16-x64.zip" = @{
                Content = "Mocked PHP 8.1.33 zip content"
            }
            "$PHP_WIN_ARCHIVES_URL/php-8.1.33-Win32-vs16-x64.zip" = @{
                Content = "Mocked PHP 8.1.33 zip content"
            }
            "$PHP_WIN_ARCHIVES_URL" = @{
                Content = '[{"version":"8.1.15","fileName":"php-8.1.15-Win32-vs16-x64.zip","url":"$PHP_WIN_RELEASES_URL/php-8.1.15-Win32-vs16-x64.zip"}]'
                Links = @()
            }
            "$PHP_WIN_RELEASES_URL" = @{
                Content = '[{"version":"8.2.0","fileName":"php-8.2.0-Win32-vs16-x64.zip","url":"$PHP_WIN_RELEASES_URL/php-8.2.0-Win32-vs16-x64.zip"}]'
                Links = @()
            }
        }
        
        Mock Get-PHP-Versions {
            return @{
                Releases = @{
                    filename = "php-8.1.33-Win32-vs16-x64.zip"
                    href = "/downloads/releases/php-8.1.33-Win32-vs16-x64.zip"
                    version = "8.1.33"
                }
            }
        }
        
        
        Set-EnvVar -name "php8.1" -value $null
        $global:MockRegistry.Machine["php8.1.0"] = "C:\PHP\php-8.1.0"
        $global:MockUserInput = "y"

        $result = Install-PHP -version "8.1"
        
        $result.code | Should -Be 0
    }
    
    It "Should cancel when user declines family version install" {
        $global:MockRegistry.Machine["php8.1.0"] = "C:\PHP\php-8.1.0"
        $global:MockUserInput = "n"
        
        $result = Install-PHP -version "8.1"
        
        $result.code | Should -Be -1
    }
}

Describe "Environment Variable Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
    }
    
    It "Get-All-EnvVars should handle registry errors" {
        $global:MockRegistryThrowException = $true
        
        $result = Get-All-EnvVars
        
        $result | Should -Be $null
    }
    
    It "Get-EnvVar-ByName should handle null/empty names" {
        $result = Get-EnvVar-ByName -name ""
        $result | Should -Be $null
        
        $result = Get-EnvVar-ByName -name "   "
        $result | Should -Be $null
        
        $result = Get-EnvVar-ByName -name $null
        $result | Should -Be $null
    }
    
    It "Get-EnvVar-ByName should handle registry errors" {
        $global:MockRegistryThrowException = $true
        
        $result = Get-EnvVar-ByName -name "TEST"
        
        $result | Should -Be $null
    }
    
    It "Set-EnvVar should handle null/empty names" {
        $result = Set-EnvVar -name "" -value "test"
        $result | Should -Be -1
        
        $result = Set-EnvVar -name "   " -value "test"
        $result | Should -Be -1
        
        $result = Set-EnvVar -name $null -value "test"
        $result | Should -Be -1
    }
    
    It "Set-EnvVar should handle registry errors" {
        $global:MockRegistryThrowException = $true
        
        $result = Set-EnvVar -name "TEST" -value "value"
        
        $result | Should -Be -1
    }
    
    It "Get-Installed-PHP-Versions should return sorted versions" {
        Mock Test-Path { return $true }
        Mock Get-All-Subdirectories {
            param ($path)
            return @(
                @{ Name = "8.1"; FullName = "path\php\8.1" }
                @{ Name = "7.4"; FullName = "path\php\7.4" }
                @{ Name = "8.2"; FullName = "path\php\8.2" }
                @{ Name = "8.0"; FullName = "path\php\8.0" }
                @{ Name = "5.6"; FullName = "path\php\5.6" }
            )
        }
        
        $result = Get-Installed-PHP-Versions
        
        $result | Should -Be @("5.6", "7.4", "8.0", "8.1", "8.2")
    }
    
    It "Get-Installed-PHP-Versions should handle registry errors" {
        $global:MockRegistryThrowException = $true
        
        $result = Get-Installed-PHP-Versions
        
        $result | Should -Be @()
    }
    
    It "Get-Matching-PHP-Versions should find matching versions" {
        Mock Test-Path { return $true }
        Mock Get-All-Subdirectories {
            param ($path)
            return @(
                @{ Name = "8.1.0"; FullName = "path\php\8.1.0" }
                @{ Name = "8.2.0"; FullName = "path\php\8.2.0" }
                @{ Name = "8.1.5"; FullName = "path\php\8.1.5" }
            )
        }
        
        $result = Get-Matching-PHP-Versions -version "8.1"
        
        $result | Should -Contain "8.1.0"
        $result | Should -Contain "8.1.5"
        $result | Should -Not -Contain "8.2.0"
    }
}


