
function Get-All-Subdirectories {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $null
        }
        $path = $path.Trim()
        return Get-ChildItem -Path $path -Directory
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get all subdirectories of '$path'"; exception = $_ }
        return $null
    }
}

function Is-Directory-Exists {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }
        $path = $path.Trim()
        return (Test-Path -Path $path -PathType Container)
    } catch {
        return $false
    }
}

function Is-Directory-Not-Exists {
    param ($path)

    return -not (Is-Directory-Exists -path $path)
}

function Is-File-Exists {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }
        $path = $path.Trim()
        return (Test-Path -Path $path -PathType Leaf)
    } catch {
        return $false
    }
}

function Is-File-Not-Exists {
    param ($path)

    return -not (Is-File-Exists -path $path)
}

function Make-Directory {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return -1
        }

        $path = $path.Trim()
        if (Is-Directory-Not-Exists -path $path) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

        return 0
    } catch {
        return -1
    }
}

function Make-Symbolic-Link {
    param ($link, $target)

    try {
        if ([string]::IsNullOrWhiteSpace($link) -or [string]::IsNullOrWhiteSpace($target)) {
            return @{ code = -1; message = 'Link and target cannot be empty!'; color = 'DarkYellow' }
        }

        $link = $link.Trim()
        $target = $target.Trim()

        if (Is-Directory-Not-Exists -path $target) {
            return @{ code = -1; message = "Target directory '$target' does not exist!"; color = 'DarkYellow' }
        }

        # Make sure parent directory exists
        $parent = Split-Path -Path $link
        if (Is-Directory-Not-Exists -path $parent) {
            $created = Make-Directory -path $parent
            if ($created -ne 0) {
                return @{ code = -1; message = "Failed to create parent directory '$parent'"; color = 'DarkYellow' }
            }
        }
        # Remove old link if it exists
        if (Test-Path $link) {
            $item = Get-Item -LiteralPath $link -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                [System.IO.Directory]::Delete($link)
            } else {
                return @{ code = -1; message = "Link '$link' is not a symbolic link!"; color = 'DarkYellow' }
            }
        }

        if (Is-Not-Admin) {
            $command = "New-Item -ItemType SymbolicLink -Path '$link' -Target '$target'"
            $exitCode = (Run-Ps-Command -command $command)
            if ($exitCode -ne 0) {
                return @{ code = -1; message = "Failed to make symbolic link '$link' -> '$target'"; color = 'DarkYellow' }
            }
            return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = 'DarkGreen' }
        }

        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = 'DarkGreen' }
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to make symbolic link"; exception = $_ }
        return @{ code = -1; message = "Failed to make symbolic link '$link' -> '$target'"; color = 'DarkYellow' }
    }
}

function Extract-Zip-Core {
    param ($zipPath, $extractPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
}

function Extract-Zip {
    param ($zipPath, $extractPath, $deleteZipAfter = $false)

    try {
        Extract-Zip-Core -zipPath $zipPath -extractPath $extractPath

        if ($deleteZipAfter) {
            Remove-Item -Path $zipPath -Force
        }
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to extract zip file from $zipPath"; exception = $_ }
    }
}
