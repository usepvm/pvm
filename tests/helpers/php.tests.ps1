
BeforeAll {
    Mock Write-Host {}
    
    $testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $testIniPath = "$testDrivePath\php.ini"
    function Reset-Ini-Content {
    # Create a test php.ini file
    @"
memory_limit = 128M
;extension=php_xdebug.dll
extension=php_curl.dll
zend_extension=php_opcache.dll
display_errors = On
max_execution_time = 30
;upload_max_filesize = 2M
"@ | Set-Content -Path $testIniPath -Encoding UTF8
    }

    # Create initial ini content first
    Reset-Ini-Content
}

Describe "Get-PHPInstallInfo" {
    Context "When PHP DLL exists" {
        It "Returns PHP install info with NTS build type" {
            $testPath = 'TestDrive:\php\8.3'
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null

            # Create a mock NTS DLL file
            New-Item -Path "$testPath\php8nts.dll" -ItemType File -Force | Out-Null

            Mock Get-ChildItem {
                return @{
                    VersionInfo = @{ ProductVersion = '8.3.0' }
                    Name = 'php8nts.dll'
                    FullName = "$testPath\php8nts.dll"
                }
            }

            Mock Get-BinaryArchitecture-From-DLL { return 'x64' }

            $result = Get-PHPInstallInfo -path $testPath

            $result | Should -Not -BeNullOrEmpty
            $result.Version | Should -Be '8.3.0'
            $result.Arch | Should -Be 'x64'
            $result.BuildType | Should -Be 'NTS'
            $result.Dll | Should -Be 'php8nts.dll'
            $result.InstallPath | Should -Be $testPath
        }

        It "Returns PHP install info with TS build type" {
            $testPath = 'TestDrive:\php\8.2'
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null

            Mock Get-ChildItem {
                return @{
                    VersionInfo = @{ ProductVersion = '8.2.5' }
                    Name = 'php8ts.dll'
                    FullName = "$testPath\php8ts.dll"
                }
            }

            Mock Get-BinaryArchitecture-From-DLL { return 'x86' }

            $result = Get-PHPInstallInfo -path $testPath

            $result.BuildType | Should -Be 'TS'
            $result.Arch | Should -Be 'x86'
            $result.Version | Should -Be '8.2.5'
        }

        It "Returns first DLL when multiple match" {
            $testPath = 'TestDrive:\php\8.1'

            Mock Get-ChildItem {
                return @(
                    @{
                        VersionInfo = @{ ProductVersion = '8.1.0' }
                        Name = 'php81nts.dll'
                        FullName = "$testPath\php81nts.dll"
                    },
                    @{
                        VersionInfo = @{ ProductVersion = '8.1.0' }
                        Name = 'php81ts.dll'
                        FullName = "$testPath\php81ts.dll"
                    }
                ) | Select-Object -First 1
            }

            Mock Get-BinaryArchitecture-From-DLL { return 'x64' }

            $result = Get-PHPInstallInfo -path $testPath
            $result.Dll | Should -Be 'php81nts.dll'
        }
    }

    Context "When PHP DLL does not exist" {
        It "Returns null when no DLL found" {
            $testPath = 'TestDrive:\php\empty'
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null

            Mock Get-ChildItem { return $null }

            $result = Get-PHPInstallInfo -path $testPath
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Get-Source-Urls" {
    It "Should return correct URL structure" {
        $result = Get-Source-Urls

        $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $result.Keys.Count | Should -Be 2
        $result.Keys -contains 'Archives' | Should -Be $true
        $result.Keys -contains 'Releases' | Should -Be $true
    }

    It "Should return correct Archive URL" {
        $result = Get-Source-Urls
        $result['Archives'] | Should -Be 'https://windows.php.net/downloads/releases/archives'
    }

    It "Should return correct Releases URL" {
        $result = Get-Source-Urls
        $result['Releases'] | Should -Be 'https://windows.php.net/downloads/releases'
    }
}

Describe "Get-Installed-PHP-Versions" {
    Context "When environment variables contain PHP versions" {
        It "Should return sorted PHP versions" {
            $script:STORAGE_PATH = 'C:\mock\path'
            $script:LOG_ERROR_PATH = 'C:\mock\error'
            Mock Cache-Data { return 0 }
            Mock Can-Use-Cache { return $false }
            Mock Get-Installed-PHP-Versions-From-Directory {
                return @(
                    @{version = '5.6'; arch = 'x64'; buildType = 'nts'}
                    @{version = '7.4'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.0'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.1'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.2'; arch = 'x64'; buildType = 'nts'}
                )
            }

            $result = Get-Installed-PHP-Versions
            $expected = @('5.6', '7.4', '8.0', '8.1', '8.2')

            $result.Count | Should -Be $expected.Count
            for ($i = 0; $i -lt $result.Count; $i++) {
                $result[$i].version | Should -Be $expected[$i]
            }
        }

        It "Should return empty array when no PHP versions are found" {
            Mock Can-Use-Cache { return $false }
            Mock Get-Installed-PHP-Versions-From-Directory { return @() }

            $result = Get-Installed-PHP-Versions
            $result.Count | Should -Be 0
        }

        It "Should handle single digit versions" {
            Mock Cache-Data { return 0 }
            Mock Can-Use-Cache { return $false }
            Mock Get-Installed-PHP-Versions-From-Directory {
                return @(
                    @{version = '7.4'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.1'; arch = 'x64'; buildType = 'nts'}
                )
            }

            $result = Get-Installed-PHP-Versions
            $result.Count | Should -Be 2
            $result[0].version | Should -Be '7.4'
            $result[1].version | Should -Be '8.1'
        }

        It "Should filter the right arch input" {
            Mock Get-OrUpdateCache {
                return @(
                    @{version = '5.6'; arch = 'x64'; buildType = 'nts'}
                    @{version = '5.6'; arch = 'x86'; buildType = 'nts'}
                    @{version = '7.4'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.0'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.0'; arch = 'x86'; buildType = 'nts'}
                )
            }

            $result = Get-Installed-PHP-Versions -arch 'x86'

            $result.Count | Should -Be 2
            $result[0].version | Should -Be '5.6'
            $result[1].version | Should -Be '8.0'
        }

        It "Should filter the right build type input" {
            Mock Get-OrUpdateCache {
                return @(
                    @{version = '5.6'; arch = 'x64'; buildType = 'nts'}
                    @{version = '5.6'; arch = 'x64'; buildType = 'ts'}
                    @{version = '7.4'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.0'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.0'; arch = 'x64'; buildType = 'ts'}
                )
            }

            $result = Get-Installed-PHP-Versions -buildType 'nts'

            $result.Count | Should -Be 3
            $result[0].version | Should -Be '5.6'
            $result[1].version | Should -Be '7.4'
            $result[2].version | Should -Be '8.0'
        }
    }

    Context "When exceptions occur" {
        It "Should return empty array and log error when Get-Installed-PHP-Versions-From-Directory throws exception" {
            Mock Get-OrUpdateCache { throw 'Test exception' }
            Mock Log-Data { return 0 }

            $result = Get-Installed-PHP-Versions
            $result.Count | Should -Be 0

            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq 'Get-Installed-PHP-Versions - Failed to retrieve installed PHP versions'
            }
        }
    }
}

Describe "Get-UserSelected-PHP-Version" {
    It "Should return null when no installed versions are provided" {
        $result = Get-UserSelected-PHP-Version -installedVersions @()
        $result | Should -Be $null
    }

    It "Should return first version when only one is provided" {
        $result = Get-UserSelected-PHP-Version -installedVersions @(@{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'})
        $result.version | Should -Be '8.1'
    }

    It "Should return null when no version is selected" {
        Mock Read-Host { return '' }
        Mock Write-Host { }

        $result = Get-UserSelected-PHP-Version -installedVersions @(
            @{ version = '7.4'; Arch = 'x64'; BuildType = 'ts'}
            @{ version = '8.0'; Arch = 'x64'; BuildType = 'ts'}
            @{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'}
        )
        $result.code | Should -Be -1
    }

    It "Should prompt user and return selected version when multiple are provided" {
        Mock Read-Host { return '2' }
        Mock Write-Host { }

        $result = Get-UserSelected-PHP-Version -installedVersions @(
            @{ version = '7.4'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\7.4'}
            @{ version = '8.0'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\8.0'}
            @{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\8.1'}
        )
        $result.version | Should -Be '8.1'
        $result.code | Should -Be 0
        $result.path | Should -Be 'C:\php\8.1'
    }

    It "Should print current next to active php version" {
        Mock Read-Host { return '2' }
        Mock Write-Host { }
        Mock Get-Current-PHP-Version { return @{ version = '8.0'; arch = 'x64'; buildType = 'ts'}}

        $result = Get-UserSelected-PHP-Version -installedVersions @(
            @{ version = '7.4'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\7.4'}
            @{ version = '8.0'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\8.0'}
            @{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\8.1'}
        )

        $version = '8.0 '.PadRight(15, '.')
        Assert-MockCalled Write-Host -ParameterFilter { $Object -eq " [1] $version x64 ts (Current)" }
    }
}

Describe "Get-Matching-PHP-Versions" {
    Context "When matching versions exist" {
        It "Should return matching versions for partial version number" {
            Mock Get-Installed-PHP-Versions { return @(
                @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                @{Version = '8.0'; Arch = 'x64'; BuildType = 'NTS'}
                @{Version = '7.4'; Arch = 'x64'; BuildType = 'NTS'}
            )}

            $result = Get-Matching-PHP-Versions -version '8'
            $expected = @('8.0', '8.1', '8.2')

            $result.Count | Should -Be $expected.Count
            $result | Where-Object { $_.version -eq '8.2' } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.version -eq '8.1' } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.version -eq '8.0' } | Should -Not -BeNullOrEmpty
        }

        It "Should return exact match for pattern version number" {
            Mock Get-Installed-PHP-Versions {
                return @(
                    @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.9'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.0'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '7.4'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }

            $result = Get-Matching-PHP-Versions -version '8.1'
            $result.Count | Should -Be 2
            $result[0].version | Should -Be '8.1.9'
        }

        It "Should return exact match for full version number" {
            Mock Get-Installed-PHP-Versions {
                return @(
                    @{Version = '7.4'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.0'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.9'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }

            $result = Get-Matching-PHP-Versions -version '8.1.9'
            $result.Length | Should -Be 1
            $result.version | Should -Be '8.1.9'
        }

        It "Should return empty array when no matches found" {
            Mock Get-Installed-PHP-Versions {
                return @('php7.4', 'php8.0', 'php8.1')
            }
            Mock Log-Data { return 0 }

            $result = Get-Matching-PHP-Versions -version '9'
            $result.Count | Should -Be 0
        }
    }

    Context "When exceptions occur" {
        It "Should return null and log error when Get-Installed-PHP-Versions throws exception" {
            Mock Get-Installed-PHP-Versions { throw 'Test exception' }
            Mock Log-Data { return 0 }

            $result = Get-Matching-PHP-Versions -version '8.1'
            $result | Should -Be $null

            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq 'Get-Matching-PHP-Versions - Failed to check if PHP version 8.1 is installed'
            }
        }
    }
}

Describe "Is-PHP-Version-Installed" {
    Context "When version exists" {
        It "Should return true for installed version" {
            Mock Get-Matching-PHP-Versions {
                param ($version)
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.2'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }

            $result = Is-PHP-Version-Installed -version @{version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
            $result | Should -Be $true
        }

        It "Should return false for non-installed version" {
            Mock Get-Matching-PHP-Versions {
                param ($version)
                return @(
                    @{Version = '8.1.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.2'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }

            $result = Is-PHP-Version-Installed -version @{version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
            $result | Should -Be $null
        }

        It "Should return false when no matching versions found" {
            Mock Get-Matching-PHP-Versions {
                return @()
            }

            $result = Is-PHP-Version-Installed -version '9.0'
            $result | Should -Be $null
        }
    }

    Context "When exceptions occur" {
        It "Should return false and log error when Get-Matching-PHP-Versions throws exception" {
            Mock Get-Matching-PHP-Versions { throw 'Test exception' }
            Mock Log-Data { return 0 }

            $result = Is-PHP-Version-Installed -version '8.1'
            $result | Should -Be $false

            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq 'Is-PHP-Version-Installed - Failed to check if PHP version 8.1 is installed'
            }
        }
    }
}

Describe "Refresh-Installed-PHP-Versions-Cache" {
    Context "When cache is successfully refreshed" {
        It "Should return 0 on success" {
            Mock Get-Installed-PHP-Versions-From-Directory {
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }
            Mock Cache-Data { return 0 }

            $result = Refresh-Installed-PHP-Versions-Cache
            $result | Should -Be 0
        }

        It "Should call Get-Installed-PHP-Versions-From-Directory" {
            Mock Get-Installed-PHP-Versions-From-Directory {
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }
            Mock Cache-Data { return 0 }

            $result = Refresh-Installed-PHP-Versions-Cache

            Assert-MockCalled Get-Installed-PHP-Versions-From-Directory -Exactly 1
        }

        It "Should call Cache-Data with installed_php_versions file and depth 1" {
            Mock Get-Installed-PHP-Versions-From-Directory {
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }
            Mock Cache-Data { return 0 }

            $result = Refresh-Installed-PHP-Versions-Cache

            Assert-MockCalled Cache-Data -Exactly 1 -ParameterFilter {
                $cacheFileName -eq 'installed_php_versions' -and $depth -eq 1
            }
        }

        It "Should cache the results from Get-Installed-PHP-Versions-From-Directory" {
            $mockVersions = @(
                @{Version = '7.4'; Arch = 'x64'; BuildType = 'NTS'}
                @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
            )
            Mock Get-Installed-PHP-Versions-From-Directory { return $mockVersions }
            Mock Cache-Data { return 0 }

            $result = Refresh-Installed-PHP-Versions-Cache

            Assert-MockCalled Cache-Data -Exactly 1 -ParameterFilter {
                $data.Count -eq 2 -and $data[0].Version -eq '7.4'
            }
        }
    }

    Context "When exceptions occur" {
        It "Should return -1 on exception" {
            Mock Get-Installed-PHP-Versions-From-Directory { throw 'Test exception' }
            Mock Log-Data { return 0 }

            $result = Refresh-Installed-PHP-Versions-Cache
            $result | Should -Be -1
        }

        It "Should log error when exception occurs" {
            Mock Get-Installed-PHP-Versions-From-Directory { throw 'Test exception' }
            Mock Log-Data { return 0 }

            $result = Refresh-Installed-PHP-Versions-Cache

            Assert-MockCalled Log-Data -Exactly 1 -ParameterFilter {
                $data.header -eq 'Refresh-Installed-PHP-Versions-Cache - Failed to refresh installed PHP versions cache'
            }
        }

        It "Should return -1 when Cache-Data throws exception" {
            Mock Get-Installed-PHP-Versions-From-Directory {
                return @(@{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'})
            }
            Mock Cache-Data { throw 'Cache exception' }
            Mock Log-Data { return 0 }

            $result = Refresh-Installed-PHP-Versions-Cache
            $result | Should -Be -1
        }
    }
}

Describe "Get-Installed-PHP-Versions-From-Directory" {
    BeforeAll {
        $script:STORAGE_PATH = 'C:\test\storage'
    }

    Context "When PHP versions exist" {
        It "Should return installed PHP versions with php.exe present" {
            Mock Get-All-Subdirectories {
                return @(
                    @{FullName = 'C:\test\storage\php\8.1'}
                    @{FullName = 'C:\test\storage\php\8.2'}
                )
            }
            Mock Test-Path { return $true }
            Mock Get-PHPInstallInfo {
                param ($path)
                if ($path -eq 'C:\test\storage\php\8.1') {
                    return @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'; InstallPath = 'C:\test\storage\php\8.1'}
                } else {
                    return @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'; InstallPath = 'C:\test\storage\php\8.2'}
                }
            }

            $result = Get-Installed-PHP-Versions-From-Directory
            $result.Count | Should -Be 2
        }

        It "Should skip directories without php.exe" {
            Mock Get-All-Subdirectories {
                return @(
                    @{FullName = 'C:\test\storage\php\8.1'}
                    @{FullName = 'C:\test\storage\php\invalid'}
                    @{FullName = 'C:\test\storage\php\8.2'}
                )
            }
            Mock Test-Path {
                param ($path)
                return $path -notmatch 'invalid'
            }
            Mock Get-PHPInstallInfo {
                param ($path)
                if ($path -eq 'C:\test\storage\php\8.1') {
                    return @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                } elseif ($path -eq 'C:\test\storage\php\8.2') {
                    return @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                }
            }

            $result = Get-Installed-PHP-Versions-From-Directory
            $result.Count | Should -Be 2
        }

        It "Should return versions sorted by version number" {
            Mock Get-All-Subdirectories {
                return @(
                    @{FullName = 'C:\test\storage\php\8.2'}
                    @{FullName = 'C:\test\storage\php\7.4'}
                    @{FullName = 'C:\test\storage\php\8.1'}
                )
            }
            Mock Test-Path { return $true }
            Mock Get-PHPInstallInfo {
                param ($path)
                if ($path -eq 'C:\test\storage\php\8.2') {
                    return @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                } elseif ($path -eq 'C:\test\storage\php\7.4') {
                    return @{Version = '7.4'; Arch = 'x86'; BuildType = 'TS'}
                } else {
                    return @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                }
            }

            $result = Get-Installed-PHP-Versions-From-Directory
            $result.Count | Should -Be 3
            $result[0].Version | Should -Be '7.4'
            $result[1].Version | Should -Be '8.1'
            $result[2].Version | Should -Be '8.2'
        }
    }

    Context "When no PHP versions exist" {
        It "Should return empty array when no directories exist" {
            Mock Get-All-Subdirectories { return @() }

            $result = Get-Installed-PHP-Versions-From-Directory
            $result.Count | Should -Be 0
        }

        It "Should return empty array when no php.exe files are present" {
            Mock Get-All-Subdirectories {
                return @(
                    @{FullName = 'C:\test\storage\php\invalid1'}
                    @{FullName = 'C:\test\storage\php\invalid2'}
                )
            }
            Mock Test-Path { return $false }

            $result = Get-Installed-PHP-Versions-From-Directory
            $result.Count | Should -Be 0
        }
    }

    Context "When calling Get-All-Subdirectories" {
        It "Should call Get-All-Subdirectories with php storage path" {
            Mock Get-All-Subdirectories { return @() }

            Get-Installed-PHP-Versions-From-Directory

            Assert-MockCalled Get-All-Subdirectories -Exactly 1 -ParameterFilter {
                $path -eq "$STORAGE_PATH\php"
            }
        }
    }
}

Describe "Is-Two-PHP-Versions-Equal" {
    Context "When both versions are equal" {
        It "Returns true when all properties match" {
            $version1 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }
            $version2 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $true
        }

        It "Returns true for x86 TS build versions" {
            $version1 = @{
                version = '8.1.5'
                arch = 'x86'
                buildType = 'TS'
            }
            $version2 = @{
                version = '8.1.5'
                arch = 'x86'
                buildType = 'TS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $true
        }
    }

    Context "When versions differ" {
        It "Returns false when version numbers differ" {
            $version1 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }
            $version2 = @{
                version = '8.2.0'
                arch = 'x64'
                buildType = 'NTS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }

        It "Returns false when architecture differs" {
            $version1 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }
            $version2 = @{
                version = '8.3.0'
                arch = 'x86'
                buildType = 'NTS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }

        It "Returns false when build type differs" {
            $version1 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }
            $version2 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'TS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
    }

    Context "With null or incomplete versions" {
        It "Returns false when first version is null" {
            $version2 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $null -version2 $version2
            $result | Should -Be $false
        }

        It "Returns false when second version is null" {
            $version1 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $null
            $result | Should -Be $false
        }

        It "Returns false when both versions are null" {
            $result = Is-Two-PHP-Versions-Equal -version1 $null -version2 $null
            $result | Should -Be $false
        }

        It "Returns false when a property value is missing (null)" {
            $version1 = @{
                version = '8.3.0'
                arch = $null
                buildType = 'NTS'
            }
            $version2 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
    }

    Context "With edge cases" {
        It "Returns true for versions with additional properties" {
            $version1 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
                Dll = 'php8_nts.dll'
                InstallPath = 'C:\php\8.3'
            }
            $version2 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $true
        }

        It "Returns false when version is empty string vs null" {
            $version1 = @{
                version = ''
                arch = 'x64'
                buildType = 'NTS'
            }
            $version2 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }

            $result = Is-Two-PHP-Versions-Equal -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
    }
}

Describe "Get-BinaryArchitecture-From-DLL" {
    Context "Reading PE format from binary files" {
        It "Returns x64 architecture when machine type is 0x8664" {
            $dllPath = 'TestDrive:\php\php8_x64.dll'
            New-Item -Path $dllPath -ItemType File -Force | Out-Null

            # Convert TestDrive path to actual filesystem path
            $actualPath = (Resolve-Path -Path $dllPath).ProviderPath

            # Create a minimal PE file structure for x64
            # PE Header starts at offset 0x3C
            $bytes = [byte[]]::new(1024)

            # Write MZ header
            $bytes[0] = 0x4D  # 'M'
            $bytes[1] = 0x5A  # 'Z'

            # PE offset is at 0x3C (60 decimal)
            $peOffset = 0x80
            [BitConverter]::GetBytes($peOffset) | `
                ForEach-Object -Begin { $i = 0 } -Process { $bytes[0x3C + $i] = $_; $i++ }

            # At PE offset, write "PE\0\0"
            $bytes[$peOffset] = 0x50      # 'P'
            $bytes[$peOffset + 1] = 0x45  # 'E'

            # Machine type at PE offset + 4 (0x8664 for x64)
            [BitConverter]::GetBytes([uint16]0x8664) | `
                ForEach-Object -Begin { $i = 0 } -Process { $bytes[$peOffset + 4 + $i] = $_; $i++ }

            [System.IO.File]::WriteAllBytes($actualPath, $bytes)

            $result = Get-BinaryArchitecture-From-DLL -path $actualPath
            $result | Should -Be 'x64'
        }

        It "Returns x86 architecture when machine type is 0x014c" {
            $dllPath = 'TestDrive:\php\php8_x86.dll'
            New-Item -Path $dllPath -ItemType File -Force | Out-Null

            # Convert TestDrive path to actual filesystem path
            $actualPath = (Resolve-Path -Path $dllPath).ProviderPath

            # Create a minimal PE file structure for x86
            $bytes = [byte[]]::new(1024)

            # Write MZ header
            $bytes[0] = 0x4D  # 'M'
            $bytes[1] = 0x5A  # 'Z'

            # PE offset is at 0x3C (60 decimal)
            $peOffset = 0x80
            [BitConverter]::GetBytes($peOffset) | `
                ForEach-Object -Begin { $i = 0 } -Process { $bytes[0x3C + $i] = $_; $i++ }

            # At PE offset, write "PE\0\0"
            $bytes[$peOffset] = 0x50      # 'P'
            $bytes[$peOffset + 1] = 0x45  # 'E'

            # Machine type at PE offset + 4 (0x014c for x86)
            [BitConverter]::GetBytes([uint16]0x014c) | `
                ForEach-Object -Begin { $i = 0 } -Process { $bytes[$peOffset + 4 + $i] = $_; $i++ }

            [System.IO.File]::WriteAllBytes($actualPath, $bytes)

            $result = Get-BinaryArchitecture-From-DLL -path $actualPath
            $result | Should -Be 'x86'
        }

        It "Returns Unknown for unknown machine type" {
            $dllPath = 'TestDrive:\php\php8_unknown.dll'
            New-Item -Path $dllPath -ItemType File -Force | Out-Null

            # Convert TestDrive path to actual filesystem path
            $actualPath = (Resolve-Path -Path $dllPath).ProviderPath

            # Create a minimal PE file structure with unknown type
            $bytes = [byte[]]::new(1024)

            # Write MZ header
            $bytes[0] = 0x4D  # 'M'
            $bytes[1] = 0x5A  # 'Z'

            # PE offset is at 0x3C (60 decimal)
            $peOffset = 0x80
            [BitConverter]::GetBytes($peOffset) | `
                ForEach-Object -Begin { $i = 0 } -Process { $bytes[0x3C + $i] = $_; $i++ }

            # At PE offset, write "PE\0\0"
            $bytes[$peOffset] = 0x50      # 'P'
            $bytes[$peOffset + 1] = 0x45  # 'E'

            # Machine type at PE offset + 4 (0x0000 for unknown)
            [BitConverter]::GetBytes([uint16]0x0000) | `
                ForEach-Object -Begin { $i = 0 } -Process { $bytes[$peOffset + 4 + $i] = $_; $i++ }

            [System.IO.File]::WriteAllBytes($actualPath, $bytes)

            $result = Get-BinaryArchitecture-From-DLL -path $actualPath
            $result | Should -Be 'Unknown'
        }
    }
}

Describe "Get-Zend-Extensions-List" {
    It "Returns the zend_extensions.json content as a hashtable" {
        Mock Get-EnvConfig { return @{ ZEND_EXTENSIONS_LIST = 'a,b' } }
        $result = Get-Zend-Extensions-List
        $result.Count | Should -Be 2
    }
}

Describe "Get-PHP-Data" {
    BeforeEach {
        Reset-Ini-Content
    }

    It "Returns extensions with correct status" {
        $extensions = (Get-PHP-Data -PhpIniPath $testIniPath).extensions
        $extensions | Should -Not -Be $null
        $extensions.Count | Should -BeGreaterThan 0

        $curlExt = $extensions | Where-Object { $_.Extension -like '*curl*' }
        $curlExt.Enabled | Should -Be $true

        $xdebugExt = $extensions | Where-Object { $_.Extension -like '*xdebug*' }
        $xdebugExt.Enabled | Should -Be $false
    }

    It "Handles empty ini file" {
        '' | Set-Content $testIniPath
        $extensions = (Get-PHP-Data -PhpIniPath $testIniPath).extensions
        $extensions.Count | Should -Be 0
    }
}
