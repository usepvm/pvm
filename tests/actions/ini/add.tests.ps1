
BeforeAll {
    if (-not $Global:CurrentTestDrive) {
        $currentFileName = Split-Path -Path $PSCommandPath -Leaf
        $msg = "`nTest Drive is not set for '$currentFileName'"
        $line = "`n$('=' * $msg.Length)"
        $errorMessage = $line + $msg + $line
        throw " `n$errorMessage"
    }

    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:phpPath = "$script:TEST_DRIVE\php"
    $script:testIniPath = "$script:phpPath\php.ini"
    $script:extDirectory = "$script:phpPath\ext"
    $script:testBackupPath = "$script:phpPath\$($Global:PVMConfig.constants.INI_BACKUP_DIR_NAME)"

    $null = New-Item -ItemType Directory -Path $Global:PVMConfig.paths.directories.cache -Force
    $null = New-Item -ItemType Directory -Path $script:phpPath -Force
    $null = New-Item -ItemType Directory -Path $script:extDirectory -Force

    $script:XDEBUG_BASE_URL = $Global:PVMConfig.links.xdebugBase
    $script:PECL_PACKAGES_URL = $Global:PVMConfig.links.peclPackages
    $script:XDEBUG_DOWNLOAD_URL = $Global:PVMConfig.links.xdebugDownload
    $script:XDEBUG_HISTORICAL_URL = $Global:PVMConfig.links.xdebugHistorical
    $script:PECL_PACKAGE_ROOT_URL = $Global:PVMConfig.links.peclPackageRoot
    $script:PECL_WIN_EXT_DOWNLOAD_URL = $Global:PVMConfig.links.peclWinExtDownload

    Mock New-Line { }
    Mock Show-Warning { }
    Mock Show-Message { }
    Mock Show-Error { }
    Mock Show-Success { }
    Mock Show-Info { }
    Mock Write-Gray { }

    function Reset-IniContent {
        @(
            'memory_limit = 128M'
            ';extension=php_xdebug.dll'
            'extension=php_curl.dll'
            'zend_extension=php_opcache.dll'
            'display_errors = On'
            'max_execution_time = 30'
            ';upload_max_filesize = 2M'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8
    }

    Reset-IniContent

    Mock Backup-IniFile { return 0 }
    Mock Add-LogEntry { return 0 }
    Mock Get-CurrentPHPVersion {
        return @{
            version = '8.2.0'
            path    = $script:phpPath
        }
    }

    $script:MockFileSystem = @{
        Directories   = @()
        Files         = @{}
        WebResponses  = @{}
        DownloadFails = $false
    }

    Mock Invoke-WebRequestWrapper {
        param ($uri, $outFile = $null)

        if ($script:MockFileSystem.DownloadFails) {
            throw 'Network error'
        }

        if ($script:MockFileSystem.WebResponses.ContainsKey($uri)) {
            $response = $script:MockFileSystem.WebResponses[$uri]
            if ($outFile) {
                $script:MockFileSystem.Files[$outFile] = 'Downloaded content'
                return
            }
            return @{
                Content = $response.Content
                Links   = $response.Links
            }
        }

        throw "URL not mocked: $uri"
    }
}

Describe "Select-ExtensionPackageLink" {
    BeforeEach {
        Mock Read-HostWrapper { return '0' }
    }

    It "Returns null and shows cancellation when no package is selected" {
        Mock Read-HostWrapper { return ' ' }

        $result = Select-ExtensionPackageLink -extName 'curl' -extensionLinks @(
            @{
                href       = 'https://example.test/curl.zip'
                version    = '8.2'
                extVersion = '1.0.0'
                arch       = 'x64'
                buildType  = 'TS'
                compiler   = 'VS16'
                fileName   = 'php_curl.zip'
            }
        )

        $result | Should -BeNullOrEmpty
        Should -Invoke Write-Gray -Times 1 -ParameterFilter {
            $message -eq "`nInstallation cancelled"
        }
    }

    It "Sorts packages by release, build type, and architecture before selecting" {
        $extensionLinks = @(
            @{
                href       = 'https://example.test/curl-1.0-ts-x86.zip'
                version    = '8.2'
                extVersion = '1.0.0'
                arch       = 'x86'
                buildType  = 'TS'
                compiler   = 'VS16'
                fileName   = 'php_curl-1.0-ts-x86.zip'
            }
            @{
                href       = 'https://example.test/curl-1.1-ts-x64.zip'
                version    = '8.2'
                extVersion = '1.1.0'
                arch       = 'x64'
                buildType  = 'TS'
                compiler   = 'VS16'
                fileName   = 'php_curl-1.1-ts-x64.zip'
            }
            @{
                href       = 'https://example.test/curl-1.0-nts-x64.zip'
                version    = '8.2'
                extVersion = '1.0.0'
                arch       = 'x64'
                buildType  = 'NTS'
                compiler   = 'VS16'
                fileName   = 'php_curl-1.0-nts-x64.zip'
            }
            @{
                href       = 'https://example.test/curl-1.0-nts-x86.zip'
                version    = '8.2'
                extVersion = '1.0.0'
                arch       = 'x86'
                buildType  = 'NTS'
                compiler   = 'VS16'
                fileName   = 'php_curl-1.0-nts-x86.zip'
            }
            @{
                href       = 'https://example.test/curl-0.9-x86_64.zip'
                version    = '8.2'
                extVersion = '0.9.0'
                arch       = 'x86_64'
                buildType  = 'TS'
                compiler   = 'VS16'
                fileName   = 'php_curl-0.9-x86_64.zip'
            }
            @{
                href       = 'https://example.test/curl-0.9-arm64.zip'
                version    = '8.2'
                extVersion = '0.9.0'
                arch       = 'arm64'
                buildType  = 'TS'
                compiler   = 'VS16'
                fileName   = 'php_curl-0.9-arm64.zip'
            }
        )
        Mock Read-HostWrapper { return '0' }

        $result = Select-ExtensionPackageLink -extName 'curl' -extensionLinks $extensionLinks

        $result.href | Should -Be 'https://example.test/curl-1.1-ts-x64.zip'
        $result.index | Should -Be 0
        $extensionLinks[2].index | Should -Be 1
        $extensionLinks[3].index | Should -Be 2
        $extensionLinks[0].index | Should -Be 3
        Should -Invoke Show-Message -Times 7
        Should -Invoke Show-Message -ParameterFilter {
            $message -eq "`ncurl 1.1.0"
        }
        Should -Invoke Show-Message -ParameterFilter {
            $message -eq ' [0] PHP curl 8.2 VS16 TS x64'
        }
    }

    It "Returns null when the selected index does not match a package" {
        Mock Read-HostWrapper { return '9' }

        $result = Select-ExtensionPackageLink -extName 'curl' -extensionLinks @(
            @{
                href       = 'https://example.test/curl.zip'
                version    = '8.2'
                extVersion = '1.0.0'
                arch       = 'x64'
                buildType  = 'TS'
                compiler   = 'VS16'
                fileName   = 'php_curl.zip'
            }
        )

        $result | Should -BeNullOrEmpty
        Should -Invoke Write-Gray -Times 0
    }
}

Describe "Get-PrereleaseSortKey" {
    It "Scores stable higher than rc/beta/alpha for the same version" {
        $stable = Get-PrereleaseSortKey -name '3.1.0'
        $rc     = Get-PrereleaseSortKey -name '3.1.0rc1'
        $beta   = Get-PrereleaseSortKey -name '3.1.0beta1'
        $alpha  = Get-PrereleaseSortKey -name '3.1.0alpha1'

        $stable | Should -BeGreaterThan $rc
        $rc     | Should -BeGreaterThan $beta
        $beta   | Should -BeGreaterThan $alpha
    }

    It "Scores higher prerelease numbers higher within the same tier" {
        (Get-PrereleaseSortKey -name '3.1.0rc2')    | Should -BeGreaterThan (Get-PrereleaseSortKey -name '3.1.0rc1')
        (Get-PrereleaseSortKey -name '3.1.0beta2')  | Should -BeGreaterThan (Get-PrereleaseSortKey -name '3.1.0beta1')
        (Get-PrereleaseSortKey -name '3.1.0alpha2') | Should -BeGreaterThan (Get-PrereleaseSortKey -name '3.1.0alpha1')
    }

    It "Scores higher base versions higher regardless of prerelease tier" {
        (Get-PrereleaseSortKey -name '3.2.0alpha1') | Should -BeGreaterThan (Get-PrereleaseSortKey -name '3.1.0')
    }

    It "Treats missing version segments as zero" {
        Get-PrereleaseSortKey -name '3.1' | Should -Be (Get-PrereleaseSortKey -name '3.1.0')
    }

    It "Does not overflow Int32 for realistic version numbers" {
        $score = Get-PrereleaseSortKey -name '1.5.0'
        $score | Should -BeOfType [long]
        $score | Should -BeGreaterThan ([int32]::MaxValue)
    }
}

Describe "Add-MissingPHPExtensionToIni" {
    BeforeEach {
        Reset-IniContent
        Remove-Item -Path $script:testBackupPath -Force -Recurse -ErrorAction SilentlyContinue
        Mock Get-ZendExtensionsList { return @('xdebug', 'opcache') }
    }

    It "Returns -1 when current PHP version is null" {
        Mock Get-CurrentPHPVersion { return @{ version = $null; path = $null } }
        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'curl'
        $result | Should -Be -1
    }

    It "Adds and configures xdebug in ini file" {
        Mock Get-MatchingPHPExtensionsStatus { return @( @{ name = 'xdebug'; status = 'Enabled'; enabled = $true; color = 'DarkGreen'; LineNumber = 0 } )}
        Mock Test-FileNotExists { return $false }
        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'php_xdebug.dll'
        $result | Should -Be 0
        Should -Invoke Show-Success -Times 1 -ParameterFilter {
            $message -like "- 'php_xdebug.dll' added successfully."
        }
    }

    It "Returns 0 and shows warning when extension already exists in ini file" {
        Mock Get-MatchingPHPExtensionsStatus { return @( @{ name = 'xdebug'; status = 'Enabled'; enabled = $true; color = 'DarkGreen'; LineNumber = 150 } )}
        Mock Test-FileNotExists { return $false }
        Mock Test-DirectoryNotExists { return $false }
        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'php_xdebug.dll'
        $result | Should -Be 0
        Should -Invoke Show-Warning -Times 1 -ParameterFilter {
            $message -eq "- Extension 'php_xdebug.dll' already exists in php.ini"
        }
    }

    It "Adds any extension to ini file" {
        @(
            'zend_extension=php_opcache.dll'
            'extension=php_mbstring.dll'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8

        Mock Test-FileNotExists { return $false }
        Mock Test-DirectoryNotExists { return $false }
        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'php_curl.dll'
        $result | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) -match 'extension=php_curl.dll' | Should -Be $true
        Should -Invoke Show-Success -Times 1 -ParameterFilter {
            $message -eq "- 'php_curl.dll' added successfully."
        }
    }

    It "Adds any extension in disabled state to ini file" {
        @(
            'zend_extension=php_opcache.dll'
            ';extension=php_mbstring.dll'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8

        Mock Test-FileNotExists { return $false }
        Mock Test-DirectoryNotExists { return $false }
        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'php_curl.dll' -enable $false
        $result | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) -match ';extension=php_curl.dll' | Should -Be $true
    }

    It "Adds extensions correctly for older PHP versions" {
        @(
            'zend_extension=php_opcache.dll'
            'extension=php_mbstring.dll'
        ) -join "`n" | Set-Content -Path $script:testIniPath -Encoding UTF8

        Mock Test-FileNotExists { return $false }
        Mock Test-DirectoryNotExists { return $false }
        Mock Get-CurrentPHPVersion { return @{ version = '7.1.0'; path = "$script:TEST_DRIVE\php\7.1.0" } }
        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'php_curl.dll'
        $result | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) -match 'extension=php_curl.dll' | Should -Be $true
    }

    It "Adds zend_extensions correctly" {
        'extension=php_mbstring.dll' | Set-Content -Path $script:testIniPath -Encoding UTF8

        Mock Test-FileNotExists { return $false }
        Mock Test-DirectoryNotExists { return $false }
        Mock Get-CurrentPHPVersion { return @{ version = '7.1.0'; path = "$script:TEST_DRIVE\php\7.1.0" } }
        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'php_opcache.dll'
        $result | Should -Be 0
        (Get-ContentWrapper -path $script:testIniPath) -match 'zend_extension=php_opcache.dll' | Should -Be $true
    }

    It "Returns -1 for non-existent ini file" {
        Mock Test-FileNotExists { return $true }
        $result = Add-MissingPHPExtensionToIni -iniPath 'nonexistent.ini' -extFileName 'php_curl.dll'
        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nphp.ini file not found: nonexistent.ini"
        }
    }

    It "Returns -1 when extension directory doesn't exist" {
        Mock Test-FileNotExists { return $false }
        Mock Test-DirectoryNotExists { return $true }

        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'php_curl.dll'

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nExtensions directory not found: $script:extDirectory"
        }
    }

    It "Returns -1 when extension file doesn't exist" {
        Mock Test-FileNotExists -ParameterFilter { $path -eq $script:testIniPath } { return $false }
        Mock Test-DirectoryNotExists { return $false }
        Mock Test-FileNotExists -ParameterFilter { $path -eq "$script:extDirectory\php_curl.dll" } { return $true }

        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'php_curl.dll'

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nExtension file not found: php_curl.dll"
        }
    }

    It "Returns -1 when adding new line to ini fails" {
        Mock Test-FileNotExists { return $false }
        Mock Backup-IniFile { return 0 }
        Mock Test-DirectoryNotExists { return $false }
        Mock Get-MatchingPHPExtensionsStatus { return @() }
        Mock Set-ContentWrapper { return -1 }

        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'curl'

        $result | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like "*Failed to add 'curl' to ini file*" }
    }

    It "Handles exception gracefully" {
        Mock Add-LogEntry { return 0 }
        Mock Backup-IniFile { throw 'Access denied' }
        $result = Add-MissingPHPExtensionToIni -iniPath $script:testIniPath -extFileName 'curl'
        $result | Should -Be -1
    }
}

