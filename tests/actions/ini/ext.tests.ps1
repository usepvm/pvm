
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.directories.fakeStorage)\ext-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null

    Mock Show-Error {}
    Mock Show-Message {}
    Mock Show-Info {}
    Mock Write-Gray {}
    Mock New-Line {}
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
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
                )
            }
        }
        Mock Get-AvailablePHPExtensions -MockWith { return Get-ExtensionList }
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
        Mock Get-AvailablePHPExtensions { return @{} }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
        Should -Invoke Get-AvailablePHPExtensions -Exactly 1
    }

    It "Displays available extensions matching the filter" {
        Mock Get-AvailablePHPExtensions { return Get-ExtensionList }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true -term 'pc'
        $code | Should -Be 0
        Should -Invoke Show-Info -Exactly 2
        Should -Invoke Write-Gray -Exactly 1
    }

    It "Returns -1 when no available extensions matchs the filter" {
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true -term 'nonexistent'
        $code | Should -Be -1
    }

    It "Handles thrown exception" {
        Mock Get-AvailablePHPExtensions { throw 'Error' }
        $code = Show-PHPExtensions -iniPath $testIniPath -available $true
        $code | Should -Be -1
    }

    It "Returns -1 when available extensions count is 0" {
        Mock Get-AvailablePHPExtensions { return @{} }

        $code = Show-PHPExtensions -iniPath $testIniPath -available $true

        $code | Should -Be -1
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq "`nNo extensions found"
        }
    }

    It "Displays available extensions with long descriptions that require wrapping" {
        Mock Get-AvailablePHPExtensions {
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
        Mock Get-AvailablePHPExtensions {
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

Describe "Show-PHPExtensionInfo" {
    BeforeEach {
        Mock Get-ExtensionMatchingCategories {
            return @(
                @{ extName = 'xdebug'; description = 'Debugger'; extCategory = 'Debugging'; href = '/package/xdebug' }
            )
        }
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'php_xdebug'; id = 'xdebug'; fileName = 'php_xdebug.dll'; fullPath = 'C:\php\ext\php_xdebug.dll'; version = '1.2.3'; status = 'Enabled'; color = 'DarkGreen'; lineNumber = 4; line = 'zend_extension=php_xdebug.dll'; source = 'ext,ini' }
            )
        }
        Mock Show-Warning {}
        Mock Add-LogEntry {}
        Mock Write-Color {}
    }

    It "Displays cached metadata and local installation details" {
        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Get-ExtensionMatchingCategories -Exactly 1 -ParameterFilter { $extName -eq 'xdebug' }
        Should -Invoke Get-MatchingPHPExtensionsStatus -Exactly 1 -ParameterFilter { $extName -eq 'xdebug' -and $includeIniOnly }
        Should -Invoke Show-Info -Times 2
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' Debugger' }
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' php_xdebug.dll' }
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' 1.2.3' }
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' 4' }
    }

    It "Allows selecting a local extension when multiple records match" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'xdebug-1'; id = 'xdebug'; status = 'Enabled'; color = 'DarkGreen'; lineNumber = 4; line = 'zend_extension=xdebug-1.dll' }
                @{ name = 'xdebug-2'; id = 'xdebug'; status = 'Disabled'; color = 'DarkYellow'; lineNumber = 8; line = ';zend_extension=xdebug-2.dll' }
            )
        }
        Mock Read-HostWrapper { return '1' }

        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Read-HostWrapper -Exactly 1
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' xdebug-2' }
        Should -Invoke Write-Color -ParameterFilter { $message -eq ' Disabled' -and $foreColor -eq 'DarkYellow' }
    }

    It "Retries invalid and out-of-range local selections" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'xdebug-1'; id = 'xdebug'; status = 'Enabled'; color = 'DarkGreen' }
                @{ name = 'xdebug-2'; id = 'xdebug'; status = 'Disabled'; color = 'DarkYellow' }
            )
        }
        Mock Read-HostWrapper { $script:selectionAttempts++ ; if ($script:selectionAttempts -eq 1) { return 'bad' } elseif ($script:selectionAttempts -eq 2) { return '2' } return '0' }
        $script:selectionAttempts = 0

        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Show-Warning -Times 2
        Should -Invoke Read-HostWrapper -Exactly 3
    }

    It "Displays missing metadata and unconfigured local details" {
        Mock Get-ExtensionMatchingCategories {
            return @(@{ extName = 'xdebug' })
        }
        Mock Get-MatchingPHPExtensionsStatus {
            return @(@{ name = 'xdebug'; id = 'xdebug'; status = 'Disabled'; color = 'DarkYellow'; lineNumber = 0; line = $null; fileName = $null; fullPath = $null; comment = 'DLL file not found' })
        }

        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' (not available)' }
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' (not configured)' }
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' (not found)' }
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' DLL file not found' }
    }

    It "Displays local-only status when metadata is unavailable" {
        Mock Get-ExtensionMatchingCategories { return @() }
        Mock Get-MatchingPHPExtensionsStatus {
            return @(@{ name = 'xdebug'; id = 'xdebug'; status = 'Enabled'; color = 'DarkGreen' })
        }

        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' Not found in available extensions cache' }
    }

    It "Displays not installed status when only metadata is available" {
        Mock Get-MatchingPHPExtensionsStatus { return @() }

        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName 'xdebug'

        $code | Should -Be 0
        Should -Invoke Show-Message -ParameterFilter { $message -eq ' Not installed or configured locally' }
    }

    It "Returns -1 when extension lookup fails" {
        Mock Get-ExtensionMatchingCategories { throw 'Cache unavailable' }

        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName 'xdebug'
        $code | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like "`nFailed to get information for extension 'xdebug'" }
        Should -Invoke Add-LogEntry -Exactly 1
    }

    It "Returns -1 when the extension is unknown" {
        Mock Get-ExtensionMatchingCategories { return @() }
        Mock Get-MatchingPHPExtensionsStatus { return @() }

        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName 'missing'
        $code | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -eq "`nExtension 'missing' not found" }
    }

    It "Returns -1 for an empty extension name" {
        Mock Get-ExtensionMatchingCategories { return @() }
        Mock Get-MatchingPHPExtensionsStatus { return @() }

        $code = Show-PHPExtensionInfo -iniPath $testIniPath -extName ''
        $code | Should -Be -1
    }
}
