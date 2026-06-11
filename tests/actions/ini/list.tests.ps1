
BeforeAll {
    $testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $testIniPath = "$testDrivePath\php.ini"

    Mock Write-Host {}

    $global:MockFileSystem = @{
        Directories = @()
        Files = @{}
        WebResponses = @{}
        DownloadFails = $false
    }

    function Invoke-WebRequest {
        param ($Uri, $OutFile = $null)

        if ($global:MockFileSystem.DownloadFails) {
            throw 'Network error'
        }

        if ($global:MockFileSystem.WebResponses.ContainsKey($Uri)) {
            $response = $global:MockFileSystem.WebResponses[$Uri]
            if ($OutFile) {
                $global:MockFileSystem.Files[$OutFile] = 'Downloaded content'
                return
            }
            return @{
                Content = $response.Content
                Links = $response.Links
            }
        }

        throw "URL not mocked: $Uri"
    }
}

Describe "Get-Extension-Categories-By-Page Tests" {
    It "Returns extensions links by page" {
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching&pageID=1" } -MockWith {
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

        $result = Get-Extension-Categories-By-Page -extCategory 'Caching' -link '/packages.php?catpid=3&amp;catname=Caching' -page 1

        $result.availableExtensions.Count | Should -Be 4
        $result.availableExtensions[0].href | Should -Be '/package/APC'
        $result.availableExtensions[1].href | Should -Be '/package/APCu'
        $result.availableExtensions[2].href | Should -Be '/package/memcache'
        $result.availableExtensions[3].href | Should -Be '/package/memcached'
        $result.hasMore | Should -Be $false
    }

    It "Sets hasMore to true when more pages are available" {
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching&pageID=1" } -MockWith {
            return @{
                Content = 'Mocked PHP extension Caching content'
                Links = @(
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

        $result = Get-Extension-Categories-By-Page -extCategory 'Caching' -link '/packages.php?catpid=3&amp;catname=Caching' -page 1

        $result.hasMore | Should -Be $true
    }
}

Describe "Get-PHPExtensions-From-Source" {
    BeforeAll {
        Mock Cache-Data { return 0 }
        Mock Invoke-WebRequest -ParameterFilter { $Uri -eq $PECL_PACKAGES_URL } -MockWith {
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
        Mock Get-Extension-Categories-By-Page {
            param ($link)
            if ($link -eq '/packages.php?catpid=1&amp;catname=Authentication') {
                return @{
                    hasMore = $false
                    availableExtensions = @(
                        @{ href = '/package/courierauth' }
                        @{ href = '/package/krb5' }
                    )
                }
            }
            if ($link -eq '/packages.php?catpid=3&amp;catname=Caching') {
                return @{
                    hasMore = $false
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
        $list = Get-PHPExtensions-From-Source
        $list.Count | Should -Be 3 # include xdebug category
    }

    It "Handles thrown exception" {
        Mock Get-Extension-Categories-By-Page { throw 'Network error' }
        $list = Get-PHPExtensions-From-Source
        $list.Count | Should -Be 0
    }
}

Describe "List-PHP-Extensions" {
    BeforeAll {
        Mock Get-PHP-Data {
            return @{
                extensions = @(
                    @{Extension = 'curl'; Enabled = $true; Type = 'extension'}
                    @{Extension = 'opcache'; Enabled = $false; Type = 'zend_extension'}
                )
            }
        }

        function Get-Extension-List {
            return @{
                Authentication = @(
                    @{
                        outerHTML = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName = 'A';
                        href = '/package/courierauth';
                        extName = 'courierauth';
                        extCategory = 'Authentication';
                    },
                    @{
                        outerHTML = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName = 'A';
                        href = '/package/krb5';
                        extName = 'krb5';
                        extCategory = 'Authentication'
                    }
                )
                Caching = @(
                    @{
                        outerHTML = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName = 'A';
                        href = '/package/APC';
                        extName = 'APC';
                        extCategory = 'Caching'
                    }
                    @{
                        outerHTML = '<a href="/package/APC"><strong>APC</strong></a>';
                        tagName = 'A';
                        href = '/package/APCu';
                        extName = 'APCu';
                        extCategory = 'Caching'
                    }
                )
            }
        }
        Mock Get-Data-From-Cache { return Get-Extension-List }
        Mock Get-PHPExtensions-From-Source -MockWith{ return Get-Extension-List }
        Mock Display-Extensions-States {}
        Mock Display-Installed-Extensions {}
    }

    It "Returns -1 when no extensions are installed" {
        Mock Get-PHP-Data { return @{ extensions = @() } }
        $code = List-PHP-Extensions -iniPath $testIniPath
        $code | Should -Be -1
    }

    It "Displays installed extensions" {
        $code = List-PHP-Extensions -iniPath $testIniPath
        $code | Should -Be 0
        Assert-MockCalled Get-PHP-Data -Exactly 1
        Assert-MockCalled Display-Extensions-States -Exactly 1
        Assert-MockCalled Display-Installed-Extensions -Exactly 1
    }

    It "Displays local extensions matching the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -term 'pc'
        $code | Should -Be 0
        Assert-MockCalled Get-PHP-Data -Exactly 1
        Assert-MockCalled Display-Extensions-States -Exactly 1
        Assert-MockCalled Display-Installed-Extensions -Exactly 1
    }

    It "Returns -1 when no local extensions matchs the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -term 'nonexistent'
        $code | Should -Be -1
        Assert-MockCalled Get-PHP-Data -Exactly 1
        Assert-MockCalled Display-Extensions-States -Exactly 0
        Assert-MockCalled Display-Installed-Extensions -Exactly 0
    }

    It "Returns -1 when no extensions are found" {
        Mock Test-Path { return $false }
        Mock Get-PHPExtensions-From-Source { return @{} }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
        Assert-MockCalled Get-PHPExtensions-From-Source -Exactly 1
        Assert-MockCalled Get-Data-From-Cache -Exactly 0
    }

    It "Displays available extensions from cache" {
        Mock Can-Use-Cache { return $true }
        Mock Get-Data-From-Cache {
            return @{
                GUI = @(
                    @{href = '/package/php_xcb'; extName = 'php_xcb'; extCategory = 'GUI'}
                    @{href = '/package/tk'; extName = 'tk'; extCategory = 'GUI'}
                    @{href = '/package/php_xcb'; extName = 'php_xcb'; extCategory = 'GUI'}
                );
                Images = @(
                    @{href = '/package/cairo'; extName = 'cairo'; extCategory = 'Images'}
                    @{href = '/package/cairo_wrapper'; extName = 'cairo_wrapper'; extCategory = 'Images'}
                )
            }
        }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
        Assert-MockCalled Get-Data-From-Cache -Exactly 1
        Assert-MockCalled Get-PHPExtensions-From-Source -Exactly 0
    }

    It "Displays available extensions from source when cache is empty" {
        Mock Can-Use-Cache { return $true }
        Mock Get-Data-From-Cache { return @{} }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
        Assert-MockCalled Get-Data-From-Cache -Exactly 1
        Assert-MockCalled Get-PHPExtensions-From-Source -Exactly 1
    }

    It "Displays available extensions matching the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true -term 'pc'
        $code | Should -Be 0
    }

    It "Returns -1 when no available extensions matchs the filter" {
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true -term 'nonexistent'
        $code | Should -Be -1
    }

    It "Handles thrown exception" {
        Mock Can-Use-Cache { throw 'Error' }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
    }

    It "Returns -1 when available extensions count is 0" {
        Mock Can-Use-Cache { return $false }
        Mock Get-OrUpdateCache -ParameterFilter { $cacheFileName -eq 'available_extensions' } { return @{} }
        Mock Write-Host {}
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nNo extensions found"
        }
    }

    It "Displays available extensions with long descriptions that require wrapping" {
        Mock Can-Use-Cache { return $false }
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
        Mock -CommandName Get-Variable -ParameterFilter { $Name -eq 'Host' } -MockWith {
            return @{ Value = @{
                UI = @{
                    RawUI = @{
                        WindowSize = @{ Width = 50 }
                    }
                }
            }}
        }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
    }

    It "Displays available extensions with very long word without spaces to trigger breakPos fallback" {
        Mock Can-Use-Cache { return $false }
        Mock Get-OrUpdateCache -ParameterFilter { $cacheFileName -eq 'available_extensions' } {
            return @{
                TestCategory = @(
                    @{ extName = 'a' * 150; extCategory = 'TestCategory' }
                )
            }
        }
        $code = List-PHP-Extensions -iniPath $testIniPath -available $true
        $code | Should -Be 0
    }
}
