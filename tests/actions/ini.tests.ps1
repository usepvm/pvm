
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\ini-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"

    $script:PECL_PACKAGE_ROOT_URL = $PVMConfig.links.peclPackageRoot
    $script:PECL_WIN_EXT_DOWNLOAD_URL = $PVMConfig.links.peclWinExtDownload

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.paths.cache -Force | Out-Null

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$($PVMConfig.paths.php)\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force

    Mock Show-Error {}
    Mock Show-Warning {}
    Mock Show-Message {}
    Mock Show-Info {}
    Mock Write-Color {}
    Mock New-Line {}

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

Describe "Invoke-IniAction" {
    BeforeEach {
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } -MockWith { return $true }
        Reset-IniContent
        Remove-ItemWrapper -path $testBackupPath -ErrorAction SilentlyContinue
    }

    Context "info action" {
        It "Executes info action successfully" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'info' -params @('--search=cache')
            $result | Should -Be 0
        }
    }

    Context "extension info action" {
        It "Executes extension info action successfully" {
            Mock Test-FileNotExists { return $false }
            Mock Show-PHPExtensionInfo { return 0 }

            $result = Invoke-IniAction -action 'ext' -params @('info', 'xdebug')

            $result | Should -Be 0
            Should -Invoke Show-PHPExtensionInfo -Exactly 1 -ParameterFilter { $extName -eq 'xdebug' }
        }

        It "Requires exactly one extension name" {
            Mock Test-FileNotExists { return $false }

            Invoke-IniAction -action 'ext' -params @('info') | Should -Be -1
        }
    }

    Context "get action" {
        It "Gets single setting" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'get' -params @('memory_limit')

            $result | Should -Be 0
        }

        It "Gets multiple settings" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'get' -params @('memory_limit', 'display_errors')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'get' -params @()
            $result | Should -Be -1
        }
    }

    Context "set action" {
        It "Sets single setting" {
            Mock Test-FileNotExists { return $false }
            Mock Read-HostWrapper { return '256M' }
            $result = Invoke-IniAction -action 'set' -params @('memory_limit')
            $result | Should -Be 0
        }

        It "Sets multiple settings" {
            Mock Test-FileNotExists { return $false }
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "Enter new value for 'memory_limit'" } -MockWith { '512M' }
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "Enter new value for 'max_execution_time'" } -MockWith { '60' }

            $result = Invoke-IniAction -action 'set' -params @('memory_limit', 'max_execution_time')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'set' -params @()
            $result | Should -Be -1
        }
    }

    Context "enable action" {
        It "Enables single extension" {
            Mock Test-FileNotExists { return $false }
            Mock Get-ChildItemWrapper {
                return @( @{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$extDirectory\php_xdebug.dll" } )
            }
            $result = Invoke-IniAction -action 'enable' -params @('xdebug')
            $result | Should -Be 0
        }

        It "Enables multiple extensions" {
            Mock Test-FileNotExists { return $false }
            @"
;extension=php_xdebug.dll
;extension=php_gd.dll
extension=php_curl.dll
"@ | Set-ContentWrapper -path "$phpVersionPath\php.ini"

            $script:callCount = 0
            Mock Get-ChildItemWrapper {
                $script:callCount++
                if ($script:callCount -eq 1) { return @(@{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$extDirectory\php_xdebug.dll" }) }
                if ($script:callCount -eq 2) { return @(@{ BaseName = 'php_gd'; Name = 'php_gd.dll'; FullName = "$extDirectory\php_gd.dll" }) }
            }

            $result = Invoke-IniAction -action 'enable' -params @('xdebug', 'gd')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'enable' -params @()
            $result | Should -Be -1
        }
    }

    Context "disable action" {
        It "Disables single extension" {
            Mock Test-FileNotExists { return $false }
            Mock Get-ChildItemWrapper {
                return @( @{ BaseName = 'php_curl'; Name = 'php_curl.dll'; FullName = "$extDirectory\php_curl.dll" } )
            }
            $result = Invoke-IniAction -action 'disable' -params @('curl')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'disable' -params @()
            $result | Should -Be -1
        }
    }

    Context "status action" {
        It "Checks single extension status" {
            Mock Test-FileNotExists { return $false }
            Mock Get-ChildItemWrapper {
                return @( @{ BaseName = 'php_curl'; Name = 'php_curl.dll'; FullName = "$extDirectory\php_curl.dll" } )
            }
            $result = Invoke-IniAction -action 'status' -params @('curl')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'status' -params @()
            $result | Should -Be -1
        }
    }

    Context "restore action" {
        It "Restores from backup" {
            Mock Test-FileNotExists { return $false } -ParameterFilter { $Path -eq "$phpVersionPath\php.ini" }

            $script:callCount = 0
            Mock Test-FileNotExists {
                $script:callCount++
                if ($script:callCount -eq 1) { return $true }
                else { return $false }
            } -ParameterFilter { $Path -eq "$phpVersionPath\php.ini.bak" }
            # Create a backup first
            $null = Backup-IniFile -iniPath "$phpVersionPath\php.ini"
            $result = Invoke-IniAction -action 'restore' -params @()
            $result | Should -Be 0
        }
    }

    Context "add action" {
        BeforeAll {
            $script:getRandomFile = $false
            $script:MockFileSystem = @{
                Directories   = @()
                Files         = @{}
                WebResponses  = @{
                    "$PECL_PACKAGE_ROOT_URL/nonexistent_ext"                                   = @{
                        Content = 'Mocked PHP nonexistent_ext content'
                        Links   = @()
                    }
                    "$PECL_PACKAGE_ROOT_URL/pdo_mysql"                                         = @{
                        Content = 'Mocked pdo_mysql content'
                        Links   = @(
                            @{ href = '/package/pdo_mysql/1.4.0/windows' },
                            @{ href = '/package/pdo_mysql/2.1.0/windows' }
                        )
                    }
                    "$PECL_PACKAGE_ROOT_URL/curl"                                              = @{
                        Content = 'Mocked curl content'
                        Links   = @(
                            @{ href = '/package/curl/1.4.0/windows' },
                            @{ href = '/package/curl/2.1.0/windows' }
                        )
                    }
                    "$PECL_PACKAGE_ROOT_URL/curl/1.4.0/windows"                                = @{
                        Content = 'Mocked PHP curl 1.4.0 content'
                        Links   = @(
                            @{ href = 'other_link' },
                            @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" },
                            @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip" }
                        )
                    }
                    "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" = @{
                        Content = 'Mocked PHP curl 1.4.0 zip content'
                    }
                    "$PECL_PACKAGE_ROOT_URL/curl/2.1.0/windows"                                = @{
                        Content = 'Mocked PHP curl 2.1.0 content'
                        Links   = @()
                    }
                }
                DownloadFails = $false
            }

            Mock Read-HostWrapper {
                param ($Prompt)
                if ($Prompt -eq "`nInsert the [number] you want to install") {
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
            Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith {
                return 'y'
            }
            Mock Install-Extension { return 0 }
            Mock Install-XDebugExtension { return 0 }
        }

        It "Installs extension" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'add' -params @('curl')
            $result | Should -Be 0
        }

        It "Installs xdebug extension" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'add' -params @('xdebug')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'add' -params @()
            $result | Should -Be -1
        }

        It "Installs pecl extension with skip confirmation" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'add' -params @('pdo_mysql', '-y')

            $result | Should -Be 0
            Should -Invoke Install-Extension -Times 1 -ParameterFilter {
                $skipConfirmation -eq $true
            }
        }

        It "Installs xdebug extension with skip confirmation" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'add' -params @('xdebug', '-y')

            $result | Should -Be 0
            Should -Invoke Install-XDebugExtension -Times 1 -ParameterFilter {
                $skipConfirmation -eq $true
            }
        }
    }

    Context "remove action" {
        It "Uninstalls extension" {
            Mock Test-FileNotExists { return $false }
            Mock Uninstall-Extension { return 0 }

            $result = Invoke-IniAction -action 'remove' -params @('curl', 'xdebug')

            $result | Should -Be 0

            Should -Invoke Uninstall-Extension -Times 1 -ParameterFilter {
                $iniPath -eq "$phpVersionPath\php.ini" -and
                $extNames.Count -eq 2 -and
                $extNames[0] -eq 'curl' -and
                $extNames[1] -eq 'xdebug'
            }
        }

        It "Requires at least one parameter" {
            Mock Test-FileNotExists { return $false }
            Mock Uninstall-Extension { return 0 }

            $result = Invoke-IniAction -action 'remove' -params @()

            $result | Should -Be -1

            Should -Invoke Uninstall-Extension -Times 0
        }

        It "Uninstalls extension with skip confirmation" {
            Mock Test-FileNotExists { return $false }
            Mock Uninstall-Extension { return 0 }

            $result = Invoke-IniAction -action 'remove' -params @('xdebug', 'curl', '-y')

            $result | Should -Be 0

            Should -Invoke Uninstall-Extension -Times 1 -ParameterFilter {
                $skipConfirmation -eq $true
            }
        }
    }

    Context "ext action" {
        It "Lists extensions" {
            Mock Test-FileNotExists { return $false }
            Mock Get-MatchingPHPExtensionsStatus {
                return @(@{
                        fullPath   = "$extDirectory\pdo_mysql.dll"
                        fileName   = 'pdo_mysql.dll'
                        name       = 'pdo_mysql'
                        source     = 'ext,ini'
                        line       = 'extension=pdo_mysql.dll'
                        lineNumber = 4
                        status     = 'Disabled'
                        color      = 'DarkYellow'
                    })
            }
            $result = Invoke-IniAction -action 'ext' -params @('--search=sql')
            $result | Should -Be 0
        }
    }

    Context "error handling" {
        It "Handles invalid action" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'invalid' -params @()
            $result | Should -Be 0
        }

        It "Handles missing PHP current version" {
            Mock Get-CurrentPHPVersion { return $null }
            $result = Invoke-IniAction -action 'info' -params @()
            $result | Should -Be -1
        }

        It "Handles missing php.ini file" {
            Remove-ItemWrapper -path "$phpVersionPath\php.ini" -Force
            $result = Invoke-IniAction -action 'info' -params @()
            $result | Should -Be -1
        }

        It "Returns -1 on unexpected error" {
            Mock Get-CurrentPHPVersion { throw 'Unexpected error' }
            $result = Invoke-IniAction -action 'info' -params @()
            $result | Should -Be -1
        }
    }
}
