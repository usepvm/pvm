
BeforeAll {
    if (-not $Global:CurrentTestDrive) {
        $currentFileName = Split-Path -Path $PSCommandPath -Leaf
        $msg = "`nTest Drive is not set for '$currentFileName'"
        $line = "`n$('=' * $msg.Length)"
        $errorMessage = $line + $msg + $line
        throw " `n$errorMessage"
    }

    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:phpVersionPath = "$script:TEST_DRIVE\php-8.2"
    $script:extDirectory = "$script:phpVersionPath\ext"
    $script:testIniPath = "$script:phpVersionPath\php.ini"
    $script:testBackupPath = "$script:testIniPath.bak"

    $script:PECL_PACKAGE_ROOT_URL = $Global:PVMConfig.links.peclPackageRoot
    $script:PECL_WIN_EXT_DOWNLOAD_URL = $Global:PVMConfig.links.peclWinExtDownload

    $null = New-Item -ItemType Directory -Path $Global:PVMConfig.paths.directories.cache -Force
    $null = New-Item -ItemType Directory -Path $script:phpVersionPath -Force
    $null = New-Item -ItemType Directory -Path $script:extDirectory -Force

    Mock Show-Error { }
    Mock Show-Warning { }
    Mock Show-Message { }
    Mock Show-Info { }
    Mock Write-Color { }
    Mock New-Line { }

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

    Mock Add-LogEntry { return 0 }

    Mock Get-CurrentPHPVersion {
        return @{
            version = '8.2.0'
            path    = $script:phpVersionPath
        }
    }

    Mock Get-PHPInfo { return 0 }
    Mock Get-IniSetting { return 0 }
    Mock Set-IniSetting { return 0 }
    Mock Enable-IniExtension { return 0 }
    Mock Disable-IniExtension { return 0 }
    Mock Get-IniExtensionStatus { return 0 }
    Mock Restore-IniBackup { return 0 }
    Mock Show-PHPExtensionInfo { return 0 }
    Mock Show-PHPExtensions { return 0 }
    Mock Invoke-PhpIniBackup { return 0 }
    Mock Invoke-PhpIniBackupCleanup { return 0 }
    Mock Install-IniExtension { return 0 }
    Mock Uninstall-Extension { return 0 }
    Mock Get-ChildItemWrapper { return @() }
    Mock Read-HostWrapper { return '256M' }
    Mock Resolve-Alias { param ($alias) return $alias }

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

Describe "Invoke-IniAction" {
    BeforeEach {
        Mock Test-FileNotExists { return $false }
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

            $result = Invoke-IniAction -action 'ext' -params @('info', 'xdebug')

            $result | Should -Be 0
            Should -Invoke Show-PHPExtensionInfo -Exactly 1 -ParameterFilter { $extName -eq 'xdebug' }
        }

        It "Requires exactly one extension name" {
            Mock Test-FileNotExists { return $false }

            $code = Invoke-IniAction -action 'ext' -params @('info')

            $code | Should -Be -1
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
            $result = Invoke-IniAction -action 'set' -params @('memory_limit')
            $result | Should -Be 0
        }

        It "Sets multiple settings" {
            Mock Test-FileNotExists { return $false }

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

            $result = Invoke-IniAction -action 'enable' -params @('xdebug')
            $result | Should -Be 0
        }

        It "Enables multiple extensions" {
            Mock Test-FileNotExists { return $false }

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
            Mock Test-FileNotExists { return $false }

            $result = Invoke-IniAction -action 'restore' -params @()
            $result | Should -Be 0
            Should -Invoke Restore-IniBackup -Times 1 -ParameterFilter {
                $iniPath -eq "$script:phpVersionPath\php.ini"
            }
        }
    }

    Context "backup action" {
        It "Creates backup successfully" {
            Mock Test-FileNotExists { return $false }
            Mock Invoke-PhpIniBackup { return 0 }

            $result = Invoke-IniAction -action 'backup' -params @()

            $result | Should -Be 0
            Should -Invoke Invoke-PhpIniBackup -Times 1 -ParameterFilter {
                $iniPath -eq "$script:phpVersionPath\php.ini"
            }
        }

        It "Cleans up old backups with --clean flag" {
            Mock Test-FileNotExists { return $false }
            Mock Invoke-PhpIniBackupCleanup { return 0 }

            $result = Invoke-IniAction -action 'backup' -params @('--clean')

            $result | Should -Be 0
            Should -Invoke Invoke-PhpIniBackupCleanup -Times 1 -ParameterFilter {
                $iniBackupPath -eq "$script:phpVersionPath\$($Global:PVMConfig.constants.INI_BACKUP_DIR_NAME)"
            }
        }

        It "Returns -1 when backup fails" {
            Mock Test-FileNotExists { return $false }
            Mock Invoke-PhpIniBackup { return -1 }

            $result = Invoke-IniAction -action 'backup' -params @()

            $result | Should -Be -1
        }

        It "Returns -1 when cleanup fails" {
            Mock Test-FileNotExists { return $false }
            Mock Invoke-PhpIniBackupCleanup { return -1 }

            $result = Invoke-IniAction -action 'backup' -params @('--clean')

            $result | Should -Be -1
        }
    }

    Context "add action" {
        BeforeAll {
            $script:MockFileSystem = @{
                Directories   = @()
                Files         = @{}
                WebResponses  = @{
                    "$script:PECL_PACKAGE_ROOT_URL/nonexistent_ext"                                   = @{
                        Content = 'Mocked PHP nonexistent_ext content'
                        Links   = @()
                    }
                    "$script:PECL_PACKAGE_ROOT_URL/pdo_mysql"                                         = @{
                        Content = 'Mocked pdo_mysql content'
                        Links   = @(
                            @{ href = '/package/pdo_mysql/1.4.0/windows' },
                            @{ href = '/package/pdo_mysql/2.1.0/windows' }
                        )
                    }
                    "$script:PECL_PACKAGE_ROOT_URL/curl"                                              = @{
                        Content = 'Mocked curl content'
                        Links   = @(
                            @{ href = '/package/curl/1.4.0/windows' },
                            @{ href = '/package/curl/2.1.0/windows' }
                        )
                    }
                    "$script:PECL_PACKAGE_ROOT_URL/curl/1.4.0/windows"                                = @{
                        Content = 'Mocked PHP curl 1.4.0 content'
                        Links   = @(
                            @{ href = 'other_link' },
                            @{ href = "$script:PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" },
                            @{ href = "$script:PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip" }
                        )
                    }
                    "$script:PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" = @{
                        Content = 'Mocked PHP curl 1.4.0 zip content'
                    }
                    "$script:PECL_PACKAGE_ROOT_URL/curl/2.1.0/windows"                                = @{
                        Content = 'Mocked PHP curl 2.1.0 content'
                        Links   = @()
                    }
                }
                DownloadFails = $false
            }

            Mock Expand-Zip { }
            Mock Remove-ItemWrapper { }
            Mock Move-ItemWrapper { }
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
            Should -Invoke Install-IniExtension -Times 1 -ParameterFilter {
                $skipConfirmation -eq $true
            }
        }

        It "Installs xdebug extension with skip confirmation" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'add' -params @('xdebug', '-y')

            $result | Should -Be 0
            Should -Invoke Install-IniExtension -Times 1 -ParameterFilter {
                $skipConfirmation -eq $true
            }
        }
    }

    Context "remove action" {
        It "Uninstalls extension" {
            Mock Test-FileNotExists { return $false }

            $result = Invoke-IniAction -action 'remove' -params @('curl', 'xdebug')

            $result | Should -Be 0

            Should -Invoke Uninstall-Extension -Times 1 -ParameterFilter {
                $iniPath -eq "$script:phpVersionPath\php.ini" -and
                $extNames.Count -eq 2 -and
                $extNames[0] -eq 'curl' -and
                $extNames[1] -eq 'xdebug'
            }
        }

        It "Requires at least one parameter" {
            Mock Test-FileNotExists { return $false }

            $result = Invoke-IniAction -action 'remove' -params @()

            $result | Should -Be -1

            Should -Invoke Uninstall-Extension -Times 0
        }

        It "Uninstalls extension with skip confirmation" {
            Mock Test-FileNotExists { return $false }

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

            $result = Invoke-IniAction -action 'ext' -params @('--search=sql')
            $result | Should -Be 0
        }
    }

    Context "when duplicate extension/settings names are provided" {
        BeforeEach {
            Mock Test-FileNotExists { return $false }
        }

        It "Removes duplicate ext names and calls Get-IniSetting once" {
            Mock Get-IniSetting { return 0 }

            $code = Invoke-IniAction -action 'get' -params @('memory', 'memory')

            $code | Should -Be 0
            Should -Invoke Get-IniSetting -ParameterFilter {
                $keys -eq @('memory')
            }
        }

        It "Removes duplicate ext names and calls Set-IniSetting once" {
            Mock Set-IniSetting { return 0 }

            $code = Invoke-IniAction -action 'set' -params @('memory', 'memory')

            $code | Should -Be 0
            Should -Invoke Set-IniSetting -ParameterFilter {
                $keys -eq @('memory')
            }
        }

        It "Removes duplicate ext names and calls Enable-IniExtension once" {
            Mock Enable-IniExtension { return 0 }

            $code = Invoke-IniAction -action 'enable' -params @('sql', 'sql')

            $code | Should -Be 0
            Should -Invoke Enable-IniExtension -ParameterFilter {
                $extNames -eq @('sql')
            }
        }

        It "Removes duplicate ext names and calls Disable-IniExtension once" {
            Mock Disable-IniExtension { return 0 }

            $code = Invoke-IniAction -action 'disable' -params @('sql', 'sql')

            $code | Should -Be 0
            Should -Invoke Disable-IniExtension -ParameterFilter {
                $extNames -eq @('sql')
            }
        }

        It "Removes duplicate ext names and calls Get-IniExtensionStatus" {
            Mock Get-IniExtensionStatus { return 0 }

            $code = Invoke-IniAction -action 'status' -params @('sql', 'sql')

            $code | Should -Be 0
            Should -Invoke Get-IniExtensionStatus -ParameterFilter {
                $extNames -eq @('sql')
            }
        }

        It "Removes duplicate ext names and calls Install-IniExtension" {
            Mock Install-IniExtension { return 0 }

            $code = Invoke-IniAction -action 'add' -params @('sql', 'sql')

            $code | Should -Be 0
            Should -Invoke Install-IniExtension -ParameterFilter {
                $extNames -eq @('sql')
            }
        }

        It "Removes duplicate ext names and calls Uninstall-Extension" {
            Mock Uninstall-Extension { return 0 }

            $code = Invoke-IniAction -action 'remove' -params @('sql', 'sql')

            $code | Should -Be 0
            Should -Invoke Uninstall-Extension -ParameterFilter {
                $extNames -eq @('sql')
            }
        }
    }

    Context "error handling" {
        It "Handles invalid action" {
            Mock Test-FileNotExists { return $false }
            $result = Invoke-IniAction -action 'invalid' -params @()
            $result | Should -Be -1
        }

        It "Handles missing PHP current version" {
            Mock Get-CurrentPHPVersion { return $null }
            $result = Invoke-IniAction -action 'info' -params @()
            $result | Should -Be -1
        }

        It "Handles missing php.ini file" {
            Mock Test-FileNotExists { return $true } -ParameterFilter { $path -eq "$script:phpVersionPath\php.ini" }
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
