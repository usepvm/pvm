
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\add-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.paths.directories.cache -Force | Out-Null

    $script:XDEBUG_BASE_URL = $PVMConfig.links.xdebugBase
    $script:PECL_PACKAGES_URL = $PVMConfig.links.peclPackages
    $script:XDEBUG_DOWNLOAD_URL = $PVMConfig.links.xdebugDownload
    $script:XDEBUG_HISTORICAL_URL = $PVMConfig.links.xdebugHistorical
    $script:PECL_PACKAGE_ROOT_URL = $PVMConfig.links.peclPackageRoot
    $script:PECL_WIN_EXT_DOWNLOAD_URL = $PVMConfig.links.peclWinExtDownload

    Mock New-Line {}
    Mock Show-Warning {}
    Mock Show-Message {}
    Mock Show-Error {}
    Mock Show-Success {}
    Mock Show-Info {}
    Mock Write-Gray {}

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
"@ | Set-ContentWrapper -path $testIniPath
    }

    # Create initial ini content first
    Reset-IniContent

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$TEST_DRIVE\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    Copy-ItemWrapper -path $testIniPath -destination "$phpVersionPath\php.ini"

    # Mock Add-LogEntry function
    Mock Add-LogEntry {
        param ($logPath, $message, $data)
        return $true
    }

    # Mock Get-CurrentPHPVersion function
    Mock Get-CurrentPHPVersion {
        return @{
            version = '8.2.0'
            path    = $phpVersionPath
        }
    }

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
        $handler = Get-ExtensionConfigHandler -extName 'php_unknown.dll'

        $handler | Should -Not -BeNullOrEmpty
        $handler.GetType().Name | Should -Be 'ScriptBlock'
    }

    It "Returns default handler for empty input" {
        $handler = Get-ExtensionConfigHandler -extName ''

        $handler | Should -Not -BeNullOrEmpty
        $handler.GetType().Name | Should -Be 'ScriptBlock'
    }
}

Describe "Install-Extension Tests" {
    BeforeAll {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
        Mock Get-CurrentPHPVersion { return @{ version = '8.2'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.2.0" } }
        Mock Read-HostWrapper {
            param ($Prompt)
            if ($Prompt -eq "`nEnter the [number] of your selection") {
                return '0'
            }
        }
        Mock Add-MissingPHPExtensionToIni { return 0 }
        Mock Invoke-WebRequestWrapper { }
        Mock Move-ItemWrapper { }
        Mock Get-ContentWrapper { return "zend_extension=opcache" }
        Mock Add-ContentWrapper { }
    }

    It "Successfully installs extension using source handler" {
        Mock Invoke-WebRequestWrapper { return $null }
        Mock Expand-Zip { }
        Mock Move-ItemWrapper { }
        Mock Remove-ItemWrapper { }
        $mockFile = @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" }
        Mock Get-ChildItemWrapper { return @( $mockFile ) }
        Mock Add-MissingPHPExtensionToIni { return 0 }
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

        $code = Install-Extension -iniPath $testIniPath -extName 'curl' -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Add-MissingPHPExtensionToIni -Exactly 1
    }

    It "Uses extension config handler for configuration" {
        $mockFile = @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" }
        Mock Get-ChildItemWrapper { return @( $mockFile ) }
        Mock Get-ExtensionConfigHandler {
            param ($extName)
            return {
                param ($iniPath, $fileName, $extVersion)
                # Mock config handler
                return 0
            }
        }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'xdebug'
                source = 'xdebug.org'
                data = @(
                    @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-3.1.0-8.1-vs16-x64.dll"; arch = 'x64'; buildType = 'ts'; version = '8.1'; extVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x64.dll' }
                )
            }
        }

        $code = Install-Extension -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Get-ExtensionConfigHandler -Exactly 1
    }

    It "Returns -1 when no packages found" {
        Mock Get-ExtensionPackages { return @{ extName = 'xdebug'; data = $null; source = 'xdebug.org' } }

        $code = Install-Extension -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be -1
        Should -Invoke Show-Error -Exactly 1
    }
}

