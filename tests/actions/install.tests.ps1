
BeforeAll {
    Mock Write-Host {}
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    # Global test variables
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\install-drive"
    $PVMConfig.paths.logError = "$TEST_DRIVE\error.log"
    $PVMConfig.paths.storage = "$TEST_DRIVE\storage"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    $script:PHP_WIN_ARCHIVES_URL = $PVMConfig.links.phpWinArchives
    $script:PHP_WIN_RELEASES_URL = $PVMConfig.links.phpWinReleases

    # Mock registry for testing environment variables
    $script:MockRegistry = @{
        Machine = @{
            'Path' = 'C:\Windows\System32;C:\Program Files\Git\bin'
        }
    }

    $script:MockRegistryThrowException = $false
    $script:MockRegistryException = 'Registry access denied'

    # Mock file system
    $script:MockFileSystem = @{
        Directories = @()
        Files = @{}
        WebResponses = @{}
        DownloadFails = $false
    }

    # Test helper functions
    function Reset-MockState {
        $script:MockRegistryThrowException = $false
        $script:MockFileSystem.DownloadFails = $false
        $script:MockFileSystem.WebResponses = @{}
        $script:MockFileSystem.Files = @{}
        $script:MockFileSystem.Directories = @()
        $script:MockRegistry = @{
            Machine = @{
                'Path' = 'C:\Windows\System32;C:\Program Files\Git\bin'
            }
        }
    }

    function Set-MockWebResponse {
        param ($url, $content, $links = @())
        $script:MockFileSystem.WebResponses[$url] = @{
            Content = $content
            Links = $links
        }
    }

    # Mock functions for testing
    Mock Add-LogEntry {
        param ($logPath, $message, $data)
        Write-Host -Object "LOG: $message - $data"
        return $true
    }

    Mock Get-Web-Response {
        param ($Uri, $OutFile = $null)

        if ($script:MockFileSystem.DownloadFails) {
            throw 'Network error'
        }

        if ($script:MockFileSystem.WebResponses.ContainsKey($Uri)) {
            $response = $script:MockFileSystem.WebResponses[$Uri]
            if ($OutFile) {
                $script:MockFileSystem.Files[$OutFile] = 'Downloaded content'
                return
            }
            return @{
                Content = $response.Content
                Links = $response.Links
            }
        }

        throw "URL not mocked: $Uri"
    }

    Mock Test-Path {
        param ([string]$Path, $PathType = $null)

        if ($PathType -eq 'Container') {
            return $script:MockFileSystem.Directories -contains $Path
        }
        return $script:MockFileSystem.Files.ContainsKey($Path)
    }

    Mock Read-Host {
        param ($Prompt)
        return $script:MockUserInput
    }

    Mock Test-Not-Admin { return $false }

    # Environment variable wrapper functions
    Mock Get-All-EnvVars-Core {
        if ($script:MockRegistryThrowException) {
            throw $script:MockRegistryException
        }

        $result = @{}
        $script:MockRegistry.Machine.GetEnumerator() | ForEach-Object { $result[$_.Key] = $_.Value }
        return $result
    }

    Mock Get-EnvVar-ByName-Core {
        param ($name)

        if ($script:MockRegistryThrowException) {
            throw $script:MockRegistryException
        }

        return $script:MockRegistry.Machine[$name]
    }

    Mock Set-EnvVar-Core {
        param ($name, $value)

        if ($script:MockRegistryThrowException) {
            throw $script:MockRegistryException
        }

        if ($null -eq $value) {
            $script:MockRegistry.Machine.Remove($name)
        } else {
            $script:MockRegistry.Machine[$name] = $value
        }
    }
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

# Test Suites
Describe "Get-Source-Urls Tests" {
    It "Should return ordered hashtable with correct URLs" {
        $urls = Get-Source-Urls
        $urls | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $urls['Archives'] | Should -Be 'https://windows.php.net/downloads/releases/archives'
        $urls['Releases'] | Should -Be 'https://windows.php.net/downloads/releases'
    }
}

Describe "Get-Latest-PHP-Version Tests" {
    BeforeEach {
        Reset-MockState
        Mock Write-Host {}
    }

    It "Should return the latest available version" {
        $mockLinks = @(
            @{ href = '/downloads/releases/php-8.0.10-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.1.12-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.2.1-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.1.15-nts-Win32-vs16-x64.zi' }
        )

        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links $mockLinks
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links $mockLinks

        $result = Get-Latest-PHP-Version

        $result | Should -Not -BeNullOrEmpty
        $result.version | Should -Be '8.2.1'
        $result.arch | Should -Be 'x64'
        $result.BuildType | Should -Be 'TS'
    }

    It "Should filter by architecture and build type" {
        $mockLinks = @(
            @{ href = '/downloads/releases/php-8.3.0-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.3.1-nts-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.3.2-Win32-vs16-x86.zip' },
            @{ href = '/downloads/releases/php-8.3.3-nts-Win32-vs16-x86.zip' }
        )

        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links $mockLinks
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links $mockLinks

        $result = Get-Latest-PHP-Version -arch 'x86' -buildType 'nts'

        $result | Should -Not -BeNullOrEmpty
        $result.version | Should -Be '8.3.3'
        $result.arch | Should -Be 'x86'
        $result.BuildType | Should -Be 'nts'
    }

    It "Should return null when no versions are available" {
        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links @()
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links @()

        $result = Get-Latest-PHP-Version

        $result | Should -BeNullOrEmpty
    }

    It "Should handle exception gracefully" {
        Mock Get-Source-Urls { throw 'Error' }

        $result = Get-Latest-PHP-Version

        $result | Should -BeNullOrEmpty
    }

    It "Should read from cache if available" {
        Mock Get-OrUpdateCache {
            return @(
                @{version = '5.6'; arch = 'x64'; buildType = 'nts'}
                @{version = '5.6'; arch = 'x86'; buildType = 'nts'}
                @{version = '7.4'; arch = 'x64'; buildType = 'nts'}
                @{version = '8.0'; arch = 'x64'; buildType = 'nts'}
                @{version = '8.0'; arch = 'x86'; buildType = 'nts'}
            )
        }

        $result = Get-Latest-PHP-Version

        $result.version | Should -Be '8.0'
        $result.arch | Should -Be 'x64'
        $result.BuildType | Should -Be 'nts'
    }

    It "Should read from source if cache is empty" {
        Mock Get-Data-From-Cache { return @() }

        $mockLinks = @(
            @{ href = '/downloads/releases/php-8.3.0-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.3.1-nts-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.3.2-Win32-vs16-x86.zip' },
            @{ href = '/downloads/releases/php-8.3.3-nts-Win32-vs16-x86.zip' }
        )

        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links $mockLinks
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links $mockLinks

        $result = Get-Latest-PHP-Version

        $result | Should -Not -BeNullOrEmpty
    }

    It "Should return empty array when exceptions occur" {
        Mock Get-OrUpdateCache { throw 'Test exception' }

        $result = Get-Latest-PHP-Version

        $result | Should -BeNullOrEmpty
    }

    It "Should return empty array when exceptions occur in Get-Web-Response" {
        Mock Get-Web-Response { throw 'Test exception' }

        $result = Get-Latest-PHP-Version

        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-PHP-Versions-From-Url Tests" {
    BeforeEach {
        Reset-MockState
    }

    It "Should parse PHP versions correctly" {
        $mockLinks = @(
            @{ href = '/downloads/releases/php-8.1.0-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.1.1-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-debug-8.1.0-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.1.0-nts-Win32-vs16-x64.zip' }
        )
        Set-MockWebResponse -url 'https://test.com' -links $mockLinks

        $result = Get-PHP-Versions-From-Url -url 'https://test.com' -version '8.1'

        $result.Count | Should -Be 3
        $result[0].version | Should -Be '8.1.0'
        $result[1].version | Should -Be '8.1.1'
        $result[2].version | Should -Be '8.1.0'
    }

    It "Should handle network errors gracefully" {
        $script:MockFileSystem.DownloadFails = $true

        $result = Get-PHP-Versions-From-Url -url 'https://test.com' -version '8.1'

        $result | Should -Be @()
    }

    It "Should filter out debug and nts versions" {
        $mockLinks = @(
            @{ href = '/downloads/releases/php-8.1.0-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-debug-8.1.0-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-devel-8.1.0-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.1.0-nts-Win32-vs16-x64.zip' }
        )
        Set-MockWebResponse -url 'https://test.com' -links $mockLinks

        $result = Get-PHP-Versions-From-Url -url 'https://test.com' -version '8.1'

        $result.Length | Should -Be 2
        $result[0].version | Should -Be '8.1.0'
        $result[1].version | Should -Be '8.1.0'
    }
}

Describe "Get-PHP-Versions Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
    }

    It "Should return versions for x64 architecture" {
        $mockLinks = @(
            @{ href = '/downloads/releases/php-8.1.0-Win32-vs16-x64.zip' },
            @{ href = '/downloads/releases/php-8.1.0-Win32-vs16-x86.zip' }
        )

        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links $mockLinks
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links $mockLinks

        $result = Get-PHP-Versions -version '8.1' -arch 'x64'

        $result.Count | Should -BeGreaterThan 0
    }

    It "Should return versions for NTS Build type" {
        $mockLinks = @(
            @{ href = '/downloads/releases/php-8.1.0-Win32-vs16-nts-x64.zip' },
            @{ href = '/downloads/releases/php-8.1.0-Win32-vs16-x64.zip' }
        )

        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links $mockLinks
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links $mockLinks

        $result = Get-PHP-Versions -version '8.1' -buildType 'nts'

        $result.Count | Should -BeGreaterThan 0
    }

    It "Should handle exception gracefully" {
        Mock Get-Source-Urls { throw 'Error' }

        $result = Get-PHP-Versions -version '8.1'

        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It "Should skip when fetched is empty after filtering" {
        Mock Get-PHP-Versions-From-Url { return @(
            @{ fileName = 'php-8.1.0-Win32-vs16-x64.zip'; version = '8.1.0'; buildType = 'nts'; arch = 'x86' }
            @{ fileName = 'php-8.1.0-Win32-vs16-x64.zip'; version = '8.1.0'; buildType = 'ts'; arch = 'x86' }
        ) }

        $result = Get-PHP-Versions -version '8.1' -arch 'x64'

        $result.Count | Should -Be 0
    }
}

Describe "Get-PHP" {
    BeforeAll {
        Mock New-Directory { return 0 }
        Mock Get-PHP-From-Url { return "$TEST_DRIVE\php" }
    }

    It "Should download PHP successfully" {
        $result = Get-PHP -versionObject @{ fileName = 'php-8.1.0-Win32-vs16-x64.zip'; version = '8.1.0' }
        $result | Should -Be "$TEST_DRIVE\php"
    }

    It "Returns null if directory creation fails" {
        Mock New-Directory { return -1 }
        $result = Get-PHP -versionObject @{ fileName = 'php-8.1.0-Win32-vs16-x64.zip'; version = '8.1.0' }
        $result | Should -BeNullOrEmpty
    }

    It "Handles exception gracefully" {
        Mock Get-Source-Urls { throw 'Test exception' }
        $result = Get-PHP -versionObject @{ fileName = 'php-8.1.0-Win32-vs16-x64.zip'; version = '8.1.0' }
        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-PHP-From-Url Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
    }

    It "Should download file successfully" {
        $urls = Get-Source-Urls
        $versionObject = @{ fileName = 'php-8.1.0-Win32-vs16-x64.zip'; version = '8.1.0' }

        # Mock the actual URL that will be called
        $expectedUrl = "$($urls['Archives'])/php-8.1.0-Win32-vs16-x64.zip"
        Set-MockWebResponse -url $expectedUrl -content 'Downloaded content'

        $result = Get-PHP-From-Url -destination "$TEST_DRIVE\php" -url $expectedUrl -versionObject $versionObject

        $result | Should -Be "$TEST_DRIVE\php"
        $script:MockFileSystem.Files.ContainsKey("$TEST_DRIVE\php\php-8.1.0-Win32-vs16-x64.zip") | Should -Be $true
    }

    It "Should handle download failure" {
        $script:MockFileSystem.DownloadFails = $true
        $versionObject = @{ fileName = 'php-8.1.0-Win32-vs16-x64.zip' }

        $result = Get-PHP-From-Url -destination "$TEST_DRIVE\php" -url 'https://test.com/php.zip' -versionObject $versionObject

        $result | Should -Be $null
    }
}

Describe "Expand-And-Configure Tests" {
    BeforeAll {
        Mock Add-Type { param ($AssemblyName) }
        Mock Copy-Item {
            param ($Path, $Destination)
            $script:MockFileSystem.Files[$Destination] = 'Copied content'
        }
        Mock Remove-Item {
            param ($Path)
            if ($script:MockFileSystem.Files.ContainsKey($Path)) {
                $script:MockFileSystem.Files.Remove($Path)
            }
        }
    }

    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
        $script:MockFileSystem.Files["$TEST_DRIVE\php\php.ini-development"] = 'development config'
    }

    It "Should extract and configure PHP" {
        Mock Expand-Zip { }
        { Expand-And-Configure -path "$TEST_DRIVE\php.zip" -fileNamePath "$TEST_DRIVE\php" } | Should -Not -Throw
        $script:MockFileSystem.Files.ContainsKey("$TEST_DRIVE\php\php.ini") | Should -Be $true
    }

    It "Should handle extraction failure" {
        Mock Remove-Item { throw 'Test exception' }

        { Expand-And-Configure -path "$TEST_DRIVE\php.zip" -fileNamePath "$TEST_DRIVE\php" } | Should -Not -Throw
    }
}

