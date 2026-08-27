
BeforeAll {
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\set-drive"
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    $script:testIniPath = "$TEST_DRIVE\php.ini"
    $script:extDirectory = "$TEST_DRIVE\ext"
    $script:testBackupPath = "$testIniPath.bak"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
    New-Item -ItemType Directory -Path $PVMConfig.paths.cache -Force | Out-Null

    Mock Show-Warning {}
    Mock Show-Message {}
    Mock Show-Error {}
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

    # Create directory and symlink for current PHP version
    $phpVersionPath = "$TEST_DRIVE\php-8.2"
    New-Item -ItemType Directory -Path $phpVersionPath -Force
    Copy-ItemWrapper -path $testIniPath -destination "$phpVersionPath\php.ini"
}

AfterAll {
    Remove-ItemWrapper -path $TEST_DRIVE -Recurse -Force
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Set-IniSetting" {
    BeforeEach {
        Reset-IniContent
        Remove-ItemWrapper -path $testBackupPath -ErrorAction SilentlyContinue
    }

    It "Accepts key parameter without value" {
        Mock Read-HostWrapper { return '256M' }
        $result = Set-IniSetting -iniPath $testIniPath -keys @('memory_limit')
        $result | Should -Be 0
    }

    It "Accepts key parameter with value" {
        $result = Set-IniSetting -iniPath $testIniPath -keys @('memory_limit=1G')
        $result | Should -Be 0
    }

    It "Handles null key" {
        $result = Set-IniSetting -iniPath $testIniPath -keys $null
        $result | Should -Be -1
    }

    It "Updates existing setting" {
        Mock Read-HostWrapper { return '256M' }
        $code = Set-IniSetting -iniPath $testIniPath -keys @('memory_limit')
        $code | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^memory_limit\s*=\s*256M' | Should -Be $true
    }

    It "Updates setting with spaces" {
        Mock Read-HostWrapper { return 'Off' }
        $code = Set-IniSetting -iniPath $testIniPath -keys @('display_errors')
        $code | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^display_errors\s*=\s*Off' | Should -Be $true
    }

    It "Updates setting and disables" {
        Mock Read-HostWrapper { return '60' }
        $code = Set-IniSetting -iniPath $testIniPath -keys @('max_execution_time') -enable $false
        $code | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^;max_execution_time\s*=\s*60' | Should -Be $true
    }

    It "Prompts user when multiple matches found and requires input" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-ContentWrapper -path $testIniPath

        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nSelect a number" } -MockWith { return '0' }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "Enter new value for 'memory_limit'" } -MockWith { return '4G' }

        $code = Set-IniSetting -iniPath $testIniPath -keys @('memory')
        $code | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^memory_limit\s*=\s*4G' | Should -Be $true
    }

    It "Prompts user when multiple matches found and does not require input" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-ContentWrapper -path $testIniPath

        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nSelect a number" } -MockWith { return '0' }

        $code = Set-IniSetting -iniPath $testIniPath -keys @('memory=2G')
        $code | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^memory_limit\s*=\s*2G' | Should -Be $true
    }

    It "Creates backup before modifying" {
        Mock Read-HostWrapper { return '256M' }
        $null = Set-IniSetting -iniPath $testIniPath -keys @('memory_limit')
        Test-Path $testBackupPath | Should -Be $true
    }

    It "Fails for non-existent setting" {
        $code = Set-IniSetting -iniPath $testIniPath -keys @('nonexistent_setting=value')
        $code | Should -Be -1
    }

    It "Prints error message for non-valid number" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-ContentWrapper -path $testIniPath

        $script:callCount = 0
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nSelect a number" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { return 'A' }
            if ($script:callCount -eq 2) { return '-1' }
            else { return '1' }
        }

        $code = Set-IniSetting -iniPath $testIniPath -keys @('memory=1G')
        $code | Should -Be 0
    }

    It "Displays '(not set)' when multiple matching settings include blank values" {
        @"
memory_limit=
memory_limit=2G
"@ | Set-ContentWrapper -path $testIniPath

        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "`nSelect a number" } -MockWith { return '0' }
        Mock Read-HostWrapper -ParameterFilter { $prompt -eq "Enter new value for 'memory_limit'" } -MockWith { return '3G' }

        $code = Set-IniSetting -iniPath $testIniPath -keys @('memory')
        $code | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^memory_limit\s*=\s*3G' | Should -Be $true
    }

    It "Validates key=value format" {
        $code = Set-IniSetting -iniPath $testIniPath -keys @('invalidformat')
        $code | Should -Be -1

        $code = Set-IniSetting -iniPath $testIniPath -keys @('novalue=')
        $code | Should -Be -1

        $code = Set-IniSetting -iniPath $testIniPath -keys @('=nokey')
        $code | Should -Be -1
    }

    It "Handles values with special characters" {
        Mock Read-HostWrapper { return '10M' }
        $code = Set-IniSetting -iniPath $testIniPath -keys @('upload_max_filesize')
        $code | Should -Be 0
        (Get-ContentWrapper -path $testIniPath) -match '^upload_max_filesize\s*=\s*10M' | Should -Be $true
    }

    It "Returns -1 on error" {
        Mock Get-ContentWrapper { throw 'Access denied' }
        $code = Set-IniSetting -iniPath $testIniPath -keys @('memory_limit=256M')
        $code | Should -Be -1
    }
}
