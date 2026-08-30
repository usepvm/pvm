
function Test-GitAvailable {
    try {
        $null = Get-Command -Name git -ErrorAction Stop
        return $true
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Git is not available"; exception = $_ }
        return $false
    }
}

function Get-GitStatus {
    try {
        $status = git -C $PVMRoot status --porcelain
        return $status
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve git status"; exception = $_ }
        return $null
    }
}

function Get-CurrentGitBranch {
    try {
        $branch = git -C $PVMRoot rev-parse --abbrev-ref HEAD
        return $branch.Trim()
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve current git branch"; exception = $_ }
        return $null
    }
}

function Get-CurrentGitCommit {
    try {
        $commit = git -C $PVMRoot rev-parse HEAD
        return $commit.Trim()
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve current git commit"; exception = $_ }
        return $null
    }
}

function Get-LatestGitCommit {
    param ($branch = 'main')

    try {
        git -C $PVMRoot fetch origin $branch >$null 2>$null
        $commit = git -C $PVMRoot rev-parse origin/$branch 2>$null
        return $commit.Trim()
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve latest git commit"; exception = $_ }
        return $null
    }
}

function Get-PVMVersionFromGit {
    try {
        $version = git -C $PVMRoot describe --tags --abbrev=0 2>$null
        if ($version) {
            return $version.Trim()
        }
        return $null
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to retrieve PVM version from git"; exception = $_ }
        return $null
    }
}

function Format-Version {
    param ($version)

    return ($version -replace '^v', '') -replace '(\.0)+$', ''
}

function Update-PVM {
    param ($checkOnly = $false, $quiet = $false)

    if (-not (Test-GitAvailable)) {
        Show-Error -message 'Git is not installed or not available in PATH. Please install Git to use the update feature.'
        return -1
    }

    if (Test-DirectoryNotExists -path "$PVMRoot\.git") {
        Show-Error -message 'PVM is not installed from a git repository. Cannot update.'
        return -1
    }

    $currentBranch = Get-CurrentGitBranch
    if (-not $currentBranch) {
        Show-Error -message 'Failed to determine current git branch.'
        return -1
    }

    $gitStatus = Get-GitStatus
    if ($gitStatus) {
        $gitStatusText = $gitStatus | ForEach-Object -Process {
            $_.Trim().Replace('  ', ' ')
        }

        $gitStatusText = '- ' + ($gitStatusText -join "`n- ")

        if (-not $quiet) {
            Show-Error -message "You have uncommitted changes. Please commit or stash your changes before updating.`n`nGit status:`n$gitStatusText"
        }

        return -1
    }

    $currentCommit = Get-CurrentGitCommit
    if (-not $currentCommit) {
        Show-Error -message 'Failed to get current git commit.'
        return -1
    }

    if (-not $quiet) {
        Show-Info -message "`nChecking for updates..."
    }

    $latestCommit = Get-LatestGitCommit -branch $currentBranch
    if (-not $latestCommit) {
        Show-Error -message 'Failed to fetch latest updates from remote repository.'
        return -1
    }

    if ($currentCommit -eq $latestCommit) {
        $currentVersion = $PVMConfig.version
        Show-Success -message "PVM is already up to date (version $currentVersion)."
        return 0
    }

    $currentVersion = Get-PVMVersionFromGit
    $latestVersion = git -C $PVMRoot describe --tags --abbrev=0 origin/$currentBranch 2>$null

    if ($checkOnly) {
        $msg = "`nUpdate available!"
        if ($currentVersion -and $latestVersion) {
            $msg = "`nUpdate available"

            $currentVersionNormalized = Format-Version -version $currentVersion
            $latestVersionNormalized = Format-Version -version $latestVersion

            if ($currentVersionNormalized -lt $latestVersionNormalized) {
                $msg += ": $currentVersion -> $latestVersion"
            }
        }
        Write-DarkYellow -message $msg
        return 0
    }

    Show-Warning -message "`nUpdate available. Pulling changes..."

    try {
        $oldVersion = $PVMConfig.version
        git -C $PVMRoot pull origin $currentBranch >$null 2>$null

        $newVersion = Get-PVMVersionFromGit
        if (-not $newVersion) {
            $newVersion = $PVMConfig.version
        }

        # Normalize versions for comparison (remove 'v' prefix)
        $oldVersionNormalized = Format-Version -version $oldVersion
        $newVersionNormalized = Format-Version -version $newVersion

        if ($oldVersionNormalized -eq $newVersionNormalized) {
            Show-Success -message "PVM has been updated successfully. No version change (still $newVersion)."
            return 0
        }

        Show-Success -message "PVM has been updated successfully to version $newVersion."
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to pull updates"; exception = $_ }
        Show-Error -message "Failed to pull updates: $_"
        return -1
    }
}
