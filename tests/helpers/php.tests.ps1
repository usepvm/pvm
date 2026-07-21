
BeforeAll {
    Mock Write-Host {}

    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\php-drive"
    $PVMConfig.paths.cache = "$TEST_DRIVE\cache"
    $script:testPhpPath = "$TEST_DRIVE\PHP"
    $script:testExtPath = "$testPhpPath\ext"
    $script:testIniPath = "$testPhpPath\php.ini"
    $script:TEMPLATES_PATH = $PVMConfig.paths.templates = "$TEST_DRIVE\storage\data\templates"
    $script:ZEND_EXTENSIONS_LIST_PATH = $PVMConfig.paths.zendExtensionsList = "$TEMPLATES_PATH\zend_extensions.json"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $testPhpPath -Force | Out-Null

    function Reset-IniContent {
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
    Reset-IniContent
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-PHPInstallInfo" {
    Context "When PHP DLL exists" {
        It "Returns PHP install info with NTS build type" {
            $testPath = "$TEST_DRIVE\php\8.3"
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

            Mock Get-BinaryArchitectureFromDLL { return 'x64' }

            $result = Get-PHPInstallInfo -path $testPath

            $result | Should -Not -BeNullOrEmpty
            $result.Version | Should -Be '8.3.0'
            $result.Arch | Should -Be 'x64'
            $result.BuildType | Should -Be 'NTS'
            $result.Dll | Should -Be 'php8nts.dll'
            $result.InstallPath | Should -Be $testPath
        }

        It "Returns PHP install info with TS build type" {
            $testPath = "$TEST_DRIVE\php\8.2"
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null

            Mock Get-ChildItem {
                return @{
                    VersionInfo = @{ ProductVersion = '8.2.5' }
                    Name = 'php8ts.dll'
                    FullName = "$testPath\php8ts.dll"
                }
            }

            Mock Get-BinaryArchitectureFromDLL { return 'x86' }

            $result = Get-PHPInstallInfo -path $testPath

            $result.BuildType | Should -Be 'TS'
            $result.Arch | Should -Be 'x86'
            $result.Version | Should -Be '8.2.5'
        }

        It "Returns first DLL when multiple match" {
            $testPath = "$TEST_DRIVE\php\8.1"

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

            Mock Get-BinaryArchitectureFromDLL { return 'x64' }

            $result = Get-PHPInstallInfo -path $testPath
            $result.Dll | Should -Be 'php81nts.dll'
        }
    }

    Context "When PHP DLL does not exist" {
        It "Returns null when no DLL found" {
            $testPath = "$TEST_DRIVE\php\empty"
            New-Item -Path $testPath -ItemType Directory -Force | Out-Null

            Mock Get-ChildItem { return $null }

            $result = Get-PHPInstallInfo -path $testPath
            $result | Should -BeNullOrEmpty
        }
    }
}

Describe "Get-SourceUrls" {
    It "Should return correct URL structure" {
        $result = Get-SourceUrls

        $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $result.Keys.Count | Should -Be 2
        $result.Keys -contains 'Archives' | Should -Be $true
        $result.Keys -contains 'Releases' | Should -Be $true
    }

    It "Should return correct Archive URL" {
        $result = Get-SourceUrls
        $result['Archives'] | Should -Be 'https://windows.php.net/downloads/releases/archives'
    }

    It "Should return correct Releases URL" {
        $result = Get-SourceUrls
        $result['Releases'] | Should -Be 'https://windows.php.net/downloads/releases'
    }
}

Describe "Get-InstalledPHPVersions" {
    Context "When environment variables contain PHP versions" {
        It "Should return sorted PHP versions" {
            $script:STORAGE_PATH = 'C:\mock\path'
            $script:LOG_ERROR_PATH = 'C:\mock\error'
            Mock Save-CachedData { return 0 }
            Mock Test-CanUseCache { return $false }
            Mock Get-InstalledPHPVersionsFromDisk {
                return @(
                    @{version = '5.6'; arch = 'x64'; buildType = 'nts'}
                    @{version = '7.4'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.0'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.1'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.2'; arch = 'x64'; buildType = 'nts'}
                )
            }

            $result = Get-InstalledPHPVersions
            $expected = @('5.6', '7.4', '8.0', '8.1', '8.2')

            $result.Count | Should -Be $expected.Count
            for ($i = 0; $i -lt $result.Count; $i++) {
                $result[$i].version | Should -Be $expected[$i]
            }
        }

        It "Should return empty array when no PHP versions are found" {
            Mock Test-CanUseCache { return $false }
            Mock Get-InstalledPHPVersionsFromDisk { return @() }

            $result = Get-InstalledPHPVersions
            $result.Count | Should -Be 0
        }

        It "Should handle single digit versions" {
            Mock Save-CachedData { return 0 }
            Mock Test-CanUseCache { return $false }
            Mock Get-InstalledPHPVersionsFromDisk {
                return @(
                    @{version = '7.4'; arch = 'x64'; buildType = 'nts'}
                    @{version = '8.1'; arch = 'x64'; buildType = 'nts'}
                )
            }

            $result = Get-InstalledPHPVersions
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

            $result = Get-InstalledPHPVersions -arch 'x86'

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

            $result = Get-InstalledPHPVersions -buildType 'nts'

            $result.Count | Should -Be 3
            $result[0].version | Should -Be '5.6'
            $result[1].version | Should -Be '7.4'
            $result[2].version | Should -Be '8.0'
        }
    }

    Context "When exceptions occur" {
        It "Should return empty array and log error when Get-InstalledPHPVersionsFromDisk throws exception" {
            Mock Get-OrUpdateCache { throw 'Test exception' }
            Mock Add-LogEntry { return 0 }

            $result = Get-InstalledPHPVersions
            $result.Count | Should -Be 0

            Should -Invoke Add-LogEntry -Exactly 1 -ParameterFilter {
                $data.header -eq 'Get-InstalledPHPVersions - Failed to retrieve installed PHP versions'
            }
        }
    }
}

Describe "Get-UserSelectedPHPVersion" {
    It "Should return null when no installed versions are provided" {
        $result = Get-UserSelectedPHPVersion -installedVersions @()
        $result | Should -Be $null
    }

    It "Should return first version when only one is provided" {
        $result = Get-UserSelectedPHPVersion -installedVersions @(@{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'})
        $result.version | Should -Be '8.1'
    }

    It "Should return null when no version is selected" {
        Mock Read-Host { return '' }
        Mock Write-Host { }

        $result = Get-UserSelectedPHPVersion -installedVersions @(
            @{ version = '7.4'; Arch = 'x64'; BuildType = 'ts'}
            @{ version = '8.0'; Arch = 'x64'; BuildType = 'ts'}
            @{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'}
        )
        $result.code | Should -Be -1
    }

    It "Should prompt user and return selected version when multiple are provided" {
        Mock Read-Host { return '2' }
        Mock Write-Host { }

        $result = Get-UserSelectedPHPVersion -installedVersions @(
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
        Mock Get-CurrentPHPVersion { return @{ version = '8.0'; arch = 'x64'; buildType = 'ts'}}

        $list = @(
            @{ version = '7.4'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\7.4'}
            @{ version = '8.0'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\8.0'}
            @{ version = '8.1'; Arch = 'x64'; BuildType = 'ts'; InstallPath = 'C:\php\8.1'}
        )
        $null = Get-UserSelectedPHPVersion -installedVersions $list

        $maxNameLength = ($list.version | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2)
        $version = '8.0 '.PadRight($maxNameLength, '.')
        Should -Invoke Write-Host -ParameterFilter { $Object -eq " [1] $version x64 ts (Current)" }
    }
}

Describe "Get-MatchingPHPVersions" {
    Context "When matching versions exist" {
        It "Should return matching versions for partial version number" {
            Mock Get-InstalledPHPVersions { return @(
                @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                @{Version = '8.0'; Arch = 'x64'; BuildType = 'NTS'}
                @{Version = '7.4'; Arch = 'x64'; BuildType = 'NTS'}
            )}

            $result = Get-MatchingPHPVersions -version '8'
            $expected = @('8.0', '8.1', '8.2')

            $result.Count | Should -Be $expected.Count
            $result | Where-Object { $_.version -eq '8.2' } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.version -eq '8.1' } | Should -Not -BeNullOrEmpty
            $result | Where-Object { $_.version -eq '8.0' } | Should -Not -BeNullOrEmpty
        }

        It "Should return exact match for pattern version number" {
            Mock Get-InstalledPHPVersions {
                return @(
                    @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.9'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.0'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '7.4'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }

            $result = Get-MatchingPHPVersions -version '8.1'
            $result.Count | Should -Be 2
            $result[0].version | Should -Be '8.1.9'
        }

        It "Should return exact match for full version number" {
            Mock Get-InstalledPHPVersions {
                return @(
                    @{Version = '7.4'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.0'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.9'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }

            $result = Get-MatchingPHPVersions -version '8.1.9'
            $result.Length | Should -Be 1
            $result.version | Should -Be '8.1.9'
        }

        It "Should return empty array when no matches found" {
            Mock Get-InstalledPHPVersions {
                return @('php7.4', 'php8.0', 'php8.1')
            }
            Mock Add-LogEntry { return 0 }

            $result = Get-MatchingPHPVersions -version '9'
            $result.Count | Should -Be 0
        }
    }

    Context "When exceptions occur" {
        It "Should return null and log error when Get-InstalledPHPVersions throws exception" {
            Mock Get-InstalledPHPVersions { throw 'Test exception' }
            Mock Add-LogEntry { return 0 }

            $result = Get-MatchingPHPVersions -version '8.1'
            $result | Should -Be $null

            Should -Invoke Add-LogEntry -Exactly 1 -ParameterFilter {
                $data.header -eq 'Get-MatchingPHPVersions - Failed to check if PHP version 8.1 is installed'
            }
        }
    }
}

Describe "Test-PHPVersionInstalled" {
    Context "When version exists" {
        It "Should return true for installed version" {
            Mock Get-MatchingPHPVersions {
                param ($version)
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.2'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }

            $result = Test-PHPVersionInstalled -version @{version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
            $result | Should -Be $true
        }

        It "Should return false for non-installed version" {
            Mock Get-MatchingPHPVersions {
                param ($version)
                return @(
                    @{Version = '8.1.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.1.2'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }

            $result = Test-PHPVersionInstalled -version @{version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
            $result | Should -Be $null
        }

        It "Should return false when no matching versions found" {
            Mock Get-MatchingPHPVersions {
                return @()
            }

            $result = Test-PHPVersionInstalled -version '9.0'
            $result | Should -Be $null
        }
    }

    Context "When exceptions occur" {
        It "Should return false and log error when Get-MatchingPHPVersions throws exception" {
            Mock Get-MatchingPHPVersions { throw 'Test exception' }
            Mock Add-LogEntry { return 0 }

            $result = Test-PHPVersionInstalled -version '8.1'
            $result | Should -Be $false

            Should -Invoke Add-LogEntry -Exactly 1 -ParameterFilter {
                $data.header -eq 'Test-PHPVersionInstalled - Failed to check if PHP version 8.1 is installed'
            }
        }
    }
}

Describe "Update-InstalledPHPVersionsCache" {
    Context "When cache is successfully refreshed" {
        It "Should return 0 on success" {
            Mock Get-InstalledPHPVersionsFromDisk {
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                    @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }
            Mock Save-CachedData { return 0 }

            $result = Update-InstalledPHPVersionsCache
            $result | Should -Be 0
        }

        It "Should call Get-InstalledPHPVersionsFromDisk" {
            Mock Get-InstalledPHPVersionsFromDisk {
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }
            Mock Save-CachedData { return 0 }

            $null = Update-InstalledPHPVersionsCache

            Should -Invoke Get-InstalledPHPVersionsFromDisk -Exactly 1
        }

        It "Should call Save-CachedData with installed_php_versions file and depth 1" {
            Mock Get-InstalledPHPVersionsFromDisk {
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }
            Mock Save-CachedData { return 0 }

            $null = Update-InstalledPHPVersionsCache

            Should -Invoke Save-CachedData -Exactly 1 -ParameterFilter {
                $cacheFileName -eq 'installed_php_versions' -and $depth -eq 1
            }
        }

        It "Should cache the results from Get-InstalledPHPVersionsFromDisk" {
            $mockVersions = @(
                @{Version = '7.4'; Arch = 'x64'; BuildType = 'NTS'}
                @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
            )
            Mock Get-InstalledPHPVersionsFromDisk { return $mockVersions }
            Mock Save-CachedData { return 0 }

            $null = Update-InstalledPHPVersionsCache

            Should -Invoke Save-CachedData -Exactly 1 -ParameterFilter {
                $data.Count -eq 2 -and $data[0].Version -eq '7.4'
            }
        }
    }

    Context "When exceptions occur" {
        It "Should return -1 when Save-CachedData returns -1" {
            Mock Get-InstalledPHPVersionsFromDisk {
                return @(
                    @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                )
            }
            Mock Save-CachedData { return -1 }

            $result = Update-InstalledPHPVersionsCache
            $result | Should -Be -1
        }

        It "Should return -1 on exception" {
            Mock Get-InstalledPHPVersionsFromDisk { throw 'Test exception' }
            Mock Add-LogEntry { return 0 }

            $result = Update-InstalledPHPVersionsCache
            $result | Should -Be -1
        }

        It "Should log error when exception occurs" {
            Mock Get-InstalledPHPVersionsFromDisk { throw 'Test exception' }
            Mock Add-LogEntry { return 0 }

            $null = Update-InstalledPHPVersionsCache

            Should -Invoke Add-LogEntry -Exactly 1 -ParameterFilter {
                $data.header -eq 'Update-InstalledPHPVersionsCache - Failed to refresh installed PHP versions cache'
            }
        }

        It "Should return -1 when Save-CachedData throws exception" {
            Mock Get-InstalledPHPVersionsFromDisk {
                return @(@{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'})
            }
            Mock Save-CachedData { throw 'Cache exception' }
            Mock Add-LogEntry { return 0 }

            $result = Update-InstalledPHPVersionsCache
            $result | Should -Be -1
        }
    }
}

Describe "Get-InstalledPHPVersionsFromDisk" {
    BeforeAll {
        $script:STORAGE_PATH = "$TEST_DRIVE\storage"
    }

    Context "When PHP versions exist" {
        It "Should return installed PHP versions with php.exe present" {
            Mock Get-AllSubdirectories {
                return @(
                    @{FullName = "$TEST_DRIVE\storage\php\8.1"}
                    @{FullName = "$TEST_DRIVE\storage\php\8.2"}
                )
            }
            Mock Test-Path { return $true }
            Mock Get-PHPInstallInfo {
                param ($path)
                if ($path -eq "$TEST_DRIVE\storage\php\8.1") {
                    return @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'; InstallPath = "$TEST_DRIVE\storage\php\8.1"}
                } else {
                    return @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'; InstallPath = "$TEST_DRIVE\storage\php\8.2"}
                }
            }

            $result = Get-InstalledPHPVersionsFromDisk
            $result.Count | Should -Be 2
        }

        It "Should skip directories without php.exe" {
            Mock Get-AllSubdirectories {
                return @(
                    @{FullName = "$TEST_DRIVE\storage\php\8.1"}
                    @{FullName = "$TEST_DRIVE\storage\php\invalid"}
                    @{FullName = "$TEST_DRIVE\storage\php\8.2"}
                )
            }
            Mock Test-Path {
                param ($path)
                return $path -notmatch 'invalid'
            }
            Mock Get-PHPInstallInfo {
                param ($path)
                if ($path -eq "$TEST_DRIVE\storage\php\8.1") {
                    return @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                } elseif ($path -eq "$TEST_DRIVE\storage\php\8.2") {
                    return @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                }
            }

            $result = Get-InstalledPHPVersionsFromDisk
            $result.Count | Should -Be 2
        }

        It "Should return versions sorted by version number" {
            Mock Get-AllSubdirectories {
                return @(
                    @{FullName = "$TEST_DRIVE\storage\php\8.2"}
                    @{FullName = "$TEST_DRIVE\storage\php\7.4"}
                    @{FullName = "$TEST_DRIVE\storage\php\8.1"}
                )
            }
            Mock Test-Path { return $true }
            Mock Get-PHPInstallInfo {
                param ($path)
                if ($path -eq "$TEST_DRIVE\storage\php\8.2") {
                    return @{Version = '8.2'; Arch = 'x64'; BuildType = 'NTS'}
                } elseif ($path -eq "$TEST_DRIVE\storage\php\7.4") {
                    return @{Version = '7.4'; Arch = 'x86'; BuildType = 'TS'}
                } else {
                    return @{Version = '8.1'; Arch = 'x64'; BuildType = 'NTS'}
                }
            }

            $result = Get-InstalledPHPVersionsFromDisk
            $result.Count | Should -Be 3
            $result[0].Version | Should -Be '7.4'
            $result[1].Version | Should -Be '8.1'
            $result[2].Version | Should -Be '8.2'
        }
    }

    Context "When no PHP versions exist" {
        It "Should return empty array when no directories exist" {
            Mock Get-AllSubdirectories { return @() }

            $result = Get-InstalledPHPVersionsFromDisk
            $result.Count | Should -Be 0
        }

        It "Should return empty array when no php.exe files are present" {
            Mock Get-AllSubdirectories {
                return @(
                    @{FullName = "$TEST_DRIVE\storage\php\invalid1"}
                    @{FullName = "$TEST_DRIVE\storage\php\invalid2"}
                )
            }
            Mock Test-Path { return $false }

            $result = Get-InstalledPHPVersionsFromDisk
            $result.Count | Should -Be 0
        }
    }

    Context "When calling Get-AllSubdirectories" {
        It "Should call Get-AllSubdirectories with php storage path" {
            Mock Get-AllSubdirectories { return @() }

            Get-InstalledPHPVersionsFromDisk

            Should -Invoke Get-AllSubdirectories -Exactly 1 -ParameterFilter {
                $path -eq $PVMConfig.paths.php
            }
        }
    }
}

Describe "Test-TwoPHPVersionsEqual" {
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

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $version2
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

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $version2
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

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $version2
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

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $version2
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

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $version2
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

            $result = Test-TwoPHPVersionsEqual -version1 $null -version2 $version2
            $result | Should -Be $false
        }

        It "Returns false when second version is null" {
            $version1 = @{
                version = '8.3.0'
                arch = 'x64'
                buildType = 'NTS'
            }

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $null
            $result | Should -Be $false
        }

        It "Returns false when both versions are null" {
            $result = Test-TwoPHPVersionsEqual -version1 $null -version2 $null
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

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $version2
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

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $version2
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

            $result = Test-TwoPHPVersionsEqual -version1 $version1 -version2 $version2
            $result | Should -Be $false
        }
    }
}

Describe "Get-BinaryArchitectureFromDLL" {
    Context "Reading PE format from binary files" {
        It "Returns x64 architecture when machine type is 0x8664" {
            $dllPath = "$TEST_DRIVE\php\php8_x64.dll"
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

            $result = Get-BinaryArchitectureFromDLL -path $actualPath
            $result | Should -Be 'x64'
        }

        It "Returns x86 architecture when machine type is 0x014c" {
            $dllPath = "$TEST_DRIVE\php\php8_x86.dll"
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

            $result = Get-BinaryArchitectureFromDLL -path $actualPath
            $result | Should -Be 'x86'
        }

        It "Returns Unknown for unknown machine type" {
            $dllPath = "$TEST_DRIVE\php\php8_unknown.dll"
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

            $result = Get-BinaryArchitectureFromDLL -path $actualPath
            $result | Should -Be 'Unknown'
        }
    }

    It "Returns Unknown when file does not exist" {
        Mock Test-FileNotExists { return $true }

        $result = Get-BinaryArchitectureFromDLL -path "$TEST_DRIVE\php\php8.dll"

        $result | Should -Be 'Unknown'
    }
}

Describe "Set-ZendExtensionsList" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $TEMPLATES_PATH | Out-Null
        $script:DEFAULT_ZEND_EXTENSIONS = $PVMConfig.defaults.zendExtensions
    }
    It "Creates zend_extensions.json" {
        $result = Set-ZendExtensionsList
        $result | Should -Be 0

        $result = Get-ZendExtensionsList
        $result.Count | Should -Be $DEFAULT_ZEND_EXTENSIONS.Count
    }

    It "Returns -1 when exception is thrown" {
        Mock Set-Content { throw 'Test exception' }
        $result = Set-ZendExtensionsList
        $result | Should -Be -1
    }
}

Describe "Get-ZendExtensionsList" {
    BeforeAll {
        New-Item -ItemType Directory -Force -Path $TEMPLATES_PATH | Out-Null
        $testContent = @('opcache', 'xdebug', 'swoole')
        $testContent | ConvertTo-Json -Depth 10 | Set-Content -Path $ZEND_EXTENSIONS_LIST_PATH
        $script:DEFAULT_ZEND_EXTENSIONS = $PVMConfig.defaults.zendExtensions
    }

    It "Returns the zend_extensions.json content as a hashtable" {
        $result = Get-ZendExtensionsList
        $result.Count | Should -Be 3
        $result | Should -Contain 'opcache'
        $result | Should -Contain 'xdebug'
        $result | Should -Contain 'swoole'
    }

    It "Falls back to DEFAULT_ZEND_EXTENSIONS value" {
        Remove-Item -Path "$TEMPLATES_PATH\zend_extensions.json"
        $result = Get-ZendExtensionsList
        $result.Count | Should -Be $DEFAULT_ZEND_EXTENSIONS.Count
    }

    It "Returns default value when exception is thrown" {
        Mock Test-FileExists { return $true }
        Mock Get-Content { throw 'Test exception' }
        $result = Get-ZendExtensionsList
        $result.Count | Should -Be $DEFAULT_ZEND_EXTENSIONS.Count
    }
}

Describe "Get-ZendExtensionsInfo" {
    It "Returns empty list when ext directory does not exist" {
        Mock Test-DirectoryNotExists { return $true }

        $result = Get-ZendExtensionsInfo -phpPath $testPhpPath
        $result.Count | Should -Be 0
    }

    It "Returns list of zend extensions status" {
        @"
extension=php_curl.dll
zend_extension=php_opcache.dll
;upload_max_filesize = 2M
"@ | Set-Content -Path $testIniPath -Encoding UTF8
        New-Item -ItemType Directory -Force -Path $testExtPath | Out-Null
        New-Item -Path "$testExtPath\opcache.dll" -ItemType File -Force | Out-Null
        New-Item -Path "$testExtPath\php_xdebug.dll" -ItemType File -Force | Out-Null

        $result = Get-ZendExtensionsInfo -phpPath $testPhpPath
        $result.Count | Should -Be 2

        ($result | Where-Object { $_.Name -eq 'opcache' }).Enabled | Should -Be $true
        ($result | Where-Object { $_.Name -eq 'xdebug' }).Enabled | Should -Be $false
    }

    It "Returns Copyright from DLL VersionInfo" {
        New-Item -ItemType Directory -Force -Path $testExtPath | Out-Null
        New-Item -Path "$testExtPath\opcache.dll" -ItemType File -Force | Out-Null
        Mock Get-ChildItem {
            return @{
                VersionInfo = @{
                    ProductVersion = '8.3.0'
                    LegalCopyright = 'Copyright (c) PHP Group'
                }
            }
        }

        $result = Get-ZendExtensionsInfo -phpPath $testPhpPath
        $result.Count | Should -Be 2
        $result[0].Copyright | Should -Be 'Copyright (c) PHP Group'
    }

    It "Returns empty string when LegalCopyright is null" {
        New-Item -ItemType Directory -Force -Path $testExtPath | Out-Null
        New-Item -Path "$testExtPath\opcache.dll" -ItemType File -Force | Out-Null

        Mock Get-ChildItem {
            return @{
                VersionInfo = @{
                    ProductVersion = '8.3.0'
                    LegalCopyright = $null
                }
            }
        }

        $result = Get-ZendExtensionsInfo -phpPath $testPhpPath
        $result.Count | Should -Be 2
        $result[0].Copyright | Should -Be ''
    }
}

Describe "Get-PHPData" {
    BeforeEach {
        Reset-IniContent
    }

    It "Returns extensions with correct status" {
        $extensions = (Get-PHPData -PhpIniPath $testIniPath).extensions
        $extensions | Should -Not -Be $null
        $extensions.Count | Should -BeGreaterThan 0

        $curlExt = $extensions | Where-Object { $_.Extension -like '*curl*' }
        $curlExt.Enabled | Should -Be $true

        $xdebugExt = $extensions | Where-Object { $_.Extension -like '*xdebug*' }
        $xdebugExt.Enabled | Should -Be $false
    }

    It "Handles empty ini file" {
        '' | Set-Content -Path $testIniPath
        $extensions = (Get-PHPData -PhpIniPath $testIniPath).extensions
        $extensions.Count | Should -Be 0
    }
}

Describe "Test-PHPVersionFormat" {
    It 'accepts major version only' {
        Test-PHPVersionFormat -version '8' | Should -BeTrue
    }

    It 'accepts major.minor' {
        Test-PHPVersionFormat -version '8.2' | Should -BeTrue
    }

    It 'accepts major.minor.patch' {
        Test-PHPVersionFormat -version '8.2.10' | Should -BeTrue
    }

    It 'rejects trailing dot' {
        Test-PHPVersionFormat -version '8.' | Should -BeFalse
    }

    It 'rejects leading dot' {
        Test-PHPVersionFormat -version '.8' | Should -BeFalse
    }

    It 'rejects four segments' {
        Test-PHPVersionFormat -version '8.2.3.4' | Should -BeFalse
    }

    It 'rejects non-numeric input' {
        Test-PHPVersionFormat -version 'abc' | Should -BeFalse
    }

    It 'rejects empty string' {
        Test-PHPVersionFormat -version '' | Should -BeFalse
    }

    It 'rejects null' {
        Test-PHPVersionFormat -version $null | Should -BeFalse
    }

    It 'rejects double-digit segments' {
        Test-PHPVersionFormat -version '8.10' | Should -BeTrue
    }

    It 'rejects negative numbers' {
        Test-PHPVersionFormat -version '-8.2' | Should -BeFalse
    }
}