Describe "Set-Opcache Tests" {
    BeforeAll {
        Mock Set-Content {
            param ($Path, $Value, $Encoding = $null)
            $script:MockFileSystem.Files[$Path] = $Value -join "`n"
        }
        Mock Get-Content {
            param ([string]$Path)
            if ($script:MockFileSystem.Files.ContainsKey($Path)) {
                $content = $script:MockFileSystem.Files[$Path]
                return $content -split "`n"
            }
            throw "File not found in mock system: $Path"
        }
    }
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
        $script:MockFileSystem.Files["$TEST_DRIVE\php\php.ini"] = @"
;extension_dir = "ext"
;zend_extension = opcache
;opcache.enable = 1
;opcache.enable_cli = 1
"@
    }

    It "Should enable Opcache successfully" {
        $code = Set-Opcache -version '8.1' -phpPath "$TEST_DRIVE\php"

        $code | Should -Be 0
        $content = $script:MockFileSystem.Files["$TEST_DRIVE\php\php.ini"]
        $content | Should -Match 'extension_dir = "ext"'
        $content | Should -Match 'zend_extension = opcache'
        $content | Should -Match 'opcache\.enable = 1'
        $content | Should -Match 'opcache\.enable_cli = 1'
    }

    It "Should handle missing php.ini" {
        $script:MockFileSystem.Files.Remove("$TEST_DRIVE\php\php.ini")

        $code = Set-Opcache -version '8.1' -phpPath "$TEST_DRIVE\php"
        $code | Should -Be -1
    }

    It "Should handle exception gracefully" {
        Mock Get-Content { throw 'Error reading file' }

        $code = Set-Opcache -version '8.1' -phpPath "$TEST_DRIVE\php"
        $code | Should -Be -1
    }
}

