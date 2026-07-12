
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\add-drive"
    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"
    $script:CACHE_PATH = $PVMConfig.paths.cache = "$TEST_DRIVE\cache"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null

    $script:PECL_PACKAGES_URL = $PVMConfig.links.peclPackages
    $script:XDEBUG_DOWNLOAD_URL = $PVMConfig.links.xdebugDownload
    $script:XDEBUG_HISTORICAL_URL = $PVMConfig.links.xdebugHistorical
    $script:PECL_PACKAGE_ROOT_URL = $PVMConfig.links.peclPackageRoot
    $script:PECL_WIN_EXT_DOWNLOAD_URL = $PVMConfig.links.peclWinExtDownload

    Mock Write-Host {}

    function Reset-Ini-Content {
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
    Reset-Ini-Content

    # Mock global variables
    $PVMConfig.paths.logError = "$TEST_DRIVE\error.log"
    $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$TEST_DRIVE\php"

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$TEST_DRIVE\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
    Copy-Item -Path $testIniPath "$phpVersionPath\php.ini" -Force

    # Mock Log-Data function
    Mock Log-Data {
        param ($logPath, $message, $data)
        return $true
    }

    # Mock Get-Current-PHP-Version function
    Mock Get-Current-PHP-Version {
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

    Mock Get-Web-Response {
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

Describe "Get-XDebug-FROM-URL Tests" {
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
        Mock Write-Host { }
        Reset-MockState
    }

    It "Should parse XDebug versions correctly" {
        $mockLinks = @(
            @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x86_64.dll' },
            @{ href = '/download/php_xdebug-2.9.0-8.1-vs16-x86_64.dll' },
            @{ href = '/download/php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll' },
            @{ href = '/download/php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll' },
            @{ href = '/download/php_random.dll' }
        )
        Set-MockWebResponse -url 'https://test.com' -links $mockLinks

        $result = Get-XDebug-FROM-URL -url 'https://test.com' -version '8.1'

        $result.Count | Should -Be 4
        $result[0].xDebugVersion | Should -Be '3.1.0'
        $result[1].xDebugVersion | Should -Be '2.9.0'
    }

    It "Should handle network errors" {
        $script:MockFileSystem.DownloadFails = $true

        $result = Get-XDebug-FROM-URL -url 'https://test.com' -version '8.1'

        $result | Should -Be @()
    }

    It "Should parse xdebug with x86 architecture and unknown compiler" {
        $mockLinks = @(
            @{ href = '/download/php_xdebug-3.1.0-8.1-x86.dll' },
            @{ href = '/download/php_xdebug-2.9.0-8.1-nts-x86.dll' }
        )
        Set-MockWebResponse -url 'https://test.com' -links $mockLinks

        $result = Get-XDebug-FROM-URL -url 'https://test.com' -version '8.1'

        $result.Count | Should -Be 2
        $result[0].arch | Should -Be 'x86'
        $result[0].compiler | Should -Be 'unknown'
        $result[1].arch | Should -Be 'x86'
        $result[1].compiler | Should -Be 'unknown'
    }
}

Describe "Install-XDebug-Extension" {
    BeforeAll {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x64.dll'; outerHTML = "<a href='/download/php_xdebug-3.1.0-8.1-vs16-x64.dll'>php_xdebug-3.1.0-8.1-vs16-x64.dll</a>" }
                @{ href = '/download/php_xdebug-2.9.0-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '2.9.0'; fileName = 'php_xdebug-2.9.0-8.1-vs16-x86_64.dll'; outerHTML = "<a href='/download/php_xdebug-2.9.0-8.1-vs16-x86_64.dll'>php_xdebug-2.9.0-8.1-vs16-x86_64.dll</a>" }
                @{ href = '/download/php_xdebug-3.1.0-8.1-nts-vs16-x64.dll'; arch = 'x64'; buildType = 'nts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll'; outerHTML = "<a href='/download/php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll'>php_xdebug-3.1.0-8.1-nts-vs16-x86_64.dll</a>" }
                @{ href = '/download/php_xdebug-2.9.0-8.1-nts-vc16-x64.dll'; arch = 'x64'; buildType = 'nts'; version = '8.1'; xDebugVersion = '2.9.0'; fileName = 'php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll'; outerHTML = "<a href='/download/php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll'>php_xdebug-2.9.0-8.1-nts-vc16-x86_64.dll</a>" }
            )
        }
        Mock Read-Host {
            param ($Prompt)
            if ($Prompt -eq "`nInsert the [number] you want to install") {
                return ''
            }
        }

        function Reset-MockState {
            $script:MockRegistryThrowException = $false
            $script:MockFileSystem.DownloadFails = $false
            $script:MockFileSystem.WebResponses = @{}
            $script:MockFileSystem.Files = @{}
            $script:MockFileSystem.Directories = @()
        }

        function Add-Content {
            param ($Path, $Value)
            if ($script:MockFileSystem.Files.ContainsKey($Path)) {
                $script:MockFileSystem.Files[$Path] += "`n$Value"
            }
            else {
                $script:MockFileSystem.Files[$Path] = $Value
            }
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
        $script:MockFileSystem.Directories += "$TEST_DRIVE\php"
        $script:MockFileSystem.Directories += "$TEST_DRIVE\php\ext"
        $script:MockFileSystem.Files["$TEST_DRIVE\php\php.ini"] = @"
;extension_dir = "ext"
zend_extension = opcache
opcache.enable = 1
"@
        Reset-MockState
        $mockLinks = @(
            @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x64.dll' }
        )
        Set-MockWebResponse -url $XDEBUG_HISTORICAL_URL -links $mockLinks
    }

    It "Returns -1 when user does not choose a dll extension version to install" {
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }

    It "Returns -1 when user does choose a non valid dll extension version to install" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '-10' }
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }

    It "Returns -1 when user does not want to overwrite existing dll extension version" {
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-3.1.0-8.1-vs16-x64.dll" -content 'XDebug DLL content'
        Mock Test-Path { return $true }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_xdebug-3.1.0-8.1-vs16-x64.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { return 'n' }
        Mock Remove-Item { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }

    It "Returns 0 when user wants to overwrite existing dll extension version" {
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-3.1.0-8.1-vs16-x64.dll" -content 'XDebug DLL content'
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-2.9.0-8.1-vs16-x64.dll" -content 'XDebug DLL content'
        Mock Test-Path { return $false }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Remove-Item { }
        Mock Move-Item { }
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0
    }

    It "Handles exception gracefully" {
        Mock Sort-Object { throw 'Error' }
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }

    It "Returns -1 when no compatible extension version is found" {
        Mock Can-Use-Cache { return $false }
        Mock Get-XDebug-FROM-URL { return @() }
        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be -1
    }

    It "Filters xdebug versions by architecture" {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = 'x86'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x64.dll'; outerHTML = "<a>test</a>" }
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x86.dll'; arch = 'x86'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x86.dll'; outerHTML = "<a>test</a>" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Get-Web-Response { }
        Mock Move-Item { }
        Mock Get-Content { return "zend_extension=opcache" }
        Mock Set-Content { }
        Mock Remove-Item { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0
    }

    It "Filters xdebug versions by build type" {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = 'x64'; buildType = 'nts'; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-3.1.0-8.1-ts-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-ts-x64.dll'; outerHTML = "<a>test</a>" }
                @{ href = '/download/php_xdebug-3.1.0-8.1-nts-x64.dll'; arch = 'x64'; buildType = 'nts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-nts-x64.dll'; outerHTML = "<a>test</a>" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Get-Web-Response { }
        Mock Move-Item { }
        Mock Get-Content { return "zend_extension=opcache" }
        Mock Set-Content { }
        Mock Remove-Item { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0
    }

    It "Sorts prerelease versions correctly (alpha, beta, rc)" {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x64.dll'; outerHTML = "<a>test</a>" }
                @{ href = '/download/php_xdebug-3.1.0rc1-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0rc1'; fileName = 'php_xdebug-3.1.0rc1-8.1-vs16-x64.dll'; outerHTML = "<a>test</a>" }
                @{ href = '/download/php_xdebug-3.1.0beta1-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0beta1'; fileName = 'php_xdebug-3.1.0beta1-8.1-vs16-x64.dll'; outerHTML = "<a>test</a>" }
                @{ href = '/download/php_xdebug-3.1.0alpha1-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0alpha1'; fileName = 'php_xdebug-3.1.0alpha1-8.1-vs16-x64.dll'; outerHTML = "<a>test</a>" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Get-Web-Response { }
        Mock Move-Item { }
        Mock Get-Content { return "zend_extension=opcache" }
        Mock Set-Content { }
        Mock Remove-Item { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0
    }

    It "Replaces existing xdebug configuration in ini file" {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x64.dll'; outerHTML = "<a>test</a>" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Get-Web-Response { }
        Mock Move-Item { }
        Mock Remove-Item { }

        # Simulate existing xdebug in ini
        $existingIniContent = @(
            "zend_extension=opcache",
            ";zend_extension=php_xdebug-2.9.0-8.1-vs16-x64.dll",
            "opcache.enable = 1"
        )
        Mock Get-Content { return $existingIniContent }
        Mock Set-Content { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0

        # Verify Set-Content was called to update the ini
        Should -Invoke Set-Content -Times 1 -ParameterFilter { $Path -eq $testIniPath }
    }

    It "Adds xdebug v3 config when no existing xdebug found" {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x64.dll'; outerHTML = "<a>test</a>" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Get-Web-Response { }
        Mock Move-Item { }
        Mock Remove-Item { }
        Mock Get-Content { return "zend_extension=opcache`nopache.enable = 1" }
        Mock Add-Content { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0

        # Verify Add-Content was called for xdebug config
        Should -Invoke Add-Content -Times 1 -ParameterFilter { $Path -eq $testIniPath }
    }

    It "Adds xdebug v2 config when version 2.x is selected" {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = 'x64'; buildType = 'ts'; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-2.9.0-8.1-vs16-x64.dll'; arch = 'x64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '2.9.0'; fileName = 'php_xdebug-2.9.0-8.1-vs16-x64.dll'; outerHTML = "<a>test</a>" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Get-Web-Response { }
        Mock Move-Item { }
        Mock Remove-Item { }
        Mock Get-Content { return "zend_extension=opcache`nopache.enable = 1" }
        Mock Add-Content { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0

        # Verify Add-Content was called with v2 config
        Should -Invoke Add-Content -Times 1 -ParameterFilter {
            $Path -eq $testIniPath -and $Value -match 'xdebug.remote_enable'
        }
    }

    It "Handles x86_64 architecture in sorting" {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = $null; buildType = $null; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x86.dll'; arch = 'x86'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x86.dll'; outerHTML = "<a>test</a>" }
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x86_64.dll'; arch = 'x86_64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x86_64.dll'; outerHTML = "<a>test</a>" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Get-Web-Response { }
        Mock Move-Item { }
        Mock Remove-Item { }
        Mock Get-Content { return "zend_extension=opcache" }
        Mock Add-Content { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0
    }

    It "Handles unknown architecture in sorting" {
        Mock Get-Current-PHP-Version { return @{ version = '8.1'; arch = $null; buildType = $null; path = "$TEST_DRIVE\php\8.1.0" } }
        Mock Get-XDebug-FROM-URL {
            return @(
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-x86.dll'; arch = 'x86'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-x86.dll'; outerHTML = "<a>test</a>" }
                @{ href = '/download/php_xdebug-3.1.0-8.1-vs16-arm64.dll'; arch = 'arm64'; buildType = 'ts'; version = '8.1'; xDebugVersion = '3.1.0'; fileName = 'php_xdebug-3.1.0-8.1-vs16-arm64.dll'; outerHTML = "<a>test</a>" }
            )
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '1' }
        Mock Get-Web-Response { }
        Mock Move-Item { }
        Mock Remove-Item { }
        Mock Get-Content { return "zend_extension=opcache" }
        Mock Add-Content { }

        $code = Install-XDebug-Extension -iniPath $testIniPath
        $code | Should -Be 0
    }

    It "Skips overwrite prompt and installs when skipConfirmation is true and file exists" {
        Mock Can-Use-Cache { return $false }
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-3.1.0-8.1-vs16-x64.dll" -content 'XDebug DLL content'
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-2.9.0-8.1-vs16-x64.dll" -content 'XDebug DLL content'
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Is-File-Exists { return $true }
        Mock Remove-Item { }
        Mock Move-Item { }
        Mock Get-Content { return "zend_extension=opcache" }
        Mock Add-Content { }

        $code = Install-XDebug-Extension -iniPath $testIniPath -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Read-Host -Exactly 0 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }

    It "Prompts overwrite when skipConfirmation is false and file exists and user cancels" {
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-3.1.0-8.1-vs16-x64.dll" -content 'XDebug DLL content'
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Is-File-Exists { return $true }
        Mock Read-Host -ParameterFilter { $Prompt -like '*already exists*' } -MockWith { return 'n' }
        Mock Remove-Item { }

        $code = Install-XDebug-Extension -iniPath $testIniPath -skipConfirmation $false

        $code | Should -Be -1
        Should -Invoke Read-Host -Exactly 1 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }

    It "Prompts overwrite when skipConfirmation is false and file exists and user confirms" {
        Mock Can-Use-Cache { return $false }
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-3.1.0-8.1-vs16-x64.dll" -content 'XDebug DLL content'
        Set-MockWebResponse -url "$XDEBUG_DOWNLOAD_URL/php_xdebug-2.9.0-8.1-vs16-x64.dll" -content 'XDebug DLL content'
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Is-File-Exists { return $true }
        Mock Read-Host -ParameterFilter { $Prompt -like '*already exists*' } -MockWith { return 'y' }
        Mock Remove-Item { }
        Mock Move-Item { }
        Mock Get-Content { return "zend_extension=opcache" }
        Mock Add-Content { }

        $code = Install-XDebug-Extension -iniPath $testIniPath -skipConfirmation $false

        $code | Should -Be 0
        Should -Invoke Read-Host -Exactly 1 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }
}

Describe "Add-Missing-PHPExtension-To-Ini" {
    BeforeEach {
        Reset-Ini-Content
        Remove-Item -Path $testBackupPath -ErrorAction SilentlyContinue
        Mock Get-Zend-Extensions-List { return @('xdebug', 'opcache') }
    }

    It "Returns -1 when current PHP version is null" {
        Mock Get-Current-PHP-Version { return @{ version = $null; path = $null } }
        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'curl'
        $result | Should -Be -1
    }

    It "Adds and configures xdebug in ini file" {
        Mock Test-Path { return $true }
        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'php_xdebug.dll'
        $result | Should -Be 0
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq "- Extension 'php_xdebug.dll' already exists in php.ini"
        }
    }

    It "Adds any extension to ini file" {
        @"
zend_extension=php_opcache.dll
extension=php_mbstring.dll
"@ | Set-Content -Path $testIniPath

        Mock Test-Path { return $true }
        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'php_curl.dll'
        $result | Should -Be 0
        (Get-Content -Path $testIniPath) -match 'extension=php_curl.dll' | Should -Be $true
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq "- 'php_curl.dll' added successfully."
        }
    }

    It "Adds any extension in disabled state to ini file" {
        @"
zend_extension=php_opcache.dll
;extension=php_mbstring.dll
"@ | Set-Content -Path $testIniPath

        Mock Test-Path { return $true }
        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'php_curl.dll' -enable $false
        $result | Should -Be 0
        (Get-Content -Path $testIniPath) -match ';extension=php_curl.dll' | Should -Be $true
    }

    It "Adds extensions correctly for older PHP versions" {
        @"
zend_extension=php_opcache.dll
extension=php_mbstring.dll
"@ | Set-Content -Path $testIniPath

        Mock Test-Path { return $true }
        Mock Get-Current-PHP-Version { return @{ version = '7.1.0'; path = "$TEST_DRIVE\php\7.1.0" } }
        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'php_curl.dll'
        $result | Should -Be 0
        (Get-Content -Path $testIniPath) -match 'extension=php_curl.dll' | Should -Be $true
    }

    It "Adds zend_extensions correctly" {
        @"
extension=php_mbstring.dll
"@ | Set-Content -Path $testIniPath

        Mock Test-Path { return $true }
        Mock Get-Current-PHP-Version { return @{ version = '7.1.0'; path = "$TEST_DRIVE\php\7.1.0" } }
        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'php_opcache.dll'
        $result | Should -Be 0
        (Get-Content -Path $testIniPath) -match 'zend_extension=php_opcache.dll' | Should -Be $true
    }

    It "Returns -1 for non-existent ini file" {
        Mock Test-Path { return $false }
        $result = Add-Missing-PHPExtension-To-Ini -iniPath 'nonexistent.ini' -extFileName 'php_curl.dll'
        $result | Should -Be -1
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nphp.ini file not found: nonexistent.ini"
        }
    }

    It "Returns -1 when extension directory doesn't exist" {
        Mock Test-Path -ParameterFilter { $Path -eq $testIniPath } { return $true }
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } { return $false }

        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'php_curl.dll'

        $result | Should -Be -1
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nExtensions directory not found: $extDirectory"
        }
    }

    It "Returns -1 when extension file doesn't exist" {
        Mock Test-Path -ParameterFilter { $Path -eq $testIniPath } { return $true }
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } { return $true }
        Mock Test-Path -ParameterFilter { $Path -eq "$extDirectory\php_curl.dll" } { return $false }

        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'php_curl.dll'

        $result | Should -Be -1
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nExtension file not found: php_curl.dll"
        }
    }

    It "Handles exception gracefully" {
        Mock Log-Data { return 0 }
        Mock Backup-IniFile { throw 'Access denied' }
        $result = Add-Missing-PHPExtension-To-Ini -iniPath $testIniPath -extFileName 'curl'
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

        Mock Read-Host {
            param ($Prompt)
            if ($Prompt -eq "`nInsert the [number] you want to install") {
                return '0'
            }
        }

        Mock Get-ChildItem {
            param ($Path)
            if ($script:getRandomFile) {
                return @( @{ Name = 'random_file' } )
            }
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\php_curl-1.4.0-7.4-ts-vc15-x86\php_curl.dll" } )
        }
        Mock Extract-Zip { }
        Mock Remove-Item { }
        Mock Move-Item { }
        Mock Test-Path { return $true }
    }

    BeforeEach {
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
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { '' }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when user does choose a non valid zip extension version to install" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith {
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
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith {
            return 'n'
        }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when user answers yes to replace existing extension" {
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith {
            return 'y'
        }
        Mock Move-Item { }
        Mock Add-Missing-PHPExtension-To-Ini { return -1 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Returns -1 when no extension matching installed php version (arch & build type)" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x64'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
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
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x64'; buildType = 'ts' } }
        Mock Get-Extension-From-URL { return $null }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Installs extension successfully" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip'>8.2 Thread Safe (TS) x86</a>" }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x86.zip"; arch = 'x86'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-nts-vs16-x86.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x86.zip'>8.2 Non Thread Safe (NTS) x86</a>" }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x64.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip'>8.2 Thread Safe (TS) x64</a>" }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x64.zip"; arch = 'x64'; buildType = 'nts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-nts-vs16-x64.zip'; outerHTML = "<a href='$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-nts-vs16-x64.zip'>8.2 Non Thread Safe (NTS) x64</a>" }
                )
            }
        }
        Mock Test-Path { return $false }
        Mock Add-Missing-PHPExtension-To-Ini { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    Context "When extension has no direct link" {
        BeforeEach {
            Mock Get-Web-Response -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/nonexistent_ext" } -MockWith {
                throw 'Network error'
            }
            Mock Get-Web-Response -ParameterFilter { $Uri -eq $PECL_PACKAGES_URL } -MockWith {
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
            Mock Get-Web-Response -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=1&amp;catname=Authentication" } -MockWith {
                return @{
                    Content = 'Mocked PHP extension Auth content'
                    Links   = @(
                        @{ href = $null }
                        @{ href = '/package/courierauth' }
                        @{ href = '/package/krb5' }
                    )
                }
            }
            Mock Get-Web-Response -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=3&amp;catname=Caching" } -MockWith {
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
            Mock Get-Web-Response -ParameterFilter { $Uri -eq "$($PECL_PACKAGES_URL)?catpid=7&amp;catname=EmptyCat" } -MockWith {
                return @{
                    Content = 'Mocked PHP extension EmptyCat content'
                    Links   = @()
                }
            }
            Mock Get-Web-Response -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/courierauth" } -MockWith {
                return @{
                    Content = 'Mocked courierauth content'
                    Links   = @(
                        @{ href = '/package/courierauth/1.4.0/windows' },
                        @{ href = '/package/courierauth/2.1.0/windows' }
                    )
                }
            }
            Mock Get-Web-Response -ParameterFilter { $Uri -eq "$PECL_PACKAGE_ROOT_URL/courierauth/1.4.0/windows" } -MockWith {
                return @{
                    Content = 'Mocked PHP courierauth 1.4.0 content'
                    Links   = @(
                        @{ href = 'other_link' },
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip" },
                        @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x64.zip" }
                    )
                }
            }
            Mock Get-Web-Response -ParameterFilter { $Uri -eq "$PECL_WIN_EXT_DOWNLOAD_URL/courierauth/1.4.0/php_courierauth-1.4.0-8.2-ts-vs16-x86.zip" } -MockWith {
                $script:MockFileSystem.Files[$OutFile] = 'Downloaded content'
                return
            }
            Mock Get-ChildItem {
                param ($Path)
                return @( @{ Name = 'php_courierauth.dll'; FullName = "$TEST_DRIVE\php_courierauth-1.4.0-7.4-ts-vc15-x86\php_courierauth.dll" } )
            }
        }

        It "Falls back to matching links if extension direct link is not found" {
            Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x64'; buildType = 'ts' } }
            Mock Get-Extension-From-URL {
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
            Mock Test-Path { return $false }
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith {
                return 'y'
            }
            Mock Add-Missing-PHPExtension-To-Ini { return 0 }

            $code = Install-Extension -iniPath $testIniPath -extName 'cour'
            $code | Should -Be 0
        }

        It "Returns -1 when no extension is found" {
            $code = Install-Extension -iniPath $testIniPath -extName 'nonexistent_ext'
            $code | Should -Be -1
        }

        It "Returns -1 when user does not choose a dll extension version to install" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { '' }
            $code = Install-Extension -iniPath $testIniPath -extName 'cache'
            $code | Should -Be -1
        }
    }

    It "Handles thrown exception" {
        $script:MockFileSystem.DownloadFails = $true
        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Displays multiple extension versions with prerelease sorting" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = $null; buildType = $null } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0/php_curl-1.5.0-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.5.0'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0rc1/php_curl-1.5.0rc1-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.5.0rc1'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0beta1/php_curl-1.5.0beta1-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.5.0beta1'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.5.0alpha1/php_curl-1.5.0alpha1-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.5.0alpha1'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip"; arch = 'x64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                )
            }
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Test-Path { return $false }
        Mock Add-Missing-PHPExtension-To-Ini { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Sorts extensions with x86_64 architecture correctly" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = $null; buildType = $null } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86_64.zip"; arch = 'x86_64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                )
            }
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '0' }
        Mock Test-Path { return $false }
        Mock Add-Missing-PHPExtension-To-Ini { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Sorts extensions with unknown architecture correctly" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = $null; buildType = $null } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-arm64.zip"; arch = 'arm64'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; compiler = 'vs16' }
                )
            }
        }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nInsert the [number] you want to install" } -MockWith { return '1' }
        Mock Test-Path { return $false }
        Mock Add-Missing-PHPExtension-To-Ini { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Returns -1 when no dll file matches the pattern" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItem {
            # Return a file that doesn't match the expected pattern
            return @( @{ Name = 'random_file.dll'; FullName = "$TEST_DRIVE\extracted\random_file.dll" } )
        }
        Mock Test-Path { return $false }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Prompts user when file already exists and user cancels" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItem {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-Path -ParameterFilter { $Path -match '\.dll$' } { return $true }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { return 'n' }
        Mock Remove-Item { }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Prompts user when file already exists and user overwrites" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItem {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-Path -ParameterFilter { $Path -match '\.dll$' } { return $true }
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith { return 'Y' }
        Mock Move-Item { }
        Mock Remove-Item { }
        Mock Add-Missing-PHPExtension-To-Ini { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Returns -1 when adding extension to ini fails" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts' ; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItem {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Test-Path { return $false }
        Mock Move-Item { }
        Mock Remove-Item { }
        Mock Add-Missing-PHPExtension-To-Ini { return -1 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Skips overwrite prompt and installs when skipConfirmation is true and file exists" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts'; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItem {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Is-File-Exists { return $true }
        Mock Move-Item { }
        Mock Remove-Item { }
        Mock Add-Missing-PHPExtension-To-Ini { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl' -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Read-Host -Exactly 0 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }

    It "Prompts overwrite when skipConfirmation is false and file exists and user cancels" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts'; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItem {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Is-File-Exists { return $true }
        Mock Read-Host -ParameterFilter { $Prompt -like '*already exists*' } -MockWith { return 'n' }
        Mock Remove-Item { }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl' -skipConfirmation $false

        $code | Should -Be -1
        Should -Invoke Read-Host -Exactly 1 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }

    It "Prompts overwrite when skipConfirmation is false and file exists and user confirms" {
        Mock Get-Current-PHP-Version { return @{ version = '8.2.0'; path = "$TEST_DRIVE\php\8.2.0"; arch = 'x86'; buildType = 'ts' } }
        Mock Get-Extension-From-URL {
            return @{
                extName = 'curl'
                data    = @(
                    @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip"; arch = 'x86'; buildType = 'ts'; version = '8.2'; extVersion = '1.4.0'; fileName = 'php_curl-1.4.0-8.2-ts-vs16-x86.zip'; outerHTML = "<a>test</a>" }
                )
            }
        }
        Mock Get-ChildItem {
            return @( @{ Name = 'php_curl.dll'; FullName = "$TEST_DRIVE\extracted\php_curl.dll" } )
        }
        Mock Is-File-Exists { return $true }
        Mock Read-Host -ParameterFilter { $Prompt -like '*already exists*' } -MockWith { return 'y' }
        Mock Move-Item { }
        Mock Remove-Item { }
        Mock Add-Missing-PHPExtension-To-Ini { return 0 }

        $code = Install-Extension -iniPath $testIniPath -extName 'curl' -skipConfirmation $false

        $code | Should -Be 0
        Should -Invoke Read-Host -Exactly 1 -ParameterFilter {
            $Prompt -like '*already exists*'
        }
    }
}

Describe "Install-IniExtension" {
    It "Handles null extension name" {
        $code = Install-IniExtension -iniPath $testIniPath -extName $null
        $code | Should -Be -1
    }

    It "Installs xdebug" {
        Mock Install-XDebug-Extension { return 0 }
        $code = Install-IniExtension -iniPath $testIniPath -extName 'xdebug'
        $code | Should -Be 0
    }

    It "Installs extension" {
        Mock Install-Extension { return 0 }
        $code = Install-IniExtension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be 0
    }

    It "Returns -1 on error" {
        Mock Install-Extension { return -1 }
        $code = Install-IniExtension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Handles thrown exception" {
        Mock Log-Data { return 0 }
        Mock Install-Extension { throw 'Network error' }
        $code = Install-IniExtension -iniPath $testIniPath -extName 'curl'
        $code | Should -Be -1
    }

    It "Passes skipConfirmation true to Install-XDebug-Extension" {
        Mock Install-XDebug-Extension { return 0 }

        $code = Install-IniExtension -iniPath $testIniPath -extNames @('xdebug') -skipConfirmation $true

        $code | Should -Be 0
        Should -Invoke Install-XDebug-Extension -Exactly 1 -ParameterFilter {
            $skipConfirmation -eq $true
        }
    }

    It "Passes skipConfirmation false to Install-XDebug-Extension by default" {
        Mock Install-XDebug-Extension { return 0 }

        $code = Install-IniExtension -iniPath $testIniPath -extNames @('xdebug')

        $code | Should -Be 0
        Should -Invoke Install-XDebug-Extension -Exactly 1 -ParameterFilter {
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
