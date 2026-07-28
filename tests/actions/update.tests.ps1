
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
        Mock Test-DirectoryNotExists { return $false }
        Mock Test-GitAvailable { return $true }
        Mock Get-CurrentGitBranch { return 'main' }
        Mock Get-GitStatus { return $null }
        Mock Get-CurrentGitCommit { return 'abc123' }
        Mock Get-LatestGitCommit { return 'abc123' }
        Mock Get-PVMVersionFromGit { return 'v1.0.0' }
        Mock git { return $null }
    }

    Context "Git availability" {
        It "returns error when git is not available" {
            Mock Test-GitAvailable { return $false }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'Git is not installed'
        }
    }

    Context "Repository validation" {
        It "returns error when .git directory doesn't exist" {
            Mock Test-DirectoryNotExists { return $true }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'not installed from a git repository'
        }

        It "returns error when current branch cannot be determined" {
            Mock Get-CurrentGitBranch { return $null }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'Failed to determine current git branch'
        }

        It "returns error when current branch is an empty string" {
            Mock Get-CurrentGitBranch { return '' }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
        }
    }

    Context "Uncommitted changes" {
        It "returns error and lists each changed file" {
            Mock Get-GitStatus { return @('M  file1.txt', '?? file2.txt') }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'uncommitted changes'
            $result.message | Should -Match 'file1.txt'
            $result.message | Should -Match 'file2.txt'
        }

        It "collapses double spaces and trims a single status line" {
            Mock Get-GitStatus { return 'M  file.txt' }

            $result = Update-PVM -checkOnly $true

            $result.message | Should -Match '- M file.txt'
        }
    }

    Context "Commit resolution failures" {
        It "returns error when current commit cannot be determined" {
            Mock Get-CurrentGitCommit { return $null }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'Failed to get current git commit'
        }

        It "returns error when fetching the latest commit fails" {
            Mock Get-LatestGitCommit { return $null }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be -1
            $result.message | Should -Match 'Failed to fetch latest updates'
        }
    }

    Context "Already up to date" {
        It "returns success with the current config version" {
            Mock Get-CurrentGitCommit { return 'same' }
            Mock Get-LatestGitCommit { return 'same' }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be 0
            $result.message | Should -Match 'already up to date'
            $result.message | Should -Match 'v1.0.0'
        }

        It "short-circuits regardless of checkOnly value" {
            Mock Get-CurrentGitCommit { return 'same' }
            Mock Get-LatestGitCommit { return 'same' }

            $result = Update-PVM -checkOnly $false

            $result.code | Should -Be 0
            $result.message | Should -Match 'already up to date'
            Should -Invoke -CommandName git -Times 0
        }
    }

    Context "CheckOnly mode with an update available" {
        BeforeEach {
            Mock Get-CurrentGitCommit { return 'abc123' }
            Mock Get-LatestGitCommit { return 'def456' }
        }

        It "reports old -> new version when both resolve" {
            Mock Get-PVMVersionFromGit { return 'v1.0.0' }
            Mock git { return 'v1.1.0' }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be 0
            $result.message | Should -Match 'Update available: v1.0.0 -> v1.1.0'
        }

        It "falls back to a generic message when versions can't be resolved" {
            Mock Get-PVMVersionFromGit { return $null }
            Mock git { return $null }

            $result = Update-PVM -checkOnly $true

            $result.code | Should -Be 0
            $result.message | Should -Be 'Update available!'
        }

        It "never pulls in checkOnly mode" {
            Mock Get-PVMVersionFromGit { return 'v1.0.0' }
            Mock git { return 'v1.1.0' }

            Update-PVM -checkOnly $true

            Should -Invoke -CommandName git -ParameterFilter { $args -contains 'pull' } -Times 0
        }
    }

    Context "Performing the update" {
        BeforeEach {
            Mock Get-CurrentGitCommit { return 'abc123' }
            Mock Get-LatestGitCommit { return 'def456' }
        }

        It "pulls and reports the new version on success" {
            $Global:PVMConfig = @{ version = 'v1.0.0' }
            Mock Get-PVMVersionFromGit { return 'v1.1.0' }

            $result = Update-PVM -checkOnly $false

            $result.code | Should -Be 0
            $result.message | Should -Match 'updated successfully to version v1.1.0'
            Should -Invoke -CommandName git -ParameterFilter { $args -contains 'pull' } -Times 1
        }

        It "reports no version change when normalized versions match" {
            $Global:PVMConfig = @{ version = 'v1.0' }
            Mock Get-PVMVersionFromGit { return 'v1.0.0' }

            $result = Update-PVM -checkOnly $false

            $result.code | Should -Be 0
            $result.message | Should -Match 'No version change'
        }

        It "falls back to the config version when the new version can't be resolved" {
            $Global:PVMConfig = @{ version = 'v1.0.0' }
            Mock Get-PVMVersionFromGit { return $null }

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

Describe "Test-GitAvailable" {
    It "returns true when git command resolves" {
        Mock Get-Command { return @{ Name = 'git' } }

        Test-GitAvailable | Should -Be $true
    }

    It "returns false when git command is not found" {
        Mock Get-Command { throw 'command not found' }

        Test-GitAvailable | Should -Be $false
    }
}

Describe "Get-GitStatus" {
    It "returns porcelain status output" {
        Mock git { return 'M file.txt' }

        Get-GitStatus | Should -Be 'M file.txt'
    }

    It "returns null when git throws" {
        Mock git { throw 'not a repo' }

        Get-GitStatus | Should -BeNullOrEmpty
    }
}

Describe "Get-CurrentGitBranch" {
    It "returns a trimmed branch name" {
        Mock git { return "main`n" }

        Get-CurrentGitBranch | Should -Be 'main'
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        Get-CurrentGitBranch | Should -BeNullOrEmpty
    }
}

Describe "Get-CurrentGitCommit" {
    It "returns a trimmed commit hash" {
        Mock git { return "abc123`n" }

        Get-CurrentGitCommit | Should -Be 'abc123'
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        Get-CurrentGitCommit | Should -BeNullOrEmpty
    }
}

Describe "Get-LatestGitCommit" {
    It "fetches origin and returns the trimmed remote commit" {
        Mock git {
            if ($args -contains 'fetch') { return $null }
            return "def456`n"
        }

        Get-LatestGitCommit -branch 'main' | Should -Be 'def456'
    }

    It "returns null when fetch/rev-parse throws" {
        Mock git { throw 'network error' }

        Get-LatestGitCommit -branch 'main' | Should -BeNullOrEmpty
    }

    It "defaults branch to 'main' when not specified" {
        Mock git {
            if ($args -contains 'fetch') { return $null }
            return 'def456'
        }

        Get-LatestGitCommit | Should -Be 'def456'
    }
}

Describe "Get-PVMVersionFromGit" {
    It "returns the trimmed latest tag" {
        Mock git { return "v1.2.3`n" }

        Get-PVMVersionFromGit | Should -Be 'v1.2.3'
    }

    It "returns null when no tags exist" {
        Mock git { return $null }

        Get-PVMVersionFromGit | Should -BeNullOrEmpty
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        Get-PVMVersionFromGit | Should -BeNullOrEmpty
    }
}

Describe "Format-Version" {
    It "strips a leading 'v' prefix" {
        Format-Version -version 'v1.2.3' | Should -Be '1.2.3'
    }

    It "strips a single trailing .0 segment" {
        Format-Version -version 'v1.2.0' | Should -Be '1.2'
    }

    It "strips multiple trailing .0 segments" {
        Format-Version -version 'v1.0.0' | Should -Be '1'
    }

    It "leaves a version with no prefix or trailing zeros unchanged" {
        Format-Version -version '1.2.3' | Should -Be '1.2.3'
    }
}
