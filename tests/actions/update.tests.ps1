
BeforeAll {
    Mock Write-Host {}
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Get-Config -rootPath $PVMRoot
    $PVMConfig.version = 'v1.0.0'
}

AfterAll {
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Update-PVM" {
    BeforeEach {
        Mock Is-Directory-Not-Exists { return $false }
        Mock Test-Git-Available { return $true }
        Mock Get-Current-Git-Branch { return 'main' }
        Mock Get-Git-Status { return $null }
        Mock Get-Current-Git-Commit { return 'abc123' }
        Mock Get-Latest-Git-Commit { return 'abc123' }
        Mock Get-PVM-Version-From-Git { return 'v1.0.0' }
        Mock git { return $null }
    }

    Context "Git availability" {
        It "returns error when git is not available" {
            Mock Test-Git-Available { return $false }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'Git is not installed'
        }
    }

    Context "Repository validation" {
        It "returns error when .git directory doesn't exist" {
            Mock Is-Directory-Not-Exists { return $true }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'not installed from a git repository'
        }

        It "returns error when current branch cannot be determined" {
            Mock Get-Current-Git-Branch { return $null }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'Failed to determine current git branch'
        }

        It "returns error when current branch is an empty string" {
            Mock Get-Current-Git-Branch { return '' }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
        }
    }

    Context "Uncommitted changes" {
        It "returns error and lists each changed file" {
            Mock Get-Git-Status { return @('M  file1.txt', '?? file2.txt') }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'uncommitted changes'
            $result.message | Should -Match 'file1.txt'
            $result.message | Should -Match 'file2.txt'
        }

        It "collapses double spaces and trims a single status line" {
            Mock Get-Git-Status { return 'M  file.txt' }

            $result = Update-PVM -checkOnly $true

            $result.message | Should -Match '- M file.txt'
        }
    }

    Context "Commit resolution failures" {
        It "returns error when current commit cannot be determined" {
            Mock Get-Current-Git-Commit { return $null }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'Failed to get current git commit'
        }

        It "returns error when fetching the latest commit fails" {
            Mock Get-Latest-Git-Commit { return $null }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'Failed to fetch latest updates'
        }
    }

    Context "Already up to date" {
        It "returns success with the current config version" {
            Mock Get-Current-Git-Commit { return 'same' }
            Mock Get-Latest-Git-Commit { return 'same' }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be 0
            $result.message | Should -Match 'already up to date'
            $result.message | Should -Match 'v1.0.0'
        }

        It "short-circuits regardless of checkOnly value" {
            Mock Get-Current-Git-Commit { return 'same' }
            Mock Get-Latest-Git-Commit { return 'same' }

            $result = Update-PVM -checkOnly $false

            $result.code | Should -Be 0
            $result.message | Should -Match 'already up to date'
            Should -Invoke -CommandName git -Times 0
        }
    }

    Context "CheckOnly mode with an update available" {
        BeforeEach {
            Mock Get-Current-Git-Commit { return 'abc123' }
            Mock Get-Latest-Git-Commit { return 'def456' }
        }

        It "reports old -> new version when both resolve" {
            Mock Get-PVM-Version-From-Git { return 'v1.0.0' }
            Mock git { return 'v1.1.0' }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be 0
            $result.message | Should -Match 'Update available: v1.0.0 -> v1.1.0'
        }

        It "falls back to a generic message when versions can't be resolved" {
            Mock Get-PVM-Version-From-Git { return $null }
            Mock git { return $null }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be 0
            $result.message | Should -Be 'Update available!'
        }

        It "never pulls in checkOnly mode" {
            Mock Get-PVM-Version-From-Git { return 'v1.0.0' }
            Mock git { return 'v1.1.0' }

            Update-PVM -checkOnly $true

            Should -Invoke -CommandName git -ParameterFilter { $args -contains 'pull' } -Times 0
        }
    }

    Context "Performing the update" {
        BeforeEach {
            Mock Get-Current-Git-Commit { return 'abc123' }
            Mock Get-Latest-Git-Commit { return 'def456' }
        }

        It "pulls and reports the new version on success" {
            $Global:PVMConfig = @{ version = 'v1.0.0' }
            Mock Get-PVM-Version-From-Git { return 'v1.1.0' }

            $result = Update-PVM -checkOnly $false

            $result.code | Should -Be 0
            $result.message | Should -Match 'updated successfully to version v1.1.0'
            Should -Invoke -CommandName git -ParameterFilter { $args -contains 'pull' } -Times 1
        }

        It "reports no version change when normalized versions match" {
            $Global:PVMConfig = @{ version = 'v1.0' }
            Mock Get-PVM-Version-From-Git { return 'v1.0.0' }

            $result = Update-PVM -checkOnly $false

            $result.code | Should -Be 0
            $result.message | Should -Match 'No version change'
        }

        It "falls back to the config version when the new version can't be resolved" {
            $Global:PVMConfig = @{ version = 'v1.0.0' }
            Mock Get-PVM-Version-From-Git { return $null }

            $result = Update-PVM -checkOnly $false

            $result.code | Should -Be 0
            $result.message | Should -Match 'No version change \(still v1.0.0\)'
        }

        It "returns an error when git pull throws" {
            Mock git {
                if ($args -contains 'pull') { throw 'network error' }
                return $null
            }

            $result = Update-PVM -checkOnly $false

            $result.code | Should -Be -1
            $result.message | Should -Match 'Failed to pull updates'
        }
    }
}

