
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
}

AfterAll {
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-Last-Update-Check-Timestamp" {
    BeforeAll {
        $script:CACHE_PATH = $PVMConfig.paths.cache = 'TestDrive:\storage\data\cache'
        New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null
        $script:TIMESTAMP_FILE = "$CACHE_PATH\last_update_check.txt"
    }

    AfterEach {
        if (Test-Path $TIMESTAMP_FILE) {
            Remove-Item -Path $TIMESTAMP_FILE -Force
        }
    }

    Context "When the timestamp file does not exist" {
        It "Returns null" {
            $result = Get-Last-Update-Check-Timestamp
            $result | Should -Be $null
        }
    }

    Context "When the timestamp file exists" {
        It "Returns a DateTime parsed from the file content" {
            $date = Get-Date '2026-01-01 10:00:00'
            $date | Set-Content -Path $TIMESTAMP_FILE

            $result = Get-Last-Update-Check-Timestamp

            $result | Should -BeOfType [DateTime]
            $result | Should -Be $date
        }

        It "Returns null when the file content cannot be parsed as a DateTime" {
            'not-a-date' | Set-Content -Path $TIMESTAMP_FILE

            $result = Get-Last-Update-Check-Timestamp

            $result | Should -Be $null
        }
    }
}

Describe "Set-Last-Update-Check-Timestamp" {
    BeforeAll {
        $script:CACHE_PATH = $PVMConfig.paths.cache = 'TestDrive:\storage\data\cache'
        $script:TIMESTAMP_FILE = "$CACHE_PATH\last_update_check.txt"
    }

    Context "When writing succeeds" {
        It "Creates the cache directory" {
            Mock Make-Directory { return 0 }
            Mock Get-Date { return (Get-Date '2026-01-01') }

            Set-Last-Update-Check-Timestamp

            Should -Invoke Make-Directory -Times 1 -ParameterFilter {
                $path -eq $CACHE_PATH
            }
        }

        It "Writes the current date to the timestamp file and returns 0" {
            New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null

            $result = Set-Last-Update-Check-Timestamp

            $result | Should -Be 0
            Test-Path $TIMESTAMP_FILE | Should -Be $true
        }
    }

    Context "When writing fails" {
        It "Returns -1 when Set-Content throws" {
            New-Item -ItemType Directory -Path $CACHE_PATH -Force | Out-Null
            Mock Set-Content { throw 'Test exception' }

            $result = Set-Last-Update-Check-Timestamp

            $result | Should -Be -1
        }
    }
}

Describe "Should-Check-For-Updates" {
    BeforeAll {
        $script:ORIGINAL_ENABLE_UPDATE_CHECK = $PVMConfig.env.ENABLE_UPDATE_CHECK
        $script:ORIGINAL_UPDATE_CHECK_INTERVAL_HOURS = $PVMConfig.env.UPDATE_CHECK_INTERVAL_HOURS
    }

    AfterAll {
        $PVMConfig.env.ENABLE_UPDATE_CHECK = $ORIGINAL_ENABLE_UPDATE_CHECK
        $PVMConfig.env.UPDATE_CHECK_INTERVAL_HOURS = $ORIGINAL_UPDATE_CHECK_INTERVAL_HOURS
    }

    Context "When update checks are disabled" {
        It "Returns false without checking the last timestamp" {
            $PVMConfig.env.ENABLE_UPDATE_CHECK = $false
            Mock Get-Last-Update-Check-Timestamp {}

            $result = Should-Check-For-Updates

            $result | Should -Be $false
            Should -Invoke Get-Last-Update-Check-Timestamp -Times 0
        }
    }

    Context "When update checks are enabled" {
        BeforeEach {
            $PVMConfig.env.ENABLE_UPDATE_CHECK = $true
            $PVMConfig.env.UPDATE_CHECK_INTERVAL_HOURS = 24
        }

        It "Returns true when there is no previous check timestamp" {
            Mock Get-Last-Update-Check-Timestamp { return $null }

            $result = Should-Check-For-Updates

            $result | Should -Be $true
        }

        It "Returns true when enough hours have passed since the last check" {
            Mock Get-Last-Update-Check-Timestamp { return (Get-Date).AddHours(-25) }

            $result = Should-Check-For-Updates

            $result | Should -Be $true
        }

        It "Returns false when not enough hours have passed since the last check" {
            Mock Get-Last-Update-Check-Timestamp { return (Get-Date).AddHours(-1) }

            $result = Should-Check-For-Updates

            $result | Should -Be $false
        }

        It "Returns true when the elapsed time exactly equals the interval" {
            Mock Get-Last-Update-Check-Timestamp { return (Get-Date).AddHours(-24) }

            $result = Should-Check-For-Updates

            $result | Should -Be $true
        }
    }
}

Describe "Check-For-Updates-Quietly" {
    Context "When an update check is not due" {
        It "Returns without calling Update-PVM" {
            Mock Should-Check-For-Updates { return $false }
            Mock Update-PVM {}
            Mock Set-Last-Update-Check-Timestamp {}

            $result = Check-For-Updates-Quietly

            $result | Should -Be 0
            Should -Invoke Update-PVM -Times 0
            Should -Invoke Set-Last-Update-Check-Timestamp -Times 0
        }
    }

    Context "When an update check is due" {
        It "Calls Update-PVM with checkOnly and records the timestamp" {
            Mock Should-Check-For-Updates { return $true }
            Mock Update-PVM { return @{ code = 0; message = 'No update available' } }
            Mock Set-Last-Update-Check-Timestamp {}

            $result = Check-For-Updates-Quietly

            $result | Should -Be 0
            Should -Invoke Update-PVM -Times 1 -ParameterFilter {
                $checkOnly -eq $true
            }
            Should -Invoke Set-Last-Update-Check-Timestamp -Times 1
        }

        It "Writes a message to the host when an update is available" {
            Mock Should-Check-For-Updates { return $true }
            Mock Update-PVM { return @{ code = 0; message = 'Update available: v2.7.0' } }
            Mock Set-Last-Update-Check-Timestamp {}
            Mock Write-Host {}

            $result = Check-For-Updates-Quietly

            $result | Should -Be 0
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -like "*Update available: v2.7.0*Run 'pvm update' to update.*"
            }
        }

        It "Does not write to the host when the result code is not 0" {
            Mock Should-Check-For-Updates { return $true }
            Mock Update-PVM { return @{ code = -1; message = 'Update available: v2.7.0' } }
            Mock Set-Last-Update-Check-Timestamp {}
            Mock Write-Host {}

            $result = Check-For-Updates-Quietly

            $result | Should -Be -1
            Should -Invoke Write-Host -Times 0
        }

        It "Does not write to the host when no update is available" {
            Mock Should-Check-For-Updates { return $true }
            Mock Update-PVM { return @{ code = 0; message = 'PVM is already up to date' } }
            Mock Set-Last-Update-Check-Timestamp {}
            Mock Write-Host {}

            $result = Check-For-Updates-Quietly

            $result | Should -Be 0
            Should -Invoke Write-Host -Times 0
        }

        It "Returns -1 and logs error when Update-PVM throws exception" {
            Mock Should-Check-For-Updates { return $true }
            Mock Update-PVM { throw 'Network error' }
            Mock Set-Last-Update-Check-Timestamp {}
            Mock Log-Data {}

            $result = Check-For-Updates-Quietly

            $result | Should -Be -1
            Should -Invoke Log-Data -Times 1
        }
    }
}
