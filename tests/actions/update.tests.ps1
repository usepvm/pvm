
BeforeAll {
    $script:PVMRootBackup = $PVMRoot
    $script:PVMConfigBackup = Copy-ObjectDeep -object $PVMConfig
    $PVMConfig.test.setFakePaths.Invoke($TEST_DRIVE)

    Mock Show-Success { }
    Mock Show-Error { }
    Mock Show-Info { }
    Mock Show-Warning { }
    Mock Write-DarkYellow { }
}

AfterAll {
    $Global:PVMRoot = $PVMRootBackup
    $Global:PVMConfig = $PVMConfigBackup
}

Describe "Test-GitAvailable" {
    It "returns true when git command resolves" {
        Mock Get-Command { return @{ Name = 'git' } }

        $code = Test-GitAvailable

        $code | Should -Be $true
    }

    It "returns false when git command is not found" {
        Mock Get-Command { throw 'command not found' }

        $code = Test-GitAvailable

        $code | Should -Be $false
    }
}

Describe "Get-GitStatus" {
    It "returns porcelain status output" {
        Mock git { return 'M file.txt' }

        $code = Get-GitStatus

        $code | Should -Be 'M file.txt'
    }

    It "returns null when git throws" {
        Mock git { throw 'not a repo' }

        $code = Get-GitStatus

        $code | Should -BeNullOrEmpty
    }
}

Describe "Get-CurrentGitBranch" {
    It "returns a trimmed branch name" {
        Mock git { return "main`n" }

        $code = Get-CurrentGitBranch

        $code | Should -Be 'main'
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        $code = Get-CurrentGitBranch

        $code | Should -BeNullOrEmpty
    }
}

Describe "Get-CurrentGitCommit" {
    It "returns a trimmed commit hash" {
        Mock git { return "abc123`n" }

        $code = Get-CurrentGitCommit

        $code | Should -Be 'abc123'
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        $code = Get-CurrentGitCommit

        $code | Should -BeNullOrEmpty
    }
}

Describe "Get-LatestGitCommit" {
    It "fetches origin and returns the trimmed remote commit" {
        Mock git {
            if ($args -contains 'fetch') { return $null }
            return "def456`n"
        }

        $code = Get-LatestGitCommit -branch 'main'

        $code | Should -Be 'def456'
    }

    It "returns null when fetch/rev-parse throws" {
        Mock git { throw 'network error' }

        $code = Get-LatestGitCommit -branch 'main'

        $code | Should -BeNullOrEmpty
    }

    It "defaults branch to 'main' when not specified" {
        Mock git {
            if ($args -contains 'fetch') { return $null }
            return 'def456'
        }

        $code = Get-LatestGitCommit

        $code | Should -Be 'def456'
    }
}

Describe "Get-GitCommitDifference" {
    It "returns local and remote commit counts" {
        Mock git { return "2`t3`n" }

        $difference = Get-GitCommitDifference -currentCommit 'local' -latestCommit 'remote'

        $difference.local | Should -Be 2
        $difference.remote | Should -Be 3
    }

    It "returns zero counts when commits are equal" {
        Mock git { return '0 0' }

        $difference = Get-GitCommitDifference -currentCommit 'same' -latestCommit 'same'

        $difference.local | Should -Be 0
        $difference.remote | Should -Be 0
    }

    It "returns null when git returns no output" {
        Mock git { return $null }

        $difference = Get-GitCommitDifference -currentCommit 'local' -latestCommit 'remote'

        $difference | Should -BeNullOrEmpty
    }

    It "returns null when git output does not contain two counts" {
        Mock git { return 'invalid' }

        $difference = Get-GitCommitDifference -currentCommit 'local' -latestCommit 'remote'

        $difference | Should -BeNullOrEmpty
    }

    It "returns null when git throws" {
        Mock git { throw 'not a repository' }
        Mock Add-LogEntry { }

        $difference = Get-GitCommitDifference -currentCommit 'local' -latestCommit 'remote'

        $difference | Should -BeNullOrEmpty
    }
}

Describe "Get-PVMVersionFromGit" {
    It "returns the trimmed latest tag" {
        Mock git { return "v1.2.3`n" }

        $code = Get-PVMVersionFromGit

        $code | Should -Be 'v1.2.3'
    }

    It "returns null when no tags exist" {
        Mock git { return $null }

        $code = Get-PVMVersionFromGit

        $code | Should -BeNullOrEmpty
    }

    It "returns null when git throws" {
        Mock git { throw 'error' }

        $code = Get-PVMVersionFromGit

        $code | Should -BeNullOrEmpty
    }
}

