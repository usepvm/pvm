
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\fetch-drive"
    Mock Write-Host {}
    $script:PECL_PACKAGES_URL = $PVMConfig.links.peclPackages
    $script:PECL_PACKAGE_ROOT_URL = $PVMConfig.links.peclPackageRoot
    $script:PECL_WIN_EXT_DOWNLOAD_URL = $PVMConfig.links.peclWinExtDownload

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-Extension-Matching-Categories-By-Page Tests" {
    It "Returns matching categories links by page" {
        Mock Get-Web-Response -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching&pageID=1" } -MockWith {
            return @{
                Content = 'Mocked PHP extension Caching content'
                Links = @(
                    @{ href = '/package/APC' }
                    @{ href = '/package/APCu' }
                    @{ href = '/package/memcache' }
                    @{ href = '/package/memcached' }
                )
            }
        }

        $result = Get-Extension-Matching-Categories-By-Page -extName 'mem' -link '/packages.php?catpid=3&amp;catname=Caching' -page 1

        $result.resultLinks.Count | Should -Be 2
        $result.resultLinks[0].href | Should -Be '/package/memcache'
        $result.resultLinks[1].href | Should -Be '/package/memcached'
        $result.hasMore | Should -Be $false
    }

    It "Sets hasMore to true when next page link exists" {
        Mock Get-Web-Response -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching&pageID=1" } -MockWith {
            return @{
                Content = 'Mocked PHP extension Caching content'
                Links = @(
                    @{ href = $null }
                    @{ href = '/packages.php?catpid=3&amp;catname=Caching&pageID=2' }
                    @{ href = '/package/APC' }
                    @{ href = '/package/APCu' }
                    @{ href = '/package/memcache' }
                    @{ href = '/package/memcached' }
                )
            }
        }

        $result = Get-Extension-Matching-Categories-By-Page -extName 'mem' -link '/packages.php?catpid=3&amp;catname=Caching' -page 1

        $result.hasMore | Should -Be $true
    }
}

Describe "Select-Extension-Links-From-URL" {
    It "Returns filtered links for given extension" {
        Mock Get-Web-Response -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache" } -MockWith {
            return @{
                Content = 'Mocked memcache content'
                Links = @(
                    @{ href = '/package/memcache/3.4.0/windows' },
                    @{ href = '/package/memcache/3.3.0/windows' }
                    @{ href = '/package/memcache/3.2.0/windows' }
                    @{ href = $null }
                    @{ href = 'random_link' }
                )
            }
        }

        $result = Select-Extension-Links-From-URL -extName 'memcache'

        $result.Count | Should -Be 3
        $result[0].href | Should -Be '/package/memcache/3.4.0/windows'
        $result[1].href | Should -Be '/package/memcache/3.3.0/windows'
        $result[2].href | Should -Be '/package/memcache/3.2.0/windows'
    }
}

Describe "Get-Packages-From-Source-Links Tests" {
    It "Returns formatted list for matching packages" {
        Mock Add-LogEntry { return 0 }
        Mock Get-Web-Response -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.4.0/windows" } -MockWith {
            return @{
                Content = 'Mocked PHP memcache 3.4.0 content'
                Links = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.4.0/php_memcache-3.4.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.4.0/php_memcache-3.4.0-8.2-ts-vs16-x64.zip" }
                )
            }
        }
        Mock Get-Web-Response -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.3.0/windows" } -MockWith {
            return @{
                Content = 'Mocked PHP memcache 3.4.0 content'
                Links = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.3.0/php_memcache-3.3.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.3.0/php_memcache-3.3.0-8.2-ts-vs16-x64.zip" }
                )
            }
        }
        Mock Get-Web-Response -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.2.0/windows" } -MockWith {
            return @{
                Content = 'Mocked PHP memcache 3.4.0 content'
                Links = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.2.0/php_memcache-3.2.0-8.2-nts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.2.0/php_memcache-3.2.0-8.2-ts-x64.zip" }
                )
            }
        }

        $result = Get-Packages-From-Source-Links -extName 'memcache' -version '8.2' -links @(
            @{ href = '/package/memcache/3.4.0/windows' },
            @{ href = '/package/memcache/3.3.0/windows' },
            @{ href = '/package/memcache/3.2.0/windows' }
        )

        $result.Count | Should -Be 6
        $result[0].extVersion | Should -Be '3.4.0'
        $result[1].arch | Should -Be 'x64'
        $result[2].arch | Should -Be 'x86'
        $result[3].extVersion | Should -Be '3.3.0'
        $result[4].buildType | Should -Be 'NTS'
        $result[5].compiler | Should -Be 'unknown'
    }

    It "Handles exception gracefully" {
        Mock Get-Web-Response { throw 'Network error' }

        $result = Get-Packages-From-Source-Links -extName 'memcache' -version '8.2' -links @( @{ href = '/package/memcache/3.4.0/windows' } )

        $result.Count | Should -Be 0
    }
}