Describe "Install-Extension" {
    BeforeAll {
        function New-TestPackage {
            param ($arch = 'x86', $buildType = 'ts', $extVersion = '1.4.0', $extName = 'curl')

            $file = "php_$extName-$extVersion-8.2-$buildType-vs16-$arch.zip"
            return @{
                href       = "https://mock/$extName/$extVersion/$file"
                arch       = $arch
                buildType  = $buildType
                version    = '8.2'
                extVersion = $extVersion
                fileName   = $file
            }
        }

        function Set-TestPackages {
            param ($Packages, $ExtName = 'curl', $Source = 'pecl.php.net')
            $script:ResolveLinksResult = @{ extName = $ExtName; source = $Source; data = @($Packages) }
        }

        Mock Read-HostWrapper {
            param ($prompt)
            if ($prompt -eq "`nEnter the [number] of your selection") { return '0' }
        }
        Mock Add-LogEntry { return 0 }
    }

    BeforeEach {
        # Controls for the mocked handlers
        $script:ResolveLinksResult = $null
        $script:DownloadResult     = @{ Name = 'php_curl.dll'; FullName = "$script:TEST_DRIVE\extracted\php_curl.dll" }
        $script:DownloadArgs       = $null
        $script:ConfigCode         = 0

        Mock Get-CurrentPHPVersion {
            return @{ version = '8.2.0'; path = "$script:TEST_DRIVE\php\8.2.0"; arch = $null; buildType = $null }
        }

        Mock Get-ExtensionHandlers {
            return @{
                SourceHandlers = @{
                    'xdebug.org' = @{
                        SupportedExtensions = @('xdebug')
                        ResolveLinks        = { param ($extName) return $script:ResolveLinksResult }
                        GetPackages         = {}
                        Download            = {
                            param ($chosenItem, $phpPath, $skipConfirmation, $extName)
                            $script:DownloadArgs = @{
                                chosenItem       = $chosenItem
                                phpPath          = $phpPath
                                skipConfirmation = $skipConfirmation
                                extName          = $extName
                            }
                            return $script:DownloadResult
                        }
                        MoreInfoUrl         = 'https://mock/xdebug-historical'
                    }
                    'pecl.php.net' = @{
                        SupportedExtensions = @('*')
                        ResolveLinks        = { param ($extName) return $script:ResolveLinksResult }
                        GetPackages         = {}
                        Download            = {
                            param ($chosenItem, $phpPath, $skipConfirmation, $extName)
                            $script:DownloadArgs = @{
                                chosenItem       = $chosenItem
                                phpPath          = $phpPath
                                skipConfirmation = $skipConfirmation
                                extName          = $extName
                            }
                            return $script:DownloadResult
                        }
                        MoreInfoUrl         = { param ($extName) return "https://mock/pecl/$extName" }
                    }
                }
                ExtensionConfigHandlers = @{
                    'xdebug'  = { param ($iniPath, $fileName, $extVersion) return $script:ConfigCode }
                    'default' = { param ($iniPath, $fileName, $extVersion) return $script:ConfigCode }
                }
            }
        }
    }

    It "Returns -1 when user cancels the extension installation" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '' }

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Write-Gray -Times 1 -ParameterFilter { $message -like '*Installation cancelled*' }
    }

    It "Returns -1 when user enters an invalid selection" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return 'unknown' }

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Warning -Times 1 -ParameterFilter { $message -like '*You answer is invalid*' }
    }

    It "Returns -1 when user enters a negative selection" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return -1 }

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Warning -Times 1 -ParameterFilter { $message -like '*Number must be between 0 and 1*' }
    }

    It "Returns -1 when user enters a selection outside the valid range" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return 5 }

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Warning -Times 1 -ParameterFilter { $message -like '*Number must be between 0 and 1*' }
    }

    It "Returns -1 when no handler is found for the selected source" {
        Mock Get-SourceHandler { return $null }

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter { $message -like '*No handler found for source*' }
    }

    It "Returns -1 when no source supports the extension" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '1' }

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like "*Source 'xdebug.org' does not support extension 'curl'*" }
    }

    It "Returns -1 when ResolveLinks returns null" {
        $script:ResolveLinksResult = $null

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter { $message -like '*No packages found for curl*' }
    }

    It "Returns -1 when ResolveLinks returns an empty list" {
        $script:ResolveLinksResult = @{ extName = 'nonexistent_ext'; source = 'pecl.php.net'; data = @() }

        $code = Install-Extension -iniPath $script:testIniPath -extName 'nonexistent_ext'

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter { $message -like '*No packages found for nonexistent_ext*' }
    }

    It "Returns -1 when no package matches installed php arch & build type" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.2.0'; path = "$script:TEST_DRIVE\php\8.2.0"; arch = 'x64'; buildType = 'ts' } }
        Set-TestPackages -Packages @(
            (New-TestPackage -arch 'x86' -buildType 'ts'),
            (New-TestPackage -arch 'x86' -buildType 'nts'),
            (New-TestPackage -arch 'x64' -buildType 'nts')
        )

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -like "*No packages found for 'curl' matching current PHP architecture/build type*"
        }
    }

    It "Returns -1 when user does not choose a version (empty answer)" {
        Mock Read-HostWrapper { }
        Set-TestPackages -Packages @((New-TestPackage -arch 'x86'), (New-TestPackage -arch 'x64'))

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Write-Gray -ParameterFilter { $message -like '*Installation cancelled*' }
    }

    It "Returns -1 when user picks an invalid package index" {
        $script:callCount = 0
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { return '0' }
            return ''
        }
        Set-TestPackages -Packages @((New-TestPackage -arch 'x86'), (New-TestPackage -arch 'x64'))

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter { $message -like '*You chose the wrong index*' }
    }

    It "Returns -1 when download handler returns nothing" {
        Set-TestPackages -Packages @((New-TestPackage))
        $script:DownloadResult = $null

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter { $message -like '*Failed to download curl*' }
    }

    It "Returns -1 when config handler fails" {
        Set-TestPackages -Packages @((New-TestPackage))
        $script:ConfigCode = -1

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter { $message -like '*Failed to apply configuration for curl*' }
    }

    It "Installs extension successfully" {
        Set-TestPackages -Packages @((New-TestPackage))

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be 0
        Should -Invoke Show-Success -Times 1 -ParameterFilter { $message -like '*curl installed successfully*' }
    }

    It "Passes extName to Download only for pecl.php.net" {
        Set-TestPackages -Packages @((New-TestPackage))

        $null = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $script:DownloadArgs.extName | Should -Be 'curl'
        $script:DownloadArgs.phpPath | Should -Be (Split-Path -Path $script:testIniPath -Parent)
    }

    It "Forwards skipConfirmation = true to Download" {
        Set-TestPackages -Packages @((New-TestPackage))

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl' -skipConfirmation $true

        $code | Should -Be 0
        $script:DownloadArgs.skipConfirmation | Should -BeTrue
    }

    It "Forwards skipConfirmation = false to Download by default" {
        Set-TestPackages -Packages @((New-TestPackage))

        $null = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $script:DownloadArgs.skipConfirmation | Should -BeFalse
    }

    It "Lists pre-release versions without failing" {
        Set-TestPackages -Packages @(
            (New-TestPackage -arch 'x64' -extVersion '1.5.0'),
            (New-TestPackage -arch 'x64' -extVersion '1.5.0rc1'),
            (New-TestPackage -arch 'x64' -extVersion '1.5.0beta1'),
            (New-TestPackage -arch 'x64' -extVersion '1.5.0alpha1'),
            (New-TestPackage -arch 'x64' -extVersion '1.4.0')
        )

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl' -skipConfirmation $true

        $code | Should -Be 0
    }

    It "Handles x86_64 and arm64 architectures" {
        Set-TestPackages -Packages @(
            (New-TestPackage -arch 'x86'),
            (New-TestPackage -arch 'x86_64'),
            (New-TestPackage -arch 'arm64')
        )

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl' -skipConfirmation $true

        $code | Should -Be 0
    }

    It "Shows the more info url" {
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nEnter the [number] of your selection" } -MockWith { return '1' }
        $script:DownloadResult = @{ Name = 'php_xdebug.dll'; FullName = "$script:TEST_DRIVE\extracted\php_xdebug.dll" }
        Set-TestPackages -ExtName 'xdebug' -Source 'xdebug.org' -Packages @(
            (New-TestPackage -extName 'xdebug' -arch 'x86' -buildType 'ts'),
            (New-TestPackage -extName 'xdebug' -arch 'x86' -buildType 'nts')
        )

        $code = Install-Extension -iniPath $script:testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Show-Info -Times 1 -ParameterFilter {
            $message -like '*This is a partial list. For a complete list, visit: https://mock/xdebug-historical*'
        }
    }

    It "Shows the scriptblock more info url for pecl" {
        Set-TestPackages -Packages @((New-TestPackage -arch 'x86'), (New-TestPackage -arch 'x64'))

        $null = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        Should -Invoke Show-Info -Times 1 -ParameterFilter {
            $message -like '*visit: https://mock/pecl/curl*'
        }
    }

    It "Handles exception gracefully" {
        Set-TestPackages -Packages @((New-TestPackage))
        Mock Get-CurrentPHPVersion { throw 'Error' }

        $code = Install-Extension -iniPath $script:testIniPath -extName 'curl'

        $code | Should -Be -1
        Should -Invoke Add-LogEntry
    }
}