Describe "Select-Version Tests" {
    BeforeEach {
        Reset-MockState
        $script:MockUserInput = ''
    }

    It "Should return single version when only one available" {
        Mock Write-Host { }
        $versions = @{
            'Archives' = @(@{ version = '8.1.0'; fileName = 'php-8.1.0.zip' })
        }

        $result = Select-Version -matchingVersions $versions

        $result.version | Should -Be '8.1.0'
    }

    It "Should return null when user cancels" {
        Mock Write-Host { }
        $versions = @{
            'Archives' = @(
                @{ version = '8.1.0'; fileName = 'php-8.1.0.zip' },
                @{ version = '8.1.1'; fileName = 'php-8.1.1.zip' }
            )
        }
        $script:MockUserInput = ''

        $result = Select-Version -matchingVersions $versions

        $result | Should -Be $null
    }

    It "Returns null when user provides invalid input" {
        Mock Write-Host { }
        $versions = @{
            'Archives' = @(
                @{ version = '8.1.0'; fileName = 'php-8.1.0.zip' },
                @{ version = '8.1.1'; fileName = 'php-8.1.1.zip' }
            )
        }
        $script:MockUserInput = 'invalid'

        $result = Select-Version -matchingVersions $versions

        $result | Should -Be $null
    }

    It "Should return selected version when user provides valid input" {
        Mock Write-Host { }
        $versions = @{
            'Archives' = @(
                @{ version = '8.1.0'; arch = 'x64'; buildType = 'TS'; fileName = 'php-8.1.0.zip' },
                @{ version = '8.1.1'; arch = 'x64'; buildType = 'TS'; fileName = 'php-8.1.1.zip' }
            )
        }
        $script:MockUserInput = '1'

        $result = Select-Version -matchingVersions $versions -version '8.1' -arch 'x64' -buildType 'TS'

        $result.version | Should -Be '8.1.1'
    }
}

