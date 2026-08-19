
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
        Should -Invoke Show-Info -Exactly 1
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
