
BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive
}

Describe "Test-OS64Bit" {
    It "Returns a boolean value indicating OS architecture" {
        $result = Test-OS64Bit
        $result | Should -BeOfType [bool]
    }
}

Describe "Get-ConsoleWidth" {
    It "Returns the console width as an integer" {
        $result = Get-ConsoleWidth
        $result | Should -BeOfType [int]
        $result | Should -BeGreaterThan 0
    }
}

Describe "Test-Admin" {
    Context "When checking admin status" {
        It "Returns a boolean value" {
            $result = Test-Admin
            $result | Should -BeOfType [bool]
        }
    }
}

Describe "Test-NotAdmin" {
    It "Returns a boolean value" {
        $result = Test-NotAdmin
        $result | Should -BeOfType [bool]
    }

    It "Returns true when not running as admin" {
        Mock Test-Admin { return $false }
        $result = Test-NotAdmin
        $result | Should -Be $true
    }

    It "Returns false when running as admin" {
        Mock Test-Admin { return $true }
        $result = Test-NotAdmin
        $result | Should -Be $false
    }
}

Describe "Convert-MegabytesToBytes" {
    It "Converts megabytes to bytes correctly" {
        $result = Convert-MegabytesToBytes -megabytes 1

        $result | Should -Be ([int64]1048576)
    }

    It "Returns 0 for zero megabytes" {
        $result = Convert-MegabytesToBytes -megabytes 0

        $result | Should -Be 0
    }

    It "Returns 0 for negative megabytes" {
        $result = Convert-MegabytesToBytes -megabytes -100

        $result | Should -Be 0
    }

    It "Handles large values correctly" {
        $result = Convert-MegabytesToBytes -megabytes 1024

        $result | Should -Be ([int64]1073741824)
    }
}

Describe "Convert-BytesToMegabytes" {
    It "Converts bytes to megabytes correctly" {
        $result = Convert-BytesToMegabytes -bytes ([int64]1048576)

        $result | Should -Be 1
    }

    It "Returns 0 for zero bytes" {
        $result = Convert-BytesToMegabytes -bytes 0

        $result | Should -Be 0
    }

    It "Returns 0 for negative bytes" {
        $result = Convert-BytesToMegabytes -bytes -100

        $result | Should -Be 0
    }

    It "Rounds to 2 decimal places" {
        $result = Convert-BytesToMegabytes -bytes ([int64]1572864)

        $result | Should -Be 1.5
    }
}

Describe "Test-YesResponse" {
    It "Should return true for 'y' and 'Y' responses" {
        Test-YesResponse -response 'y' | Should -Be $true
        Test-YesResponse -response 'Y' | Should -Be $true
    }

    It "Should return false for other responses" {
        Test-YesResponse -response 'n' | Should -Be $false
        Test-YesResponse -response 'N' | Should -Be $false
    }
}

Describe "Test-NoResponse" {
    It "Should return true for 'n' and 'N' responses" {
        Test-NoResponse -response 'n' | Should -Be $true
        Test-NoResponse -response 'N' | Should -Be $true
    }

    It "Should return false for other responses" {
        Test-NoResponse -response 'y' | Should -Be $false
        Test-NoResponse -response 'Y' | Should -Be $false
    }
}

Describe "Test-IsNotQuiet" {
    It "Returns false when verbosity is None" {
        $result = Test-IsNotQuiet -verbosity 'None'

        $result | Should -Be $false
    }

    It "Returns true when verbosity is not None" {
        $result = Test-IsNotQuiet -verbosity 'Normal'

        $result | Should -Be $true
    }
}

Describe "Get-BaseUrl" {
    It "Should return the expected base URL" {
        $result = Get-BaseUrl -url 'https://example.com/test'
        $result | Should -Be 'example.com'
    }

    It "Should return an empty string for an invalid URL" {
        $result = Get-BaseUrl -url 'invalid-url'
        $result | Should -Be $null
    }

    It "Should return an empty string for an empty URL" {
        $result = Get-BaseUrl -url ''
        $result | Should -Be $null
    }

    It "Should return an empty string for a null URL" {
        $result = Get-BaseUrl -url $null
        $result | Should -Be $null
    }
}

