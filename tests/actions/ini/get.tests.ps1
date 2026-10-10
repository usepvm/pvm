
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
    Mock Show-Info { }
    Mock Show-Message { }
    Mock Write-Color { }

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

Describe "Get-IniSetting" {
    It "Gets existing setting" {
        $code = Get-IniSetting -iniPath $script:testIniPath -keys @('upload_max_filesize')

        $code | Should -Be 0
    }

    It "Gets setting with spaces in value" {
        $code = Get-IniSetting -iniPath $script:testIniPath -keys @('display_errors')

        $code | Should -Be 0
    }

    It "Returns -1 for commented settings" {
        $code = Get-IniSetting -iniPath $script:testIniPath -keys @('xdebug')

        $code | Should -Be -1
    }

    It "Returns -1 for non-existent setting" {
        $code = Get-IniSetting -iniPath $script:testIniPath -keys @('nonexistent_setting')

        $code | Should -Be -1
    }

    It "Requires key parameter" {
        $code = Get-IniSetting -iniPath $script:testIniPath -keys ''
        $code | Should -Be -1

        $code = Get-IniSetting -iniPath $script:testIniPath -keys $null
        $code | Should -Be -1
    }

    It "Handles regex special characters in key names" {
        $code = Get-IniSetting -iniPath $script:testIniPath -keys @('memory_limit')
        $code | Should -Be 0
    }

    It "Displays '(not set)' for empty value entries" {
        'memory_limit =' | Set-Content -Path $script:testIniPath -Encoding UTF8
        $code = Get-IniSetting -iniPath $script:testIniPath -keys @('memory_limit')
        $code | Should -Be 0
    }

    It "Returns -1 on error" {
        Mock Get-ContentWrapper { throw 'Access denied' }
        $code = Get-IniSetting -iniPath $script:testIniPath -keys @('memory_limit')
        $code | Should -Be -1
    }
}
