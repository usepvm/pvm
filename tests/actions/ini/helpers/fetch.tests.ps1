
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

Describe "Select-ExtensionLinksFromURL" {
    It "Returns filtered links for given extension" {
        Mock Get-WebResponse -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache" } -MockWith {
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

        $result = Select-ExtensionLinksFromURL -extName 'memcache'

        $result.Count | Should -Be 3
        $result[0].href | Should -Be '/package/memcache/3.4.0/windows'
        $result[1].href | Should -Be '/package/memcache/3.3.0/windows'
        $result[2].href | Should -Be '/package/memcache/3.2.0/windows'
    }
}

Describe "Get-PackagesFromSourceLinks Tests" {
    It "Returns formatted list for matching packages" {
        Mock Add-LogEntry { return 0 }
        Mock Get-WebResponse -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.4.0/windows" } -MockWith {
            return @{
                Content = 'Mocked PHP memcache 3.4.0 content'
                Links = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.4.0/php_memcache-3.4.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.4.0/php_memcache-3.4.0-8.2-ts-vs16-x64.zip" }
                )
            }
        }
        Mock Get-WebResponse -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.3.0/windows" } -MockWith {
            return @{
                Content = 'Mocked PHP memcache 3.4.0 content'
                Links = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.3.0/php_memcache-3.3.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.3.0/php_memcache-3.3.0-8.2-ts-vs16-x64.zip" }
                )
            }
        }
        Mock Get-WebResponse -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.2.0/windows" } -MockWith {
            return @{
                Content = 'Mocked PHP memcache 3.4.0 content'
                Links = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.2.0/php_memcache-3.2.0-8.2-nts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.2.0/php_memcache-3.2.0-8.2-ts-x64.zip" }
                )
            }
        }

        $result = Get-PackagesFromSourceLinks -extName 'memcache' -version '8.2' -links @(
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
        Mock Get-WebResponse { throw 'Network error' }

        $result = Get-PackagesFromSourceLinks -extName 'memcache' -version '8.2' -links @( @{ href = '/package/memcache/3.4.0/windows' } )

        $result.Count | Should -Be 0
    }
}

Describe "Get-ExtensionMatchingCategories Tests" {
    BeforeAll {
        Mock Get-WebResponse -ParameterFilter { $Uri -eq $PECL_PACKAGES_URL } -MockWith {
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

        function Get-ExtensionList {
            return [pscustomobject] @{
                Authentication = @(
                    @{
                        outerHTML   = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName     = 'A';
                        href        = '/package/courierauth';
                        extName     = 'courierauth';
                        extCategory = 'Authentication';
                        description = 'Courier Authentication'
                    },
                    @{
                        outerHTML   = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName     = 'A';
                        href        = '/package/krb5';
                        extName     = 'krb5';
                        extCategory = 'Authentication'
                        description = 'Kerberos 5'
                    }
                )
                Caching        = @(
                    @{
                        outerHTML   = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName     = 'A';
                        href        = '/package/APC';
                        extName     = 'APC';
                        extCategory = 'Caching'
                        description = 'APC'
                    }
                    @{
                        outerHTML   = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName     = 'A';
                        href        = '/package/APCu';
                        extName     = 'APCu';
                        extCategory = 'Caching'
                        description = 'APCu'
                    }
                    @{
                        outerHTML   = '<a href="/package/memcache"><strong>memcache</strong></a>';
                        tagName     = 'A';
                        href = '/package/memcache'
                        extName     = 'memcache';
                        extCategory = 'Caching'
                        description = 'memcache'
                    }
                    @{
                        outerHTML   = '<a href="/package/memcached"><strong>memcached</strong></a>';
                        tagName     = 'A';
                        href = '/package/memcached'
                        extName     = 'memcached';
                        extCategory = 'Caching'
                        description = 'memcached'
                    }

                )
            }
        }
        Mock Get-DataFromCache { return Get-ExtensionList }
        Mock Get-PHPExtensionsFromSource -MockWith { return Get-ExtensionList }
    }

    It "Returns matching categories links" {
        $result = Get-ExtensionMatchingCategories -extName 'mem'

        $result.Count | Should -Be 2
        $result[0].href | Should -Be '/package/memcache'
        $result[1].href | Should -Be '/package/memcached'
    }

    It "Displays matching extensions from source when cache is empty" {
        Mock Test-CanUseCache { return $true }
        Mock Get-DataFromCache { return @{} }

        $result = Get-ExtensionMatchingCategories -extName 'mem'

        $result.Count | Should -Be 2
        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-PHPExtensionsFromSource -Exactly 1
    }
}

Describe "Get-ExtensionLinksFromURL Tests" {
    BeforeEach {
        $PVMConfig.paths.cache = "$TEST_DRIVE\cache"
    }

    It "Returns filtered links" {
        Mock Select-ExtensionLinksFromURL {
            return @(
                @{ href = '/package/memcache/3.4.0/windows' },
                @{ href = '/package/memcache/3.3.0/windows' },
                @{ href = '/package/memcache/3.2.0/windows' }
            )
        }

        $result = Get-ExtensionLinksFromURL -extName 'memcache' -version '8.2'

        $result.extName | Should -Be 'memcache'
        $result.links.Count | Should -Be 3
    }

    Context "When extension has no direct link" {
        BeforeEach {
            Mock Test-CanUseCache { return $false }
            Mock Select-ExtensionLinksFromURL -ParameterFilter { $extName -eq 'mem' } { throw 'Error' }
            Mock Select-ExtensionLinksFromURL -ParameterFilter { $extName -eq 'memcache' } {
                @{ href = '/package/memcache/3.4.0/windows' },
                @{ href = '/package/memcache/3.3.0/windows' },
                @{ href = '/package/memcache/3.2.0/windows' }
            }
        }

        It "Returns null when no matching categories links found" {
            Mock Get-ExtensionMatchingCategories { return @() }

            $result = Get-ExtensionLinksFromURL -extName 'mem' -version '8.2'

            $result | Should -Be $null
        }

        It "Takes the only link found" {
            Mock Get-ExtensionMatchingCategories { return @( @{ href = '/package/memcache'; extName = 'memcache' } ) }

            $result = Get-ExtensionLinksFromURL -extName 'mem' -version '8.2'

            $result.extName | Should -Be 'memcache'
            $result.links.Count | Should -Be 3
        }
    }

    Context "When multiple matching categories links found" {
        BeforeEach {
            Mock Get-ExtensionMatchingCategories { return @(
                @{ href = '/package/memcache'; extName = 'memcache' },
                @{ href = '/package/memcached'; extName = 'memcached' }
            ) }
            Mock Select-ExtensionLinksFromURL -ParameterFilter { $extName -eq 'memcache' } {
                @{ href = '/package/memcache/3.4.0/windows' },
                @{ href = '/package/memcache/3.3.0/windows' },
                @{ href = '/package/memcache/3.2.0/windows' }
            }
        }

        It "Prompts user to select link when multiple found and returns selected" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }

            $result = Get-ExtensionLinksFromURL -extName 'mem' -version '8.2'

            $result.extName | Should -Be 'memcache'
            $result.links.Count | Should -Be 3
        }

        It "Returns null when user skips selection" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '' }

            $result = Get-ExtensionLinksFromURL -extName 'mem' -version '8.2'

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

            $result = Get-ExtensionLinksFromURL -extName 'mem' -version '8.2'

            $result.extName | Should -Be 'memcache'
            $result.links.Count | Should -Be 3
        }

        It "Handles defensive check when chosen item is null" {
            # Test the defensive check by having a null element in the array
            Mock Get-ExtensionMatchingCategories { return @( @{ href = '/package/memcache' }, $null, @{ href = '/package/memcached' } ) }
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '1' }

            $result = Get-ExtensionLinksFromURL -extName 'mem' -version '8.2'

            # Should return null and show error message when chosen item is null
            $result | Should -Be $null
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -like "*You chose the wrong index*"
            }
        }
    }
}