Describe "Add-MissingPHPExtensionToIni" {
    BeforeEach {
        Reset-IniContent
        Remove-ItemWrapper -path $testBackupPath -ErrorAction SilentlyContinue
        Mock Get-ZendExtensionsList { return @('xdebug', 'opcache') }
    }

    It "Returns -1 when current PHP version is null" {
        Mock Get-CurrentPHPVersion { return @{ version = $null; path = $null } }
        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'curl'
        $result | Should -Be -1
    }

    It "Adds and configures xdebug in ini file" {
        Mock Get-MatchingPHPExtensionsStatus { return @( @{ name = 'xdebug'; status = 'Enabled'; enabled = $true; color = 'DarkGreen'; LineNumber = 0 } )}
        Mock Test-Path { return $true }
        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'php_xdebug.dll'
        $result | Should -Be 0
        Should -Invoke Show-Success -Times 1 -ParameterFilter {
            $message -like "- 'php_xdebug.dll' added successfully."
        }
    }

    It "Returns 0 and shows warning when extension already exists in ini file" {
        Mock Get-MatchingPHPExtensionsStatus { return @( @{ name = 'xdebug'; status = 'Enabled'; enabled = $true; color = 'DarkGreen'; LineNumber = 150 } )}
        Mock Test-Path { return $true }
        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'php_xdebug.dll'
        $result | Should -Be 0
        Should -Invoke Show-Warning -Times 1 -ParameterFilter {
            $message -eq "- Extension 'php_xdebug.dll' already exists in php.ini"
        }
    }

    It "Adds any extension to ini file" {
        @"
zend_extension=php_opcache.dll
extension=php_mbstring.dll
"@ | Set-ContentWrapper -path $testIniPath

        Mock Test-Path { return $true }
        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'php_curl.dll'
        $result | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match 'extension=php_curl.dll' | Should -Be $true
        Should -Invoke Show-Success -Times 1 -ParameterFilter {
            $message -eq "- 'php_curl.dll' added successfully."
        }
    }

    It "Adds any extension in disabled state to ini file" {
        @"
zend_extension=php_opcache.dll
;extension=php_mbstring.dll
"@ | Set-ContentWrapper -path $testIniPath

        Mock Test-Path { return $true }
        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'php_curl.dll' -enable $false
        $result | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match ';extension=php_curl.dll' | Should -Be $true
    }

    It "Adds extensions correctly for older PHP versions" {
        @"
zend_extension=php_opcache.dll
extension=php_mbstring.dll
"@ | Set-ContentWrapper -path $testIniPath

        Mock Test-Path { return $true }
        Mock Get-CurrentPHPVersion { return @{ version = '7.1.0'; path = "$TEST_DRIVE\php\7.1.0" } }
        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'php_curl.dll'
        $result | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match 'extension=php_curl.dll' | Should -Be $true
    }

    It "Adds zend_extensions correctly" {
        @"
extension=php_mbstring.dll
"@ | Set-ContentWrapper -path $testIniPath

        Mock Test-Path { return $true }
        Mock Get-CurrentPHPVersion { return @{ version = '7.1.0'; path = "$TEST_DRIVE\php\7.1.0" } }
        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'php_opcache.dll'
        $result | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match 'zend_extension=php_opcache.dll' | Should -Be $true
    }

    It "Returns -1 for non-existent ini file" {
        Mock Test-Path { return $false }
        $result = Add-MissingPHPExtensionToIni -iniPath 'nonexistent.ini' -extFileName 'php_curl.dll'
        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nphp.ini file not found: nonexistent.ini"
        }
    }

    It "Returns -1 when extension directory doesn't exist" {
        Mock Test-Path -ParameterFilter { $Path -eq $testIniPath } { return $true }
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } { return $false }

        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'php_curl.dll'

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nExtensions directory not found: $extDirectory"
        }
    }

    It "Returns -1 when extension file doesn't exist" {
        Mock Test-Path -ParameterFilter { $Path -eq $testIniPath } { return $true }
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } { return $true }
        Mock Test-Path -ParameterFilter { $Path -eq "$extDirectory\php_curl.dll" } { return $false }

        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'php_curl.dll'

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nExtension file not found: php_curl.dll"
        }
    }

    It "Handles exception gracefully" {
        Mock Add-LogEntry { return 0 }
        Mock Backup-IniFile { throw 'Access denied' }
        $result = Add-MissingPHPExtensionToIni -iniPath $testIniPath -extFileName 'curl'
        $result | Should -Be -1
    }
}

