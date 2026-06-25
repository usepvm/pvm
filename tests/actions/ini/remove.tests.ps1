
BeforeAll {
    $script:testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $script:testIniPath = "$testDrivePath\php.ini"
    $script:extDirectory = "$testDrivePath\ext"
    $script:testBackupPath = "$testIniPath.bak"

    Mock Write-Host {}
    Mock Log-Data { return 0 }

    function Reset-Ini-Content {
        # Create a test php.ini file
        @"
memory_limit = 128M
extension=php_curl.dll
extension=php_xdebug.dll
zend_extension=php_opcache.dll
display_errors = On
"@ | Set-Content -Path $testIniPath -Encoding UTF8
    }

    # Create initial ini content first
    Reset-Ini-Content
    New-Item -ItemType Directory -Path $extDirectory -Force | Out-Null
}

Describe "Remove-Extension-From-Ini-File" {
    BeforeEach { Reset-Ini-Content }

    It "Removes the matching line and returns 0" {
        $extension = @{ line = 'extension=php_curl.dll'; lineNumber = 2 }

        $result = Remove-Extension-From-Ini-File -iniPath $testIniPath -extensionObject $extension

        $result            | Should -Be 0
        $content = Get-Content -Path $testIniPath
        $content           | Should -Not -Contain 'extension=php_curl.dll'
        $content.Count     | Should -Be 4
    }

    It "Returns -1 when line content matches but line number does not" {
        $extension = @{ line = 'extension=php_curl.dll'; lineNumber = 99 }

        $result = Remove-Extension-From-Ini-File -iniPath $testIniPath -extensionObject $extension

        $result        | Should -Be -1
        $content = Get-Content -Path $testIniPath
        $content.Count | Should -Be 5
    }

    It "Returns -1 when line number matches but content does not" {
        $extension = @{ line = 'extension=php_nonexistent.dll'; lineNumber = 2 }

        $result = Remove-Extension-From-Ini-File -iniPath $testIniPath -extensionObject $extension

        $result        | Should -Be -1
        $content = Get-Content -Path $testIniPath
        $content.Count | Should -Be 5
    }

    It "Returns -1 when Get-Content throws" {
        $extension = @{ line = 'extension=php_curl.dll'; lineNumber = 2 }

        Mock Get-Content { throw 'Read error' }

        $result = Remove-Extension-From-Ini-File -iniPath $testIniPath -extensionObject $extension

        $result | Should -Be -1
        Assert-MockCalled Log-Data -Times 1
    }
}

Describe "Remove-Extension-From-Ext-Directory" {
    It "Removes the file and returns 0 when file exists and paths match" {
        Mock Is-File-Not-Exists { return $false }
        Mock Remove-Item { }
        $extensionObject = @{
            fileName = 'php_curl.dll'
            fullPath = "$extDirectory\php_curl.dll"
            name     = 'curl'
        }

        $result = Remove-Extension-From-Ext-Directory -extensionDirectory $extDirectory -extensionObject $extensionObject

        $result | Should -Be 0
        Test-Path "$extDirectory\php_curl.dll" | Should -Be $false
    }

    It "Returns -1 when file does not exist on disk" {
        Mock Is-File-Not-Exists { return $true }

        $extensionObject = @{
            fileName = 'php_curl.dll'
            fullPath = "$extDirectory\php_curl.dll"
            name     = 'curl'
        }

        $result = Remove-Extension-From-Ext-Directory -extensionDirectory $extDirectory -extensionObject $extensionObject

        $result | Should -Be -1
    }

    It "Returns -1 when fullPath does not match the constructed path" {
        Mock Is-File-Not-Exists { return $false }

        $extensionObject = @{
            fileName = 'php_curl.dll'
            fullPath = 'C:\some\other\path\php_curl.dll'
            name     = 'curl'
        }

        $result = Remove-Extension-From-Ext-Directory -extensionDirectory $extDirectory -extensionObject $extensionObject

        $result | Should -Be -1
    }

    It "Returns -1 and logs when Remove-Item throws" {
        Mock Is-File-Not-Exists { return $false }
        Mock Remove-Item { throw 'Access denied' }

        $extensionObject = @{
            fileName = 'php_curl.dll'
            fullPath = "$extDirectory\php_curl.dll"
            name     = 'curl'
        }

        $result = Remove-Extension-From-Ext-Directory -extensionDirectory $extDirectory -extensionObject $extensionObject

        $result | Should -Be -1
        Assert-MockCalled Remove-Item -Times 1
        Assert-MockCalled Log-Data -Times 1
    }
}

