
$ProgressPreference = 'SilentlyContinue'

function Get-Source-Urls {
    return [ordered]@{
        "Archives" = "https://windows.php.net/downloads/releases/archives"
        "Releases" = "https://windows.php.net/downloads/releases"
    }
}


function Get-PHP-Versions-From-Url {
    param(
        [string]$url,
        [string]$version
    )
    
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
        $filteredLinks | ForEach-Object { $_.href }
    } catch {
        Write-Error "Failed to fetch versions from $url"
    }
}

function Get-PHP-Versions {
    param(
        [string]$version
    )
    
    $urls = Get-Source-Urls
    $fetchedVersions = @{}
    foreach ($key in $urls.Keys) {
        # Fetch versions from releases and archives
        $fetched = Get-PHP-Versions-From-Url -url $urls[$key] -version $version
        if ($fetched.Count -gt 0) {
            $sysArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' } else { 'x86' }
            $fetched = $fetched | Where-Object { $_ -match "$sysArch" }
            $fetchedVersions[$key] = $fetched | Select-Object -Last 5
        }
    }

    # Combine both versions and filter by user-provided version
    return $fetchedVersions
}

function Make-Directory {
    param ( [string]$path )

    if (Test-Path -Path $path -PathType Container) {
        return $false
    }
    mkdir $path | Out-Null
    return $true
}

function Download-PHP-From-Url {
    param (
        [string]$destination,
        [string]$url,
        [string]$version
    )

    # Download the selected PHP version
    try {
        Invoke-WebRequest -Uri $url -OutFile "$destination\$version.zip"
        return $destination
    } catch {
    }
    return $null
}

function Download-PHP {
    param (
        [string]$version
    )
    
    $urls = Get-Source-Urls
    
    $fileName = "$version.zip"

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
        $downloadedFilePath = Download-PHP-From-Url -destination $destination -url $downloadUrl -version $version

        if ($downloadedFilePath) {
            return $downloadedFilePath
        }
    }

    return $null
}


function Add-Env-Variable {
    param( [string]$newVariableName, [string]$newVariableValue )
   
    [System.Environment]::SetEnvironmentVariable($newVariableName, $newVariableValue, [System.EnvironmentVariableTarget]::Machine)
    # $existingVariableName = [System.Environment]::GetEnvironmentVariable($newVariableName, [System.EnvironmentVariableTarget]::Machine)
    # if ($existingVariableName -eq $null) {
    #     [System.Environment]::SetEnvironmentVariable($newVariableName, $newVariableValue, [System.EnvironmentVariableTarget]::Machine)
    # }
}

function Display-Version-List {
    param( $matchingVersions )
    Write-Host "`nMatching PHP versions:"

    $matchingVersions.GetEnumerator() | ForEach-Object {
        $key = $_.Key
        $versionsList = $_.Value
        Write-Host "`n$key versions:`n"
        $versionsList | ForEach-Object {
            $versionItem = $_ -replace '/downloads/releases/archives/|/downloads/releases/|.zip', ''
            Write-Host $versionItem
        }
    }
}

function Extract-And-Configure {
    param(
        [string]$path,
        [string]$fileNamePath
    )
    
    Extract-Zip -zipPath $path -extractPath $fileNamePath
    Copy-Item -Path "$fileNamePath\php.ini-development" -Destination "$fileNamePath\php.ini"

}

function Extract-Zip {
    param ( [string]$zipPath, [string]$extractPath )
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
    param($key, $value)
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