Describe "ConvertTo-EnvEntries" {
    It "Trims entries and removes empty path segments" {
        $result = ConvertTo-EnvEntries -value ' C:\One ; ;C:\Two;  ; C:\Three '

        $result | Should -Be 'C:\One;C:\Two;C:\Three'
    }

    It "Removes duplicate paths while preserving the first occurrence" {
        $result = ConvertTo-EnvEntries -value 'C:\One;C:\Two;C:\One;C:\Three;C:\Two' -RemoveDuplicates

        $result | Should -Be 'C:\One;C:\Two;C:\Three'
    }

    It "Treats paths with different casing as duplicates and trims entries" {
        $result = ConvertTo-EnvEntries -value ' C:\One ; c:\one; C:\Two ; ' -RemoveDuplicates

        $result | Should -Be 'C:\One;C:\Two'
    }

    It "Removes empty path segments" {
        $result = ConvertTo-EnvEntries -value ';C:\One;; '

        $result | Should -Be 'C:\One'
    }
}

Describe "Format-EnvContent" {
    It "Trims entries and removes empty path segments" {
        $result = Format-EnvContent -value ' C:\One ; ;C:\Two;  ; C:\Three '

        $result | Should -Be 'C:\One;C:\Two;C:\Three'
    }

    It "Returns an empty value for empty content" {
        $result = Format-EnvContent -value ' ;  ; '

        $result | Should -Be ''
    }
}

Describe "Remove-PathDuplicates" {
    It "Removes duplicate paths while preserving the first occurrence" {
        $result = Remove-PathDuplicates -path 'C:\One;C:\Two;C:\One;C:\Three;C:\Two'

        $result | Should -Be 'C:\One;C:\Two;C:\Three'
    }

    It "Treats paths with different casing as duplicates and trims entries" {
        $result = Remove-PathDuplicates -path ' C:\One ; c:\one; C:\Two ; '

        $result | Should -Be 'C:\One;C:\Two'
    }

    It "Removes empty path segments" {
        $result = Remove-PathDuplicates -path ';C:\One;; '

        $result | Should -Be 'C:\One'
    }
}