Describe "Uninstall-Extension" {
    BeforeEach {
        Reset-Ini-Content
        New-Item -ItemType File -Path "$extDirectory\php_curl.dll"    -Force | Out-Null
        New-Item -ItemType File -Path "$extDirectory\php_xdebug.dll"  -Force | Out-Null
        New-Item -ItemType File -Path "$extDirectory\php_opcache.dll" -Force | Out-Null

        Mock Is-Directory-Not-Exists { return $false }
        Mock Is-File-Not-Exists { return $false }
        Mock Read-Host { return 'n' }
    }

    AfterEach {
        Remove-Item -Path "$extDirectory\*" -Force -ErrorAction SilentlyContinue
    }

    It "Returns -1 immediately when extNames is empty" {
        $result = Uninstall-Extension -iniPath $testIniPath -extNames @()

        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq "`nPlease provide at least one extension name to uninstall"
        }
    }

    It "Returns -1 when ext directory does not exist" {
        Mock Is-Directory-Not-Exists { return $true }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl')

        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like "*Extensions directory not found*"
        }
    }

    It "Adds Not Found result and returns -1 when extension is not in ini" {
        Mock Get-Matching-PHPExtensionsStatus { return @() }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('nonexistent')

        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like "*nonexistent*"
        }
    }

    It "Adds Not Found result and returns -1 when extension file is missing from disk" {
        Mock Is-File-Not-Exists { return $true }
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext,ini'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl')

        $result | Should -Be -1
    }

    It "Adds failure result and returns -1 when Remove-Extension-From-Ext-Directory fails" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext,ini'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }
        Mock Read-Host { return 'y' }
        Mock Is-File-Not-Exists { return $false }
        Mock Remove-Extension-From-Ext-Directory { return -1 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl')

        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like "*Failed to remove*ext directory*"
        }
    }

    It "Adds failure result and returns -1 when Remove-Extension-From-Ini-File fails" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext,ini'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }
        Mock Read-Host { return 'y' }
        Mock Is-File-Not-Exists { return $false }
        Mock Remove-Extension-From-Ext-Directory { return 0 }
        Mock Remove-Extension-From-Ini-File { return -1 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl')

        $result | Should -Be -1
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -like "*Failed to remove*php.ini*"
        }
    }

    It "Returns 0 and shows Uninstalled for ext,ini source extension" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext,ini'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }
        Mock Read-Host { return 'y' }
        Mock Is-File-Not-Exists { return $false }
        Mock Remove-Extension-From-Ext-Directory { return 0 }
        Mock Remove-Extension-From-Ini-File { return 0 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl')

        $result | Should -Be 0
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq ' Uninstalled'
        }
    }

    It "Returns 0 and skips ini removal for ext-only source extension" {
        Mock Is-Directory-Not-Exists { return $false }
        Mock Is-File-Not-Exists { return $false }
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }
        Mock Read-Host { return 'y' }
        Mock Remove-Extension-From-Ext-Directory { return 0 }
        Mock Remove-Extension-From-Ini-File { return 0 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl')

        $result | Should -Be 0
        Assert-MockCalled Remove-Extension-From-Ini-File -Times 0
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq ' Uninstalled'
        }
    }

    It "Processes multiple extensions and returns -1 when any fails" {
        Mock Get-Matching-PHPExtensionsStatus -ParameterFilter { $extName -eq 'curl' } {
            return @(@{
                    fullPath = "$extDirectory\php_curl.dll"
                    fileName = 'php_curl.dll'
                    name     = 'curl'
                    source   = 'ext'
                })
        }
        Mock Get-Matching-PHPExtensionsStatus -ParameterFilter { $extName -eq 'nonexistent' } {
            return @()
        }
        Mock Remove-Extension-From-Ext-Directory { return 0 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl', 'nonexistent')

        $result | Should -Be -1
    }

    It "Returns -1 and logs when an unexpected exception is thrown" {
        Mock Get-Matching-PHPExtensionsStatus { throw 'Unexpected error' }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl')

        $result | Should -Be -1
        Assert-MockCalled Log-Data -Times 1
    }

    It "Skips extension removal for non-existent extension" {
        Mock Is-Directory-Not-Exists { return $false }
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\pdo_pgsql.dll"
                    fileName   = 'pdo_pgsql.dll'
                    name       = 'pdo_pgsql'
                    source     = 'ext,ini'
                    line       = 'extension=pdo_pgsql.dll'
                    lineNumber = 2
                    status     = 'Enabled'
                    color      = 'DarkGreen'
                })
        }
        Mock Read-Host { return 'y' }
        Mock Is-File-Not-Exists { return $true }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('sql')

        $result | Should -Be -1
    }

    It "Prints error message for non-valid number" {
        Mock Is-Directory-Not-Exists { return $false }
        Mock Is-File-Not-Exists { return $false }
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\pdo_pgsql.dll"
                    fileName   = 'pdo_pgsql.dll'
                    name       = 'pdo_pgsql'
                    source     = 'ext,ini'
                    line       = 'extension=pdo_pgsql.dll'
                    lineNumber = 2
                    status     = 'Enabled'
                    color      = 'DarkGreen'
                },
                @{
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
        $script:callCount = 0
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { return 'A' }
            if ($script:callCount -eq 2) { return -1 }
            else { return 1 }
        }

        Mock Read-Host -ParameterFilter { $Prompt -eq "`nAre you sure you want to uninstall 'pdo_mysql'? (y/n)" } -MockWith {
            return 'y'
        }
        Mock Remove-Extension-From-Ext-Directory { return 0 }
        Mock Remove-Extension-From-Ini-File { return 0 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('sql')

        $result | Should -Be 0
        Assert-MockCalled Write-Host -Times 1 -ParameterFilter {
            $Object -eq ' Uninstalled'
        }
    }

    It "Skips confirmation prompt and uninstalls when skipConfirmation is true" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext,ini'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }
        Mock Is-File-Not-Exists { return $false }
        Mock Remove-Extension-From-Ext-Directory { return 0 }
        Mock Remove-Extension-From-Ini-File { return 0 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl') -skipConfirmation $true

        $result | Should -Be 0
        Should -Invoke Read-Host -Exactly 0 -ParameterFilter {
            $Prompt -like "*Are you sure*"
        }
    }

    It "Prompts confirmation when skipConfirmation is false and cancels on 'n'" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext,ini'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }
        Mock Is-File-Not-Exists { return $false }
        Mock Read-Host -ParameterFilter { $Prompt -like "*Are you sure*" } -MockWith { return 'n' }
        Mock Remove-Extension-From-Ext-Directory { return 0 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl') -skipConfirmation $false

        $result | Should -Be -1
        Should -Invoke Read-Host -Exactly 1 -ParameterFilter {
            $Prompt -like "*Are you sure*"
        }
        Should -Invoke Remove-Extension-From-Ext-Directory -Exactly 0
    }

    It "Prompts confirmation when skipConfirmation is false and proceeds on 'y'" {
        Mock Get-Matching-PHPExtensionsStatus {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext,ini'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }
        Mock Is-File-Not-Exists { return $false }
        Mock Read-Host -ParameterFilter { $Prompt -like "*Are you sure*" } -MockWith { return 'y' }
        Mock Remove-Extension-From-Ext-Directory { return 0 }
        Mock Remove-Extension-From-Ini-File { return 0 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl') -skipConfirmation $false

        $result | Should -Be 0
        Should -Invoke Read-Host -Exactly 1 -ParameterFilter {
            $Prompt -like "*Are you sure*"
        }
    }

    It "Skips confirmation for all extensions when skipConfirmation is true with multiple extNames" {
        Mock Get-Matching-PHPExtensionsStatus -ParameterFilter { $extName -eq 'curl' } {
            return @(@{
                    fullPath   = "$extDirectory\php_curl.dll"
                    fileName   = 'php_curl.dll'
                    name       = 'curl'
                    source     = 'ext,ini'
                    line       = 'extension=php_curl.dll'
                    lineNumber = 2
                })
        }
        Mock Get-Matching-PHPExtensionsStatus -ParameterFilter { $extName -eq 'xdebug' } {
            return @(@{
                    fullPath   = "$extDirectory\php_xdebug.dll"
                    fileName   = 'php_xdebug.dll'
                    name       = 'xdebug'
                    source     = 'ext,ini'
                    line       = 'extension=php_xdebug.dll'
                    lineNumber = 3
                })
        }
        Mock Is-File-Not-Exists { return $false }
        Mock Remove-Extension-From-Ext-Directory { return 0 }
        Mock Remove-Extension-From-Ini-File { return 0 }

        $result = Uninstall-Extension -iniPath $testIniPath -extNames @('curl', 'xdebug') -skipConfirmation $true

        $result | Should -Be 0
        Should -Invoke Read-Host -Exactly 0 -ParameterFilter {
            $Prompt -like "*Are you sure*"
        }
    }
}
