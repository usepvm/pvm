
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive

    $script:phpPath = "$script:TEST_DRIVE\php"
    $script:testIniPath = "$script:phpPath\php.ini"
    $script:testBackupPath = "$script:phpPath\$($Global:PVMConfig.constants.INI_BACKUP_DIR_NAME)"

    Mock Show-Error { }
    Mock Show-Success { }
    Mock Show-Warning { }
    Mock Show-Info { }
    Mock Show-Message { }
    Mock Write-Gray { }
    Mock Add-LogEntry { return 0 }
    Mock Format-NiceTimestamp {
        return @{
            Date = '01 January'
            Time = '12:00:00'
            Relative = 'just now'
            DateTime = Get-Date
        }
    }
}

Describe "Restore-IniBackup" {
    BeforeEach {
        Mock Test-DirectoryNotExists { return $false }
        Mock Get-ChildItemWrapper {
            return @(
                [PSCustomObject]@{
                    Name = 'php.ini_2026-01-01_12-00.bak'
                    FullName = "$script:testBackupPath\php.ini_2026-01-01_12-00.bak"
                    CreationTime = Get-Date
                    Length = 1024
                }
            )
        }
        Mock Read-HostWrapper { return '0' }
        Mock Copy-ItemWrapper { return 0 }
    }

    It "Returns 0 when restore succeeds" {
        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be 0
        Should -Invoke Show-Info -Times 1
        Should -Invoke Show-Message -Times 1
        Should -Invoke Write-Gray -Times 1
        Should -Invoke Copy-ItemWrapper -Times 1
        Should -Invoke Show-Success -Times 1
    }

    It "Returns -1 when backup directory does not exist" {
        Mock Test-DirectoryNotExists { return $true }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1
        Should -Invoke Get-ChildItemWrapper -Times 0
    }

    It "Returns -1 when no backup files found" {
        Mock Get-ChildItemWrapper { return @() }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1
        Should -Invoke Copy-ItemWrapper -Times 0
    }

    It "Returns -1 when backup files is null" {
        Mock Get-ChildItemWrapper { return $null }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be -1
        Should -Invoke Show-Error -Times 1
    }

    It "Returns -1 when user enters invalid number" {
        Mock Read-HostWrapper { return 'invalid' }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be -1
        Should -Invoke Show-Warning -Times 1
        Should -Invoke Copy-ItemWrapper -Times 0
    }

    It "Returns -1 when user enters number out of range" {
        Mock Read-HostWrapper { return '99' }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be -1
        Should -Invoke Show-Warning -Times 1
        Should -Invoke Copy-ItemWrapper -Times 0
    }

    It "Returns -1 when user enters negative number" {
        Mock Read-HostWrapper { return '-1' }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be -1
        Should -Invoke Show-Warning -Times 1
        Should -Invoke Copy-ItemWrapper -Times 0
    }

    It "Returns -1 when Copy-ItemWrapper throws" {
        Mock Copy-ItemWrapper { throw 'Access denied' }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
        Should -Invoke Show-Error -Times 1
    }

    It "Handles multiple backup files" {
        Mock Get-ChildItemWrapper {
            return @(
                [PSCustomObject]@{
                    Name = 'php.ini_2026-01-01_12-00.bak'
                    FullName = "$script:testBackupPath\php.ini_2026-01-01_12-00.bak"
                    CreationTime = Get-Date
                    Length = 1024
                }
                [PSCustomObject]@{
                    Name = 'php.ini_2026-01-01_11-00.bak'
                    FullName = "$script:testBackupPath\php.ini_2026-01-01_11-00.bak"
                    CreationTime = (Get-Date).AddHours(-1)
                    Length = 2048
                }
            )
        }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be 0
        Should -Invoke Show-Message -Times 2
    }

    It "Selects correct backup based on user choice" {
        Mock Get-ChildItemWrapper {
            return @(
                [PSCustomObject]@{
                    Name = 'php.ini_2026-01-01_12-00.bak'
                    FullName = "$script:testBackupPath\php.ini_2026-01-01_12-00.bak"
                    CreationTime = Get-Date
                    Length = 1024
                }
                [PSCustomObject]@{
                    Name = 'php.ini_2026-01-01_11-00.bak'
                    FullName = "$script:testBackupPath\php.ini_2026-01-01_11-00.bak"
                    CreationTime = (Get-Date).AddHours(-1)
                    Length = 2048
                }
            )
        }
        Mock Read-HostWrapper { return '1' }

        $result = Restore-IniBackup -iniPath $script:testIniPath

        $result | Should -Be 0
        Should -Invoke Copy-ItemWrapper -ParameterFilter {
            $path -eq "$script:testBackupPath\php.ini_2026-01-01_11-00.bak"
        }
    }
}
