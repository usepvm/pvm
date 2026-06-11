
function Get-Data-From-Cache {
    param ($cacheFileName)

    try {
        $jsonData = Get-Content "$CACHE_PATH\$cacheFileName.json" -Raw | ConvertFrom-Json
        return $jsonData
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }
        return @{}
    }
}

function Can-Use-Cache {
    param ($cacheFileName)

    try {
        $path = "$CACHE_PATH\$cacheFileName.json"
        $useCache = $false

        if (Is-File-Exists -path $path) {
            $fileAgeHours = (New-TimeSpan -Start (Get-Item $path).LastWriteTime -End (Get-Date)).TotalHours
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
        $path = "$CACHE_PATH\$cacheFileName.json"
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