Describe "Get-Extension-Matching-Categories Tests" {
    BeforeAll {
        Mock Get-Web-Response -ParameterFilter { $Uri -eq $PECL_PACKAGES_URL } -MockWith {
            return @{
                Content = 'Mocked PHP extensions content'
                Links = @(
                    @{ href = $null }
                    @{ href = 'random_link' }
                    @{ href = '/packages.php?catpid=1&amp;catname=Authentication';
                        outerHTML = '<a href="/packages.php?catpid=1&amp;catname=Authentication">Authentication</a>' }
                    @{ href = '/packages.php?catpid=3&amp;catname=Caching';
                        outerHTML = '<a href="/packages.php?catpid=3&amp;catname=Caching">Caching</a>' }
                    @{ href = '/packages.php?catpid=7&amp;catname=EmptyCat';
                        outerHTML = '<a href="/packages.php?catpid=7&amp;catname=EmptyCat">EmptyCat</a>' }
                )
            }
        }
        Mock Get-Extension-Matching-Categories-By-Page {
            param ($link)
            if ($link -eq '/packages.php?catpid=1&amp;catname=Authentication') {
                return @{ hasMore = $false; resultLinks = @() }
            }
            if ($link -eq '/packages.php?catpid=3&amp;catname=Caching') {
                return @{
                    hasMore = $false
                    resultLinks = @(
                        @{ href = '/package/memcache' }
                        @{ href = '/package/memcached' }
                    )
                }
            }
            if ($link -eq '/packages.php?catpid=7&amp;catname=EmptyCat') {
                return @{ hasMore = $false; resultLinks = @() }
            }
        }
    }

    It "Returns matching categories links" {
        $result = Get-Extension-Matching-Categories -extName 'mem'

        $result.Count | Should -Be 2
        $result[0].href | Should -Be '/package/memcache'
        $result[1].href | Should -Be '/package/memcached'
    }

    It "Loops for next page when hasMore is true" {
        Mock Get-Extension-Matching-Categories-By-Page {
            if ($link -eq '/packages.php?catpid=3&amp;catname=Caching') {
                if ($page -eq 1) {
                    return @{ hasMore = $true; resultLinks = @( @{ href = '/package/memcache' } ) }
                } else {
                    return @{ hasMore = $false; resultLinks = @( @{ href = '/package/memcached' } ) }
                }
            }
        }

        $result = Get-Extension-Matching-Categories -extName 'mem'

        $result.Count | Should -Be 2
    }
}

