
function Get-Data-From-Cache {
    param ($cacheFileName)

    try {
        if ([string]::IsNullOrWhiteSpace($cacheFileName)) {
            return @{}
        }

        $path = Get-Cache-FilePath -filename $cacheFileName
        if (Is-File-Not-Exists -path $path) {
            return @{}
        }

        $jsonString = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($jsonString)) {
            return @{}
        }

        $jsonData = $jsonString | ConvertFrom-Json
        return $jsonData
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }
        return @{}
    }
}

function Can-Use-Cache {
    param ($cacheFileName)

    try {
        if ([string]::IsNullOrWhiteSpace($cacheFileName)) {
            return $false
        }

        $path = Get-Cache-FilePath -filename $cacheFileName
        $useCache = $false

        if (Is-File-Exists -path $path) {
            $cacheFile = Get-Item -Path $path -ErrorAction SilentlyContinue
            if ($null -eq $cacheFile) {
                return $false
            }

            $fileAgeHours = (New-TimeSpan -Start $cacheFile.LastWriteTime -End (Get-Date)).TotalHours
            $useCache = ($fileAgeHours -lt $PVMConfig.env.CACHE_MAX_HOURS)
        }

        return $useCache
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }

        return $false
    }
}

function Cache-Data {
    param ($cacheFileName, $data, $depth = 3)

    try {
        if ([string]::IsNullOrWhiteSpace($cacheFileName)) {
            Write-Host -Object "Cache file name cannot be empty." -ForegroundColor DarkYellow
            return -1
        }

        if ($null -eq $data) {
            Write-Host -Object "Data cannot be null." -ForegroundColor DarkYellow
            return -1
        }

        $jsonString = $data | ConvertTo-Json -Depth $depth
        $path = Get-Cache-FilePath -filename $cacheFileName
        $created = Make-Directory -path (Split-Path -Path $path)
        if ($created -ne 0) {
            Write-Host -Object "Failed to create directory $(Split-Path -Path $path)" -ForegroundColor DarkYellow
            return -1
        }
        Set-Content -Path $path -Value $jsonString -Encoding UTF8
        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to cache data"; exception = $_ }
        return -1
    }
}

function Get-Cache-FilePath {
    param ($filename)

    if ($filename -notmatch '\.json$') {
        $filename = "$filename.json"
    }

    return "$($PVMConfig.paths.cache)\$filename"
}

function Get-OrUpdateCache {
    param ($cacheFileName, $compute, $depth = 3)

    $useCache = Can-Use-Cache -cacheFileName $cacheFileName

    if ($useCache) {
        $data = Get-Data-From-Cache -cacheFileName $cacheFileName
        if ($null -ne $data -and $data.Count -gt 0) {
            return $data
        }
    }

    $data = & $compute

    if ($null -ne $data) {
        $null = Cache-Data -cacheFileName $cacheFileName -data $data -depth $depth
    }

    return $data
}