Describe "Copy-ObjectDeep" {
    It "Returns null when input is null" {
        $result = Copy-ObjectDeep -object $null
        $result | Should -Be $null
    }

    It "Returns primitive value as-is" {
        $result = Copy-ObjectDeep -object 42
        $result | Should -Be 42

        $result = Copy-ObjectDeep -object "test string"
        $result | Should -Be "test string"

        $result = Copy-ObjectDeep -object $true
        $result | Should -Be $true
    }

    It "Deep copies ordered dictionary" {
        $original = [ordered]@{
            key1 = "value1"
            key2 = 42
            key3 = $false
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.GetType().Name | Should -Be "OrderedDictionary"
        $copy.key1 | Should -Be "value1"
        $copy.key2 | Should -Be 42
        $copy.key3 | Should -Be $false

        # Verify it's a deep copy, not a reference
        $copy.key1 = "modified"
        $original.key1 | Should -Be "value1"
    }

    It "Deep copies hashtable" {
        $original = @{
            name = "test"
            count = 10
            active = $true
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.GetType().Name | Should -Be "Hashtable"
        $copy.name | Should -Be "test"
        $copy.count | Should -Be 10
        $copy.active | Should -Be $true

        # Verify it's a deep copy, not a reference
        $copy.name = "modified"
        $original.name | Should -Be "test"
    }

    It "Deep copies array" {
        $original = @(1, 2, 3, "four", $false)

        $copy = Copy-ObjectDeep -object $original

        $copy.Count | Should -Be 5
        $copy[0] | Should -Be 1
        $copy[1] | Should -Be 2
        $copy[2] | Should -Be 3
        $copy[3] | Should -Be "four"
        $copy[4] | Should -Be $false

        # Verify it's a deep copy, not a reference
        $copy[0] = 99
        $original[0] | Should -Be 1
    }

    It "Deep copies nested ordered dictionary" {
        $original = [ordered]@{
            level1 = [ordered]@{
                level2 = [ordered]@{
                    value = "deep"
                }
            }
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.level1.level2.value | Should -Be "deep"

        # Verify it's a deep copy
        $copy.level1.level2.value = "modified"
        $original.level1.level2.value | Should -Be "deep"
    }

    It "Deep copies nested hashtable" {
        $original = @{
            outer = @{
                inner = @{
                    data = "nested"
                }
            }
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.outer.inner.data | Should -Be "nested"

        # Verify it's a deep copy
        $copy.outer.inner.data = "modified"
        $original.outer.inner.data | Should -Be "nested"
    }

    It "Deep copies array of hashtables" {
        $original = @(
            @{ name = "first"; value = 1 },
            @{ name = "second"; value = 2 }
        )

        $copy = Copy-ObjectDeep -object $original

        $copy.Count | Should -Be 2
        $copy[0].name | Should -Be "first"
        $copy[1].value | Should -Be 2

        # Verify it's a deep copy
        $copy[0].name = "modified"
        $original[0].name | Should -Be "first"
    }

    It "Deep copies ordered dictionary containing arrays" {
        $original = [ordered]@{
            items = @(1, 2, 3)
            names = @("alice", "bob")
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.items.Count | Should -Be 3
        $copy.names.Count | Should -Be 2

        # Verify it's a deep copy
        $copy.items[0] = 99
        $original.items[0] | Should -Be 1
    }

    It "Recreates scriptblock as new instance" {
        $original = { Write-Host "test" }

        $copy = Copy-ObjectDeep -object $original

        $copy.GetType().Name | Should -Be "ScriptBlock"
        $copy.ToString() | Should -Be $original.ToString()

        # Verify it's a new instance
        $copy = { Write-Host "modified" }
        $original.ToString() | Should -Not -Be "modified"
    }

    It "Handles complex nested structure" {
        $original = [ordered]@{
            data = @{
                items = @(
                    [ordered]@{ name = "item1"; values = @(1, 2, 3) },
                    [ordered]@{ name = "item2"; values = @(4, 5, 6) }
                )
                config = [ordered]@{
                    enabled = $true
                    options = @("opt1", "opt2")
                }
            }
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.data.items.Count | Should -Be 2
        $copy.data.items[0].name | Should -Be "item1"
        $copy.data.items[0].values[1] | Should -Be 2
        $copy.data.config.enabled | Should -Be $true
        $copy.data.config.options[0] | Should -Be "opt1"

        # Verify deep copy
        $copy.data.items[0].values[0] = 999
        $original.data.items[0].values[0] | Should -Be 1
    }

    It "Handles empty collections" {
        $emptyOrdered = [ordered]@{}
        $emptyHashtable = @{}
        $emptyArray = @()

        $copyOrdered = Copy-ObjectDeep -object $emptyOrdered
        $copyHashtable = Copy-ObjectDeep -object $emptyHashtable
        $copyArray = Copy-ObjectDeep -object $emptyArray

        $copyOrdered.Count | Should -Be 0
        $copyHashtable.Count | Should -Be 0
        $copyArray.Count | Should -Be 0
    }

    It "Deep copies PSCustomObject" {
        $original = [PSCustomObject]@{
            name  = "test"
            count = 10
            active = $true
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.GetType().Name | Should -Be "PSCustomObject"
        $copy.name | Should -Be "test"
        $copy.count | Should -Be 10
        $copy.active | Should -Be $true

        # Verify it's a deep copy, not a reference
        $copy.name = "modified"
        $original.name | Should -Be "test"
    }

    It "Deep copies nested PSCustomObject" {
        $original = [PSCustomObject]@{
            level1 = [PSCustomObject]@{
                level2 = [PSCustomObject]@{
                    value = "deep"
                }
            }
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.level1.level2.value | Should -Be "deep"

        # Verify it's a deep copy
        $copy.level1.level2.value = "modified"
        $original.level1.level2.value | Should -Be "deep"
    }

    It "Deep copies PSCustomObject containing arrays" {
        $original = [PSCustomObject]@{
            items = @(1, 2, 3)
            names = @("alice", "bob")
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.items.Count | Should -Be 3
        $copy.names.Count | Should -Be 2

        # Verify it's a deep copy
        $copy.items[0] = 99
        $original.items[0] | Should -Be 1
    }

    It "Deep copies array of PSCustomObjects" {
        $original = @(
            [PSCustomObject]@{ name = "first"; value = 1 },
            [PSCustomObject]@{ name = "second"; value = 2 }
        )

        $copy = Copy-ObjectDeep -object $original

        $copy.Count | Should -Be 2
        $copy[0].name | Should -Be "first"
        $copy[1].value | Should -Be 2

        # Verify it's a deep copy
        $copy[0].name = "modified"
        $original[0].name | Should -Be "first"
    }

    It "Deep copies PSCustomObject containing hashtable" {
        $original = [PSCustomObject]@{
            config = @{
                enabled = $true
                nested  = @{ value = "inner" }
            }
        }

        $copy = Copy-ObjectDeep -object $original

        $copy.config.enabled | Should -Be $true
        $copy.config.nested.value | Should -Be "inner"

        # Verify it's a deep copy
        $copy.config.nested.value = "modified"
        $original.config.nested.value | Should -Be "inner"
    }

    It "Handles empty PSCustomObject" {
        $emptyObject = [PSCustomObject]@{}

        $copyObject = Copy-ObjectDeep -object $emptyObject

        $copyObject.GetType().Name | Should -Be "PSCustomObject"
        @($copyObject.PSObject.Properties).Count | Should -Be 0
    }
}

Describe "Format-Seconds" {
    Context "When formatting seconds" {
        It "Formats seconds less than 60 with decimal precision" {
            $result = Format-Seconds -totalSeconds 30.5
            $result | Should -Be '30.5s'

            $result = Format-Seconds -totalSeconds 45.123
            $result | Should -Be '45.1s'

            $result = Format-Seconds -totalSeconds 0
            $result | Should -Be '0s'
        }

        It "Formats minutes and seconds without hours" {
            $result = Format-Seconds -totalSeconds 90
            $result | Should -Be '01:30'

            $result = Format-Seconds -totalSeconds 125
            $result | Should -Be '02:05'

            $result = Format-Seconds -totalSeconds 3599
            $result | Should -Be '59:59'
        }

        It "Formats hours, minutes, and seconds" {
            $result = Format-Seconds -totalSeconds 3600
            $result | Should -Be '01:00:00'

            $result = Format-Seconds -totalSeconds 3661
            $result | Should -Be '01:01:01'

            $result = Format-Seconds -totalSeconds 7325
            $result | Should -Be '02:02:05'

            $result = Format-Seconds -totalSeconds 86400
            $result | Should -Be '24:00:00'
        }

        It "Handles negative values by converting to zero" {
            $result = Format-Seconds -totalSeconds -10
            $result | Should -Be '0s'

            $result = Format-Seconds -totalSeconds -100.5
            $result | Should -Be '0s'
        }

        It "Handles decimal values in minute ranges" {
            $result = Format-Seconds -totalSeconds 90.7
            $result | Should -Be '01:30'

            $result = Format-Seconds -totalSeconds 125.9
            $result | Should -Be '02:05'
        }

        It "Handles decimal values in hour ranges" {
            $result = Format-Seconds -totalSeconds 3600.5
            $result | Should -Be '01:00:00'

            $result = Format-Seconds -totalSeconds 3661.8
            $result | Should -Be '01:01:01'
        }

        It "Handles null input" {
            $result = Format-Seconds -totalSeconds $null
            $result | Should -Be '0s'
        }

        It "Handles string input that can be converted" {
            $result = Format-Seconds -totalSeconds '90'
            $result | Should -Be '01:30'
        }

        It "Handles string input that cannot be converted" {
            $result = Format-Seconds -totalSeconds 'not a number'
            $result | Should -Be -1
        }
    }
}

Describe "Get-BinaryArchitectureFromDLL" {
    Context "Reading PE format from binary files" {
        It "Returns x64 architecture when machine type is 0x8664" {
            $dllPath = "$script:TEST_DRIVE\php\php8_x64.dll"
            New-Item -Path $dllPath -ItemType File -Force | Out-Null

            # Convert TestDrive path to actual filesystem path
            $actualPath = $dllPath # (Resolve-Path -Path $dllPath).ProviderPath

            # Create a minimal PE file structure for x64
            # PE Header starts at offset 0x3C
            $bytes = [byte[]]::new(1024)

            # Write MZ header
            $bytes[0] = 0x4D  # 'M'
            $bytes[1] = 0x5A  # 'Z'

            # PE offset is at 0x3C (60 decimal)
            $peOffset = 0x80
            [BitConverter]::GetBytes($peOffset).CopyTo($bytes, 0x3C)

            # At PE offset, write "PE\0\0"
            $bytes[$peOffset] = 0x50      # 'P'
            $bytes[$peOffset + 1] = 0x45  # 'E'

            # Machine type at PE offset + 4 (0x8664 for x64)
            [BitConverter]::GetBytes([uint16]0x8664).CopyTo($bytes, $peOffset + 4)

            [System.IO.File]::WriteAllBytes($actualPath, $bytes)

            $result = Get-BinaryArchitectureFromDLL -path $actualPath
            $result | Should -Be 'x64'
        }

        It "Returns x86 architecture when machine type is 0x014c" {
            $dllPath = "$script:TEST_DRIVE\php\php8_x86.dll"
            New-Item -Path $dllPath -ItemType File -Force | Out-Null

            # Convert TestDrive path to actual filesystem path
            $actualPath = $dllPath #  (Resolve-Path -Path $dllPath).ProviderPath

            # Create a minimal PE file structure for x86
            $bytes = [byte[]]::new(1024)

            # Write MZ header
            $bytes[0] = 0x4D  # 'M'
            $bytes[1] = 0x5A  # 'Z'

            # PE offset is at 0x3C (60 decimal)
            $peOffset = 0x80
            [BitConverter]::GetBytes($peOffset).CopyTo($bytes, 0x3C)

            # At PE offset, write "PE\0\0"
            $bytes[$peOffset] = 0x50      # 'P'
            $bytes[$peOffset + 1] = 0x45  # 'E'

            # Machine type at PE offset + 4 (0x014c for x86)
            [BitConverter]::GetBytes([uint16]0x014c).CopyTo($bytes, $peOffset + 4)

            [System.IO.File]::WriteAllBytes($actualPath, $bytes)

            $result = Get-BinaryArchitectureFromDLL -path $actualPath
            $result | Should -Be 'x86'
        }

        It "Returns Unknown for unknown machine type" {
            $dllPath = "$script:TEST_DRIVE\php\php8_unknown.dll"
            New-Item -Path $dllPath -ItemType File -Force | Out-Null

            # Convert TestDrive path to actual filesystem path
            $actualPath = $dllPath # (Resolve-Path -Path $dllPath).ProviderPath

            # Create a minimal PE file structure with unknown type
            $bytes = [byte[]]::new(1024)

            # Write MZ header
            $bytes[0] = 0x4D  # 'M'
            $bytes[1] = 0x5A  # 'Z'

            # PE offset is at 0x3C (60 decimal)
            $peOffset = 0x80
            [BitConverter]::GetBytes($peOffset).CopyTo($bytes, 0x3C)

            # At PE offset, write "PE\0\0"
            $bytes[$peOffset] = 0x50      # 'P'
            $bytes[$peOffset + 1] = 0x45  # 'E'

            # Machine type at PE offset + 4 (0x0000 for unknown)
            [BitConverter]::GetBytes([uint16]0x0000).CopyTo($bytes, $peOffset + 4)

            [System.IO.File]::WriteAllBytes($actualPath, $bytes)

            $result = Get-BinaryArchitectureFromDLL -path $actualPath
            $result | Should -Be 'Unknown'
        }
    }

    It "Returns Unknown when file does not exist" {
        Mock Test-FileNotExists { return $true }

        $result = Get-BinaryArchitectureFromDLL -path "$script:TEST_DRIVE\php\php8.dll"

        $result | Should -Be 'Unknown'
    }
}
