
function Get-AllSubdirectories {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $null
        }
        $path = $path.Trim()
        return Get-ChildItem -Path $path -Directory
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get all subdirectories of '$path'"; exception = $_ }
        return $null
    }
}

function Test-DirectoryExists {
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

function Test-DirectoryNotExists {
    param ($path)

    return -not (Test-DirectoryExists -path $path)
}

function Test-FileExists {
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

function Test-FileNotExists {
    param ($path)

    return -not (Test-FileExists -path $path)
}

function New-Directory {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return -1
        }

        $path = $path.Trim()
        if (Test-DirectoryNotExists -path $path) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

        return 0
    } catch {
        return -1
    }
}

function New-SymbolicLink {
    param ($link, $target)

    try {
        if ([string]::IsNullOrWhiteSpace($link) -or [string]::IsNullOrWhiteSpace($target)) {
            return @{ code = -1; message = 'Link and target cannot be empty!'; color = 'DarkYellow' }
        }

        $link = $link.Trim()
        $target = $target.Trim()

        if (Test-DirectoryNotExists -path $target) {
            return @{ code = -1; message = "Target directory '$target' does not exist!"; color = 'DarkYellow' }
        }

        # Make sure parent directory exists
        $parent = Split-Path -Path $link
        if (Test-DirectoryNotExists -path $parent) {
            $created = New-Directory -path $parent
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

        if (Test-NotAdmin) {
            $command = "New-Item -ItemType SymbolicLink -Path '$link' -Target '$target'"
            $exitCode = (Invoke-PSCommand -command $command)
            if ($exitCode -ne 0) {
                return @{ code = -1; message = "Failed to create symbolic link '$link' -> '$target'"; color = 'DarkYellow' }
            }
            return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = 'DarkGreen' }
        }

        New-Item -ItemType SymbolicLink -Path $link -Target $target | Out-Null
        return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = 'DarkGreen' }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create symbolic link"; exception = $_ }
        return @{ code = -1; message = "Failed to create symbolic link '$link' -> '$target'"; color = 'DarkYellow' }
    }
}

function Expand-ZipCore {
    param ($zipPath, $extractPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
}

function Expand-Zip {
    param ($zipPath, $extractPath, $deleteZipAfter = $false)

    try {
        Expand-ZipCore -zipPath $zipPath -extractPath $extractPath

        if ($deleteZipAfter) {
            Remove-Item -Path $zipPath -Force
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to expand zip file from $zipPath"; exception = $_ }
    }
}
