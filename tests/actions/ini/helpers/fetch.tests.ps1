
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\fetch-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:PECL_PACKAGES_URL = $PVMConfig.links.peclPackages
    $script:PECL_PACKAGE_ROOT_URL = $PVMConfig.links.peclPackageRoot
    $script:PECL_WIN_EXT_DOWNLOAD_URL = $PVMConfig.links.peclWinExtDownload

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    Mock Show-Message {}
    Mock Show-Error {}
    Mock Show-Info {}
    Mock Write-Gray {}
    Mock Show-Warning {}

    $script:MockFileSystem = @{
        Directories   = @()
        Files         = @{}
        WebResponses  = @{}
        DownloadFails = $false
    }

    Mock Invoke-WebRequestWrapper {
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
                Links   = $response.Links
            }
        }

        throw "URL not mocked: $Uri"
    }
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-ExtensionCategoriesByPage Tests" {
    It "Returns extensions links by page" {
        Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching&pageID=1" } -MockWith {
            return @{
                Content = 'Mocked PHP extension Caching content'
                Links   = @(
                    @{ href = '/package/APC' }
                    @{ href = '/package/APCu' }
                    @{ href = '/package/memcache' }
                    @{ href = '/package/memcached' }
                )
            }
        }

        $result = Get-ExtensionCategoriesByPage -extCategory 'Caching' -link '/packages.php?catpid=3&amp;catname=Caching' -page 1

        $result.availableExtensions.Count | Should -Be 4
        $result.availableExtensions[0].href | Should -Be '/package/APC'
        $result.availableExtensions[1].href | Should -Be '/package/APCu'
        $result.availableExtensions[2].href | Should -Be '/package/memcache'
        $result.availableExtensions[3].href | Should -Be '/package/memcached'
        $result.hasMore | Should -Be $false
    }

    It "Sets hasMore to true when more pages are available" {
        Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching&pageID=1" } -MockWith {
            return @{
                Content = 'Mocked PHP extension Caching content'
                Links   = @(
                    @{ href = $null }
                    @{ href = 'random_link.php' }
                    @{ href = '/packages.php?catpid=3&amp;catname=Caching&pageID=2' }
                    @{ href = '/package/APC' }
                    @{ href = '/package/APCu' }
                    @{ href = '/package/memcache' }
                    @{ href = '/package/memcached' }
                )
            }
        }

        $result = Get-ExtensionCategoriesByPage -extCategory 'Caching' -link '/packages.php?catpid=3&amp;catname=Caching' -page 1

        $result.hasMore | Should -Be $true
    }
}

Describe "Get-PHPExtensionsFromSource" {
    BeforeAll {
        Mock Save-CachedData { return 0 }
        Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq $PECL_PACKAGES_URL } -MockWith {
            return @{
                Content = 'Mocked PHP extensions content'
                Links   = @(
                    @{ href = $null }
                    @{ href = 'random_link' }
                    @{ href       = '/packages.php?catpid=1&amp;catname=Authentication';
                        outerHTML = '<a href="/packages.php?catpid=1&amp;catname=Authentication">Authentication</a>'
                    }
                    @{ href       = '/packages.php?catpid=3&amp;catname=Caching';
                        outerHTML = '<a href="/packages.php?catpid=3&amp;catname=Caching">Caching</a>'
                    }
                    @{ href       = '/packages.php?catpid=7&amp;catname=EmptyCat';
                        outerHTML = '<a href="/packages.php?catpid=7&amp;catname=EmptyCat">EmptyCat</a>'
                    }
                )
            }
        }
        Mock Get-ExtensionCategoriesByPage {
            param ($link)
            if ($link -eq '/packages.php?catpid=1&amp;catname=Authentication') {
                return @{
                    hasMore             = $false
                    availableExtensions = @(
                        @{ href = '/package/courierauth' }
                        @{ href = '/package/krb5' }
                    )
                }
            }
            if ($link -eq '/packages.php?catpid=3&amp;catname=Caching') {
                return @{
                    hasMore             = $false
                    availableExtensions = @(
                        @{ href = '/package/memcache' }
                        @{ href = '/package/memcached' }
                    )
                }
            }
            if ($link -eq '/packages.php?catpid=7&amp;catname=EmptyCat') {
                return @{ hasMore = $false; availableExtensions = @() }
            }
        }
    }

    BeforeEach {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
    }

    It "Returns list of available extensions" {
        $list = Get-PHPExtensionsFromSource
        $list.Count | Should -Be 3 # include xdebug category
    }

    It "Handles thrown exception" {
        Mock Get-ExtensionCategoriesByPage { throw 'Network error' }
        $list = Get-PHPExtensionsFromSource
        $list.Count | Should -Be 0
    }
}

