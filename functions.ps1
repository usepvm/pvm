
$ProgressPreference = 'SilentlyContinue'

function Get-Source-Urls {
    return [ordered]@{
        "Archives" = "https://windows.php.net/downloads/releases/archives"
        "Releases" = "https://windows.php.net/downloads/releases"
    }
}


function Get-PHP-Versions-From-Url {
    param ($url, $version)
    
    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links

        # Filter the links to find versions that match the given version
        $filteredLinks = $links | Where-Object { 
            $_.href -match "php-$version(\.\d+)*-win" -and
            $_.href -notmatch "php-debug" -and
            $_.href -notmatch "php-devel" -and
            $_.href -notmatch "nts"
        }

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $filteredLinks = $filteredLinks | ForEach-Object { 
            $version = $_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
            $fileName = $_.href -split "/"
            $fileName = $fileName[$fileName.Count - 1]
            $formattedList += @{ href = $_.href; version = $version; fileName = $fileName }
        }
        
        return $formattedList
    } catch {
        Write-Error "Failed to fetch versions from $url"
    }
}

function Get-PHP-Versions {
    param ($version)
    
    $urls = Get-Source-Urls
    $fetchedVersions = @{}
    foreach ($key in $urls.Keys) {
        $fetched = Get-PHP-Versions-From-Url -url $urls[$key] -version $version
        if ($fetched.Count -gt 0) {
            $sysArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' } else { 'x86' }
            $fetched = $fetched | Where-Object { $_.href -match "$sysArch" }
            $fetchedVersions[$key] = $fetched | Select-Object -Last 5
        }
    }

    return $fetchedVersions
}

function Make-Directory {
    param ($path)

    if (Test-Path -Path $path -PathType Container) {
        return $false
    }
    mkdir $path | Out-Null
    return $true
}

function Download-PHP-From-Url {
    param ($destination, $url, $versionObject)

    # Download the selected PHP version
    $fileName = $versionObject.fileName
    try {
        Invoke-WebRequest -Uri $url -OutFile "$destination\$fileName"
        return $destination
    } catch {
    }
    return $null
}

function Download-PHP {
    param ($versionObject)
    
    $urls = Get-Source-Urls
    
    $fileName = $versionObject.fileName
    $version = $versionObject.version

    $destination = $USER_ENV["PHP_VERSIONS_PATH"]
    
    $newDstination = Read-Host "`nThe PHP will be installed in this path $destination, type the new destination if you would like to change it"

    if ($newDstination) {
        $directoryMade = Make-Directory -path $newDstination
        Set-Env -key "PHP_VERSIONS_PATH" -value $newDstination
        $destination = $newDstination
    }


    Write-Host "`nDownloading $version..."
    
    foreach ($key in $urls.Keys) {
        $_url = $urls[$key]
        $downloadUrl = "$_url/$fileName"
        $downloadedFilePath = Download-PHP-From-Url -destination $destination -url $downloadUrl -version $versionObject

        if ($downloadedFilePath) {
            return $downloadedFilePath
        }
    }

    return $null
}


function Display-Version-List {
    param ($matchingVersions)
    Write-Host "`nMatching PHP versions:"

    $matchingVersions.GetEnumerator() | ForEach-Object {
        $key = $_.Key
        $versionsList = $_.Value
        Write-Host "`n$key versions:`n"
        $versionsList | ForEach-Object {
            $versionItem = $_.version -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
            Write-Host "  $versionItem"
        }
    }
}

function Extract-And-Configure {
    param ($path, $fileNamePath)
    
    Extract-Zip -zipPath $path -extractPath $fileNamePath
    Copy-Item -Path "$fileNamePath\php.ini-development" -Destination "$fileNamePath\php.ini"

}

function Extract-Zip {
    param ($zipPath, $extractPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
}


function Get-Env {
    $envData = @{}
    Get-Content $ENV_FILE | Where-Object { $_ -match "(.+)=(.+)" } | ForEach-Object {
        $key, $value = $_ -split '=', 2
        $envData[$key.Trim()] = $value.Trim()
    }
    return $envData
}

function Set-Env {
    param ($key, $value)
    # Read the file into an array of lines
    $envLines = Get-Content $ENV_FILE

    # Modify the line with the key
    $envLines = $envLines | ForEach-Object {
        if ($_ -match "^$key=") { "$key=$value" }
        else { $_ }
    }

    # Write the modified lines back to the .env file
    $envLines | Set-Content $ENV_FILE
}