Describe "Install-Extension" {
    BeforeAll {
        $script:MockFileSystem = @{
            Directories   = @()
            Files         = @{}
            WebResponses  = @{}
            DownloadFails = $false
        }

        Mock Read-HostWrapper {
            param ($Prompt)
            if ($Prompt -eq "`nEnter the [number] of your selection") {
                return '0'
            }
        }

        Mock Get-ChildItemWrapper {
            if ($script:getRandomFile) {
                return @( @{ Name = 'random_file' } )
            }
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\php_curl-1.4.0-7.4-ts-vc15-x86\php_curl.dll" } )
        }
        Mock Expand-Zip { }
        Mock Remove-ItemWrapper { }
        Mock Move-ItemWrapper { }
        Mock Test-Path { return $true }
    }

    BeforeEach {
        Mock Show-SpinnerWhileJob {
            param ($scriptBlock, $message, $noClear, $argumentList, $rethrow)
            $result = & $scriptBlock @argumentList
            return $result.pvmData
        }
        $script:getRandomFile = $false
        $script:MockFileSystem.DownloadFails = $false
        $script:MockFileSystem.WebResponses = @{
            "$PECL_PACKAGE_ROOT_URL/nonexistent_ext"                                                 = @{
                Content = 'Mocked PHP nonexistent_ext content'
                Links   = @()
            }
            "$PECL_PACKAGE_ROOT_URL/pdo_mysql"                                                       = @{
                Content = 'Mocked pdo_mysql content'
                Links   = @(
                    @{ href = '/package/pdo_mysql/1.4.0/windows' },
                    @{ href = '/package/pdo_mysql/2.1.0/windows' }
                )
            }
            "$PECL_PACKAGE_ROOT_URL/curl"                                                            = @{
                Content = 'Mocked curl content'
                Links   = @(
                    @{ href = '/package/curl/1.4.0/windows' },
                    @{ href = '/package/curl/2.1.0/windows' }
                )
            }
            "$PECL_PACKAGE_ROOT_URL/curl/1.4.0/windows"                                              = @{
                Content = 'Mocked PHP curl 1.4.0 content'
                Links   = @(
                    @{ href = 'other_link' },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" },
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip" }
                )
            }
            "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"               = @{
                Content = 'Mocked PHP curl 1.4.0 zip content'
            }
            "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86_64.zip"            = @{
                Content = 'Mocked PHP curl 1.4.0 zip content'
            }
            "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-arm64.zip"             = @{
                Content = 'Mocked PHP curl 1.4.0 zip content'
            }
            "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0/php_curl-1.5.0-8.2-ts-vs16-x64.zip"               = @{
                Content = 'Mocked PHP curl 1.5.0 zip content'
            }
            "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x64.zip" = @{
                Content = 'Mocked PHP courierauth 1.4.0 zip content'
            }
            "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0alpha1/php_curl-1.5.0alpha1-8.2-ts-vs16-x64.zip"   = @{
                Content = 'Mocked PHP curl 1.5.0alpha1 zip content'
            }
            "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0alpha2/php_curl-1.5.0alpha2-8.2-ts-vs16-x64.zip"   = @{
                Content = 'Mocked PHP curl 1.5.0alpha2 zip content'
            }
            "$PECL_PACKAGE_ROOT_URL/curl/2.1.0/windows"                                              = @{
                Content = 'Mocked PHP curl 2.1.0 content'
                Links   = @()
            }
        }
    }

    It "Returns -1 when user cancels the extension installation" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { '' }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Write-Gray -Times 1 -ParameterFilter { $message -like '*Installation cancelled*' }
    }

    It "Returns -1 when user enters an invalid selection" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { 'unknown' }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Warning -Times 1 -ParameterFilter { $message -like '*You answer is invalid*' }
    }

    It "Returns -1 when user enters a negative selection" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { -1 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Warning -Times 1 -ParameterFilter { $message -like '*Number must be between 0 and 1*' }
    }

    It "Returns -1 when user enters a selection outside the valid range" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { 5 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Warning -Times 1 -ParameterFilter { $message -like '*Number must be between 0 and 1*' }
    }

    It "Returns -1 when no handler is found for the selected source" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { 0 }
        Mock Get-SourceHandler { return $null }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter { $message -like '*No handler found for source*' }
    }

    It "Returns -1 when gets empty list from extension" {
        $code = Install-Extension -iniPath $testIniPath -extName 'nonexistent_ext'
        $code | Should -Be -1
    }

    It "Returns -1 when No package is found" {
        Mock Add-Member { throw 'error' }
        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when user does not choose a zip extension version to install" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { '' }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when user does choose a non valid zip extension version to install" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith {
            return '5'
        }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when downloaded zip extension has no dll" {
        $script:getRandomFile = $true
        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when user answers no to replace existing extension" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith {
            return 'n'
        }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when user answers yes to replace existing extension" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith {
            return 'y'
        }
        Mock Move-ItemWrapper { }
        Mock Add-MissingPHPExtensionToIni { return -1 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when no extension matching installed php version (arch & build type)" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x64'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.1/php_curl-1.4.1-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.1/php_curl-1.4.1-8.2-nts-vs16-x86.zip"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x64.zip"; arch = 'x64'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0' }
                )
            }
        }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when no matching extension is found" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x64'; buildType = 'ts' } }
        Mock Get-ExtensionPackages { return $null }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Installs extension successfully" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip'>8.2 Thread Safe (TS) x86</a>" }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x86.zip"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-nts-vs16-x86.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x86.zip'>8.2 Non Thread Safe (NTS) x86</a>" }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x64.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip'>8.2 Thread Safe (TS) x64</a>" }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x64.zip"; arch = 'x64'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-nts-vs16-x64.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x64.zip'>8.2 Non Thread Safe (NTS) x64</a>" }
                )
            }
        }
        Mock Test-Path { return $false }
        Mock Add-MissingPHPExtensionToIni { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    Context "When extension has no direct link" {
        BeforeEach {
            Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/nonexistent_ext" } -MockWith {
                throw 'Network error'
            }
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
            Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=1&amp;catname=Authentication" } -MockWith {
                return @{
                    Content = 'Mocked PHP extension Auth content'
                    Links   = @(
                        @{ href = $null }
                        @{ href = '/package/courierauth' }
                        @{ href = '/package/krb5' }
                    )
                }
            }
            Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching" } -MockWith {
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
            Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=7&amp;catname=EmptyCat" } -MockWith {
                return @{
                    Content = 'Mocked PHP extension EmptyCat content'
                    Links   = @()
                }
            }
            Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/courierauth" } -MockWith {
                return @{
                    Content = 'Mocked courierauth content'
                    Links   = @(
                        @{ href = '/package/courierauth/1.4.0/windows' },
                        @{ href = '/package/courierauth/2.1.0/windows' }
                    )
                }
            }
            Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/courierauth/1.4.0/windows" } -MockWith {
                return @{
                    Content = 'Mocked PHP courierauth 1.4.0 content'
                    Links   = @(
                        @{ href = 'other_link' },
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip" },
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x64.zip" }
                    )
                }
            }
            Mock Invoke-WebRequestWrapper -ParameterFilter { $Uri -eq "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip" } -MockWith {
                $script:MockFileSystem.Files[$OutFile] = 'Downloaded content'
                return
            }
            Mock Get-ChildItemWrapper {
                return @( @{ Name = 'php_courierauth.dll'; FullName = "$TEST_DRIVE\php_courierauth-1.4.0-7.4-ts-vc15-x86\php_courierauth.dll" } )
            }
        }

        It "Falls back to matching links if extension direct link is not found" {
            Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x64'; buildType = 'ts' } }
            Mock Get-ExtensionPackages {
                return @{
                    extName = 'courierauth'
                    source  = 'pecl.php.net'
                    data    = @(
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_courierauth-1.4.0-8.2-ts-vs16-x64.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x64.zip'>8.2 Thread Safe (TS) x64</a>" }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-nts-vs16-x64.zip"; arch = 'x64'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_courierauth-1.4.0-8.2-nts-vs16-x64.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-nts-vs16-x64.zip'>8.2 Non Thread Safe (NTS) x64</a>" }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_courierauth-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip'>8.2 Thread Safe (TS) x86</a>" }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-nts-vs16-x86.zip"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_courierauth-1.4.0-8.2-nts-vs16-x86.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-nts-vs16-x86.zip'>8.2 Non Thread Safe (NTS) x86</a>" }
                    )
                }
            }
            Mock Test-Path { return $false }
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith {
                return 'y'
            }
            Mock Add-MissingPHPExtensionToIni { return 0 }

            $code = Install-Extension -iniPath $testIniPath -extName 'cour'
            $code | Should -Be 0
        }

        It "Returns -1 when no extension is found" {
            $code = Install-Extension -iniPath $testIniPath -extName 'nonexistent_ext'
            $code | Should -Be -1
        }

        It "Returns -1 when user does not choose a dll extension version to install" {
            Mock Get-ExtensionPackages {
                return @{
                    extName = 'courierauth'
                    data    = @(
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_courierauth-1.4.0-8.2-ts-vs16-x64.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x64.zip'>8.2 Thread Safe (TS) x64</a>" }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-nts-vs16-x64.zip"; arch = 'x64'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_courierauth-1.4.0-8.2-nts-vs16-x64.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-nts-vs16-x64.zip'>8.2 Non Thread Safe (NTS) x64</a>" }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_courierauth-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip'>8.2 Thread Safe (TS) x86</a>" }
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-nts-vs16-x86.zip"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_courierauth-1.4.0-8.2-nts-vs16-x86.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-nts-vs16-x86.zip'>8.2 Non Thread Safe (NTS) x86</a>" }
                    )
                }
            }
            $script:callCount = 0
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith {
                $script:callCount++
                if ($script:callCount -eq 1) { return '0' }
                return ''
            }
            $code = Install-Extension -iniPath $testIniPath -extName 'courierauth'
            $code | Should -Be -1
            Should -Invoke Show-Error -Times 1 -ParameterFilter { $message -like '*You chose the wrong index*' }
        }
    }

    It "Handles thrown exception" {
        $script:MockFileSystem.DownloadFails = $true
        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Displays multiple extension versions with prerelease sorting" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = $null; buildType = $null } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0/php_curl-1.5.0-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.5.0'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0rc1/php_curl-1.5.0rc1-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.5.0rc1'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0beta1/php_curl-1.5.0beta1-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.5.0beta1'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0alpha1/php_curl-1.5.0alpha1-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.5.0alpha1'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                )
            }
        }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '0' }
        Mock Test-Path { return $false }
        Mock Add-MissingPHPExtensionToIni { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Sorts extensions with x86_64 architecture correctly" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = $null; buildType = $null } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86_64.zip"; arch = 'x86_64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                )
            }
        }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '0' }
        Mock Test-Path { return $false }
        Mock Add-MissingPHPExtensionToIni { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Sorts extensions with unknown architecture correctly" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = $null; buildType = $null } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-arm64.zip"; arch = 'arm64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                )
            }
        }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '0' }
        Mock Test-Path { return $false }
        Mock Add-MissingPHPExtensionToIni { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Returns -1 when no dll file matches the pattern" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItemWrapper {
            # Return a file that doesn't match the expected pattern
            return @( @{ Name = 'random_file.dll'; FullName = "$TEST_DRIVE\extracted\random_file.dll" } )
        }
        Mock Test-Path { return $false }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Prompts user when file already exists and user cancels" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItemWrapper {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-Path -ParameterFilter { $Path -match '\.dll$' } { return $true }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { return 'n' }
        Mock Remove-ItemWrapper { }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Prompts user when file already exists and user overwrites" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItemWrapper {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-Path -ParameterFilter { $Path -match '\.dll$' } { return $true }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { return 'Y' }
        Mock Move-ItemWrapper { }
        Mock Remove-ItemWrapper { }
        Mock Add-MissingPHPExtensionToIni { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Returns -1 when adding extension to ini fails" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItemWrapper {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-Path { return $false }
        Mock Move-ItemWrapper { }
        Mock Remove-ItemWrapper { }
        Mock Add-MissingPHPExtensionToIni { return -1 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Skips overwrite prompt and installs when skipConfirmation is true and file exists" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts'; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItemWrapper {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-FileExists { return $true }
        Mock Move-ItemWrapper { }
        Mock Remove-ItemWrapper { }
        Mock Add-MissingPHPExtensionToIni { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl' -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Read-HostWrapper -Exactly 0 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }

    It "Prompts overwrite when skipConfirmation is false and file exists and user cancels" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts'; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItemWrapper {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-FileExists { return $true }
        Mock Read-HostWrapper -ParameterFilter { $prompt -like '*already exists*' } -MockWith { return 'n' }
        Mock Remove-ItemWrapper { }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl' -skipConfirmation $false

        $code | Should -Be -1
        Should -Invoke Read-HostWrapper -Exactly 1 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }

    It "Prompts overwrite when skipConfirmation is false and file exists and user confirms" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'curl'
                source  = 'pecl.php.net'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts'; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItemWrapper {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-FileExists { return $true }
        Mock Read-HostWrapper -ParameterFilter { $prompt -like '*already exists*' } -MockWith { return 'y' }
        Mock Move-ItemWrapper { }
        Mock Remove-ItemWrapper { }
        Mock Add-MissingPHPExtensionToIni { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl' -skipConfirmation $false

        $code | Should -Be 0
        Should -Invoke Read-HostWrapper -Exactly 1 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }

    It "Returns -1 when user does not choose a dll extension version to install" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0" } }
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
        Mock Read-HostWrapper { }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
        Should -Invoke Write-Gray -ParameterFilter { $message -like '*Installation cancelled*' }
    }

    It "Returns -1 when no matching extension is found" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0" } }
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

        $script:callCount = 0
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { return '0' }
            return '-1'
        }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like "*You chose the wrong index*" }
    }

    It "Handles exception gracefully" {
        Mock Get-CurrentPHPVersion { throw 'Error' }
        Mock Add-LogEntry { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
        Should -Invoke Add-LogEntry
    }

    It "Returns -1 when no source supports the extension" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '1' }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like "*Source 'xdebug.org' does not support extension 'curl'*" }
    }

    It "Shows the more info url" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0" } }
        Mock Get-SourceHandler {
            param ($sourceUrl)
            return @{
                ResolveLinks = {
                    return @{
                        extName = 'xdebug'
                        source = 'xdebug.org'
                        data = @(
                            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.1-8.2-ts-vs16-x86.dll"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.1-8.2-nts-vs16-x86.dll"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0' }
                            @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.0-8.2-nts-vs16-x64.dll"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                        )
                    }
                }
                GetPackages = {
                    return @(
                        @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.1-8.2-ts-vs16-x86.dll"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                        @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.1-8.2-nts-vs16-x86.dll"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0' }
                        @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.0-8.2-nts-vs16-x64.dll"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                    )
                }
                Download = { return @{ Name = 'php_xdebug.dll'; FullName = "$TEST_DRIVE\extracted\php_xdebug.dll" } }
                MoreInfoUrl = $XDEBUG_HISTORICAL_URL
            }
        }
        Mock Get-ExtensionConfigHandler {
            param ($extName)
            return { return 0 }
        }
        Mock Get-ExtensionPackages {
            return @{
                extName = 'xdebug'
                source  = 'xdebug.org'
                data    = @(
                    @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.1-8.2-ts-vs16-x86.dll"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                    @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.1-8.2-nts-vs16-x86.dll"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0' }
                    @{ href = "$XDEBUG_BASE_URL/download/php_xdebug-1.4.0-8.2-nts-vs16-x64.dll"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0' }
                )
            }
        }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '1' }

        $code = Install-Extension -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Show-Info -ParameterFilter { $message -like "*This is a partial list. For a complete list, visit: $XDEBUG_HISTORICAL_URL*" } -Times 1
    }
}