Describe "Install-IniExtension" {
    It "Handles null extension name" {
        $code = Install-IniExtension -iniPath $script:testIniPath -extNames $null
        $code | Should -Be -1
    }

    It "Installs xdebug" {
        Mock Install-Extension { return 0 }
        $code = Install-IniExtension -iniPath $script:testIniPath -extNames 'xdebug'
        $code | Should -Be 0
    }

    It "Installs pecl extension" {
        Mock Install-Extension { return 0 }
        $code = Install-IniExtension -iniPath $script:testIniPath -extNames 'curl'
        $code | Should -Be 0
    }

    It "Returns -1 on error" {
        Mock Install-Extension { return -1 }
        $code = Install-IniExtension -iniPath $script:testIniPath -extNames 'curl'
        $code | Should -Be -1
    }

    It "Handles thrown exception" {
        Mock Add-LogEntry { return 0 }
        Mock Install-Extension { throw 'Network error' }
        $code = Install-IniExtension -iniPath $script:testIniPath -extNames 'curl'
        $code | Should -Be -1
    }

    It "Passes skipConfirmation true to Install-IniExtension" {
        Mock Install-Extension { return 0 }

        $code = Install-IniExtension -iniPath $script:testIniPath -extNames @('xdebug') -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Install-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $true
        }
    }

    It "Passes skipConfirmation false to Install-IniExtension by default" {
        Mock Install-Extension { return 0 }

        $code = Install-IniExtension -iniPath $script:testIniPath -extNames @('xdebug')

        $code | Should -Be 0
        Should -Invoke Install-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $false
        }
    }

    It "Passes skipConfirmation true to Install-Extension" {
        Mock Install-Extension { return 0 }

        $code = Install-IniExtension -iniPath $script:testIniPath -extNames @('curl') -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Install-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $true
        }
    }

    It "Passes skipConfirmation false to Install-Extension by default" {
        Mock Install-Extension { return 0 }

        $code = Install-IniExtension -iniPath $script:testIniPath -extNames @('curl')

        $code | Should -Be 0
        Should -Invoke Install-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $false
        }
    }

    It "Returns -1 if one extension fails to install" {
        Mock Install-Extension {
            param ($iniPath, $extName)

            if ($extName -eq 'unknown') { return -1 }
            return 0
        }

        $code = Install-IniExtension -iniPath $script:testIniPath -extNames @('curl', 'unknown')

        $code | Should -Be -1
    }
}
