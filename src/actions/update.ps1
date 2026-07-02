
function Test-Git-Available {
    try {
        $null = Get-Command git -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Get-Git-Status {
    try {
        $status = git -C $PVMRoot status --porcelain
        return $status
    } catch {
        return $null
    }
}

function Get-Current-Git-Branch {
    try {
        $branch = git -C $PVMRoot rev-parse --abbrev-ref HEAD
        return $branch.Trim()
    } catch {
        return $null
    }
}

function Get-Current-Git-Commit {
    try {
        $commit = git -C $PVMRoot rev-parse HEAD
        return $commit.Trim()
    } catch {
        return $null
    }
}

function Get-Latest-Git-Commit {
    param ($branch = 'main')

    try {
        git -C $PVMRoot fetch origin $branch 2>$null
        $commit = git -C $PVMRoot rev-parse origin/$branch
        return $commit.Trim()
    } catch {
        return $null
    }
}

function Get-PVM-Version-From-Git {
    try {
        $version = git -C $PVMRoot describe --tags --abbrev=0 2>$null
        if ($version) {
            return $version.Trim()
        }
        return $null
    } catch {
        return $null
    }
}

function Normalize-Version {
    param($version)

    return ($version -replace '^v', '') -replace '(\.0)+$', ''
}

function Update-PVM {
    param ($checkOnly = $false, $quiet = $false)

    if (-not (Test-Git-Available)) {
        return @{
            code    = -1
            message = 'Git is not installed or not available in PATH. Please install Git to use the update feature.'
            color   = 'DarkYellow'
        }
    }

    if (Is-Directory-Not-Exists -path "$PVMRoot\.git") {
        return @{
            code    = -1
            message = 'PVM is not installed from a git repository. Cannot update.'
            color   = 'DarkYellow'
        }
    }

    $currentBranch = Get-Current-Git-Branch
    if (-not $currentBranch) {
        return @{
            code    = -1
            message = 'Failed to determine current git branch.'
            color   = 'DarkYellow'
        }
    }

    $gitStatus = Get-Git-Status
    if ($gitStatus) {
        $gitStatusText = $gitStatus | ForEach-Object {
            $_.Trim().Replace('  ', ' ')
        }

        $gitStatusText = '- ' + ($gitStatusText -join "`n- ")

        return @{
            code    = -1
            message = "You have uncommitted changes. Please commit or stash your changes before updating.`n`nGit status:`n$gitStatusText"
            color   = 'DarkYellow'
        }
    }

    $currentCommit = Get-Current-Git-Commit
    if (-not $currentCommit) {
        return @{
            code    = -1
            message = 'Failed to get current git commit.'
            color   = 'DarkYellow'
        }
    }

    if (-not $quiet) {
        Write-Host -Object "`nChecking for updates..." -ForegroundColor Cyan
    }

    $latestCommit = Get-Latest-Git-Commit -branch $currentBranch
    if (-not $latestCommit) {
        return @{
            code    = -1
            message = 'Failed to fetch latest updates from remote repository.'
            color   = 'DarkYellow'
        }
    }

    if ($currentCommit -eq $latestCommit) {
        $currentVersion = $PVMConfig.version
        return @{
            code    = 0
            message = "PVM is already up to date (version $currentVersion)."
            color   = 'DarkGreen'
        }
    }

    $currentVersion = Get-PVM-Version-From-Git
    $latestVersion = git -C $PVMRoot describe --tags --abbrev=0 origin/$currentBranch 2>$null

    if ($checkOnly) {
        $msg = "Update available!"
        if ($currentVersion -and $latestVersion) {
            $msg = "Update available"

            $currentVersionNormalized = Normalize-Version -version $currentVersion
            $latestVersionNormalized = Normalize-Version -version $latestVersion

            if ($currentVersionNormalized -lt $latestVersionNormalized) {
                $msg += ": $currentVersion -> $latestVersion"
            }
        }
        return @{
            code    = 0
            message = $msg
            color   = 'DarkYellow'
        }
    }

    Write-Host -Object "Update available. Pulling changes..." -ForegroundColor Yellow

    try {
        $oldVersion = $PVMConfig.version
        git -C $PVMRoot pull origin $currentBranch 2>$null

        $newVersion = Get-PVM-Version-From-Git
        if (-not $newVersion) {
            $newVersion = $PVMConfig.version
        }

        # Normalize versions for comparison (remove 'v' prefix)
        $oldVersionNormalized = Normalize-Version -version $oldVersion
        $newVersionNormalized = Normalize-Version -version $newVersion

        if ($oldVersionNormalized -eq $newVersionNormalized) {
            return @{
                code    = 0
                message = "PVM has been updated successfully. No version change (still $newVersion)."
                color   = 'DarkGreen'
            }
        }

        return @{
            code    = 0
            message = "PVM has been updated successfully to version $newVersion."
            color   = 'DarkGreen'
        }
    } catch {
        return @{
            code    = -1
            message = "Failed to pull updates: $_"
            color   = 'DarkYellow'
        }
    }
}