Describe "Install-IniExtension" {
    It "Handles null extension name" {
        $code = Install-IniExtension -iniPath $testIniPath -extNames $null
        $code | Should -Be -1
    }

    It "Installs xdebug" {
        Mock Install-Extension { return 0 }
        $code = Install-IniExtension -iniPath $testIniPath -extNames 'xdebug'
        $code | Should -Be 0
    }

    It "Installs pecl extension" {
        Mock Install-Extension { return 0 }
        $code = Install-IniExtension -iniPath $testIniPath -extNames 'curl'
        $code | Should -Be 0
    }

    It "Returns -1 on error" {
        Mock Install-Extension { return -1 }
        $code = Install-IniExtension -iniPath $testIniPath -extNames 'curl'
        $code | Should -Be -1
    }

    It "Handles thrown exception" {
        Mock Add-LogEntry { return 0 }
        Mock Install-Extension { throw 'Network error' }
        $code = Install-IniExtension -iniPath $testIniPath -extNames 'curl'
        $code | Should -Be -1
    }

    It "Passes skipConfirmation true to Install-IniExtension" {
        Mock Install-Extension { return 0 }

        $code = Install-IniExtension -iniPath $testIniPath -extNames @('xdebug') -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Install-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $true
        }
    }

    It "Passes skipConfirmation false to Install-IniExtension by default" {
        Mock Install-Extension { return 0 }

        $code = Install-IniExtension -iniPath $testIniPath -extNames @('xdebug')

        $code | Should -Be 0
        Should -Invoke Install-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $false
        }
    }

    It "Passes skipConfirmation true to Install-Extension" {
        Mock Install-Extension { return 0 }

        $code = Install-IniExtension -iniPath $testIniPath -extNames @('curl') -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Install-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $true
        }
    }

    It "Passes skipConfirmation false to Install-Extension by default" {
        Mock Install-Extension { return 0 }

        $code = Install-IniExtension -iniPath $testIniPath -extNames @('curl')

        $code | Should -Be 0
        Should -Invoke Install-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $false
        }
    }

    It "Returns -1 if one extension fails to install" {
        Mock Install-Extension {
            param ($extName)

            if ($extName -eq 'unknown') { return -1 }
            return 0
        }

        $code = Install-IniExtension -iniPath $testIniPath -extNames @('curl', 'unknown')

        $code | Should -Be -1
    }
}

