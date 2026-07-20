
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    # Mock global variables that would be defined in the main script
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\list-drive"
    $PVMConfig.paths.data = "$TEST_DRIVE\storage\data"
    $PVMConfig.paths.logError = "$TEST_DRIVE\storage\logs\error.log"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    $script:PHP_WIN_ARCHIVES_URL = $PVMConfig.links.phpWinArchives
    $script:PHP_WIN_RELEASES_URL = $PVMConfig.links.phpWinReleases

    Mock Write-Host { }

    # Mock external functions that aren't defined in the provided code
    Mock New-Directory { return 0 }
    Mock Add-LogEntry { param ($logPath, $message, $data) return 0 }
    Mock Get-SourceUrls {
        return @{
            'releases' = $PHP_WIN_RELEASES_URL
            'archives' = $PHP_WIN_ARCHIVES_URL
        }
    }
    Mock Get-CurrentPHPVersion { return @{ version = '8.2.0' } }
    Mock Get-InstalledPHPVersions { return @('php8.2.0', 'php8.1.5', 'php7.4.33') }
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-FromSource" {
    BeforeEach {
        # Clean test directory
        if (Test-Path "$TEST_DRIVE\data") {
            Remove-Item -Path "$TEST_DRIVE\data" -Recurse -Force
        }

        Mock Test-OS64Bit { return $true }
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

        Mock Get-WebResponse {
            return @{ Links = $mockLinks }
        }

        Mock Save-CachedData { }

        $result = Get-FromSource

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

    It "Should return empty list" {
        Mock Get-WebResponse {
            return @{ Links = @() }
        }
        Mock Save-CachedData { }

        $result = Get-FromSource

        $result | Should -BeOfType [hashtable]
        $result.Count | Should -Be 0
    }

    It "Should handle web request failure" {
        Mock Get-WebResponse { throw 'Network error' }
        Mock Add-LogEntry { return 0 }

        $result = Get-FromSource

        $result | Should -BeOfType [hashtable]
        $result.Keys.Count | Should -Be 0
    }
}

Describe "Get-PHPListToInstall" {
    BeforeEach {
        $PVMConfig.paths.cache = "$TEST_DRIVE\storage\cache"
    }

    It "Returns empty object when cache and/or source not working" {
        Mock Get-OrUpdateCache { return $null }

        $result = Get-PHPListToInstall

        $result.Count | Should -Be 0
    }

    It "Should read from cache" {
        Mock Test-Path { return $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString('yyyy-MM-ddTHH:mm:ss.fffffffK')
        Mock Get-Item { @{ LastWriteTime = $timeWithinLastWeek } }
        Mock Get-DataFromCache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }

        $result = Get-PHPListToInstall

        $result | Should -Not -BeNullOrEmpty
        $result.Archives | Should -Not -BeNullOrEmpty
        $result.Releases | Should -Not -BeNullOrEmpty
        Should -Invoke Get-DataFromCache -Exactly 1
    }

    It "Should fetch from source when cache is empty" {
        Mock Test-CanUseCache { return $true }
        Mock Get-DataFromCache { return @{} }
        Mock Get-FromSource {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }

        $result = Get-PHPListToInstall

        $result | Should -Not -BeNullOrEmpty
        $result.Archives | Should -Not -BeNullOrEmpty
        $result.Releases | Should -Not -BeNullOrEmpty
        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-FromSource -Exactly 1
    }

    It "Should fetch from source" {
        Mock Test-CanUseCache { return $false }
        Mock Get-FromSource {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }

        $result = Get-PHPListToInstall

        $result | Should -Not -BeNullOrEmpty
        $result.Archives | Should -Not -BeNullOrEmpty
        $result.Releases | Should -Not -BeNullOrEmpty
        Should -Invoke Get-FromSource -Exactly 1
    }

    It "Handles exceptions gracefully" {
        Mock Test-CanUseCache { throw 'Cache error' }
        $result = Get-PHPListToInstall
        $result | Should -BeNullOrEmpty
    }
}