Describe "Format-Version" {
    It "strips a leading 'v' prefix" {
        $code = Format-Version -version 'v1.2.3'

        $code | Should -Be '1.2.3'
    }

    It "strips a single trailing .0 segment" {
        $code = Format-Version -version 'v1.2.0'

        $code | Should -Be '1.2'
    }

    It "strips multiple trailing .0 segments" {
        $code = Format-Version -version 'v1.0.0'

        $code | Should -Be '1'
    }

    It "leaves a version with no prefix or trailing zeros unchanged" {
        $code = Format-Version -version '1.2.3'

        $code | Should -Be '1.2.3'
    }
}

Describe "Update-PVM" {
    BeforeEach {
        Mock Test-DirectoryNotExists { return $false }
        Mock Test-GitAvailable { return $true }
        Mock Get-CurrentGitBranch { return 'main' }
        Mock Get-GitStatus { return $null }
        Mock Get-CurrentGitCommit { return 'abc123' }
        Mock Get-LatestGitCommit { return 'abc123' }
        Mock Get-GitCommitDifference { return @{ local = 0; remote = 0 } }
        Mock Get-PVMVersionFromGit { return 'v1.0.0' }
        Mock git { return $null }
    }

    Context "Git availability" {
        It "returns error when git is not available" {
            Mock Test-GitAvailable { return $false }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'Git is not installed' }
        }
    }

    Context "Repository validation" {
        It "returns error when .git directory doesn't exist" {
            Mock Test-DirectoryNotExists { return $true }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'not installed from a git repository' }
        }

        It "returns error when current branch cannot be determined" {
            Mock Get-CurrentGitBranch { return $null }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'Failed to determine current git branch' }
        }

        It "returns error when current branch is an empty string" {
            Mock Get-CurrentGitBranch { return '' }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'Failed to determine current git branch' }
        }
    }

    Context "Uncommitted changes" {
        It "returns error and lists each changed file" {
            Mock Get-GitStatus { return @('M  file1.txt', '?? file2.txt') }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'uncommitted changes' }
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'file1.txt' }
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'file2.txt' }
        }

        It "does not list changed files when quiet flag is set" {
            Mock Get-GitStatus { return @('M  file1.txt', '?? file2.txt') }

            $result = Update-PVM -checkOnly -quiet

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 0
        }

        It "collapses double spaces and trims a single status line" {
            Mock Get-GitStatus { return 'M  file.txt' }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match '- M file.txt' }
        }
    }

    Context "Commit resolution failures" {
        It "returns error when current commit cannot be determined" {
            Mock Get-CurrentGitCommit { return $null }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'Failed to get current git commit' }
        }

        It "returns error when fetching the latest commit fails" {
            Mock Get-LatestGitCommit { return $null }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'Failed to fetch latest updates' }
        }
    }

    Context "Commit comparison failures" {
        It "returns error when commit comparison fails" {
            Mock Get-GitCommitDifference { return $null }

            $result = Update-PVM -checkOnly

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'Failed to compare current and latest git commits' }
        }

        It "returns error when local and remote branches have diverged" {
            Mock Get-CurrentGitCommit { return 'local' }
            Mock Get-LatestGitCommit { return 'remote' }
            Mock Get-GitCommitDifference { return @{ local = 1; remote = 1 } }

            $result = Update-PVM

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'branch and remote branch have diverged' }
            Should -Invoke -CommandName git -ParameterFilter { $args -contains 'pull' } -Times 0
        }
    }

    Context "Already up to date" {
        It "returns success with the current config version" {
            $PVMConfig.version = 'v1.0.0'
            Mock Get-CurrentGitCommit { return 'same' }
            Mock Get-LatestGitCommit { return 'same' }

            $result = Update-PVM -checkOnly

            $result | Should -Be 0
            Should -Invoke Show-Success -Exactly 1 -ParameterFilter { $message -match 'already up to date' }
            Should -Invoke Show-Success -Exactly 1 -ParameterFilter { $message -match 'v1.0.0' }
        }

        It "short-circuits regardless of checkOnly value" {
            Mock Get-CurrentGitCommit { return 'same' }
            Mock Get-LatestGitCommit { return 'same' }

            $result = Update-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -Exactly 1 -ParameterFilter { $message -match 'already up to date' }
            Should -Invoke -CommandName git -Times 0
        }
    }

    Context "Commit ancestry" {
        It "does not update when local commits are ahead of the remote" {
            Mock Get-CurrentGitCommit { return 'local' }
            Mock Get-LatestGitCommit { return 'remote' }
            Mock Get-GitCommitDifference { return @{ local = 1; remote = 0 } }

            $result = Update-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -Exactly 1 -ParameterFilter { $message -match 'already up to date' }
            Should -Invoke -CommandName git -ParameterFilter { $args -contains 'pull' } -Times 0
        }

        It "updates when the remote has commits that are not local" {
            Mock Get-CurrentGitCommit { return 'local' }
            Mock Get-LatestGitCommit { return 'remote' }
            Mock Get-GitCommitDifference { return @{ local = 0; remote = 1 } }

            $result = Update-PVM -checkOnly

            $result | Should -Be 1
            Should -Invoke Write-DarkYellow -Exactly 1 -ParameterFilter { $message -match 'Update available' }
        }
    }

    Context "CheckOnly mode with an update available" {
        BeforeEach {
            Mock Get-CurrentGitCommit { return 'abc123' }
            Mock Get-LatestGitCommit { return 'def456' }
            Mock Get-GitCommitDifference { return @{ local = 0; remote = 1 } }
        }

        It "reports old -> new version when both resolve" {
            Mock Get-PVMVersionFromGit { return 'v1.0.0' }
            Mock git { return 'v1.1.0' }

            $result = Update-PVM -checkOnly

            $result | Should -Be 1
            Should -Invoke Write-DarkYellow -Exactly 1 -ParameterFilter { $message -match 'Update available: v1.0.0 -> v1.1.0' }
        }

        It "falls back to a generic message when versions can't be resolved" {
            Mock Get-PVMVersionFromGit { return $null }
            Mock git { return $null }

            $result = Update-PVM -checkOnly

            $result | Should -Be 1
            Should -Invoke Write-DarkYellow -Exactly 1 -ParameterFilter { $message -match 'Update available!' }
        }

        It "never pulls in checkOnly mode" {
            Mock Get-PVMVersionFromGit { return 'v1.0.0' }
            Mock git { return 'v1.1.0' }

            $result = Update-PVM -checkOnly

            $result | Should -Be 1
            Should -Invoke -CommandName git -ParameterFilter { $args -contains 'pull' } -Times 0
        }
    }

    Context "Performing the update" {
        BeforeEach {
            Mock Get-CurrentGitCommit { return 'abc123' }
            Mock Get-LatestGitCommit { return 'def456' }
            Mock Get-GitCommitDifference { return @{ local = 0; remote = 1 } }
        }

        It "pulls and reports the new version on success" {
            $Global:PVMConfig = @{ version = 'v1.0.0' }
            Mock Get-PVMVersionFromGit { return 'v1.1.0' }

            $result = Update-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -Exactly 1 -ParameterFilter { $message -match 'updated successfully to version v1.1.0' }
            Should -Invoke -CommandName git -ParameterFilter { $args -contains 'pull' } -Times 1
        }

        It "reports no version change when normalized versions match" {
            $Global:PVMConfig = @{ version = 'v1.0' }
            Mock Get-PVMVersionFromGit { return 'v1.0.0' }

            $result = Update-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -Exactly 1 -ParameterFilter { $message -match 'No version change' }
        }

        It "falls back to the config version when the new version can't be resolved" {
            $Global:PVMConfig = @{ version = 'v1.0.0' }
            Mock Get-PVMVersionFromGit { return $null }

            $result = Update-PVM

            $result | Should -Be 0
            Should -Invoke Show-Success -Exactly 1 -ParameterFilter { $message -match 'No version change \(still v1.0.0\)' }
        }

        It "returns an error when git pull throws" {
            Mock git {
                if ($args -contains 'pull') { throw 'network error' }
                return $null
            }

            $result = Update-PVM

            $result | Should -Be -1
            Should -Invoke Show-Error -Exactly 1 -ParameterFilter { $message -match 'Failed to pull updates' }
        }
    }
}
