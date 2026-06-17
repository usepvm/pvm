
BeforeAll {
    $testDrivePath = Get-PSDrive TestDrive | Select-Object -ExpandProperty Root
    $testIniPath = "$testDrivePath\php.ini"
    $extDirectory = "$testDrivePath\ext"
    $testBackupPath = "$testIniPath.bak"

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
    New-Item -ItemType SymbolicLink -Path $PVMConfig.env.PHP_CURRENT_VERSION_PATH -Target $phpVersionPath -Force
    Copy-Item -Path $testIniPath "$phpVersionPath\php.ini" -Force
}

Describe "Set-IniSetting" {
    BeforeEach {
        Reset-Ini-Content
        Remove-Item -Path $testBackupPath -ErrorAction SilentlyContinue
    }

    It "Accepts key parameter without value" {
        Mock Read-Host { return '256M' }
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
        Mock Read-Host { return '256M' }
        Set-IniSetting -iniPath $testIniPath -keys @('memory_limit') | Should -Be 0
        (Get-Content -Path $testIniPath) -match '^memory_limit\s*=\s*256M' | Should -Be $true
    }

    It "Updates setting with spaces" {
        Mock Read-Host { return 'Off' }
        Set-IniSetting -iniPath $testIniPath -keys @('display_errors') | Should -Be 0
        (Get-Content -Path $testIniPath) -match '^display_errors\s*=\s*Off' | Should -Be $true
    }

    It "Updates setting and disables" {
        Mock Read-Host { return '60' }
        Set-IniSetting -iniPath $testIniPath -keys @('max_execution_time') -enable $false | Should -Be 0
        (Get-Content -Path $testIniPath) -match '^;max_execution_time\s*=\s*60' | Should -Be $true
    }

    It "Prompts user when multiple matches found and requires input" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-Content -Path $testIniPath

        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith { return 0 }
        Mock Read-Host -ParameterFilter { $Prompt -eq "Enter new value for 'memory_limit'" } -MockWith { return '4G' }

        Set-IniSetting -iniPath $testIniPath -keys @('memory') | Should -Be 0
        (Get-Content -Path $testIniPath) -match '^memory_limit\s*=\s*4G' | Should -Be $true
    }

    It "Prompts user when multiple matches found and does not require input" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-Content -Path $testIniPath

        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith { return 0 }

        Set-IniSetting -iniPath $testIniPath -keys @('memory=2G') | Should -Be 0
        (Get-Content -Path $testIniPath) -match '^memory_limit\s*=\s*2G' | Should -Be $true
    }

    It "Creates backup before modifying" {
        Mock Read-Host { return '256M' }
        Set-IniSetting -iniPath $testIniPath -keys @('memory_limit')
        Test-Path $testBackupPath | Should -Be $true
    }

    It "Fails for non-existent setting" {
        Set-IniSetting -iniPath $testIniPath -keys @('nonexistent_setting=value') | Should -Be -1
    }

    It "Prints error message for non-valid number" {
        @"
;memory_limit=2G
opcache.protect_memory=1
"@ | Set-Content -Path $testIniPath

        $script:callCount = 0
        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith {
            $script:callCount++
            if ($script:callCount -eq 1) { return 'A' }
            if ($script:callCount -eq 2) { return -1 }
            else { return '1' }
        }

        Set-IniSetting -iniPath $testIniPath -keys @('memory=1G') | Should -Be 0
    }

    It "Displays '(not set)' when multiple matching settings include blank values" {
        @"
memory_limit=
memory_limit=2G
"@ | Set-Content -Path $testIniPath -Encoding UTF8

        Mock Read-Host -ParameterFilter { $Prompt -eq "`nSelect a number" } -MockWith { return 0 }
        Mock Read-Host -ParameterFilter { $Prompt -eq "Enter new value for 'memory_limit'" } -MockWith { return '3G' }

        Set-IniSetting -iniPath $testIniPath -keys @('memory') | Should -Be 0
        (Get-Content -Path $testIniPath) -match '^memory_limit\s*=\s*3G' | Should -Be $true
    }

    It "Validates key=value format" {
        Set-IniSetting -iniPath $testIniPath -keys @('invalidformat') | Should -Be -1
        Set-IniSetting -iniPath $testIniPath -keys @('novalue=') | Should -Be -1
        Set-IniSetting -iniPath $testIniPath -keys @('=nokey') | Should -Be -1
    }

    It "Handles values with special characters" {
        Mock Read-Host { return '10M' }
        Set-IniSetting -iniPath $testIniPath -keys @('upload_max_filesize') | Should -Be 0
        (Get-Content -Path $testIniPath) -match '^upload_max_filesize\s*=\s*10M' | Should -Be $true
    }

    It "Returns -1 on error" {
        Mock Get-Content { throw 'Access denied' }
        Set-IniSetting -iniPath $testIniPath -keys @('memory_limit=256M') | Should -Be -1
    }
}
