
. $PSScriptRoot\functions.ps1

$ProgressPreference = 'SilentlyContinue'



#region current
function Get-Current-PHP-Version {
    $currentPhpVersion = [System.Environment]::GetEnvironmentVariable($USER_ENV["PHP_CURRENT_ENV_NAME"], [System.EnvironmentVariableTarget]::Machine)
    $currentPhpVersionKey = $null
    $envVars = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
    $envVars.Keys | Where-Object { $_ -match "php\d(\.\d+)*" }  | Where-Object {
        if ($currentPhpVersion -eq $envVars[$_] -and -not($USER_ENV["PHP_CURRNET_ENV_NAME"] -eq $_)) {
            $currentPhpVersionKey = $_
        }
    }
    if (-not $currentPhpVersionKey) {
        if ($currentPhpVersion -match 'php-([\d\.]+)') {
            $currentPhpVersionKey = $matches[1]
        }
    }
    $currentPhpVersionKey = $currentPhpVersionKey -replace 'php', ''
    return $currentPhpVersionKey
}
#endregion

#region list

function Setup-PVM {

    try {
        $path = $newPath = [Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

        $phpEnvName = $USER_ENV["PHP_CURRENT_ENV_NAME"]
        $phpEnvValue = [Environment]::GetEnvironmentVariable($phpEnvName, [System.EnvironmentVariableTarget]::Machine)
        if ($phpEnvValue -eq $null -or $path -notlike "*$phpEnvValue*") {
            $newPath += ";%$phpEnvName%"
            [Environment]::SetEnvironmentVariable($phpEnvName, 'null', [System.EnvironmentVariableTarget]::Machine)
        }

        $pvmPath = $PSScriptRoot
        if ($path -notlike "*$pvmPath*") {
            $newPath += ";%pvm%"
        }
        $pvmEnvValue = [Environment]::GetEnvironmentVariable("pvm", [System.EnvironmentVariableTarget]::Machine)
        if ($pvmEnvValue -eq $null) {
            [Environment]::SetEnvironmentVariable("pvm", $pvmPath, [System.EnvironmentVariableTarget]::Machine)
        }
        
        if ($newPath -ne $path) {
            [Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::Machine)
            return 0
        }
        return 1
    }
    catch {
        return -1
    }
}

function Display-Installed-PHP-Versions {
    $currentVersion = Get-Current-PHP-Version
    $installedPhp = Get-Installed-PHP-Versions
    
    if ($installedPhp.Count -eq 0) {
        Write-Host "No PHP versions found"
        exit 0
    }

    Write-Host "`nInstalled Versions"
    Write-Host "--------------"
    $duplicates = @()
    $installedPhp | ForEach-Object {
        $versionNumber = $_ -replace "php",""
        if ($duplicates -notcontains $versionNumber) {
            $duplicates += $versionNumber
            $isCurrent = ""
            if ($currentVersion -eq $versionNumber) {
                $isCurrent = "(Current)"
            }
            Write-Host "  $versionNumber $isCurrent"
        }
    }
}

function Cache-Fetched-PHP-Versions {
    param ($listPhpVersions)

    $jsonString = $listPhpVersions | ConvertTo-Json -Depth 3
    $versionsDataPath = "$PSScriptRoot\storage\available_versions.json"
    Make-Directory -path (Split-Path $versionsDataPath)
    Set-Content -Path $versionsDataPath -Value $jsonString
}

function Get-From-Source {

    $urls = Get-Source-Urls
    $fetchedVersions = @()
    foreach ($key in $urls.Keys) {
        $html = Invoke-WebRequest -Uri $urls[$key]
        $links = $html.Links

        # Filter the links to find versions that match the given version
        $filteredLinks = $links | Where-Object { 
            $_.href -match "php-\d+\.\d+\.\d+(?:-\d+)?-Win32.*\.zip$" -and
            $_.href -notmatch "php-debug" -and
            $_.href -notmatch "php-devel" -and
            $_.href -notmatch "nts"
        }
        # Return the filtered links (PHP version names)
        $fetchedVersions = $fetchedVersions + ($filteredLinks | ForEach-Object { $_.href })
    }
    
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x64' } else { 'x86' }
    $fetchedVersions = $fetchedVersions | Where-Object { $_ -match "$arch" }
    $fetchedVersions = $fetchedVersions | Select-Object -Last 10
    
    $fetchedVersionsGrouped = @{
        'Archives' = $fetchedVersions | Where-Object { $_ -match "archives" }
        'Releases' = $fetchedVersions | Where-Object { $_ -notmatch "archives" }
    }
    
    Cache-Fetched-PHP-Versions $fetchedVersionsGrouped
    
    return $fetchedVersionsGrouped
}

function Get-From-Cache {
    $list = @{}
    $jsonData = Get-Content "$PSScriptRoot\storage\available_versions.json" | ConvertFrom-Json
    $jsonData.PSObject.Properties.GetEnumerator() | ForEach-Object {
        $key = $_.Name
        $value = $_.Value
        
        # Add the key-value pair to the hashtable
        $list[$key] = $value
    }
    return $list
}

function Get-Available-PHP-Versions {
    param ($getFromSource = $null)
    
    $fetchedVersionsGrouped = @{}

    if (-not $getFromSource) {
        Write-Host "`nReading from the cache"
        $fetchedVersionsGrouped = Get-From-Cache
    }
    
    if ($fetchedVersionsGrouped.Count -eq 0) {
        Write-Host "`nCache empty!, Reading from the internet"
        $fetchedVersionsGrouped = Get-From-Source
    }
    
    Write-Host "`nAvailable Versions"
    Write-Host "--------------"

    $fetchedVersionsGrouped.GetEnumerator() | ForEach-Object {
        $key = $_.Key
        $fetchedVersionsGroupe = $_.Value
        Write-Host "`n$key`n"
        $fetchedVersionsGroupe | ForEach-Object {
            $versionItem = $_ -replace '/downloads/releases/archives/|/downloads/releases/|php-|-Win.*|.zip', ''
            Write-Host "  $versionItem"
        }
    }
    
    $msg = "`nThis is a partial list. For a complete list, visit"
    $msg += "`nReleases : https://windows.php.net/downloads/releases"
    $msg += "`nArchives : https://windows.php.net/downloads/releases/archives"
    Write-Host $msg
}
#endregion

#region uninstall

function Uninstall-PHP {
    param ($version)
    try {
        $name = "php$version"
        $phpPath = [System.Environment]::GetEnvironmentVariable($name, [System.EnvironmentVariableTarget]::Machine)
        Remove-Item -Path $phpPath -Recurse -Force
        [System.Environment]::SetEnvironmentVariable($name, $null, [System.EnvironmentVariableTarget]::Machine);
        return 0
    }
    catch {
        return -1
    }
}

#endregion

#region install
function Install-PHP {
    param ($version, $includeXDebug = $false, $customDir = $null)

    Write-Host "`nLoading the matching versions..."
    $matchingVersions = Get-PHP-Versions -version $version

    if ($matchingVersions.Count -eq 0) {
        Write-Host "`nNo matching PHP versions found for '$version'."
        return
    }
    
    $selectedVersionObject = $null

    if ($matchingVersions.Count -gt 1) {
        # Display matching versions
        Display-Version-List -matchingVersions $matchingVersions

        # Prompt user to choose the version
        $selectedVersionInput = Read-Host "`nEnter the exact version to install (or press Enter to cancel)"

        if (-not $selectedVersionInput) {
            Write-Host "`nInstallation cancelled."
            return
        }
        
        foreach ($entry in $matchingVersions.GetEnumerator()) {
            $selectedVersionObject = $entry.Value | Where-Object { $_.version -eq $selectedVersionInput }
            if ($selectedVersionObject) {
                break
            }
        }
    }
    
    
    if (-not $selectedVersionObject) {
        $matchingVersions.GetEnumerator() | ForEach-Object {
            $selectedVersionObject = $_.Value | Select-Object -Last 1
        }
        if (-not $selectedVersionObject) {
            Write-Host "`nNo matching version found for '$version'."
            exit 1
        }
    }

    $destination = Download-PHP -version $selectedVersionObject -customDir $dirValue
    
    Write-Host "`nExtracting the downloaded zip ..."
    $fileName = $selectedVersionObject.fileName
    $fileNameDirectory = $fileName -replace ".zip",""
    Extract-And-Configure -path "$destination\$fileName" -fileNamePath "$destination\$fileNameDirectory"
    
    if ($includeXDebug) {
        $version = ($selectedVersionObject.version -split '\.')[0..1] -join '.'
        Config-XDebug -version $version -phpPath "$destination\$fileNameDirectory" -customDir $dirValue
    }
    
    
    Write-Host "`nAdding the PHP to the environment variables ..."
    $phpVersionNumber = $selectedVersionObject.version
    $phpEnvVarName = "php$phpVersionNumber"
    # Set-Php-Env -name $phpEnvVarName -value "$destination\$selectedVersion"
    $phpPath = "$destination\$fileNameDirectory"
    pvm set $phpEnvVarName $phpPath
    Write-Host "`nRun 'pvm use $phpVersionNumber' to use this version"
}
#endregion

#region use
function Update-PHP-Version {
    param ($variableName, $variableValue)

    $phpVersion = "php$variableValue"
    $variableValueContent = [System.Environment]::GetEnvironmentVariable($phpVersion, [System.EnvironmentVariableTarget]::Machine)
    if (-not $variableValueContent) {
        $envVars = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
        $variableValue = $envVars.Keys | Where-Object { $_ -match $variableValue } | Sort-Object | Select-Object -First 1
        if (-not $variableValue) {
            Write-Host "`nThe $variableName was not set !"
            return -1;
        }
        $variableValueContent = $envVars[$variableValue]
    }
    if (-not $variableValueContent) {
        Write-Host "`nThe $variableName was not found in the environment variables!"
        return -1;
    }
    [System.Environment]::SetEnvironmentVariable($variableName, $variableValueContent, [System.EnvironmentVariableTarget]::Machine)
    return 0;
}
#endregion

#region set
function Set-PHP-Env {
    param ($name, $value)

    try {
        $content = [System.Environment]::GetEnvironmentVariable($value, [System.EnvironmentVariableTarget]::Machine)
        if ($content) {
            [System.Environment]::SetEnvironmentVariable($name, $content, [System.EnvironmentVariableTarget]::Machine)
        } else {
            [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Machine)
        }
        return 0;
    }
    catch {
        return -1;
    }
}
#endregion

#region utils
function Is-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    return $isAdmin
}
#endregion