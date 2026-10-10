
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

    Mock Show-Warning { }
    Mock Write-Color { }
    Mock Show-Error { }
    Mock Show-Message { }

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
}

Describe "Get-IniExtensionStatus" {
    BeforeEach {
        Reset-IniContent
    }

    It "Detects enabled extension" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'curl'; id='curl'; status='Enabled'; color='DarkGreen'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        $code = Get-IniExtensionStatus -iniPath $script:testIniPath -extNames @('curl')
        $code | Should -Be 0
    }

    It "Detects disabled extension" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'xdebug'; id='xdebug'; status='Disabled'; color='DarkYellow'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        $code = Get-IniExtensionStatus -iniPath $script:testIniPath -extNames @('xdebug')
        $code | Should -Be 0
    }

    It "Detects enabled zend_extension" {
        Mock Get-MatchingPHPExtensionsStatus {
            return @(
                @{ name = 'opcache'; id='opcache'; status='Enabled'; color='DarkGreen'; line=0; lineNamber=0; source='ext,ini' }
            )
        }
        $code = Get-IniExtensionStatus -iniPath $script:testIniPath -extNames @('opcache')
        $code | Should -Be 0
    }

    It "Returns -1 for non-existent extension" {
        Mock Read-HostWrapper { return 'n' }
        $code = Get-IniExtensionStatus -iniPath $script:testIniPath -extNames @('nonexistent_ext')
        $code | Should -Be -1
    }

    It "Requires extension name" {
        $code = Get-IniExtensionStatus -iniPath $script:testIniPath -extNames ''
        $code | Should -Be -1

        $code = Get-IniExtensionStatus -iniPath $script:testIniPath -extNames $null
        $code | Should -Be -1
    }

    It "Returns -1 on error" {
        Mock Get-ContentWrapper { throw 'Access denied' }
        $code = Get-IniExtensionStatus -iniPath $script:testIniPath -extNames @('curl')
        $code | Should -Be -1
    }

    It "Returns -1 if no match is found for any extension" {
        Mock Get-MatchingPHPExtensionsStatus {
            param ($extName)

            if ($extName -eq 'unknown') { return @() }
            return @( @{ name = 'curl'; id='curl'; status='Enabled'; color='DarkGreen'; line=0; lineNamber=0; source='ext,ini' } )
        }

        $code = Get-IniExtensionStatus -iniPath $script:testIniPath -extNames @('curl', 'unknown')

        $code | Should -Be -1
    }
}
