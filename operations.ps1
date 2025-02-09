
. $PSScriptRoot\functions.ps1

$ProgressPreference = 'SilentlyContinue'

$Global:ENV_FILE = "$PSScriptRoot\.env"
$Global:USER_ENV = Get-Env


#region current
function Get-Current-PHP-Version {
    $currentPhpVersion = [System.Environment]::GetEnvironmentVariable($USER_ENV["PHP_CURRENT_ENV_NAME"], [System.EnvironmentVariableTarget]::Machine)
    $currentPhpVersion -match "php-(\d+\.\d+\.\d+)-" | Out-Null
    return $matches[1]
}
#endregion

#region list
function Get-Installed-PHP-Versions {
    $currentVersion = Get-Current-PHP-Version
    $installedPhp = Get-ChildItem Env: | Where-Object { $_.Name -match "^php.{0,4}$" } | Sort-Object {
        if ($_.Value -match "php-(\d+\.\d+\.\d+)") { 
            [version] $matches[1] 
        } else {
            [version] "0.0.0"  # Assign a low version to non-PHP paths so they appear first/last
        }
    }
    Write-Host "`nInstalled Versions"
    Write-Host "--------------"
    $duplicates = @()
    $installedPhp | ForEach-Object {
        if ($_.Value -match "php-\d(\.\d+)*") {
            # $version = $_.Key
            $versionNumber = $matches[0] -replace "php-",""
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
}

function Cache-Fetched-PHP-Versions {
    param ($listPhpVersions)
    
    # $jsonObject = $listPhpVersions.GetEnumerator() | ForEach-Object {
    #     $key = $_.Key
    #     $value = $_.Value
    #     [PSCustomObject]@{ $key = $value }
    # }
    $jsonString = $listPhpVersions | ConvertTo-Json -Depth 3
    Set-Content -Path "$PSScriptRoot\available_versions.json" -Value $jsonString
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
    $jsonData = Get-Content "available_versions.json" | ConvertFrom-Json
    $jsonData.PSObject.Properties.GetEnumerator() | ForEach-Object {
        $key = $_.Name
        $value = $_.Value
        
        # Add the key-value pair to the hashtable
        $list[$key] = $value
    }
    return $list
}

function Get-Available-PHP-Versions {
    param($getFromSource = $null)
    
    # fetch from the cache
    $fetchedVersionsGrouped = @{}

    if (-not $getFromSource) {
        $fetchedVersionsGrouped = Get-From-Cache
    }
    
    if ($fetchedVersionsGrouped.Count -eq 0) {
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
            # $versionItem = $versionItem -replace '^php-|-Win.*$', ''
            Write-Host "  $versionItem"
        }
    }
    
    $msg = "`nThis is a partial list. For a complete list, visit"
    $msg += "`nReleases : https://windows.php.net/downloads/releases"
    $msg += "`nArchives : https://windows.php.net/downloads/releases/archives"
    Write-Host $msg
}
#endregion

#region install
function Install-PHP {
    param(
        [string]$version
    )

    $matchingVersions = Get-PHP-Versions -version $version

    if ($matchingVersions.Count -eq 0) {
        Write-Host "`nNo matching PHP versions found for '$version'."
        return
    }

    # Display matching versions
    Display-Version-List -matchingVersions $matchingVersions
    

    # Prompt user to choose the version
    $selectedVersion = Read-Host "`nEnter the exact version to install (or press Enter to cancel)"

    if (-not $selectedVersion) {
        Write-Host "`nInstallation cancelled."
        return
    }

    $destination = Download-PHP -version $selectedVersion
    
    Write-Host "`nExtracting the downloaded zip ..."
    Extract-And-Configure -path "$destination\$selectedVersion.zip" -fileNamePath "$destination\$selectedVersion"
    
    
    Write-Host "`nAdding the PHP to the environment variables ..."
    if ($version -match "\d+(\.\d+\.\d+)*") {
        $phpVersionNumber = $version # $matches[0]
        $phpEnvVarName = "php$phpVersionNumber"
        # Set-Php-Env -name $phpEnvVarName -value "$destination\$selectedVersion"
        $phpPath = "$destination\$selectedVersion"
        pvm set $phpEnvVarName $phpPath
        Write-Host "`nRun 'pvm use $phpVersionNumber' to use this version"
    }
    
}
#endregion

#region use
function Update-PHP-Version {
    param( [string]$variableName, [string]$variableValue )

    try {
        $variableValueContent = [System.Environment]::GetEnvironmentVariable($variableValue, [System.EnvironmentVariableTarget]::Machine)
        if (-not $variableValueContent) {
            $variableValue = $variableValue -replace '\.',''
            $variableValueContent = [System.Environment]::GetEnvironmentVariable($variableValue, [System.EnvironmentVariableTarget]::Machine)
        }
        if ($variableValueContent) {
            [System.Environment]::SetEnvironmentVariable($variableName, $variableValueContent, [System.EnvironmentVariableTarget]::Machine)
        } else {
            # If not found, try searching for a more specific version
            $envVars = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
            # Find any key that starts with "$variableValue." (e.g., "7.2.6")
            $variableValue = $envVars.Keys | Where-Object { $_ -match "^$variableValue(\.?\d+)*$" } # | Sort-Object -Descending | Select-Object -First 1
                                
            if ($variableValue) {
                $variableValueContent = $envVars[$variableValue]
            }
            [System.Environment]::SetEnvironmentVariable($variableName, $variableValueContent, [System.EnvironmentVariableTarget]::Machine)
        }
    } catch {
        Write-Host "`nSomething went wrong, believe me !!"
    }
    
}
#endregion

#region set
function Set-PHP-Env {
    param(
        [string]$name,
        [string]$value
    )

    Add-Env-Variable -newVariableName $name -newVariableValue $value
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