Describe "Install-PHP Integration Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
        $script:MockUserInput = ''
        $script:MockFileSystem.Files["$TEST_DRIVE\pvm\pvm"] = 'PVM executable'

        # Mock PHP versions response
        $mockLinks = @(
            @{ href = '/downloads/releases/php-8.1.15-Win32-vs16-x64.zip' }
        )
        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links $mockLinks
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links $mockLinks
    }

    It "Should install PHP successfully" {
        Mock Get-Matching-PHP-Versions { return $null }

        Mock Get-PHP-From-Url { return "$TEST_DRIVE\php" }

        $result = Install-PHP -version '8.1'

        $result.code | Should -Be 0
    }

    It "Should return -1 if version already installed" {
        $result = Install-PHP -version '8.1'

        $result.code | Should -Be -1
    }

    It "Returns -1 when user declines family version install" {
        Mock Get-Current-PHP-Version { return @{ version = '7.4.9' } }
        Mock Get-Matching-PHP-Versions { return @(
            @{ version = '7.4.9'; arch = 'x64'; buildType = 'TS'; fileName = 'php-7.4.9-Win32-vs16-x64.zip' },
            @{ version = '8.0.9'; arch = 'x64'; buildType = 'TS'; fileName = 'php-8.0.9-Win32-vs16-x64.zip' },
            @{ version = '8.1.9'; arch = 'x64'; buildType = 'TS'; fileName = 'php-8.1.9-Win32-vs16-x64.zip' },
            @{ version = '8.1.12'; arch = 'x64'; buildType = 'TS'; fileName = 'php-8.1.12-Win32-vs16-x64.zip' }
        ) }
        $script:MockUserInput = 'n'

        $result = Install-PHP -version '8'

        $result.code | Should -Be -1
    }

    It "Installs PHP when user accepts family version install" {
        Mock Get-Matching-PHP-Versions { return $null }
        Mock Get-PHP-From-Url { return "$TEST_DRIVE\php" }
        Mock Get-Matching-PHP-Versions { return @('7.4.9', '8.0.9', '8.1.9', '8.1.12') }
        $script:MockUserInput = 'y'

        $result = Install-PHP -version '8'

        $result.code | Should -Be 0
    }

    It "Returns -1 when user selection is null" {
        Mock Get-Matching-PHP-Versions { return $null }
        Mock Get-PHP-From-Url { return "$TEST_DRIVE\php" }
        Mock Select-Version { return $null }

        $result = Install-PHP -version '8.1'

        $result.code | Should -Be -1
    }

    It "Returns -1 when user selection is already installed" {
        Mock Get-Matching-PHP-Versions { return $null }
        Mock Get-PHP-From-Url { return "$TEST_DRIVE\php" }
        Mock Select-Version { return @{ version = '8.1.15'; fileName = 'php-8.1.15-Win32-vs16-x64.zip' } }
        Mock Test-PHP-Version-Installed { return $true }

        $result = Install-PHP -version '8.1'

        $result.code | Should -Be -1
    }

    It "Handles exception gracefully" {
        Mock Test-PHP-Version-Installed { return $false }
        Mock Get-Matching-PHP-Versions { return @('7.4.9', '8.0.9', '8.1.9', '8.1.12') }
        Mock Read-Host { throw 'Test exception' }

        $result = Install-PHP -version '8.1'

        $result.code | Should -Be -1
    }

    It "Should handle no matching versions found" {
        Set-MockWebResponse -url $PHP_WIN_ARCHIVES_URL -links @()
        Set-MockWebResponse -url $PHP_WIN_RELEASES_URL -links @()

        $result = Install-PHP -version '9.0'

        $result.code | Should -Be -1
    }

    It "Should handle download failure" {
        $script:MockFileSystem.DownloadFails = $true

        $result = Install-PHP -version '8.1'

        $result.code | Should -Be -1
    }

    It "Should prompt for family version when other versions exist" {
        $script:MockFileSystem.WebResponses = @{
            "$PHP_WIN_ARCHIVES_URL/php-8.1.15-Win32-vs16-x64.zip" = @{
                Content = 'Mocked PHP 8.1.33 zip content'
            }
            "$PHP_WIN_ARCHIVES_URL/php-8.1.33-Win32-vs16-x64.zip" = @{
                Content = 'Mocked PHP 8.1.33 zip content'
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
                    filename = 'php-8.1.33-Win32-vs16-x64.zip'
                    href = '/downloads/releases/php-8.1.33-Win32-vs16-x64.zip'
                    version = '8.1.33'
                }
            }
        }

        Set-EnvVar -name 'php8.1' -value $null
        $script:MockUserInput = 'y'

        $result = Install-PHP -version '8.1'

        $result.code | Should -Be 0
    }

    It "Should cancel when user declines family version install" {
        $script:MockUserInput = 'n'

        $result = Install-PHP -version '8.1'

        $result.code | Should -Be -1
    }
}