Describe "Select-ExtensionLinksFromURL" {
    It "Returns filtered links for given extension" {
        Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache" } -MockWith {
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
        Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.4.0/windows" } -MockWith {
            return @{
                Content = 'Mocked PHP memcache 3.4.0 content'
                Links = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.4.0/php_memcache-3.4.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.4.0/php_memcache-3.4.0-8.2-ts-vs16-x64.zip" }
                )
            }
        }
        Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.3.0/windows" } -MockWith {
            return @{
                Content = 'Mocked PHP memcache 3.4.0 content'
                Links = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.3.0/php_memcache-3.3.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/memcache/3.3.0/php_memcache-3.3.0-8.2-ts-vs16-x64.zip" }
                )
            }
        }
        Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/memcache/3.2.0/windows" } -MockWith {
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
        Mock Invoke-WebRequestWrapper { throw 'Network error' }

        $result = Get-PackagesFromSourceLinks -extName 'memcache' -version '8.2' -links @( @{ href = '/package/memcache/3.4.0/windows' } )

        $result.Count | Should -Be 0
    }
}

Describe "Get-AvailablePHPExtensions Tests" {
    BeforeAll {
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
    }

    It "Returns cached extensions when available" {
        Mock Test-CanUseCache { return $true }
        Mock Get-DataFromCache { return Get-ExtensionList }
        Mock Get-PHPExtensionsFromSource { return Get-ExtensionList }

        $result = Get-AvailablePHPExtensions

        Should -Invoke Test-CanUseCache -Exactly 1
        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-PHPExtensionsFromSource -Exactly 0
        $result.PSObject.Properties.Name.Count | Should -Be 2
        $result.Authentication.Count | Should -Be 2
        $result.Authentication[0].extName | Should -Be 'courierauth'
        $result.Caching.Count | Should -Be 4
        $result.Caching[0].extName | Should -Be 'APC'
    }

    It "Fetches extensions from source when cache is not available" {
        Mock Test-CanUseCache { return $false }
        Mock Get-DataFromCache { return Get-ExtensionList }
        Mock Get-PHPExtensionsFromSource { return Get-ExtensionList }

        $result = Get-AvailablePHPExtensions

        Should -Invoke Test-CanUseCache -Exactly 1
        Should -Invoke Get-DataFromCache -Exactly 0
        Should -Invoke Get-PHPExtensionsFromSource -Exactly 1
        $result.PSObject.Properties.Name.Count | Should -Be 2
        $result.Authentication.Count | Should -Be 2
        $result.Authentication[0].extName | Should -Be 'courierauth'
        $result.Caching.Count | Should -Be 4
        $result.Caching[0].extName | Should -Be 'APC'
    }
}

Describe "Get-FilteredPHPExtensionsByCategory Tests" {
    BeforeAll {
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
    }

    It "Returns all extensions when no search term provided" {
        $testExtensions = Get-ExtensionList
        $result = Get-FilteredPHPExtensionsByCategory -availableExtensions $testExtensions

        $result.Count | Should -Be 2
        $result.Authentication.Length | Should -Be 2
        $result.Caching.Length | Should -Be 4
    }

    It "Filters by category name when term matches category" {
        $testExtensions = Get-ExtensionList
        $result = Get-FilteredPHPExtensionsByCategory -availableExtensions $testExtensions -term 'Cach'

        $result.Count | Should -Be 1
        $result.Caching.Length | Should -Be 4
        $result.Caching[0].extName | Should -Be 'APC'
    }

    It "Filters by extension name when term matches extName" {
        $testExtensions = Get-ExtensionList
        $result = Get-FilteredPHPExtensionsByCategory -availableExtensions $testExtensions -term 'mem'

        $result.Count | Should -Be 1
        $result.Caching.Length | Should -Be 2
        $result.Caching[0].extName | Should -Be 'memcache'
        $result.Caching[1].extName | Should -Be 'memcached'
    }

    It "Filters by description when term matches description" {
        $testExtensions = Get-ExtensionList
        $result = Get-FilteredPHPExtensionsByCategory -availableExtensions $testExtensions -term 'Kerberos'

        $result.Count | Should -Be 1
        $result.Authentication.Length | Should -Be 1
        $result.Authentication[0].extName | Should -Be 'krb5'
    }

    It "Returns empty result when no matches found" {
        $testExtensions = Get-ExtensionList
        $result = Get-FilteredPHPExtensionsByCategory -availableExtensions $testExtensions -term 'nonexistent'

        $result.Count | Should -Be 0
    }

    It "Returns empty hashtable when availableExtensions is empty" {
        $emptyExtensions = [pscustomobject]@{}
        $result = Get-FilteredPHPExtensionsByCategory -availableExtensions $emptyExtensions

        $result.Count | Should -Be 0
    }

    It "Case insensitive search works" {
        $testExtensions = Get-ExtensionList
        $result = Get-FilteredPHPExtensionsByCategory -availableExtensions $testExtensions -term 'CACH'

        $result.Count | Should -Be 1
        $result.Caching.Count | Should -Be 4
    }
}