Describe "Get-Extension-Links-From-URL Tests" {
    BeforeEach {
        $PVMConfig.paths.cache = "$TEST_DRIVE\cache"
    }

    It "Returns filtered links" {
        Mock Select-Extension-Links-From-URL {
            return @(
                @{ href = '/package/memcache/3.4.0/windows' },
                @{ href = '/package/memcache/3.3.0/windows' },
                @{ href = '/package/memcache/3.2.0/windows' }
            )
        }

        $result = Get-Extension-Links-From-URL -extName 'memcache' -version '8.2'

        $result.extName | Should -Be 'memcache'
        $result.links.Count | Should -Be 3
    }

    Context "When extension has no direct link" {
        BeforeEach {
            Mock Test-Can-Use-Cache { return $false }
            Mock Select-Extension-Links-From-URL -ParameterFilter { $extName -eq 'mem' } { throw 'Error' }
            Mock Select-Extension-Links-From-URL -ParameterFilter { $extName -eq 'memcache' } {
                @{ href = '/package/memcache/3.4.0/windows' },
                @{ href = '/package/memcache/3.3.0/windows' },
                @{ href = '/package/memcache/3.2.0/windows' }
            }
        }

        It "Returns null when no matching categories links found" {
            Mock Get-Extension-Matching-Categories { return @() }

            $result = Get-Extension-Links-From-URL -extName 'mem' -version '8.2'

            $result | Should -Be $null
        }

        It "Takes the only link found" {
            Mock Get-Extension-Matching-Categories { return @( @{ href = '/package/memcache' } ) }

            $result = Get-Extension-Links-From-URL -extName 'mem' -version '8.2'

            $result.extName | Should -Be 'memcache'
            $result.links.Count | Should -Be 3
        }
    }

    Context "When multiple matching categories links found" {
        BeforeEach {
            Mock Get-Extension-Matching-Categories { return @(
                @{ href = '/package/memcache' },
                @{ href = '/package/memcached' }
            ) }
        }

        It "Prompts user to select link when multiple found and returns selected" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }

            $result = Get-Extension-Links-From-URL -extName 'mem' -version '8.2'

            $result.extName | Should -Be 'memcache'
            $result.links.Count | Should -Be 3
        }

        It "Returns null when user skips selection" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '' }

            $result = Get-Extension-Links-From-URL -extName 'mem' -version '8.2'

            $result | Should -Be $null
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -eq "`nInstallation cancelled"
            }
        }

        It "Reprompts user when typing invalid choice" {
            $script:callCount = 0
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) { return 'A' }
                if ($script:callCount -eq 2) { return '-1' }
                else { return '0' }
            }

            $result = Get-Extension-Links-From-URL -extName 'mem' -version '8.2'

            $result.extName | Should -Be 'memcache'
            $result.links.Count | Should -Be 3
        }

        It "Handles defensive check when chosen item is null" {
            # Test the defensive check by having a null element in the array
            Mock Get-Extension-Matching-Categories { return @( @{ href = '/package/memcache' }, $null, @{ href = '/package/memcached' } ) }
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '1' }

            $result = Get-Extension-Links-From-URL -extName 'mem' -version '8.2'

            # Should return null and show error message when chosen item is null
            $result | Should -Be $null
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -like "*You chose the wrong index*"
            }
        }
    }
}

Describe "Get-Extension-From-URL Tests" {
    It "Should parse extension versions correctly" {
        Mock Test-Can-Use-Cache { return $false }
        Mock Get-Extension-Links-From-URL {
            return @{
                extName = 'memcache'
                links = @(
                    @{ href = '/package/memcache/3.4.0/windows' },
                    @{ href = '/package/memcache/3.3.0/windows' },
                    @{ href = '/package/memcache/3.2.0/windows' }
                )
            }
        }
        Mock Get-Packages-From-Source-Links {
            return @(
                @{ href = '/package/memcache/3.4.0/windows'; version = '8.2'; extVersion = '3.4.0'; fileName = '/memcache/3.4.0/php_memcache-3.4.0-8.2-ts-vs16-x64.zip' }
                @{ href = '/package/memcache/3.3.0/windows'; version = '8.2'; extVersion = '3.3.0'; fileName = '/memcache/3.3.0/php_memcache-3.3.0-8.2-ts-vs16-x64.zip' }
                @{ href = '/package/memcache/3.2.0/windows'; version = '8.2'; extVersion = '3.2.0'; fileName = '/memcache/3.2.0/php_memcache-3.2.0-8.2-ts-vs16-x64.zip' }
            )
        }
        $result = Get-Extension-From-URL -extName 'memcache' -version '8.2'

        $result.data.Count | Should -Be 3
        $result.data[0].extVersion | Should -Be '3.4.0'
        $result.data[1].extVersion | Should -Be '3.3.0'
        $result.data[2].extVersion | Should -Be '3.2.0'
    }

    It "Returns null when no version found for extension" {
        Mock Get-Extension-Links-From-URL { return $null }

        $result = Get-Extension-From-URL -extName 'cache' -version '8.2'

        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nNo versions found for cache"
        }
        $result.data | Should -Be $null
    }

    It "Uses extName from linksObj when links are empty" {
        Mock Get-Extension-Links-From-URL {
            return @{ extName = 'memcache'; links = @() }
        }

        $result = Get-Extension-From-URL -extName 'mem' -version '8.2'

        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nNo versions found for memcache"
        }
        $result.extName | Should -Be 'memcache'
        $result.data   | Should -Be $null
    }
}
