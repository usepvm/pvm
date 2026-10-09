
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
    param ($link, $target, [switch]$disallowOutsideRoot)

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

        $created = New-ItemWrapper -type 'SymbolicLink' -path $link -target $target -disallowOutsideRoot:$disallowOutsideRoot
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
            $null = Remove-ItemWrapper -path $zipPath
        }

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to expand zip file from $zipPath"; exception = $_ }
        return -1
    }
}

function Get-FreeDiskSpaceBytes {
    param ($path)

    if ([string]::IsNullOrWhiteSpace($path)) {
        return -1
    }

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

function Test-DownloadPrerequisites {
    param ($url, $minimumFreeSpaceMB)

    # Keep minimum space check as fallback for extraction space
    if (Test-FreeDiskSpaceInsufficient -path $Global:PVMConfig.paths.directories.php -minimumMegabytes $minimumFreeSpaceMB) {
        return @{ temporaryDirectory = $null; message = "Insufficient disk space for installation. At least $minimumFreeSpaceMB MB is required."; color = 'DarkYellow' }
    }

    # Get remote file size and check disk space
    $remoteFileSize = Get-RemoteFileSize -uri $url
    if ($remoteFileSize -le 0) {
        return @{ temporaryDirectory = $null; message = "Failed to get remote file size or invalid size. Cannot proceed with download."; color = 'DarkYellow' }
    }

    $sizeMB = Convert-BytesToMegabytes -bytes $remoteFileSize
    if ((Get-FreeDiskSpaceBytes -path $Global:PVMConfig.paths.directories.temp) -lt $remoteFileSize) {
        return @{ temporaryDirectory = $null; message = "Insufficient disk space for download. Required: $sizeMB MB"; color = 'DarkYellow' }
    }

    $temporaryDirectory = Get-TemporaryDirectory -root $Global:PVMConfig.paths.directories.temp
    $created = New-Directory -path $temporaryDirectory
    if ($created -ne 0) {
        return @{ temporaryDirectory = $null; message = "Failed to create temporary directory '$temporaryDirectory'."; color = 'DarkYellow' }
    }

    return @{ temporaryDirectory = $temporaryDirectory; sizeMB = $sizeMB }
}

function Get-RemoteFile {
    param ($url, $destinationPath)

    return Show-SpinnerWhileJob -argumentList @($url, $destinationPath) -scriptBlock {
        param ($url, $destinationPath)

        try {
            $null = Invoke-WebRequestWrapper -uri $url -outFile $destinationPath
            return @{ pvmData = $destinationPath }
        } catch {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to download PHP from $url"; exception = $_ }
            return @{ pvmData = $null }
        }
    } -rethrow $true
}

function Get-RemoteFileSize {
    param ($uri)

    try {
        if ([string]::IsNullOrWhiteSpace($uri)) {
            return -1
        }

        $uri = $uri.Trim()
        $response = Show-SpinnerWhileJob -argumentList @($uri) -scriptBlock {
            param ($uri)

            $response = Invoke-WebRequestWrapper -uri $uri -method 'Head'

            return @{ pvmData = $response }
        } -rethrow $true

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

function Test-ValidDrivePath {
    param ($path)

    if ([string]::IsNullOrWhiteSpace($path)) {
        return $false
    }

    $path = $path.Trim()

    if ($path -notmatch '^[A-Za-z]:\\' -or $path.IndexOfAny([System.IO.Path]::GetInvalidPathChars()) -ne -1) {
        return $false
    }

    $driveInfo = [System.IO.DriveInfo]::new($path.Substring(0, 2))
    return $driveInfo.IsReady
}

function Test-InvalidDrivePath {
    param ($path)

    return -not (Test-ValidDrivePath -path $path)
}

function Test-PathUnderRoot {
    param ($path, $rootPath)

    if ([string]::IsNullOrWhiteSpace($path) -or [string]::IsNullOrWhiteSpace($rootPath)) {
        return $false
    }

    $path = [System.IO.Path]::GetFullPath($path.Trim()).TrimEnd('\')
    $rootPath = [System.IO.Path]::GetFullPath($rootPath.Trim()).TrimEnd('\')

    return $path.StartsWith("$rootPath\", [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathNotUnderRoot {
    param ($path, $rootPath)

    return -not (Test-PathUnderRoot -path $path -rootPath $rootPath)
}

function Test-PathValidAndUnderRoot {
    param ($path, $rootPath)

    try {
        return ((Test-ValidDrivePath -path $path) -and (Test-PathUnderRoot -path $path -rootPath $rootPath))
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to validate path '$path' under root '$rootPath'"; exception = $_ }
        return $false
    }
}

function Test-PathInvalidOrNotUnderRoot {
    param ($path, $rootPath)

    return -not (Test-PathValidAndUnderRoot -path $path -rootPath $rootPath)
}

function Test-PathValidUnderProjectRoot {
    param ($path)

    if ($null -eq $Global:PVMConfig -or $null -eq $Global:PVMConfig.rootPath) {
        return $false
    }

    return Test-PathValidAndUnderRoot -path $path -rootPath $Global:PVMConfig.rootPath
}

function Test-PathInvalidOrNotUnderProjectRoot {
    param ($path)

    return -not (Test-PathValidUnderProjectRoot -path $path)
}

function Get-TemporaryDirectory {
    param ($root)

    if (Test-InvalidDrivePath -path $root) {
        return $null
    }

    return "$root\temp_$([guid]::NewGuid().ToString('N'))"
}

function Get-SHA256HashFromFile {
    param ($filePath)

    $stream = $null
    $sha256 = $null
    try {
        if (Test-FileNotExists -path $filePath) {
            return $null
        }

        $stream = [System.IO.File]::OpenRead($filePath)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha256.ComputeHash($stream)

        return [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to compute SHA256 hash for '$filePath'"; exception = $_ }
        return $null
    } finally {
        if ($stream) { $stream.Close() }
        if ($sha256) { $sha256.Dispose() }
    }
}

function Get-SHA256HashesFromRemote {
    param ($url)

    try {
        if ([string]::IsNullOrWhiteSpace($url)) {
            return @{}
        }

        $url = $url.Trim()
        $response = Show-SpinnerWhileJob -argumentList @($url) -scriptBlock {
            param ($url)

            $response = Invoke-WebRequestWrapper -uri $url

            return @{ pvmData = $response }
        } -rethrow $true

        if ($null -eq $response -or $null -eq $response.Content) {
            return @{}
        }

        $hashes = @{}
        $lines = $response.Content -split "`n"

        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            if ($line -match '^([a-fA-F0-9]{64})\s+\*(.+)$') {
                $hash = $matches[1].ToLower()
                $fileName = $matches[2]
                $hashes[$fileName] = $hash
            }
        }

        return $hashes
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get SHA256 hashes from '$url'"; exception = $_ }
        return @{}
    }
}

function Test-SHA256HashValid {
    param ($filePath, $expectedHash)

    try {
        if (Test-FileNotExists -path $filePath) {
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($expectedHash)) {
            return $false
        }

        $actualHash = Get-SHA256HashFromFile -filePath $filePath

        return (($null -ne $actualHash) -and ($actualHash -eq $expectedHash.ToLower()))
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to verify SHA256 hash for '$filePath'"; exception = $_ }
        return $false
    }
}