Describe "Get-PrereleaseSortKey" {
    It "Scores stable higher than rc/beta/alpha for the same version" {
        $stable = Get-PrereleaseSortKey -Name '3.1.0'
        $rc     = Get-PrereleaseSortKey -Name '3.1.0rc1'
        $beta   = Get-PrereleaseSortKey -Name '3.1.0beta1'
        $alpha  = Get-PrereleaseSortKey -Name '3.1.0alpha1'

        $stable | Should -BeGreaterThan $rc
        $rc     | Should -BeGreaterThan $beta
        $beta   | Should -BeGreaterThan $alpha
    }

    It "Scores higher prerelease numbers higher within the same tier" {
        (Get-PrereleaseSortKey -Name '3.1.0rc2')    | Should -BeGreaterThan (Get-PrereleaseSortKey -Name '3.1.0rc1')
        (Get-PrereleaseSortKey -Name '3.1.0beta2')  | Should -BeGreaterThan (Get-PrereleaseSortKey -Name '3.1.0beta1')
        (Get-PrereleaseSortKey -Name '3.1.0alpha2') | Should -BeGreaterThan (Get-PrereleaseSortKey -Name '3.1.0alpha1')
    }

    It "Scores higher base versions higher regardless of prerelease tier" {
        (Get-PrereleaseSortKey -Name '3.2.0alpha1') | Should -BeGreaterThan (Get-PrereleaseSortKey -Name '3.1.0')
    }

    It "Treats missing version segments as zero" {
        Get-PrereleaseSortKey -Name '3.1' | Should -Be (Get-PrereleaseSortKey -Name '3.1.0')
    }

    It "Does not overflow Int32 for realistic version numbers" {
        $score = Get-PrereleaseSortKey -Name '1.5.0'
        $score | Should -BeOfType [long]
        $score | Should -BeGreaterThan ([int32]::MaxValue)
    }
}
