
function Get-DataFromCache {
    param ($cacheFileName)

    try {
        if ([string]::IsNullOrWhiteSpace($cacheFileName)) {
            return @{}
        }

        $path = Get-CacheFilePath -filename $cacheFileName
        if (Test-FileNotExists -path $path) {
            return @{}
        }

        $jsonString = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($jsonString)) {
            return @{}
        }

        $jsonData = $jsonString | ConvertFrom-Json
        return $jsonData
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }
        return @{}
    }
}

function Test-CanUseCache {
    param ($cacheFileName)

    try {
        if ([string]::IsNullOrWhiteSpace($cacheFileName)) {
            return $false
        }

        $path = Get-CacheFilePath -filename $cacheFileName
        $useCache = $false

        if (Test-FileExists -path $path) {
            $cacheFile = Get-Item -Path $path -ErrorAction SilentlyContinue
            if ($null -eq $cacheFile) {
                return $false
            }

            $fileAgeHours = (New-TimeSpan -Start $cacheFile.LastWriteTime -End (Get-Date)).TotalHours
            $useCache = ($fileAgeHours -lt $PVMConfig.env.CACHE_MAX_HOURS)
        }

        return $useCache
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get data from cache"; exception = $_ }

        return $false
    }
}

function Save-CachedData {
    param ($cacheFileName, $data, $depth = 3)

    try {
        if ([string]::IsNullOrWhiteSpace($cacheFileName)) {
            Show-Error -Message "Cache file name cannot be empty."
            return -1
        }

        if ($null -eq $data) {
            Show-Error -Message "Data cannot be null."
            return -1
        }

        $jsonString = $data | ConvertTo-Json -Depth $depth
        $path = Get-CacheFilePath -filename $cacheFileName
        $created = New-Directory -path (Split-Path -Path $path)
        if ($created -ne 0) {
            Show-Error -Message "Failed to create directory $(Split-Path -Path $path)"
            return -1
        }
        Set-Content -Path $path -Value $jsonString -Encoding UTF8
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to cache data"; exception = $_ }
        return -1
    }
}

function Get-CacheFilePath {
    param ($filename)

    if ($filename -notmatch '\.json$') {
        $filename = "$filename.json"
    }

    return "$($PVMConfig.paths.cache)\$filename"
}

function Get-OrUpdateCache {
    param ($cacheFileName, $compute, $depth = 3)

    $useCache = Test-CanUseCache -cacheFileName $cacheFileName

    if ($useCache) {
        $data = Get-DataFromCache -cacheFileName $cacheFileName
        if ($null -ne $data -and $data.Count -gt 0) {
            return $data
        }
    }

    $data = & $compute

    if ($null -ne $data) {
        $null = Save-CachedData -cacheFileName $cacheFileName -data $data -depth $depth
    }

    return $data
}