Describe "Test-Git-Available" {
    It "returns true when git command resolves" {
        Mock Get-Command { return @{ Name = 'git' } }

        Test-Git-Available | Should -Be $true
    }

    It "returns false when git command is not found" {
        Mock Get-Command { throw 'command not found' }

        Test-Git-Available | Should -Be $false
    }
}

Describe "Get-Git-Status" {
    It "returns porcelain status output" {
        Mock git { return 'M file.txt' }

        Get-Git-Status | Should -Be 'M file.txt'
    }

    It "returns null when git throws" {
        Mock git { throw 'not a repo' }

        Get-Git-Status | Should -BeNullOrEmpty
    }
}

Describe "Get-Current-Git-Branch" {
    It "returns a trimmed branch name" {
        Mock git { return "main`n" }

        Get-Current-Git-Branch | Should -Be 'main'
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        Get-Current-Git-Branch | Should -BeNullOrEmpty
    }
}

Describe "Get-Current-Git-Commit" {
    It "returns a trimmed commit hash" {
        Mock git { return "abc123`n" }

        Get-Current-Git-Commit | Should -Be 'abc123'
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        Get-Current-Git-Commit | Should -BeNullOrEmpty
    }
}

Describe "Get-Latest-Git-Commit" {
    It "fetches origin and returns the trimmed remote commit" {
        Mock git {
            if ($args -contains 'fetch') { return $null }
            return "def456`n"
        }

        Get-Latest-Git-Commit -branch 'main' | Should -Be 'def456'
    }

    It "returns null when fetch/rev-parse throws" {
        Mock git { throw 'network error' }

        Get-Latest-Git-Commit -branch 'main' | Should -BeNullOrEmpty
    }

    It "defaults branch to 'main' when not specified" {
        Mock git {
            if ($args -contains 'fetch') { return $null }
            return 'def456'
        }

        Get-Latest-Git-Commit | Should -Be 'def456'
    }
}

Describe "Get-PVM-Version-From-Git" {
    It "returns the trimmed latest tag" {
        Mock git { return "v1.2.3`n" }

        Get-PVM-Version-From-Git | Should -Be 'v1.2.3'
    }

    It "returns null when no tags exist" {
        Mock git { return $null }

        Get-PVM-Version-From-Git | Should -BeNullOrEmpty
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        Get-PVM-Version-From-Git | Should -BeNullOrEmpty
    }
}

Describe "Normalize-Version" {
    It "strips a leading 'v' prefix" {
        Normalize-Version -version 'v1.2.3' | Should -Be '1.2.3'
    }

    It "strips a single trailing .0 segment" {
        Normalize-Version -version 'v1.2.0' | Should -Be '1.2'
    }

    It "strips multiple trailing .0 segments" {
        Normalize-Version -version 'v1.0.0' | Should -Be '1'
    }

    It "leaves a version with no prefix or trailing zeros unchanged" {
        Normalize-Version -version '1.2.3' | Should -Be '1.2.3'
    }
}
