
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:phpVersionPath = "$script:TEST_DRIVE\php-8.2"
    $script:testIniPath = "$script:phpVersionPath\php.ini"
    $script:extDirectory = "$script:phpVersionPath\ext"
    $script:testBackupPath = "$script:testIniPath.bak"

    $null = New-Directory -path $Global:PVMConfig.paths.directories.cache
    $null = New-Directory -path $script:phpVersionPath
    $null = New-Directory -path $script:extDirectory

    Mock Show-Error { }
    Mock Show-Message { }
    Mock Write-Color { }

    function Reset-IniContent {
        @(
            'memory_limit = 128M'
            ';extension=php_xdebug.dll'
            'extension=php_curl.dll'
            ';extension=php_mysql.dll'
            'zend_extension=php_opcache.dll'
            'mysqli.default_port=3306'
            'display_errors = On'
            'max_execution_time = 30'
            ';upload_max_filesize = 2M'
        ) -join "`n" | Set-ContentWrapper -path $script:testIniPath
    }

    Reset-IniContent

    Mock Get-CurrentPHPVersion {
        return @{
            version = '8.2.0'
            path    = $script:phpVersionPath
        }
    }
}

Describe "Get-PHPInfo" {
    BeforeEach {
        Reset-IniContent
    }

    It "Returns PHP version info successfully" {
        $result = Get-PHPInfo
        $result | Should -Be 0
    }

    It "Displays only extensions" {
        Mock Get-AllPHPExtensionsStatus { return @() }
        Mock Show-ExtensionsStates { }
        Mock Show-InstalledExtensions { }
        Mock Get-AllPHPSettings { return @() }
        Mock Show-SettingsStates { }
        Mock Show-Settings { }

        $null = Get-PHPInfo -extensions $true

        Should -Invoke Get-AllPHPExtensionsStatus -Times 1
        Should -Invoke Show-ExtensionsStates -Times 1
        Should -Invoke Show-InstalledExtensions -Times 1
        Should -Invoke Get-AllPHPSettings -Times 0
        Should -Invoke Show-SettingsStates -Times 0
        Should -Invoke Show-Settings -Times 0
    }

    It "Displays only settings" {
        Mock Get-AllPHPExtensionsStatus { return @() }
        Mock Show-ExtensionsStates { }
        Mock Show-InstalledExtensions { }
        Mock Get-AllPHPSettings { return @() }
        Mock Show-SettingsStates { }
        Mock Show-Settings { }

        $null = Get-PHPInfo -settings $true

        Should -Invoke Get-AllPHPExtensionsStatus -Times 0
        Should -Invoke Show-ExtensionsStates -Times 0
        Should -Invoke Show-InstalledExtensions -Times 0
        Should -Invoke Get-AllPHPSettings -Times 1
        Should -Invoke Show-SettingsStates -Times 1
        Should -Invoke Show-Settings -Times 1
    }

    It "Handles missing PHP version gracefully" {
        Mock Get-CurrentPHPVersion { return @{ version = $null; path = $null } }
        $result = Get-PHPInfo
        $result | Should -Be -1
    }

    It "Displays only matching extensions and settings" {
        $result = Get-PHPInfo -term 'sql'

        $result | Should -Be 0
    }
}
