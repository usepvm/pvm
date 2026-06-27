
BeforeAll {
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot

    $script:testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $script:testIniPath = "$testDrivePath\php.ini"
    $script:extDirectory = "$testDrivePath\ext"
    $script:testBackupPath = "$testIniPath.bak"

    $script:PECL_PACKAGE_ROOT_URL = $PVMConfig.links.peclPackageRoot
    $script:PECL_WIN_EXT_DOWNLOAD_URL = $PVMConfig.links.peclWinExtDownload

    $PVMConfig.paths.cache = 'TestDrive:\cache'
    New-Item -ItemType Directory -Path $PVMConfig.paths.cache -Force | Out-Null

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
    $PVMConfig.paths.logError = "$testDrivePath\error.log"
    $PVMConfig.env.PHP_CURRENT_VERSION_PATH = "$testDrivePath\php"

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$testDrivePath\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    New-Item -ItemType SymbolicLink -Path $$PVMConfig.env.PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
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
            path = $phpVersionPath
        }
    }

    $script:MockFileSystem = @{
        Directories = @()
        Files = @{}
        WebResponses = @{}
        DownloadFails = $false
    }

    Mock Invoke-WebRequest {
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
                Links = $response.Links
            }
        }

        throw "URL not mocked: $Uri"
    }
}

