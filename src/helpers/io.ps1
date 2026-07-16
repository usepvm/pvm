
function Get-All-Subdirectories {
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

function Test-Directory-Exists {
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

function Test-Directory-Not-Exists {
    param ($path)

    return -not (Test-Directory-Exists -path $path)
}

function Test-File-Exists {
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

function Test-File-Not-Exists {
    param ($path)

    return -not (Test-File-Exists -path $path)
}

function New-Directory {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return -1
        }

        $path = $path.Trim()
        if (Test-Directory-Not-Exists -path $path) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }

        return 0
    } catch {
        return -1
    }
}

function New-Symbolic-Link {
    param ($link, $target)

    try {
        if ([string]::IsNullOrWhiteSpace($link) -or [string]::IsNullOrWhiteSpace($target)) {
            return @{ code = -1; message = 'Link and target cannot be empty!'; color = 'DarkYellow' }
        }

        $link = $link.Trim()
        $target = $target.Trim()

        if (Test-Directory-Not-Exists -path $target) {
            return @{ code = -1; message = "Target directory '$target' does not exist!"; color = 'DarkYellow' }
        }

        # Make sure parent directory exists
        $parent = Split-Path -Path $link
        if (Test-Directory-Not-Exists -path $parent) {
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

        if (Test-Not-Admin) {
            $command = "New-Item -ItemType SymbolicLink -Path '$link' -Target '$target'"
            $exitCode = (Invoke-PS-Command -command $command)
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

function Expand-Zip-Core {
    param ($zipPath, $extractPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
}

function Expand-Zip {
    param ($zipPath, $extractPath, $deleteZipAfter = $false)

    try {
        Expand-Zip-Core -zipPath $zipPath -extractPath $extractPath

        if ($deleteZipAfter) {
            Remove-Item -Path $zipPath -Force
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to expand zip file from $zipPath"; exception = $_ }
    }
}

function Get-Web-Response {
    param ($uri, $outFile = $null, $useBasicParsing = $true)

    $uri = $uri.Trim()

    $params = @{
        Uri = $uri
        UseBasicParsing = $useBasicParsing
    }

    if ($outFile) {
        $params.OutFile = $outFile
    }

    return Invoke-WebRequest @params
}
