
$ProgressPreference = 'SilentlyContinue'


function Get-Env {
    $envData = @{}
    Get-Content $ENV_FILE | Where-Object { $_ -match "(.+)=(.+)" } | ForEach-Object {
        $key, $value = $_ -split '=', 2
        $envData[$key.Trim()] = $value.Trim()
    }
    return $envData
}


$Global:ENV_FILE = "$PSScriptRoot\.env"
$Global:USER_ENV = Get-Env

function Get-Source-Urls {
    return [ordered]@{
        "Archives" = "https://windows.php.net/downloads/releases/archives"
        "Releases" = "https://windows.php.net/downloads/releases"
    }
}

function getXdebugConfigV2 {
    param($XDebugPath)

    return @"

        [xdebug]
        zend_extension="$XDebugPath"
        xdebug.remote_enable=1
        xdebug.remote_host=127.0.0.1
        xdebug.remote_port=9000
"@
}

function getXdebugConfigV3 {
    param($XDebugPath)

    return @"

        [xdebug]
        zend_extension="$XDebugPath"
        xdebug.mode=debug
        xdebug.client_host=127.0.0.1
        xdebug.client_port=9003
"@
}

function Config-XDebug {
    param ($version, $phpPath, $customDir = $null)
    
    # Fetch xdebug links
    $baseUrl = "https://xdebug.org"
    $url = "$baseUrl/download/historical"
    $xDebugList = Get-XDebug-FROM-URL -url $url -version $version
    # Get the latest xdebug version
    if ($xDebugList.Count -eq 0) {
        Write-Host "`nNo xdebug version found for $version"
        return
    }
    $xDebugSelectedVersion = $xDebugList[0]
    # Download the xdebug dll file & place the dll file in the xdebug env path
    $destination = $USER_ENV["PHP_XDEBUG_PATH"]
    
    if ($customDir) {
        $destination = "$customDir\xdebug"
    }

    Make-Directory -path $destination

    $XDebugDir = "$destination\$version"
    Make-Directory -path $XDebugDir
    $fileUrl = "$baseUrl/$($xDebugSelectedVersion.href)"
    $XDebugPath = "$XDebugDir\$($xDebugSelectedVersion.fileName)"
    
    Write-Host "`nDownloading XDEBUG $($xDebugSelectedVersion.xDebugVersion)..."
    Invoke-WebRequest -Uri $fileUrl -OutFile $XDebugPath
    # config xdebug in the php.ini file
    $xDebugConfig = getXdebugConfigV2 -XDebugPath $XDebugPath
    if ($xDebugSelectedVersion.xDebugVersion -like "3.*") {
        $xDebugConfig = getXdebugConfigV3 -XDebugPath $XDebugPath
    }
    
    Write-Host "`nConfigure XDEBUG with PHP..."
    $xDebugConfig = $xDebugConfig -replace "\ +"
    Add-Content -Path "$phpPath\php.ini" -Value $xDebugConfig
}

function Get-XDebug-FROM-URL {
    param ($url, $version)
    
    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links
        
         # Filter the links to find versions that match the given version
         $filteredLinks = $links | Where-Object { 
            $_.href -match "php_xdebug-[\d\.]+-$version-.*\.dll" -and
            $_.href -notmatch "nts"
        }
        
        # Return the filtered links (PHP version names)
        $formattedList = @()
        $filteredLinks = $filteredLinks | ForEach-Object { 
            # $version = $_.href -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
            $fileName = $_.href -split "/"
            $fileName = $fileName[$fileName.Count - 1]
            $xDebugVersion = "2.0"
            if ($_.href -match "php_xdebug-([\d\.]+)") {
                $xDebugVersion = $matches[1]
            }
            $formattedList += @{ href = $_.href; version = $version; xDebugVersion = $xDebugVersion; fileName = $fileName }
        }
        
        return $formattedList
    }
    catch {
        Write-Error "Failed to fetch versions from $url"
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
    param ( [string]$path )

    if (-not (Test-Path -Path $path -PathType Container)) {
        mkdir $path | Out-Null
    }
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
    param ($versionObject, $customDir = $null)
    
    $urls = Get-Source-Urls
    
    $fileName = $versionObject.fileName
    $version = $versionObject.version

    $destination = $USER_ENV["PHP_VERSIONS_PATH"]
    if ($customDir) {
        $destination = $customDir
    }
    Make-Directory -path $destination

    Write-Host "`nDownloading PHP $version..."
    
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

function Get-Installed-PHP-Versions {
    $envVars = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
    return $envVars.Keys | Where-Object { $_ -match "php\d(\.\d+)*" } | Sort-Object { [version]($_ -replace 'php', '') }
}

function Extract-And-Configure {
    param ($path, $fileNamePath)
    
    Remove-Item -Path $fileNamePath -Recurse -Force
    Extract-Zip -zipPath $path -extractPath $fileNamePath
    Copy-Item -Path "$fileNamePath\php.ini-development" -Destination "$fileNamePath\php.ini"
    Remove-Item -Path $path
}

function Extract-Zip {
    param ($zipPath, $extractPath)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractPath)
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


function Display-Msg-By-ExitCode {
    param($msgSuccess, $msgError, $exitCode)
    if ($exitCode -eq $true) {
        Write-Host "`n$msgSuccess"
    } else {
        Write-Host "`n$msgError"
    }
    Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1 -Global
    Update-SessionEnvironment

    exit $exitCode
}