Describe "Get-ExtensionMatchingCategories Tests" {
    BeforeAll {
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
        Mock Get-AvailablePHPExtensions -MockWith { return Get-ExtensionList }
    }

    BeforeEach {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
    }

    It "Returns matching categories links" {
        $result = Get-ExtensionMatchingCategories -extName 'mem'

        $result.Count | Should -Be 2
        $result[0].href | Should -Be '/package/memcache'
        $result[1].href | Should -Be '/package/memcached'
    }

    It "Displays matching extensions from source when cache is empty" {
        $result = Get-ExtensionMatchingCategories -extName 'mem'

        $result.Count | Should -Be 2
        Should -Invoke Get-AvailablePHPExtensions -Exactly 1
    }

    It "Returns empty when no matching extensions found" {
        Mock Get-AvailablePHPExtensions { return @{} }

        $result = Get-ExtensionMatchingCategories -extName 'mem'

        $result.Count | Should -Be 0
        Should -Invoke Show-Error -Exactly 1 -ParameterFilter {
            $message -like "*No extensions found*"
        }
    }
}

Describe "Select-ExtensionFromMatches Tests" {
    Context "When no extensions found" {
        It "Returns null" {
            $result = Select-ExtensionFromMatches -linksMatchingExtName @()

            $result | Should -BeNullOrEmpty
        }
    }

    Context "When single extension found" {
        It "Returns single extension" {
            $extensionList = @( @{ href = '/package/memcache'; extName = 'memcache' } )
            $result = Select-ExtensionFromMatches -linksMatchingExtName $extensionList

            $result.extName | Should -Be 'memcache'
        }
    }

    Context "When multiple extensions found" {
        BeforeEach {
            function Get-ExtensionList {
                return @(
                    @{ href = '/package/mysqlnd_memcache'; extName = 'mysqlnd_memcache' },
                    @{ href = '/package/memcache'; extName = 'memcache' },
                    @{ href = '/package/memcached'; extName = 'memcached' }
                )
            }
        }

        It "Prompts user to select link when multiple found and returns selected" {
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }

            $result = Select-ExtensionFromMatches -linksMatchingExtName (Get-ExtensionList)

            $result.extName | Should -Be 'memcache'
        }

        It "Returns null when user skips selection" {
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '' }

            $result = Select-ExtensionFromMatches -linksMatchingExtName (Get-ExtensionList)

            $result | Should -Be $null
            Should -Invoke Write-Gray -Times 1 -ParameterFilter {
                $message -eq "`nInstallation cancelled"
            }
        }

        It "Reprompts user when typing invalid choice" {
            $script:callCount = 0
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nInsert the [number] you want to install" } -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) { return 'A' }
                if ($script:callCount -eq 2) { return '-1' }
                else { return '0' }
            }

            $result = Select-ExtensionFromMatches -linksMatchingExtName (Get-ExtensionList)

            $result.extName | Should -Be 'memcache'
        }
    }
}

Describe "Get-ExtensionLinksFromURL Tests" {
    BeforeEach {
        $PVMConfig.paths.directories.cache = "$TEST_DRIVE\cache"
    }

    It "Returns filtered links" {
        Mock Test-CanUseCache { return $false }
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

    It "Handles defensive check when chosen item is null" {
        Mock Get-ExtensionMatchingCategories {
            return @(
                @{ href = '/package/memcache'; extName = 'memcache' },
                @{ href = '/package/memcached'; extName = 'memcached' }
            )
        }
        # Test the defensive check by having a null element in the array
        Mock Get-OrUpdateCache { throw 'Test exception' }
        Mock Get-ExtensionMatchingCategories { return @( @{ href = '/package/memcache'; extName = 'memcache' }, $null, @{ href = '/package/memcached'; extName = 'memcached' } ) }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '1' }
        Mock Select-ExtensionFromMatches { return $null }

        $result = Get-ExtensionLinksFromURL -extName 'mem' -version '8.2'

        # Should return null and show error message when chosen item is null
        $result | Should -Be $null
    }
}

Describe "Get-ExtensionFromURL Tests" {
    BeforeEach {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
    }

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
