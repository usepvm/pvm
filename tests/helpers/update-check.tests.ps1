
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $script:TEST_DRIVE = "$($PVMConfig.paths.fakeStorage)\update-check-drive"

    New-Item -ItemType Directory -Path $TEST_DRIVE -Force | Out-Null
}

AfterAll {
    Remove-Item -Path $TEST_DRIVE -Recurse -Force
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Get-Last-Update-Check-Timestamp" {
    BeforeAll {
        $script:CACHE_PATH = $PVMConfig.paths.cache = "$TEST_DRIVE\cache"
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
        $script:CACHE_PATH = $PVMConfig.paths.cache = "$TEST_DRIVE\cache"
        $script:TIMESTAMP_FILE = "$CACHE_PATH\last_update_check.txt"
    }

    Context "When writing succeeds" {
        It "Creates the cache directory" {
            Mock New-Directory {
                return 0
            }
            Mock Get-Date { return [datetime]'2026-01-01' }

            $result = Set-Last-Update-Check-Timestamp

            $result | Should -Be 0
            Should -Invoke New-Directory -Times 1 -ParameterFilter {
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

Describe "Test-Should-Check-For-Updates" {
    Context "When update checks are disabled" {
        It "Returns false without checking the last timestamp" {
            $PVMConfig.env.ENABLE_UPDATE_CHECK = $false
            Mock Get-Last-Update-Check-Timestamp {}

            $result = Test-Should-Check-For-Updates

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

            $result = Test-Should-Check-For-Updates

            $result | Should -Be $true
        }

        It "Returns true when enough hours have passed since the last check" {
            Mock Get-Last-Update-Check-Timestamp { return (Get-Date).AddHours(-25) }

            $result = Test-Should-Check-For-Updates

            $result | Should -Be $true
        }

        It "Returns false when not enough hours have passed since the last check" {
            Mock Get-Last-Update-Check-Timestamp { return (Get-Date).AddHours(-1) }

            $result = Test-Should-Check-For-Updates

            $result | Should -Be $false
        }

        It "Returns true when the elapsed time exactly equals the interval" {
            Mock Get-Last-Update-Check-Timestamp { return (Get-Date).AddHours(-24) }

            $result = Test-Should-Check-For-Updates

            $result | Should -Be $true
        }
    }
}

Describe "Test-Check-For-Updates-Quietly" {
    Context "When an update check is not due" {
        It "Returns without calling Update-PVM" {
            Mock Test-Should-Check-For-Updates { return $false }
            Mock Update-PVM {}
            Mock Set-Last-Update-Check-Timestamp {}

            $result = Test-Check-For-Updates-Quietly

            $result | Should -Be 0
            Should -Invoke Update-PVM -Times 0
            Should -Invoke Set-Last-Update-Check-Timestamp -Times 0
        }
    }

    Context "When an update check is due" {
        It "Calls Update-PVM with checkOnly and records the timestamp" {
            Mock Test-Should-Check-For-Updates { return $true }
            Mock Update-PVM { return @{ code = 0; message = 'No update available' } }
            Mock Set-Last-Update-Check-Timestamp {}

            $result = Test-Check-For-Updates-Quietly

            $result | Should -Be 0
            Should -Invoke Update-PVM -Times 1 -ParameterFilter {
                $checkOnly -eq $true
            }
            Should -Invoke Set-Last-Update-Check-Timestamp -Times 1
        }

        It "Writes a message to the host when an update is available" {
            Mock Test-Should-Check-For-Updates { return $true }
            Mock Update-PVM { return @{ code = 0; message = 'Update available: v2.7.0' } }
            Mock Set-Last-Update-Check-Timestamp {}
            Mock Write-Host {}

            $result = Test-Check-For-Updates-Quietly

            $result | Should -Be 0
            Should -Invoke Write-Host -Times 1 -ParameterFilter {
                $Object -like "*Update available: v2.7.0*Run 'pvm update' to update.*"
            }
        }

        It "Does not write to the host when the result code is not 0" {
            Mock Test-Should-Check-For-Updates { return $true }
            Mock Update-PVM { return @{ code = -1; message = 'Update available: v2.7.0' } }
            Mock Set-Last-Update-Check-Timestamp {}
            Mock Write-Host {}

            $result = Test-Check-For-Updates-Quietly

            $result | Should -Be -1
            Should -Invoke Write-Host -Times 0
        }

        It "Does not write to the host when no update is available" {
            Mock Test-Should-Check-For-Updates { return $true }
            Mock Update-PVM { return @{ code = 0; message = 'PVM is already up to date' } }
            Mock Set-Last-Update-Check-Timestamp {}
            Mock Write-Host {}

            $result = Test-Check-For-Updates-Quietly

            $result | Should -Be 0
            Should -Invoke Write-Host -Times 0
        }

        It "Returns -1 and logs error when Update-PVM throws exception" {
            Mock Test-Should-Check-For-Updates { return $true }
            Mock Update-PVM { throw 'Network error' }
            Mock Set-Last-Update-Check-Timestamp {}
            Mock Add-LogEntry {}

            $result = Test-Check-For-Updates-Quietly

            $result | Should -Be -1
            Should -Invoke Add-LogEntry -Times 1
        }
    }
}