Describe "Get-AvailablePHPVersions" {
    BeforeEach {
        Mock Write-Host { }
    }

    It "Should handle x86 architecture" {
        Mock Get-PHPListToInstall { return @{
            'Archives' = @(@{
                Link = 'php-7.1.0-Win32-x64.zip'
                BuildType = 'TS'; Arch = 'x64'; Version = '7.1.0';
            })
            'Releases' = @(@{
                Link = 'php-7.1.0-Win32-x86.zip'
                BuildType = 'TS'; Arch = 'x86'; Version = '7.1.0'
            })
        }}

        $code = Get-AvailablePHPVersions -arch 'x86'

        $code | Should -Be 0
    }

    It "Should handle x64 architecture" {
        Mock Get-PHPListToInstall { return @{
            'Archives' = @(@{
                Link = 'php-7.1.0-Win32-x64.zip'
                BuildType = 'TS'; Arch = 'x64'; Version = '7.1.0';
            })
            'Releases' = @(@{
                Link = 'php-7.1.0-Win32-x86.zip'
                BuildType = 'TS'; Arch = 'x86'; Version = '7.1.0'
            })
        }}

        $code = Get-AvailablePHPVersions -arch 'x64'

        $code | Should -Be 0
    }

    It "Should handle TS build type" {
        Mock Get-PHPListToInstall { return @{
            'Archives' = @(@{
                Link = 'php-7.1.0-Win32-x64.zip'
                BuildType = 'TS'; Arch = 'x64'; Version = '7.1.0';
            })
            'Releases' = @(@{
                Link = 'php-7.1.0-Win32-nts-x64.zip'
                BuildType = 'NTS'; Arch = 'x64'; Version = '7.1.0'
            })
        }}

        $code = Get-AvailablePHPVersions -buildType 'ts'

        $code | Should -Be 0
    }

    It "Should handle NTS build type" {
        Mock Get-PHPListToInstall { return @{
            'Archives' = @(@{
                Link = 'php-7.1.0-Win32-x64.zip'
                BuildType = 'TS'; Arch = 'x64'; Version = '7.1.0';
            })
            'Releases' = @(@{
                Link = 'php-7.1.0-Win32-nts-x64.zip'
                BuildType = 'NTS'; Arch = 'x64'; Version = '7.1.0'
            })
        }}

        $code = Get-AvailablePHPVersions -buildType 'nts'

        $code | Should -Be 0
    }

    It "Should read from cache by default" {
        Mock Get-DataFromCache {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }
        Mock Test-Path { return $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString('yyyy-MM-ddTHH:mm:ss.fffffffK')
        Mock Get-Item { @{ LastWriteTime = $timeWithinLastWeek } }

        $code = Get-AvailablePHPVersions

        $code | Should -Be 0
        Should -Invoke Get-DataFromCache -Exactly 1
    }

    It "Display available versions matching filter" {
        Mock Get-PHPListToInstall { return @{
            'Archives' = @(@{
                Link = 'php-7.1.0-Win32-x64.zip'
                BuildType = 'TS'
                Arch = 'x64'
                Version = '7.1.0'
            })
            'Releases' = @(@{
                Link = 'php-7.2.0-Win32-x64.zip'
                BuildType = 'TS'
                Arch = 'x64'
                Version = '7.2.0'
            })
        }}
        $code = Get-AvailablePHPVersions -term '7.1'
        $code | Should -Be 0
    }

    It "Return -1 when no available versions matching filter" {
        $code = Get-AvailablePHPVersions -term '9.1'
        $code | Should -Be -1
    }

    It "Return -1 when no installed versions matching filter" {
        Mock Get-InstalledPHPVersions { return @('8.2.0', '8.2.0', '8.1.5') }
        $code = Show-InstalledPHPVersions -term '9.1'
        $code | Should -Be -1
    }

    It "Should fetch from source when cache is empty" {
        Mock Test-CanUseCache { return $true }
        Mock Get-DataFromCache { return @{} }
        Mock Get-FromSource {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }

        $code = Get-AvailablePHPVersions

        $code | Should -Be 0
        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-FromSource -Exactly 1
    }

    It "Should force fetch from source when cache not exists" {
        Mock Test-Path { return $false }
        Mock Get-DataFromCache { }  # Remove return value since it won't be called
        Mock Get-FromSource {
            return @{
                'Archives' = @('php-8.1.0-Win32-x64.zip')
                'Releases' = @('php-8.2.0-Win32-x64.zip')
            }
        }

        $code = Get-AvailablePHPVersions

        $code | Should -Be 0
        Should -Not -Invoke Get-DataFromCache
        Should -Invoke Get-FromSource -Exactly 1
    }

    It "Should display versions in correct format" {
        Mock Get-DataFromCache {
            return @{
                'Archives' = @(@{
                    BuildType = 'NTS';
                    Version = '8.1.0';
                    Link = 'php-8.1.0-Win32-x64.zip';
                    Arch = 'x86'
                })
                'Releases' = @(@{
                    BuildType = 'NTS';
                    Version = '8.2.0';
                    Link = 'php-8.2.0-Win32-x64.zip';
                    Arch = 'x64';
                })
            }
        }
        Mock Test-Path { return $true }
        $timeWithinLastWeek = (Get-Date).AddHours(-160).ToString('yyyy-MM-ddTHH:mm:ss.fffffffK')
        Mock Get-Item { @{ LastWriteTime = $timeWithinLastWeek } }

        $code = Get-AvailablePHPVersions

        $code | Should -Be 0
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Available Versions*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Archives*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Releases*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*8.1.0*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*8.2.0*' }
    }

    It "Returns -1 on empty list" {
        Mock Get-PHPListToInstall { return @{} }

        $result = Get-AvailablePHPVersions

        $result | Should -Be -1
    }

    It "Should handle exceptions gracefully" {
        Mock Get-PHPListToInstall { return @{
            'Archives' = @('php-8.1.0-Win32-x64.zip')
            'Releases' = @('php-8.2.0-Win32-x64.zip')
        }}
        Mock ForEach-Object { throw 'Cache error' }
        Mock Add-LogEntry { return 0 }

        $result = Get-AvailablePHPVersions

        $result | Should -Be -1
    }
}

Describe "Show-InstalledPHPVersions" {
    BeforeEach {
        Mock Write-Host { }
    }

    It "Should display installed versions with current version marked" {
        Mock Get-CurrentPHPVersion { return @{
            version = '8.2.0'
            arch = 'x64'
            buildType = 'nts'
        }}
        Mock Get-InstalledPHPVersions { return @(
            @{Version = '8.2.0'; Arch = 'x64'; BuildType = 'NTS'}
            @{Version = '8.1.5'; Arch = 'x64'; BuildType = 'NTS'}
            @{Version = '7.4.33'; Arch = 'x64'; BuildType = 'NTS'}
        )}

        Show-InstalledPHPVersions

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Installed Versions*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*8.2.0*(Current)*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*8.1.5*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*7.4.33*' }
    }

    It "Display installed versions matching filter" {
        Mock Get-InstalledPHPVersions { return @(
            @{Version = '8.2.0'; Arch = 'x64'; BuildType = 'NTS'}
            @{Version = '8.2.0'; Arch = 'x64'; BuildType = 'TS'}
            @{Version = '8.1.5'; Arch = 'x64'; BuildType = 'NTS'}
        )}
        $code = Show-InstalledPHPVersions -term '8.2'
        $code | Should -Be 0
    }

    It "Should handle no installed versions" {
        Mock Get-CurrentPHPVersion { return @{ version = '' } }
        Mock Get-InstalledPHPVersions { return @() }

        Show-InstalledPHPVersions

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No PHP versions found*' }
    }

    It "Should handle duplicate versions" {
        Mock Get-CurrentPHPVersion { return @{
            version = '8.2.0'
            arch = 'x64'
            buildType = 'NTS'
        }}
        Mock Get-InstalledPHPVersions { return @(
            @{Version = '8.2.0'; Arch = 'x64'; BuildType = 'NTS'}
            @{Version = '8.2.0'; Arch = 'x64'; BuildType = 'NTS'}
            @{Version = '8.1.5'; Arch = 'x64'; BuildType = 'NTS'}
        )}

        Show-InstalledPHPVersions

        # Should only display unique versions
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*8.2.0*' } -Exactly 1
    }

    It "Should handle no current version set" {
        Mock Get-CurrentPHPVersion { return @{ version = '' } }
        Mock Get-InstalledPHPVersions { return @(
            @{Version = '8.2.0'; Arch = 'x64'; BuildType = 'NTS'}
            @{Version = '8.1.5'; Arch = 'x64'; BuildType = 'NTS'}
        )}

        Show-InstalledPHPVersions

        Should -Invoke Write-Host -ParameterFilter { $Object -like '*8.2.0*' -and $Object -notlike '*(Current)*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*8.1.5*' -and $Object -notlike '*(Current)*' }
    }

    It "Should handle exceptions gracefully" {
        Mock Get-CurrentPHPVersion { throw 'Error getting current version' }
        Mock Add-LogEntry { return 0 }

        { Show-InstalledPHPVersions } | Should -Not -Throw
    }
}

Describe "Get-PHPVersionsList" {
    It "Displays available versions" {
        Mock Get-AvailablePHPVersions { return 0 }

        $result = Get-PHPVersionsList -available $true

        $result | Should -Be 0
        Should -Invoke Get-AvailablePHPVersions -Exactly 1
    }

    It "Displays installed versions" {
        Mock Show-InstalledPHPVersions { return 0 }

        $result = Get-PHPVersionsList

        $result | Should -Be 0
        Should -Invoke Show-InstalledPHPVersions -Exactly 1
    }
}