AfterAll {
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Invoke-IniAction" {
    BeforeEach {
        Mock Test-Path -ParameterFilter { $Path -eq $extDirectory } -MockWith { return $true }
        Reset-Ini-Content
        Remove-Item -Path $testBackupPath -ErrorAction SilentlyContinue
    }

    Context "info action" {
        It "Executes info action successfully" {
            $result = Invoke-IniAction -action 'info' -params @('--search=cache')
            $result | Should -Be 0
        }
    }

    Context "get action" {
        It "Gets single setting" {
            $result = Invoke-IniAction -action 'get' -params @('memory_limit')

            $result | Should -Be 0
        }

        It "Gets multiple settings" {
            $result = Invoke-IniAction -action 'get' -params @('memory_limit', 'display_errors')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            $result = Invoke-IniAction -action 'get' -params @()
            $result | Should -Be -1
        }
    }

    Context "set action" {
        It "Sets single setting" {
            Mock Read-Host { return '256M' }
            $result = Invoke-IniAction -action 'set' -params @('memory_limit')
            $result | Should -Be 0
        }

        It "Sets multiple settings" {
            Mock Read-Host -ParameterFilter { $Prompt -eq "Enter new value for 'memory_limit'" } -MockWith { '512M' }
            Mock Read-Host -ParameterFilter { $Prompt -eq "Enter new value for 'max_execution_time'" } -MockWith { '60' }

            $result = Invoke-IniAction -action 'set' -params @('memory_limit', 'max_execution_time')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            $result = Invoke-IniAction -action 'set' -params @()
            $result | Should -Be -1
        }
    }

    Context "enable action" {
        It "Enables single extension" {
            Mock Get-ChildItem {
                param ($Path)
                return @( @{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$extDirectory\php_xdebug.dll" } )
            }
            $result = Invoke-IniAction -action 'enable' -params @('xdebug')
            $result | Should -Be 0
        }

        It "Enables multiple extensions" {
            @"
;extension=php_xdebug.dll
;extension=php_gd.dll
extension=php_curl.dll
"@ | Set-Content -Path "$phpVersionPath\php.ini"

            $script:callCount = 0
            Mock Get-ChildItem {
                param ($Path)
                $script:callCount++
                if ($script:callCount -eq 1) { return @(@{ BaseName = 'php_xdebug'; Name = 'php_xdebug.dll'; FullName = "$extDirectory\php_xdebug.dll" }) }
                if ($script:callCount -eq 2) { return @(@{ BaseName = 'php_gd'; Name = 'php_gd.dll'; FullName = "$extDirectory\php_gd.dll" }) }
            }

            $result = Invoke-IniAction -action 'enable' -params @('xdebug', 'gd')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            $result = Invoke-IniAction -action 'enable' -params @()
            $result | Should -Be -1
        }
    }

    Context "disable action" {
        It "Disables single extension" {
            Mock Get-ChildItem {
                param ($Path)
                return @( @{ BaseName = 'php_curl'; Name = 'php_curl.dll'; FullName = "$extDirectory\php_curl.dll" } )
            }
            $result = Invoke-IniAction -action 'disable' -params @('curl')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            $result = Invoke-IniAction -action 'disable' -params @()
            $result | Should -Be -1
        }
    }

    Context "status action" {
        It "Checks single extension status" {
            Mock Get-ChildItem {
                param ($Path)
                return @( @{ BaseName = 'php_curl'; Name = 'php_curl.dll'; FullName = "$extDirectory\php_curl.dll" } )
            }
            $result = Invoke-IniAction -action 'status' -params @('curl')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            $result = Invoke-IniAction -action 'status' -params @()
            $result | Should -Be -1
        }
    }

    Context "restore action" {
        It "Restores from backup" {
            # Create a backup first
            Backup-IniFile -iniPath "$phpVersionPath\php.ini"
            $result = Invoke-IniAction -action 'restore' -params @()
            $result | Should -Be 0
        }
    }

    Context "install action" {
        BeforeAll {
            $script:getRandomFile = $false
            $script:MockFileSystem = @{
                Directories = @()
                Files = @{}
                WebResponses = @{
                    "$PECL_PACKAGE_ROOT_URL/nonexistent_ext" = @{
                        Content = 'Mocked PHP nonexistent_ext content'
                        Links = @()
                    }
                    "$PECL_PACKAGE_ROOT_URL/pdo_mysql" = @{
                        Content = 'Mocked pdo_mysql content'
                        Links = @(
                            @{ href = '/package/pdo_mysql/1.4.0/windows' },
                            @{ href = '/package/pdo_mysql/2.1.0/windows' }
                        )
                    }
                    "$PECL_PACKAGE_ROOT_URL/curl" = @{
                        Content = 'Mocked curl content'
                        Links = @(
                            @{ href = '/package/curl/1.4.0/windows' },
                            @{ href = '/package/curl/2.1.0/windows' }
                        )
                    }
                    "$PECL_PACKAGE_ROOT_URL/curl/1.4.0/windows" = @{
                        Content = 'Mocked PHP curl 1.4.0 content'
                        Links = @(
                            @{ href = 'other_link' },
                            @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" },
                            @{ href = "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x64.zip" }
                        )
                    }
                    "$PECL_WIN_EXT_DOWNLOAD_URL/curl/1.4.0/php_curl-1.4.0-8.2-ts-vs16-x86.zip" = @{
                        Content = 'Mocked PHP curl 1.4.0 zip content'
                    }
                    "$PECL_PACKAGE_ROOT_URL/curl/2.1.0/windows" = @{
                        Content = 'Mocked PHP curl 2.1.0 content'
                        Links = @()
                    }
                }
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
                return @( @{ Name = 'php_curl.dll'; FullName = 'TestDrive:\php_curl-1.4.0-7.4-ts-vc15-x86\php_curl.dll' } )
            }
            Mock Extract-Zip { }
            Mock Remove-Item { }
            Mock Move-Item { }
            Mock Read-Host -ParameterFilter { $Prompt -eq "`nphp_curl.dll already exists. Would you like to overwrite it? (y/n)" } -MockWith {
                return 'y'
            }
            Mock Install-Extension { return 0 }
        }

        It "Installs extension" {
            $result = Invoke-IniAction -action 'add' -params @('curl')
            $result | Should -Be 0
        }

        It "Requires at least one parameter" {
            $result = Invoke-IniAction -action 'add' -params @()
            $result | Should -Be -1
        }
    }

    Context "uninstall action" {
        It "Uninstalls extension" {
            Mock Uninstall-Extension { return 0 }

            $result = Invoke-IniAction -action 'remove' -params @('curl', 'xdebug')

            $result | Should -Be 0

            Assert-MockCalled Uninstall-Extension -Times 1 -ParameterFilter {
                $iniPath -eq "$phpVersionPath\php.ini" -and
                $extNames.Count -eq 2 -and
                $extNames[0] -eq 'curl' -and
                $extNames[1] -eq 'xdebug'
            }
        }

        It "Requires at least one parameter" {
            Mock Uninstall-Extension { return 0 }

            $result = Invoke-IniAction -action 'remove' -params @()

            $result | Should -Be -1

            Assert-MockCalled Uninstall-Extension -Times 0
        }
    }

    Context "list action" {
        It "Lists extensions" {
            Mock Get-Matching-PHPExtensionsStatus {
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
            $result = Invoke-IniAction -action 'list' -params @('--search=sql')
            $result | Should -Be 0
        }
    }

    Context "error handling" {
        It "Handles invalid action" {
            $result = Invoke-IniAction -action 'invalid' -params @()
            $result | Should -Be 1
        }

        It "Handles missing PHP current version" {
            Mock Get-Current-PHP-Version { return $null }
            $result = Invoke-IniAction -action 'info' -params @()
            $result | Should -Be -1
        }

        It "Handles missing php.ini file" {
            Remove-Item -Path "$phpVersionPath\php.ini" -Force
            $result = Invoke-IniAction -action 'info' -params @()
            $result | Should -Be -1
        }

        It "Returns -1 on unexpected error" {
            Mock Get-Current-PHP-Version { throw 'Unexpected error' }
            $result = Invoke-IniAction -action 'info' -params @()
            $result | Should -Be -1
        }
    }
}
