
function Get-Data-From-Cache {
    param ($cacheFileName)

    try {
        if ([string]::IsNullOrWhiteSpace($cacheFileName)) {
            return @{}
        }

        $path = Get-Cache-FilePath -filename $cacheFileName
        $jsonString = Get-Content $path -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($jsonString)) {
            return @{}
        }

        $jsonData = $jsonString | ConvertFrom-Json
        return $jsonData
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }
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
            $cacheFile = Get-Item $path -ErrorAction SilentlyContinue
            if ($null -eq $cacheFile) {
                return $false
            }

            $fileAgeHours = (New-TimeSpan -Start $cacheFile.LastWriteTime -End (Get-Date)).TotalHours
            $useCache = ($fileAgeHours -lt $CACHE_MAX_HOURS)
        }

        return $useCache
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }

        return $false
    }
}

function Cache-Data {
    param ($cacheFileName, $data, $depth = 3)

    try {
        $jsonString = $data | ConvertTo-Json -Depth $depth
        $path = Get-Cache-FilePath -filename $cacheFileName
        $created = Make-Directory -path (Split-Path $path)
        if ($created -ne 0) {
            Write-Host "Failed to create directory $(Split-Path $path)"
            return -1
        }
        Set-Content -Path $path -Value $jsonString
        return 0
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to cache data"; exception = $_ }
        return -1
    }
}

function Get-Cache-FilePath {
    param ($filename)

    if ($filename -notmatch '\.json$') {
        $filename = "$filename.json"
    }

    return "$CACHE_PATH\$filename"
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
        $cached = Cache-Data -cacheFileName $cacheFileName -data $data -depth $depth
    }

    return $data
}
