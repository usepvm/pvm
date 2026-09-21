
function Get-AllSubdirectories {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $null
        }
        $path = $path.Trim()
        return Get-ChildItemWrapper -path $path -directory
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
        return (Test-PathWrapper -path $path -pathType 'Container')
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check directory existence"; exception = $_ }
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
        return (Test-PathWrapper -path $path -pathType 'Leaf')
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check file existence"; exception = $_ }
        return $false
    }
}

function Test-FileNotExists {
    param ($path)

    return -not (Test-FileExists -path $path)
}

function Test-PathExists {
    param ($path)

    return (Test-DirectoryExists -path $path) -or (Test-FileExists -path $path)
}

function Test-PathNotExists {
    param ($path)

    return -not (Test-PathExists -path $path)
}

function Test-SymlinkExists {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return $false
        }

        $path = $path.Trim()

        $item = Get-ItemWrapper -path $path

        return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check symlink existence"; exception = $_ }
        return $false
    }
}

function Test-SymlinkNotExists {
    param ($path)

    return -not (Test-SymlinkExists -path $path)
}

function New-Directory {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return -1
        }

        $path = $path.Trim()
        if (Test-DirectoryNotExists -path $path) {
            $created = New-ItemWrapper -type 'Directory' -path $path
            if (-not $created) {
                return -1
            }
        }

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create directory '$path'"; exception = $_ }
        return -1
    }
}

function New-File {
    param ($path)

    try {
        if ([string]::IsNullOrWhiteSpace($path)) {
            return -1
        }

        $path = $path.Trim()
        if (Test-FileNotExists -path $path) {
            $created = New-ItemWrapper -type 'File' -path $path
            if (-not $created) {
                return -1
            }
        }

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create file '$path'"; exception = $_ }
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
        $parent = Split-Path -Path $link -Parent
        if (Test-DirectoryNotExists -path $parent) {
            $created = New-Directory -path $parent
            if ($created -ne 0) {
                return @{ code = -1; message = "Failed to create parent directory '$parent'"; color = 'DarkYellow' }
            }
        }
        # Remove old link if it exists
        if (Test-SymlinkExists -path $link) {
            [System.IO.Directory]::Delete($link)
        } elseif (Test-PathExists -path $link) {
            return @{ code = -1; message = "Link '$link' is not a symbolic link!"; color = 'DarkYellow' }
        }

        if (Test-NotAdmin) {
            $command = "New-Item -ItemType SymbolicLink -Path '$link' -Target '$target'"
            $exitCode = (Invoke-PSCommand -command $command)
            if ($exitCode -ne 0) {
                return @{ code = -1; message = "Failed to create symbolic link '$link' -> '$target'"; color = 'DarkYellow' }
            }
            return @{ code = 0; message = "Created symbolic link '$link' -> '$target'"; color = 'DarkGreen' }
        }

        $created = New-ItemWrapper -type 'SymbolicLink' -path $link -target $target
        if (-not $created) {
            return @{ code = -1; message = "Failed to create symbolic link '$link' -> '$target'"; color = 'DarkYellow' }
        }

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
            Remove-ItemWrapper -path $zipPath
        }
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to expand zip file from $zipPath"; exception = $_ }
    }
}

function Test-YesResponse {
    param ($response)

    return ($response -eq 'y' -or $response -eq 'Y')
}

function Test-NoResponse {
    param ($response)

    return -not (Test-YesResponse -response $response)
}

function Get-BaseUrl {
    param ($url)

    return ([System.Uri]$url).Host
}

function Get-FreeDiskSpaceBytes {
    param ($path)

    $root = [System.IO.Path]::GetPathRoot($path)
    if ([string]::IsNullOrWhiteSpace($root)) {
        return -1
    }

    return ([System.IO.DriveInfo]::new($root)).AvailableFreeSpace
}

function Test-FreeDiskSpaceSufficient {
    param ($path, $minimumMegabytes)

    try {
        $minimumFreeSpace = Convert-MegabytesToBytes -megabytes $minimumMegabytes
        $availableFreeSpace = Get-FreeDiskSpaceBytes -path $path

        return ($minimumFreeSpace -le $availableFreeSpace)
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check for free disk space for '$path'"; exception = $_ }
        return $false
    }
}

function Test-FreeDiskSpaceInsufficient {
    param ($path, $minimumMegabytes)

    return -not (Test-FreeDiskSpaceSufficient -path $path -minimumMegabytes $minimumMegabytes)
}

function Get-RemoteFileSize {
    param ($uri)

    try {
        if ([string]::IsNullOrWhiteSpace($uri)) {
            return -1
        }

        $uri = $uri.Trim()
        $response = Invoke-WebRequestWrapper -uri $uri -method 'Head'

        if ($null -eq $response -or $null -eq $response.Headers) {
            return -1
        }

        $contentLength = $response.Headers['Content-Length'][0]

        if ([string]::IsNullOrWhiteSpace($contentLength)) {
            return -1
        }

        return [long]$contentLength
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get remote file size for '$uri'"; exception = $_ }
        return -1
    }
}

function Test-RemoteFileDiskSpaceSufficient {
    param ($uri, $downloadPath)

    try {
        $remoteFileSize = Get-RemoteFileSize -uri $uri

        if ($remoteFileSize -le 0) {
            return $false
        }

        $availableFreeSpace = Get-FreeDiskSpaceBytes -path $downloadPath

        if ($availableFreeSpace -le 0) {
            return $false
        }

        return ($remoteFileSize -le $availableFreeSpace)
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to check disk space for remote file '$uri'"; exception = $_ }
        return $false
    }
}

function Test-RemoteFileDiskSpaceInsufficient {
    param ($uri, $downloadPath)

    return -not (Test-RemoteFileDiskSpaceSufficient -uri $uri -downloadPath $downloadPath)
}

function Convert-BytesToMegabytes {
    param ($bytes)

    if ($bytes -le 0) {
        return 0
    }

    return [math]::Round($bytes / 1MB, 2)
}

function Convert-MegabytesToBytes {
    param ($megabytes)

    if ($megabytes -le 0) {
        return 0
    }

    return [int64]($megabytes * 1MB)
}