Describe "Environment Variable Tests" {
    BeforeEach {
        Mock Write-Host { }
        Reset-MockState
    }

    It "Get-All-EnvVars should handle registry errors" {
        $script:MockRegistryThrowException = $true

        $result = Get-All-EnvVars

        $result | Should -Be $null
    }

    It "Get-EnvVar-ByName should handle null/empty names" {
        $result = Get-EnvVar-ByName -name ''
        $result | Should -Be $null

        $result = Get-EnvVar-ByName -name '   '
        $result | Should -Be $null

        $result = Get-EnvVar-ByName -name $null
        $result | Should -Be $null
    }

    It "Get-EnvVar-ByName should handle registry errors" {
        $script:MockRegistryThrowException = $true

        $result = Get-EnvVar-ByName -name 'TEST'

        $result | Should -Be $null
    }

    It "Set-EnvVar should handle null/empty names" {
        $result = Set-EnvVar -name '' -value 'test'
        $result | Should -Be -1

        $result = Set-EnvVar -name '   ' -value 'test'
        $result | Should -Be -1

        $result = Set-EnvVar -name $null -value 'test'
        $result | Should -Be -1
    }

    It "Set-EnvVar should handle registry errors" {
        $script:MockRegistryThrowException = $true

        $result = Set-EnvVar -name 'TEST' -value 'value'

        $result | Should -Be -1
    }

    It "Get-Installed-PHP-Versions should return sorted versions" {
        Mock Save-Cached-Data { return 0 }
        Mock Test-Can-Use-Cache { return $false }
        Mock Get-Installed-PHP-Versions-From-Disk {
            return @(
                @{version = '8.2'; arch = 'x64'; buildType = 'nts'}
                @{version = '8.1'; arch = 'x64'; buildType = 'nts'}
                @{version = '8.0'; arch = 'x64'; buildType = 'nts'}
                @{version = '7.4'; arch = 'x64'; buildType = 'nts'}
                @{version = '5.6'; arch = 'x64'; buildType = 'nts'}
            )
        }

        $result = Get-Installed-PHP-Versions

        $result[0].version | Should -Be '5.6'
        $result[1].version | Should -Be '7.4'
    }

    It "Get-Installed-PHP-Versions should handle registry errors" {
        $script:MockRegistryThrowException = $true

        $result = Get-Installed-PHP-Versions

        $result | Should -Be @()
    }

    It "Get-Matching-PHP-Versions should find matching versions" {
        Mock Get-Installed-PHP-Versions {
            return @(
                @{version = '8.1.0'; arch = 'x64'; buildType = 'nts'}
                @{version = '8.2.0'; arch = 'x64'; buildType = 'nts'}
                @{version = '8.1.5'; arch = 'x64'; buildType = 'nts'}
            )
        }
        $result = Get-Matching-PHP-Versions -version '8.1'

        $result | Where-Object { $_.version -eq '8.1.0' } | Should -Not -BeNullOrEmpty
        $result | Where-Object { $_.version -eq '8.1.5' } | Should -Not -BeNullOrEmpty
        $result | Where-Object { $_.link -eq '8.2.0' } | Should -BeNullOrEmpty
    }
}
