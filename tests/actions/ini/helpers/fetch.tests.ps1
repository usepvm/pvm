
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\fetch-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:testPhpPath = "$TEST_DRIVE\php"
    $script:XDEBUG_HISTORICAL_URL = $PVMConfig.links.xdebugHistorical
    $script:PECL_BASE_URL = $PVMConfig.links.peclBase
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

Describe "Get-ExtensionHandlers Tests" {
    It "Returns unified handler registry with both source and config handlers" {
        $handlers = Get-ExtensionHandlers

        $handlers.SourceHandlers | Should -Not -BeNullOrEmpty
        $handlers.ExtensionConfigHandlers | Should -Not -BeNullOrEmpty
        $handlers.SourceHandlers.ContainsKey('xdebug.org') | Should -Be $true
        $handlers.SourceHandlers.ContainsKey('pecl.php.net') | Should -Be $true
        $handlers.ExtensionConfigHandlers.ContainsKey('xdebug') | Should -Be $true
    }
}

Describe "Get-SourceHandler Tests" {
    It "Returns correct handler for xdebug.org source" {
        $handler = Get-SourceHandler -sourceUrl 'xdebug.org'

        $handler | Should -Not -BeNullOrEmpty
        $handler.GetPackages | Should -Not -BeNullOrEmpty
        $handler.Download | Should -Not -BeNullOrEmpty
        $handler.MoreInfoUrl | Should -Not -BeNullOrEmpty
    }

    It "Returns correct handler for pecl.php.net source" {
        $handler = Get-SourceHandler -sourceUrl 'pecl.php.net'

        $handler | Should -Not -BeNullOrEmpty
        $handler.GetPackages | Should -Not -BeNullOrEmpty
        $handler.Download | Should -Not -BeNullOrEmpty
        $handler.MoreInfoUrl | Should -Not -BeNullOrEmpty
    }

    It "Returns default PECL handler for unknown sources" {
        $handler = Get-SourceHandler -sourceUrl 'unknown.source.com'

        $handler | Should -Not -BeNullOrEmpty
        # Should return the pecl.php.net handler as default
        $handler.MoreInfoUrl | Should -Not -BeNullOrEmpty
    }

    Context "When running source actions (download, configure and link) from xdebug source handler" {
        BeforeEach {
            Mock Show-SpinnerWhileJob {
                param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
                $result = & $scriptBlock @argumentList
                return $result.pvmData
            }
        }

        It "Returns data null when no handler found for xdebug" {
            Mock Get-CurrentPHPVersion { return @{ version = '8.2'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.2.0" } }
            Mock Get-OrUpdateCache { return $null }

            $handler = Get-SourceHandler -sourceUrl 'xdebug.org'

            Mock Get-SourceHandler { return $null }
            $result = & $handler.ResolveLinks -extName 'xdebug'

            $result.data | Should -BeNullOrEmpty
        }

        It "Returns data null when no packages found" {
            Mock Get-CurrentPHPVersion { return @{ version = '8.2'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.2.0" } }
            Mock Get-OrUpdateCache { return $null }

            $handler = Get-SourceHandler -sourceUrl 'xdebug.org'

            $result = & $handler.ResolveLinks -extName 'xdebug'

            $result.data | Should -BeNullOrEmpty
        }

        It "Resolves and returns xdebug links" {
            Mock Get-CurrentPHPVersion { return @{ version = '8.2'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.2.0" } }
            Mock Get-OrUpdateCache {
                return @{
                    extName = 'curl'
                    data    = @(
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.1/php_curl-1.4.1-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.1/php_curl-1.4.1-8.2-nts-vs16-x86.zip"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0' }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x64.zip"; arch = 'x64'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0' }
                    )
                }
            }

            $handler = Get-SourceHandler -sourceUrl 'xdebug.org'

            $result = & $handler.ResolveLinks -extName 'xdebug'

            $result.source | Should -Be 'xdebug.org'
            $result.data.Count | Should -Be 2
            $result.extName | Should -Be 'xdebug'
        }

        It "Returns null when user cancels" {
            Mock Get-XDebugFromUrl { return $null }
            Mock Invoke-WebRequestWrapper { return $null }
            Mock Test-FileExists { return $true }
            $chosenItem = @{ fileName = 'php_xdebug-3.5.3-8.3-ts-vs16-x86_64.dll'; }
            Mock Read-HostWrapper -ParameterFilter { $prompt -like "*$($chosenItem.fileName) already exists. Would you like to overwrite it?*" } -MockWith { return 'n' }
            Mock Remove-ItemWrapper { }

            $handler = Get-SourceHandler -sourceUrl 'xdebug.org'

            $handler | Should -Not -BeNullOrEmpty
            $handler.GetPackages | Should -Not -BeNullOrEmpty
            $handler.Download | Should -Not -BeNullOrEmpty
            $handler.MoreInfoUrl | Should -Be $XDEBUG_HISTORICAL_URL

            $null = & $handler.GetPackages -version '8.5'
            $result = & $handler.Download -chosenItem $chosenItem -phpPath $testPhpPath -skipConfirmation $false

            $result | Should -BeNullOrEmpty
            Should -Invoke Get-XDebugFromUrl -Times 1
            Should -Invoke Invoke-WebRequestWrapper -Times 1
            Should -Invoke Write-Gray -ParameterFilter { $message -like '*Installation cancelled*' }
        }

        It "Returns downloaded file" {
            Mock Get-XDebugFromUrl { return $null }
            Mock Invoke-WebRequestWrapper { return $null }
            $chosenItem = @{ fileName = 'php_xdebug-3.5.3-8.3-ts-vs16-x86_64.dll'; }
            Mock Move-ItemWrapper { }

            $handler = Get-SourceHandler -sourceUrl 'xdebug.org'

            $handler | Should -Not -BeNullOrEmpty
            $handler.GetPackages | Should -Not -BeNullOrEmpty
            $handler.Download | Should -Not -BeNullOrEmpty
            $handler.MoreInfoUrl | Should -Be $XDEBUG_HISTORICAL_URL

            $null = & $handler.GetPackages -version '8.5'
            $result = & $handler.Download -chosenItem $chosenItem -phpPath $testPhpPath -skipConfirmation $true

            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $chosenItem.fileName
            $result.FullName | Should -Be "$($PVMConfig.paths.directories.php)\$($chosenItem.fileName)"
            Should -Invoke Get-XDebugFromUrl -Times 1
            Should -Invoke Invoke-WebRequestWrapper -Times 1
            Should -Invoke Move-ItemWrapper -Times 1
        }

        It "Handles exception gracefully" {
            Mock Get-XDebugFromUrl { return $null }
            Mock Invoke-WebRequestWrapper { throw 'Error' }
            Mock Add-LogEntry { return 0 }

            $handler = Get-SourceHandler -sourceUrl 'xdebug.org'

            $handler | Should -Not -BeNullOrEmpty
            $handler.GetPackages | Should -Not -BeNullOrEmpty
            $handler.Download | Should -Not -BeNullOrEmpty
            $handler.MoreInfoUrl | Should -Be $XDEBUG_HISTORICAL_URL

            $null = & $handler.GetPackages -version '8.5'
            $result = & $handler.Download -chosenItem $chosenItem -phpPath $testPhpPath -skipConfirmation $true

            $result | Should -BeNullOrEmpty
            Should -Invoke Get-XDebugFromUrl -Times 1
            Should -Invoke Invoke-WebRequestWrapper -Times 1
            Should -Invoke Add-LogEntry -Times 1
        }
    }

    Context "When running source actions (download and configure) from pecl source handler" {
        BeforeEach {
            Mock Show-SpinnerWhileJob {
                param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
                $result = & $scriptBlock @argumentList
                return $result.pvmData
            }
        }

        It "Resolves and returns extension links" {
            Mock Get-CurrentPHPVersion { return @{ version = '8.2'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.2.0" } }
            Mock Get-ExtensionPackages {
                return @{
                    extName = 'curl'
                    source  = 'pecl.php.net'
                    data    = @(
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.1/php_curl-1.4.1-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.1/php_curl-1.4.1-8.2-nts-vs16-x86.zip"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0' }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                    )
                }
            }

            $handler = Get-SourceHandler -sourceUrl 'pecl.php.net'

            $result = & $handler.ResolveLinks -extName 'curl'

            $result.source | Should -Be 'pecl.php.net'
            $result.data.Count | Should -Be 3
            $result.extName | Should -Be 'curl'
        }

        It "Returns null when no dll file found in downloaded zip" {
            Mock Get-PackagesFromSourceLinks { return $null }
            Mock Invoke-WebRequestWrapper { return $null }
            $chosenItem = @{ fileName = 'php_xdebug-3.5.3-8.3-ts-vs16-x86_64.dll'; }
            Mock Expand-Zip { }
            Mock Get-ChildItemWrapper { return @() }
            Mock Remove-ItemWrapper { }

            $handler = Get-SourceHandler -sourceUrl 'pecl.php.net'

            $handler | Should -Not -BeNullOrEmpty
            $handler.GetPackages | Should -Not -BeNullOrEmpty
            $handler.Download | Should -Not -BeNullOrEmpty
            $handler.MoreInfoUrl | Should -Not -BeNullOrEmpty

            $links = @{
                extName = 'xdebug'
                source = 'pecl.php.net'
                links = @(
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.4.0/windows" },
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.3.0/windows" },
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.2.0/windows" }
                )
            }

            $null = & $handler.GetPackages -version '8.5' -linksObj $links
            $result = & $handler.Download -chosenItem $chosenItem -phpPath $testPhpPath -skipConfirmation $true -extName 'xdebug'

            $result | Should -BeNullOrEmpty
            Should -Invoke Get-PackagesFromSourceLinks -Times 1
        }

        It "Returns null when user cancels" {
            Mock Get-PackagesFromSourceLinks { return $null }
            Mock Invoke-WebRequestWrapper { return $null }
            Mock Expand-Zip { }
            $mockFile = @{ Name = 'php_xdebug.dll'; FullName = "$TEST_DRIVE\extracted\php_xdebug.dll" }
            Mock Get-ChildItemWrapper { return @( $mockFile ) }
            $chosenItem = @{ fileName = 'php_xdebug-3.5.3-8.3-ts-vs16-x86_64.dll'; }
            Mock Test-FileExists { return $true }
            Mock Read-HostWrapper -ParameterFilter { $prompt -like "*$($mockFile.Name) already exists. Would you like to overwrite it?*" } -MockWith { return 'n' }
            Mock Remove-ItemWrapper { }

            $handler = Get-SourceHandler -sourceUrl 'pecl.php.net'

            $handler | Should -Not -BeNullOrEmpty
            $handler.GetPackages | Should -Not -BeNullOrEmpty
            $handler.Download | Should -Not -BeNullOrEmpty
            $handler.MoreInfoUrl | Should -Not -BeNullOrEmpty

            $links = @{
                extName = 'xdebug'
                source = 'pecl.php.net'
                links = @(
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.4.0/windows" },
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.3.0/windows" },
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.2.0/windows" }
                )
            }
            $null = & $handler.GetPackages -version '8.5' -linksObj $links
            $result = & $handler.Download -chosenItem $chosenItem -phpPath $testPhpPath -skipConfirmation $false -extName 'xdebug'
            $link = & $handler.MoreInfoUrl -extName 'xdebug'

            $result | Should -BeNullOrEmpty
            $link | Should -Be "$PECL_PACKAGE_ROOT_URL/xdebug"
            Should -Invoke Write-Gray -ParameterFilter { $message -like '*Installation cancelled*' }
            Should -Invoke Get-PackagesFromSourceLinks -Times 1
        }

        It "Returns downloaded file" {
            Mock Get-PackagesFromSourceLinks { return $null }
            Mock Invoke-WebRequestWrapper { return $null }
            Mock Expand-Zip { }
            Mock Move-ItemWrapper { }
            Mock Remove-ItemWrapper { }
            $mockFile = @{ Name = 'php_xdebug.dll'; FullName = "$TEST_DRIVE\extracted\php_xdebug.dll" }
            Mock Get-ChildItemWrapper { return @( $mockFile ) }
            $chosenItem = @{ fileName = 'php_xdebug-3.5.3-8.3-ts-vs16-x86_64.dll'; }

            $handler = Get-SourceHandler -sourceUrl 'pecl.php.net'

            $handler | Should -Not -BeNullOrEmpty
            $handler.GetPackages | Should -Not -BeNullOrEmpty
            $handler.Download | Should -Not -BeNullOrEmpty
            $handler.MoreInfoUrl | Should -Not -BeNullOrEmpty

            $links = @{
                extName = 'xdebug'
                source = 'pecl.php.net'
                links = @(
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.4.0/windows" },
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.3.0/windows" },
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.2.0/windows" }
                )
            }
            $null = & $handler.GetPackages -version '8.5' -linksObj $links
            $result = & $handler.Download -chosenItem $chosenItem -phpPath $testPhpPath -skipConfirmation $true -extName 'xdebug'

            $result.FullName | Should -Be $mockFile.FullName
            $result.Name | Should -Be $mockFile.Name
            Should -Invoke Get-PackagesFromSourceLinks -Times 1
        }

        It "Handles exception gracefully" {
            Mock Get-PackagesFromSourceLinks { return $null }
            Mock Invoke-WebRequestWrapper { throw 'Error' }
            Mock Add-LogEntry { return 0 }

            $handler = Get-SourceHandler -sourceUrl 'pecl.php.net'

            $handler | Should -Not -BeNullOrEmpty
            $handler.GetPackages | Should -Not -BeNullOrEmpty
            $handler.Download | Should -Not -BeNullOrEmpty
            $handler.MoreInfoUrl | Should -Not -BeNullOrEmpty

            $links = @{
                extName = 'xdebug'
                source = 'pecl.php.net'
                links = @(
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.4.0/windows" },
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.3.0/windows" },
                    @{ href = "$PECL_BASE_URL/package/xdebug/3.2.0/windows" }
                )
            }
            $null = & $handler.GetPackages -version '8.5' -linksObj $links
            $result = & $handler.Download -chosenItem $chosenItem -phpPath $testPhpPath -skipConfirmation $true -extName 'xdebug'

            $result | Should -BeNullOrEmpty
            Should -Invoke Get-PackagesFromSourceLinks -Times 1
            Should -Invoke Invoke-WebRequestWrapper -Times 1
            Should -Invoke Add-LogEntry -Times 1
        }
    }
}

Describe "Get-ExtensionConfigHandler Tests" {
    It "Returns xdebug config handler for xdebug extension" {
        $handler = Get-ExtensionConfigHandler -extName 'php_xdebug.dll'

        $handler | Should -Not -BeNullOrEmpty
        # Should return the xdebug config handler scriptblock
        $handler.GetType().Name | Should -Be 'ScriptBlock'
    }

    It "Returns xdebug config handler for xdebug without prefix" {
        $handler = Get-ExtensionConfigHandler -extName 'xdebug.dll'

        $handler | Should -Not -BeNullOrEmpty
        $handler.GetType().Name | Should -Be 'ScriptBlock'
    }

    It "Returns xdebug config handler for xdebug with version" {
        $handler = Get-ExtensionConfigHandler -extName 'php_xdebug-3.1.0-8.1-vs16-x64.dll'

        $handler | Should -Not -BeNullOrEmpty
        $handler.GetType().Name | Should -Be 'ScriptBlock'
    }

    It "Returns default handler for unknown extensions" {
        Mock Add-MissingPHPExtensionToIni { 0 }

        $handler = Get-ExtensionConfigHandler -extName 'php_unknown.dll'

        $handler | Should -Not -BeNullOrEmpty
        $handler.GetType().Name | Should -Be 'ScriptBlock'
        $code = & $handler $iniPath $null $fileName $null $extVersion $null
        $code | Should -Be 0
        Should -Invoke Add-MissingPHPExtensionToIni -Times 1
    }

    It "Returns default handler for empty input" {
        $handler = Get-ExtensionConfigHandler -extName ''

        $handler | Should -Not -BeNullOrEmpty
        $handler.GetType().Name | Should -Be 'ScriptBlock'
    }

    Context "When running config actions from selected config handler" {
        It "Configures xdebug in ini file" {
            Mock Get-ContentWrapper { return '' }
            Mock Add-ContentWrapper { }

            $configHandler = Get-ExtensionConfigHandler -extName 'xdebug'

            $result = & $configHandler -iniPath $testIniPath -fileName 'php_xdebug.dll' -extVersion '3.5'

            $configHandler | Should -Not -BeNullOrEmpty
            $result | Should -Be 0
            Should -Invoke Add-ContentWrapper -Times 1
        }

        It "Handles exception gracefully" {
            Mock Get-ContentWrapper { throw 'Error' }
            Mock Add-LogEntry { return 0 }

            $configHandler = Get-ExtensionConfigHandler -extName 'xdebug'

            $result = & $configHandler -iniPath $testIniPath -fileName 'php_xdebug.dll' -extVersion '3.5'

            $configHandler | Should -Not -BeNullOrEmpty
            $result | Should -Be -1
            Should -Invoke Add-LogEntry -Times 1
        }

        It "Configures curl in ini file" {
            Mock Add-MissingPHPExtensionToIni { return 0 }

            $configHandler = Get-ExtensionConfigHandler -extName 'curl'

            $result = & $configHandler -iniPath $testIniPath -fileName 'php_curl.dll' -extVersion '1.5'

            $configHandler | Should -Not -BeNullOrEmpty
            $result | Should -Be 0
            Should -Invoke Add-MissingPHPExtensionToIni -Times 1
        }
    }
}

Describe "Get-XDebugFromUrl Tests" {
    BeforeAll {
        function Reset-MockState {
            $script:MockRegistryThrowException = $false
            $script:MockFileSystem.DownloadFails = $false
            $script:MockFileSystem.WebResponses = @{}
            $script:MockFileSystem.Files = @{}
            $script:MockFileSystem.Directories = @()
        }

        function Set-MockWebResponse {
            param ($url, $content, $links = @())
            $script:MockFileSystem.WebResponses[$url] = @{
                Content = $content
                Links   = $links
            }
        }
    }
    BeforeEach {
        Reset-MockState
    }

    It "Should parse XDebug versions correctly" {
        $mockLinks = @(
            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-3.1.0-8.1-vs16-x86_64.dll" },
            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-2.9.0-8.1-vs16-x86_64.dll" },
            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll" },
            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll" },
            @{ href = "$XDEBUG_BASE_URL/download/php_random.dll" }
        )
        Set-MockWebResponse -url 'https://test.com' -links $mockLinks

        $result = Get-XDebugFromUrl -url 'https://test.com' -version '8.1'

        $result.Count | Should -Be 4
        $result[0].extVersion | Should -Be '3.1.0'
        $result[1].extVersion | Should -Be '2.9.0'
    }

    It "Should handle network errors" {
        $script:MockFileSystem.DownloadFails = $true

        $result = Get-XDebugFromUrl -url 'https://test.com' -version '8.1'

        $result | Should -Be @()
    }

    It "Should parse xdebug with x86 architecture and unknown compiler" {
        $mockLinks = @(
            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-3.1.0-8.1-x86.dll" },
            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-2.9.0-8.1-nts-x86.dll" }
        )
        Set-MockWebResponse -url 'https://test.com' -links $mockLinks

        $result = Get-XDebugFromUrl -url 'https://test.com' -version '8.1'

        $result.Count | Should -Be 2
        $result[0].arch | Should -Be 'x86'
        $result[0].compiler | Should -Be 'unknown'
        $result[1].arch | Should -Be 'x86'
        $result[1].compiler | Should -Be 'unknown'
    }
}

Describe "Get-XdebugConfigV2 Tests" {
    It "Fetchs xdebug v2 config" {
        $res = Get-XdebugConfigV2 -XDebugPath 'php_xdebug.dll'

        $res[0] | Should -Be '[xdebug]'
        $res[1] | Should -Be ";zend_extension='php_xdebug.dll'"
        $res[2] | Should -Be 'xdebug.remote_enable=1'
        $res[3] | Should -Be 'xdebug.remote_host=127.0.0.1'
        $res[4] | Should -Be 'xdebug.remote_port=9000'
    }
}

Describe "Get-XdebugConfigV2 Tests" {
    It "Fetchs xdebug v3 config" {
        $res = Get-XdebugConfigV3 -XDebugPath 'php_xdebug.dll'

        $res[0] | Should -Be '[xdebug]'
        $res[1] | Should -Be ";zend_extension='php_xdebug.dll'"
        $res[2] | Should -Be 'xdebug.mode=debug'
        $res[3] | Should -Be 'xdebug.client_host=127.0.0.1'
        $res[4] | Should -Be 'xdebug.client_port=9003'
    }
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
        $result.availableExtensions[0].href | Should -Be "$PECL_BASE_URL/package/APC"
        $result.availableExtensions[1].href | Should -Be "$PECL_BASE_URL/package/APCu"
        $result.availableExtensions[2].href | Should -Be "$PECL_BASE_URL/package/memcache"
        $result.availableExtensions[3].href | Should -Be "$PECL_BASE_URL/package/memcached"
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

Describe "Get-ExtensionAvailableReleasesLinks" {
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

        $result = Get-ExtensionAvailableReleasesLinks -extName 'memcache'

        $result.Count | Should -Be 3
        $result[0].href | Should -Be "$PECL_BASE_URL/package/memcache/3.4.0/windows"
        $result[1].href | Should -Be "$PECL_BASE_URL/package/memcache/3.3.0/windows"
        $result[2].href | Should -Be "$PECL_BASE_URL/package/memcache/3.2.0/windows"
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
            @{ href = "$PECL_BASE_URL/package/memcache/3.4.0/windows" },
            @{ href = "$PECL_BASE_URL/package/memcache/3.3.0/windows" },
            @{ href = "$PECL_BASE_URL/package/memcache/3.2.0/windows" }
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
                    @{ href = '/package/mysqlnd_memcache'; extName = 'mysqlnd_memcache'; extCategory = 'Database'; source = 'pecl.php.net' },
                    @{ href = '/package/memcache'; extName = 'memcache'; extCategory = 'Caching'; source = 'pecl.php.net' },
                    @{ href = '/package/memcached'; extName = 'memcached'; extCategory = 'Caching'; source = 'pecl.php.net' }
                )
            }
        }

        It "Prompts user to select link when multiple found and returns selected" {
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '0' }

            $result = Select-ExtensionFromMatches -linksMatchingExtName (Get-ExtensionList)

            $result.extName | Should -Be 'memcache'
        }

        It "Returns null when user skips selection" {
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '' }

            $result = Select-ExtensionFromMatches -linksMatchingExtName (Get-ExtensionList)

            $result | Should -Be $null
            Should -Invoke Write-Gray -Times 1 -ParameterFilter {
                $message -eq "`nInstallation cancelled"
            }
        }

        It "Reprompts user when typing invalid choice" {
            $script:callCount = 0
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) { return 'A' }
                if ($script:callCount -eq 2) { return '-1' }
                else { return '0' }
            }

            $extList = Get-ExtensionList
            $result = Select-ExtensionFromMatches -linksMatchingExtName $extList

            $result.extName | Should -Be 'memcache'
            Should -Invoke Show-Warning -ParameterFilter { $message -eq 'Please enter a valid positive number.'}
            Should -Invoke Show-Warning -ParameterFilter { $message -eq "Number must be between 0 and $($extList.Length - 1)." }
        }
    }
}

Describe "Resolve-ExtensionLinks Tests" {
    BeforeEach {
        $PVMConfig.paths.directories.cache = "$TEST_DRIVE\cache"
    }

    It "Returns filtered links" {
        Mock Test-CanUseCache { return $false }
        Mock Get-ExtensionAvailableReleasesLinks {
            return @(
                @{ href = '/package/memcache/3.4.0/windows' },
                @{ href = '/package/memcache/3.3.0/windows' },
                @{ href = '/package/memcache/3.2.0/windows' }
            )
        }

        $result = Resolve-ExtensionLinks -extName 'memcache' -version '8.2'

        $result.extName | Should -Be 'memcache'
        $result.links.Count | Should -Be 3
    }

    Context "When extension has no direct link" {
        BeforeEach {
            Mock Test-CanUseCache { return $false }
            Mock Get-ExtensionAvailableReleasesLinks -ParameterFilter { $extName -eq 'mem' } { throw 'Error' }
            Mock Get-ExtensionAvailableReleasesLinks -ParameterFilter { $extName -eq 'memcache' } {
                @{ href = '/package/memcache/3.4.0/windows' },
                @{ href = '/package/memcache/3.3.0/windows' },
                @{ href = '/package/memcache/3.2.0/windows' }
            }
        }

        It "Returns null when no matching categories links found" {
            Mock Get-ExtensionMatchingCategories { return @() }

            $result = Resolve-ExtensionLinks -extName 'mem' -version '8.2'

            $result | Should -Be $null
        }

        It "Takes the only link found" {
            Mock Get-ExtensionMatchingCategories { return @( @{ href = '/package/memcache'; extName = 'memcache'; source = 'pecl.php.net' } ) }

            $result = Resolve-ExtensionLinks -extName 'mem' -version '8.2'

            $result.extName | Should -Be 'memcache'
            $result.links.Count | Should -Be 3
        }

        It "Should return empty links for sources other than pecl" {
            Mock Get-ExtensionMatchingCategories { return @(
                    @{ href = "$XDEBUG_HISTORICAL_URL"; extName = 'xdebug'; source = 'xdebug.org' }
                )
            }

            $result = Resolve-ExtensionLinks -extName 'debug' -version '8.2'

            $result.extName | Should -Be 'xdebug'
            $result.links.Count | Should -Be 0
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
        Mock Select-ExtensionFromMatches { return $null }

        $result = Resolve-ExtensionLinks -extName 'mem' -version '8.2'

        # Should return null and show error message when chosen item is null
        $result | Should -Be $null
    }
}

Describe "Get-ExtensionPackages Tests" {
    BeforeEach {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
    }

    It "Should parse extension versions correctly" {
        Mock Test-CanUseCache { return $false }
        Mock Resolve-ExtensionLinks {
            return @{
                extName = 'memcache'
                source = 'pecl.php.net'
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
        $result = Get-ExtensionPackages -extName 'memcache' -version '8.2'

        $result.data.Count | Should -Be 3
        $result.data[0].extVersion | Should -Be '3.4.0'
        $result.data[1].extVersion | Should -Be '3.3.0'
        $result.data[2].extVersion | Should -Be '3.2.0'
    }

    It "Returns null when no version found for extension" {
        Mock Resolve-ExtensionLinks { return $null }

        $result = Get-ExtensionPackages -extName 'cache' -version '8.2'

        $result.data | Should -Be $null
        $result.source | Should -Be 'unknown'
    }

    It "Uses extName from linksObj when links are empty" {
        Mock Resolve-ExtensionLinks {
            return @{ extName = 'memcache'; source = 'pecl.php.net'; links = @() }
        }

        $result = Get-ExtensionPackages -extName 'mem' -version '8.2'

        $result.extName | Should -Be 'memcache'
        $result.data   | Should -Be $null
    }

    It "Returns null when no handler found" {
        Mock Resolve-ExtensionLinks {
            return @{ extName = 'memcache'; source = 'pecl.php.net'; links = @() }
        }
        Mock Get-SourceHandler { return $null }

        $result = Get-ExtensionPackages -extName 'mem' -version '8.2'

        $result.extName | Should -Be 'memcache'
        $result.data    | Should -Be $null
        $result.source  | Should -Be 'pecl.php.net'
    }

    It "Runs GetPackages for packages from sources other than pecl" {
        Mock Get-OrUpdateCache { return $null }
        Mock Resolve-ExtensionLinks {
            return @{ extName = 'xdebug'; source = 'xdebug.org'; links = @() }
        }

        $result = Get-ExtensionPackages -extName 'mem' -version '8.2'

        $result.extName | Should -Be 'xdebug'
        $result.data    | Should -Be $null
        $result.source  | Should -Be 'xdebug.org'
        Should -Invoke Get-OrUpdateCache -Times 1
    }
}
