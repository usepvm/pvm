
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\ext-drive"
    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:PECL_PACKAGES_URL = $PVMConfig.links.peclPackages
    $script:CACHE_PATH = $PVMConfig.paths.cache = "$TEST_DRIVE\cache"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    Mock Write-Host {}

    $script:MockFileSystem = @{
        Directories   = @()
        Files         = @{}
        WebResponses  = @{}
        DownloadFails = $false
    }

    Mock Get-WebResponse {
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
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-ExtensionCategoriesByPage Tests" {
    It "Returns extensions links by page" {
        Mock Get-WebResponse -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching&pageID=1" } -MockWith {
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
        Mock Get-WebResponse -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching&pageID=1" } -MockWith {
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
        Mock Get-WebResponse -ParameterFilter { $Uri -eq $PECL_PACKAGES_URL } -MockWith {
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

Describe "Show-PHPExtensions" {
    BeforeAll {
        Mock Get-AllPHPExtensionsStatus {
            return @(
                @{ name = 'curl'; enabled = $true; status = 'Enabled' }
                @{ name = 'opcache'; enabled = $false; status = 'Disabled' }
            )
        }
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'curl'; enabled = $true; status = 'Enabled' }
                @{ name = 'opcache'; enabled = $false; status = 'Disabled' }
            )
        }

        function Get-ExtensionList {
            return @{
                Authentication = @(
                    @{
                        outerHTML   = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName     = 'A';
                        href        = '/package/courierauth';
                        extName     = 'courierauth';
                        extCategory = 'Authentication';
                    },
                    @{
                        outerHTML   = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName     = 'A';
                        href        = '/package/krb5';
                        extName     = 'krb5';
                        extCategory = 'Authentication'
                    }
                )
                Caching        = @(
                    @{
                        outerHTML   = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName     = 'A';
                        href        = '/package/APC';
                        extName     = 'APC';
                        extCategory = 'Caching'
                    }
                    @{
                        outerHTML   = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName     = 'A';
                        href        = '/package/APCu';
                        extName     = 'APCu';
                        extCategory = 'Caching'
                    }
                )
            }
        }
        Mock Get-DataFromCache { return Get-ExtensionList }
        Mock Get-PHPExtensionsFromSource -MockWith { return Get-ExtensionList }
        Mock Show-ExtensionsStates {}
        Mock Show-InstalledExtensions {}
    }

    It "Returns 0 when no extensions are installed" {
        Mock Get-AllPHPExtensionsStatus { return @() }

        $code = Show-PHPExtensions -iniPath $testIniPath

        $code | Should -Be 0
        Should -Invoke Show-ExtensionsStates -Exactly 1
        Should -Invoke Show-InstalledExtensions -Exactly 1
    }

    It "Displays installed extensions" {
        $code = Show-PHPExtensions -iniPath $testIniPath
        $code | Should -Be 0
        Should -Invoke Get-AllPHPExtensionsStatus -Exactly 1
        Should -Invoke Get-MatchingPHPExtensionsStatus -Exactly 0
        Should -Invoke Show-ExtensionsStates -Exactly 1
        Should -Invoke Show-InstalledExtensions -Exactly 1
    }

    It "Displays local extensions matching the filter" {
        $code = Show-PHPExtensions -iniPath $testIniPath -term 'pc'
        $code | Should -Be 0
        Should -Invoke Get-AllPHPExtensionsStatus -Exactly 1
        Should -Invoke Get-MatchingPHPExtensionsStatus -Exactly 1
        Should -Invoke Show-ExtensionsStates -Exactly 1
        Should -Invoke Show-InstalledExtensions -Exactly 1
    }

    It "Returns 0 when no local extensions matchs the filter" {
        Mock Get-MatchingPHPExtensionsStatus { return @() }

        $code = Show-PHPExtensions -iniPath $testIniPath -term 'nonexistent'

        $code | Should -Be 0
        Should -Invoke Get-MatchingPHPExtensionsStatus -Exactly 1
        Should -Invoke Show-ExtensionsStates -Exactly 1
        Should -Invoke Show-InstalledExtensions -Exactly 1
    }

    It "Returns -1 when no extensions are found" {
        Mock Test-Path { return $false }
        Mock Get-PHPExtensionsFromSource { return @{} }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
        Should -Invoke Get-PHPExtensionsFromSource -Exactly 1
        Should -Invoke Get-DataFromCache -Exactly 0
    }

    It "Displays available extensions from cache" {
        Mock Test-CanUseCache { return $true }
        Mock Get-DataFromCache {
            return @{
                GUI    = @(
                    @{href = '/package/php_xcb'; extName = 'php_xcb'; extCategory = 'GUI' }
                    @{href = '/package/tk'; extName = 'tk'; extCategory = 'GUI' }
                    @{href = '/package/php_xcb'; extName = 'php_xcb'; extCategory = 'GUI' }
                );
                Images = @(
                    @{href = '/package/cairo'; extName = 'cairo'; extCategory = 'Images' }
                    @{href = '/package/cairo_wrapper'; extName = 'cairo_wrapper'; extCategory = 'Images' }
                )
            }
        }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-PHPExtensionsFromSource -Exactly 0
    }

    It "Displays available extensions from source when cache is empty" {
        Mock Test-CanUseCache { return $true }
        Mock Get-DataFromCache { return @{} }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
        Should -Invoke Get-DataFromCache -Exactly 1
        Should -Invoke Get-PHPExtensionsFromSource -Exactly 1
    }

    It "Displays available extensions matching the filter" {
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true -term 'pc'
        $code | Should -Be 0
    }

    It "Returns -1 when no available extensions matchs the filter" {
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true -term 'nonexistent'
        $code | Should -Be -1
    }

    It "Handles thrown exception" {
        Mock Test-CanUseCache { throw 'Error' }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
    }

    It "Returns -1 when available extensions count is 0" {
        Mock Test-CanUseCache { return $false }
        Mock Get-OrUpdateCache -ParameterFilter { $cacheFileName -eq 'available_extensions' } { return @{} }
        Mock Write-Host {}
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nNo extensions found"
        }
    }

    It "Displays available extensions with long descriptions that require wrapping" {
        Mock Test-CanUseCache { return $false }
        Mock Get-OrUpdateCache -ParameterFilter { $cacheFileName -eq 'available_extensions' } {
            return @{
                TestCategory = @(
                    @{ extName = 'verylongextensionnameone'; extCategory = 'TestCategory' },
                    @{ extName = 'verylongextensionnametwo'; extCategory = 'TestCategory' },
                    @{ extName = 'verylongextensionnamethree'; extCategory = 'TestCategory' },
                    @{ extName = 'verylongextensionnamefour'; extCategory = 'TestCategory' },
                    @{ extName = 'verylongextensionnamefive'; extCategory = 'TestCategory' }
                )
            }
        }
        # Mock $Host.UI.RawUI.WindowSize to trigger the maxDescLength < 100 condition
        Mock Get-ConsoleWidth { 80 }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
    }

    It "Displays available extensions with very long word without spaces to trigger breakPos fallback" {
        Mock Test-CanUseCache { return $false }
        Mock Get-OrUpdateCache -ParameterFilter { $cacheFileName -eq 'available_extensions' } {
            return @{
                TestCategory = @(
                    @{ extName = 'a' * 150; extCategory = 'TestCategory' }
                )
            }
        }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
    }
}