Describe "Get-ExtensionFromURL Tests" {
    It "Should parse extension versions correctly" {
        Mock Test-CanUseCache { return $false }
        Mock Get-ExtensionLinksFromURL {
            return @{
                extName = 'memcache'
                links = @(
                    @{ href = '/package/memcache/3.4.0/windows' },
                    @{ href = '/package/memcache/3.3.0/windows' },
                    @{ href = '/package/memcache/3.2.0/windows' }
                )
            }
        }
        Mock Get-PackagesFromSourceLinks {
            return @(
                @{ href = '/package/memcache/3.4.0/windows'; version = '8.2'; extVersion = '3.4.0'; fileName = '/memcache/3.4.0/php_memcache-3.4.0-8.2-ts-vs16-x64.zip' }
                @{ href = '/package/memcache/3.3.0/windows'; version = '8.2'; extVersion = '3.3.0'; fileName = '/memcache/3.3.0/php_memcache-3.3.0-8.2-ts-vs16-x64.zip' }
                @{ href = '/package/memcache/3.2.0/windows'; version = '8.2'; extVersion = '3.2.0'; fileName = '/memcache/3.2.0/php_memcache-3.2.0-8.2-ts-vs16-x64.zip' }
            )
        }
        $result = Get-ExtensionFromURL -extName 'memcache' -version '8.2'

        $result.data.Count | Should -Be 3
        $result.data[0].extVersion | Should -Be '3.4.0'
        $result.data[1].extVersion | Should -Be '3.3.0'
        $result.data[2].extVersion | Should -Be '3.2.0'
    }

    It "Returns null when no version found for extension" {
        Mock Get-ExtensionLinksFromURL { return $null }

        $result = Get-ExtensionFromURL -extName 'cache' -version '8.2'

        $result.data | Should -Be $null
    }

    It "Uses extName from linksObj when links are empty" {
        Mock Get-ExtensionLinksFromURL {
            return @{ extName = 'memcache'; links = @() }
        }

        $result = Get-ExtensionFromURL -extName 'mem' -version '8.2'

        $result.extName | Should -Be 'memcache'
        $result.data   | Should -Be $null
    }
}
