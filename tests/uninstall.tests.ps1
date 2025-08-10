# Load required modules and functions
. "$PSScriptRoot\..\src\actions\uninstall.ps1"

Describe "Uninstall-PHP" {
    BeforeAll {
        # Mock the external functions
        function Get-PHP-Path-By-Version { param($version) }
        function Get-Matching-PHP-Versions { param($version) }
        function Get-UserSelected-PHP-Version { param($installedVersions) }
        function Log-Data { param($logPath, $message, $data) }
        
        # Create a test directory for PHP installations
        $testPhpPath = "TestDrive:\PHP"
        New-Item -Path "$testPhpPath\7.4" -ItemType Directory -Force
        New-Item -Path "$testPhpPath\8.0" -ItemType Directory -Force
    }

    Context "When PHP version is found directly" {
        BeforeEach {
            Mock Get-PHP-Path-By-Version -ParameterFilter { $version -eq "7.4" } -MockWith {
                "$testPhpPath\7.4"
            }
            
            Mock Get-Matching-PHP-Versions -MockWith { }
            Mock Get-UserSelected-PHP-Version -MockWith { }
            Mock Remove-Item -MockWith { }
            Mock Log-Data -MockWith { $true }
        }

        It "Should successfully uninstall when version is found directly" {
            $result = Uninstall-PHP -version "7.4"
            
            $result.code | Should -Be 0
            $result.message | Should -BeLike "*PHP version 7.4 has been uninstalled successfully*"
            $result.color | Should -Be "DarkGreen"
            
            Should -Invoke Get-PHP-Path-By-Version -Exactly 1
            Should -Invoke Remove-Item -Exactly 1 -ParameterFilter {
                $Path -eq "$testPhpPath\7.4" -and $Recurse -eq $true -and $Force -eq $true
            }
        }
    }

    Context "When PHP version is not found directly but matches exist" {
        BeforeEach {
            Mock Get-PHP-Path-By-Version -MockWith { $null }
            Mock Get-Matching-PHP-Versions -ParameterFilter { $version -eq "8.*" } -MockWith {
                @("8.0", "8.1")
            }
            Mock Get-UserSelected-PHP-Version -MockWith {
                @{ code = 0; version = "8.0"; path = "$testPhpPath\8.0" }
            }
            Mock Remove-Item -MockWith { }
            Mock Log-Data -MockWith { $true }
        }

        It "Should successfully uninstall after user selection" {
            $result = Uninstall-PHP -version "8.*"
            
            $result.code | Should -Be 0
            $result.message | Should -BeLike "*PHP version 8.* has been uninstalled successfully*"
            $result.color | Should -Be "DarkGreen"
            
            Should -Invoke Get-Matching-PHP-Versions -Exactly 1
            Should -Invoke Get-UserSelected-PHP-Version -Exactly 1
            Should -Invoke Remove-Item -Exactly 1 -ParameterFilter {
                $Path -eq "$testPhpPath\8.0"
            }
        }
    }

    Context "When PHP version is not found at all" {
        BeforeEach {
            Mock Get-PHP-Path-By-Version -MockWith { $null }
            Mock Get-Matching-PHP-Versions -ParameterFilter { $version -eq "5.6" } -MockWith {
                @()
            }
            Mock Get-UserSelected-PHP-Version -MockWith { }
            Mock Remove-Item -MockWith { }
            Mock Log-Data -MockWith { $true }
        }

        It "Should return version not found message" {
            $result = Uninstall-PHP -version "5.6"
            
            $result.code | Should -Be -1
            $result.message | Should -Be "Version 5.6 was not found!"
            $result.color | Should -Be "DarkYellow"
            
            Should -Invoke Get-PHP-Path-By-Version -Exactly 1
            Should -Invoke Get-Matching-PHP-Versions -Exactly 1
            Should -Invoke Remove-Item -Exactly 0
        }
    }

    Context "When user selection returns an error" {
        BeforeEach {
            Mock Get-PHP-Path-By-Version -MockWith { $null }
            Mock Get-Matching-PHP-Versions -ParameterFilter { $version -eq "8.*" } -MockWith {
                @("8.0", "8.1")
            }
            Mock Get-UserSelected-PHP-Version -MockWith {
                @{ code = -1; message = "User cancelled the selection"; color = "DarkYellow" }
            }
            Mock Remove-Item -MockWith { }
            Mock Log-Data -MockWith { $true }
        }

        It "Should return the user selection error" {
            $result = Uninstall-PHP -version "8.*"
            
            $result.code | Should -Be -1
            $result.message | Should -Be "User cancelled the selection"
            $result.color | Should -Be "DarkYellow"
            
            Should -Invoke Get-Matching-PHP-Versions -Exactly 1
            Should -Invoke Get-UserSelected-PHP-Version -Exactly 1
            Should -Invoke Remove-Item -Exactly 0
        }
    }

    Context "When user selection returns a version but no path" {
        BeforeEach {
            Mock Get-PHP-Path-By-Version -MockWith { $null }
            Mock Get-Matching-PHP-Versions -ParameterFilter { $version -eq "8.*" } -MockWith {
                @("8.0", "8.1")
            }
            Mock Get-UserSelected-PHP-Version -MockWith {
                @{ code = 0; version = "8.2"; path = $null }
            }
            Mock Remove-Item -MockWith { }
            Mock Log-Data -MockWith { $true }
        }

        It "Should return version not found message" {
            $result = Uninstall-PHP -version "8.*"
            
            $result.code | Should -Be -1
            $result.message | Should -Be "Version 8.2 was not found!"
            $result.color | Should -Be "DarkYellow"
            
            Should -Invoke Get-Matching-PHP-Versions -Exactly 1
            Should -Invoke Get-UserSelected-PHP-Version -Exactly 1
            Should -Invoke Remove-Item -Exactly 0
        }
    }

    Context "When uninstallation fails with an exception" {
        BeforeEach {
            Mock Get-PHP-Path-By-Version -ParameterFilter { $version -eq "7.4" } -MockWith {
                "$testPhpPath\7.4"
            }
            Mock Get-Matching-PHP-Versions -MockWith { }
            Mock Get-UserSelected-PHP-Version -MockWith { }
            Mock Remove-Item -MockWith { throw "Access denied" }
            Mock Log-Data -MockWith { $true }
        }

        It "Should catch the exception and return error message" {
            $result = Uninstall-PHP -version "7.4"
            
            $result.code | Should -Be -1
            $result.message | Should -Be "Failed to uninstall PHP version '7.4'"
            $result.color | Should -Be "DarkYellow"
            
            Should -Invoke Remove-Item -Exactly 1
            Should -Invoke Log-Data -Exactly 1
        }
    }

    AfterAll {
        Remove-Item -Path $testPhpPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}