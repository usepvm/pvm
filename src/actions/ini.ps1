
function Add-Missing-PHPExtension {
    param ($iniPath, $extName, $enable = $true)
    
    try {
        $phpCurrentVersion = Get-Current-PHP-Version
        if (-not $phpCurrentVersion -or -not $phpCurrentVersion.version) {
            Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }
        
        Backup-IniFile $iniPath
        
        $extName = $extName -replace '^php_', '' -replace '\.dll$', ''
        $extName = "php_$extName.dll"
        
        $lines = Get-Content $iniPath
        $commented = if ($enable) { '' } else { ';' }
        $isZendExtension = Get-Zend-Extensions-List | Where-Object { $extName -like "*$_*" }
        if ($isZendExtension) {
            $lines += "`n$commented" + "zend_extension=$extName"
        } else {
            $lines += "`n$commented" + "extension=$extName"
        }
        Set-Content $iniPath $lines -Encoding UTF8
        Write-Host "- '$extName' added successfully." -ForegroundColor DarkGreen
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to add extension '$extName'"
            exception = $_
        }
        return -1
    }
    
}

function Get-Single-PHPExtensionStatus {
    param ($iniPath, $extName)
    
    $enabledPattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"
    $disabledPattern = "^\s*;\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"
    $lines = Get-Content $iniPath

    foreach ($line in $lines) {
        if ($line -match $enabledPattern) {
            return @{ status = "Enabled"; color = "DarkGreen" }
        }
        if ($line -match $disabledPattern) {
            return @{ status = "Disabled"; color = "DarkYellow"}
        }
    }
    
    return $null
}

function Restore-IniBackup {
    param ($iniPath)

    try {
        $backupPath = "$iniPath.bak"

        if (-not (Test-Path $backupPath)) {
            Write-Host "`nBackup file not found: $backupPath"
            return -1
        }

        Copy-Item -Path $backupPath -Destination $iniPath -Force
        Write-Host "`nRestored php.ini from backup: $backupPath"
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Restore-IniBackup: Failed to restore ini backup"
            exception = $_
        }
        Write-Host "`nFailed to restore backup: $($_.Exception.Message)"
        return -1
    }
}


function Backup-IniFile {
    param ($iniPath)

    try {
        $backup = "$iniPath.bak"
        if (-not (Test-Path $backup)) {
            Copy-Item $iniPath $backup
        }
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to backup ini file"
            exception = $_
        }
        return -1
    }
}

function Get-IniSetting {
    param ($iniPath, $key)
    
    try {
        if (-not $key) {
            Write-Host "`nKey is required. Usage: pvm ini get <key>"
            return -1
        }
        
        $pattern = "^[#;]?\s*{0}\s*=\s*(.+)" -f [regex]::Escape($key)
        $lines = Get-Content $iniPath

        foreach ($line in $lines) {
            if ($line -match $pattern) {
                $value = $matches[1].Trim()
                Write-Host "- $key = $value"
                return 0
            }
        }

        Write-Host "- The setting key '$key' is not found." -ForegroundColor DarkGray
        return -1
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get ini setting '$key'"
            exception = $_
        }
        return -1
    }
}


function Set-IniSetting {
    param ($iniPath, $keyValue)
    
    try {
        if (-not ($keyValue -match '^(?<key>[^=]+)=(?<value>.+)$')) {
            Write-Host "`nInvalid format. Use key=value (e.g., memory_limit=512M)"
            return -1
        }

        $key = $matches['key'].Trim()
        $value = $matches['value'].Trim()
        $pattern = "^[#;]?\s*{0}\s*=" -f [regex]::Escape($key)
        $line = "$key = $value"
        $lines = Get-Content $iniPath

        $matched = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match $pattern) {
                $matched = $true
                return $line
            } else {
                return $_
            }
        }

        if (-not $matched) {
            Write-Host "- The setting key '$key' is not found" -ForegroundColor DarkGray
            return -1
        }
        
        Backup-IniFile $iniPath
        Set-Content $iniPath $newLines -Encoding UTF8
        Write-Host "- $key set to '$value' successfully" -ForegroundColor DarkGreen

        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to set ini setting '$key'"
            exception = $_
        }
        return -1
    }
}

function Enable-IniExtension {
    param ($iniPath, $extName)
    
    try {
        
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to enable"
            return -1
        }
        
        $status = Get-Single-PHPExtensionStatus -iniPath $iniPath -extName $extName
        
        if (-not $status) {
            Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray
            $response = Read-Host "`nWould you like to add '$extName' to the extensions list? (y/n)"
            $response = $response.Trim()
            if ($response -eq "y" -or $response -eq "Y") {
                $extensionAdded = Add-Missing-PHPExtension -iniPath $iniPath -extName $extName -enable $false
            }
        } elseif ($status -and $status.status -eq "Enabled") {
            Write-Host "- '$extName' already enabled. check with 'pvm ini status $extName'" -ForegroundColor DarkGray
            return -1
        }
        
        $lines = Get-Content $iniPath
        $pattern = "^\s*[#;]+\s*(zend_)?extension\s*=\s*([`"']?)(?![^\s`"';]*[/\\])[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"

        $modified = $false
        $newLines = $lines | ForEach-Object {
            if ($_ -match $pattern -and -not $modified) {
                $modified = $true
                return $_ -replace "^[#;]\s*", ""
            }
            return $_
        }

        if (-not $modified) {
            Write-Host "- '$extName' is already enabled or not found. check with 'pvm ini status $extName'" -ForegroundColor DarkGray
            return -1
        }

        Backup-IniFile $iniPath
        Set-Content $iniPath $newLines -Encoding UTF8
        Write-Host "- '$extName' enabled successfully." -ForegroundColor DarkGreen

        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to enable extension '$extName'"
            exception = $_
        }
        return -1
    }
}

function Disable-IniExtension {
    param ($iniPath, $extName)

    try {
        
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to disable"
            return -1
        }
        
        $status = Get-Single-PHPExtensionStatus -iniPath $iniPath -extName $extName
        if (-not $status) {
            Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray
            $response = Read-Host "`nWould you like to add '$extName' to the extensions list? (y/n)"
            $response = $response.Trim()
            if ($response -eq "y" -or $response -eq "Y") {
                $extensionAdded = Add-Missing-PHPExtension -iniPath $iniPath -extName $extName -enable $true
            }
        } elseif ($status -and $status.status -eq "Disabled") {
            Write-Host "- '$extName' is already disabled. check with 'pvm ini status $extName'" -ForegroundColor DarkGray
            return -1
        }
        
        $lines = Get-Content $iniPath
        $pattern = "^\s*(zend_)?extension\s*=\s*([`"']?)(?![^\s`"';]*[/\\])[^\s`"';]*$extName[^\s`"';]*([`"']?)\s*(;.*)?$"

        $updatedLines = @()

        $modified = $false
        $updatedLines = $lines | ForEach-Object {
            if (($_ -match $pattern) -and ($_ -notmatch '^\s*;')) {
                $modified = $true
                return ";$_"
            }
            return $_
        }

        if (-not $modified) {
            Write-Host "- '$extName' is already disabled or not found. check with 'pvm ini status $extName'" -ForegroundColor DarkGray
            return -1
        }
        
        Backup-IniFile $iniPath
        Set-Content $iniPath $updatedLines -Encoding UTF8
        Write-Host "- '$extName' disabled successfully." -ForegroundColor DarkGreen
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to disable extension '$extName'"
            exception = $_
        }
        return -1
    }
}

function Get-IniExtensionStatus {
    param ($iniPath, $extName)

    try {
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to check status"
            return -1
        }

        $status = Get-Single-PHPExtensionStatus -iniPath $iniPath -extName $extName
        if ($status) {
            Write-Host "- $extName`: $($status.status)" -ForegroundColor $status.color
            return 0
        }

        Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray

        $response = Read-Host "`nWould you like to add '$extName' to the extensions list? (y/n)"
        $response = $response.Trim()
        if ($response -eq "y" -or $response -eq "Y") {
            return (Add-Missing-PHPExtension -iniPath $iniPath -extName $extName)
        }

        return -1
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to check status for '$extName'"
            exception = $_
        }
        return -1
    }
}


function Get-PHP-Info {
    
    $currentPHPVersion = Get-Current-PHP-Version
    
    if (-not $currentPHPVersion -or -not $currentPHPVersion.version -or -not $currentPHPVersion.path) {
        Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
        return -1
    }
    
    Write-Host "`n- Running PHP version`t: $($currentPHPVersion.version)"
    Write-Host "`n- PHP path`t`t: $($currentPHPVersion.path)"
    $extensions = Get-PHPExtensionsStatus -PhpIniPath "$($currentPHPVersion.path)\php.ini"
    Display-Extensions-States -extensions $extensions
    Display-Installed-Extensions -extensions $extensions
    
    return 0
}

function Display-Extensions-States {
    param ($extensions)
    
    # Pre-count for summary
    $enabledCount = @($extensions | Where-Object Enabled).Count
    $disabledCount = $extensions.Count - $enabledCount
    
    Write-Host "`n- Extensions`t`t: Enabled: $enabledCount  |  Disabled: $disabledCount  |  Total: $($extensions.Count)`n"
}

function Display-Installed-Extensions {
    param ($extensions)
    
    # Calculate max length dynamically
    $maxNameLength = ($extensions.Extension | Measure-Object -Maximum Length).Maximum
    $maxLineLength = $maxNameLength + 10  # padding
    
    $extensions |
    Sort-Object @{Expression = { -not $_.Enabled }; Ascending = $true }, `
                @{Expression = { $_.Extension }; Ascending = $true } |
    ForEach-Object {
        $dotsCount = $maxLineLength - $_.Extension.Length
        if ($dotsCount -lt 0) { $dotsCount = 0 }
        $dots = '.' * $dotsCount

        if ($_.Enabled) {
            $status = "Enabled "
            $color = "DarkGreen"
        } else {
            $status = "Disabled"
            $color = "DarkGray"
        }

        Write-Host "  $($_.Extension) $dots " -NoNewline
        Write-Host $status -ForegroundColor $color
    }
}

function Get-PHPExtensionsStatus {
    param($PhpIniPath)

    $iniContent = Get-Content $PhpIniPath
    
    $extensions = foreach ($line in $iniContent) {
        # Match both enabled and commented lines
        if ($line -match '^\s*(;)?(zend_extension|extension)\s*=\s*"?([^";]+?)"?\s*(?:;.*)?$') {
            $rawPath = $matches[3]
            $extensionName = [System.IO.Path]::GetFileName($rawPath)
            [PSCustomObject]@{
                Extension = $extensionName
                Type      = $matches[2] # extension or zend_extension
                Enabled   = -not $matches[1]
            }
        }
    }

    return $extensions
}

function Install-XDebug-Extension {
    param ($iniPath)
    
    try {
        $currentVersion = (Get-Current-PHP-Version).version -replace '^(\d+\.\d+)\..*$', '$1'
        $baseUrl = "https://xdebug.org"
        $url = "$baseUrl/download/historical"
        $xDebugList = Get-XDebug-FROM-URL -url $url -version $currentVersion
        $xDebugList = $xDebugList | Sort-Object { [version]$_.xDebugVersion } -Descending
        $xDebugListGrouped = [ordered]@{}
        $xDebugList | 
            Group-Object xDebugVersion | 
            Sort-Object { [version]$_.Name } -Descending | 
            ForEach-Object {
                $xDebugListGrouped[$_.Name] = $_.Group
            }

        $index = 0
        $xDebugListGrouped.GetEnumerator() | ForEach-Object {
            Write-Host "`n$($_.Key)"
            $_.Value | ForEach-Object {
                $text = ($_.outerHTML -replace '<.*?>|.zip','').Trim()
                Write-Host " [$index] $text"
                $index++
            }
        }
        
        $packageIndex = Read-Host "`nInsert the [number] you want to install"
        $packageIndex = $packageIndex.Trim()
        if ([string]::IsNullOrWhiteSpace($packageIndex)) {
            Write-Host "`nInstallation cancelled"
            return -1
        }
        
        $chosenItem = $xDebugList[$packageIndex]
        if (-not $chosenItem) {
            Write-Host "`nYou chose the wrong index: $packageIndex" -ForegroundColor DarkYellow
            return -1
        }
        
        Invoke-WebRequest -Uri "$baseUrl/$($chosenItem.href.TrimStart('/'))" -OutFile "$STORAGE_PATH\php"
        $phpPath = ($iniPath | Split-Path -Parent)
        if (Test-Path "$phpPath\ext\$($chosenItem.fileName)") {
            $response = Read-Host "`n$($chosenItem.fileName) already exists. Would you like to overwrite it? (y/n)"
            $response = $response.Trim()
            if ($response -ne "y" -and $response -ne "Y") {
                Remove-Item -Path "$STORAGE_PATH\php\$($chosenItem.fileName)"
                Write-Host "`nInstallation cancelled"
                return -1
            }
        }
        Move-Item -Path "$STORAGE_PATH\php\$($chosenItem.fileName)" -Destination "$phpPath\ext"
        Remove-Item -Path "$STORAGE_PATH\php\$($chosenItem.fileName)"
        $xDebugConfig = getXdebugConfigV2 -XDebugPath $($chosenItem.fileName)
        if ($chosenItem.xDebugVersion -like "3.*") {
            $xDebugConfig = getXdebugConfigV3 -XDebugPath $($chosenItem.fileName)
        }
        $xDebugConfig = $xDebugConfig -replace "\ +"
        Add-Content -Path $iniPath -Value $xDebugConfig
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to install extension 'xdebug'"
            exception = $_
        }
        return -1
    }
}

function Install-Extension {
    param ($iniPath, $extName)
    
    try {
        $baseUrl = "https://pecl.php.net"
        try {
            $html = Invoke-WebRequest -Uri "$baseUrl/package/$extName"
        } catch {
            # check by match
            $html_cat = Invoke-WebRequest -Uri "$baseUrl/packages.php"
            $linksMatchnigExtName = @()
            $resultCat = $html_cat.Links | Where-Object {
                if (-not $_.href) { return $false }
                if ($_.href -match '^/packages\.php\?catpid=\d+&amp;catname=[A-Za-z+]+$') {
                    $html = Invoke-WebRequest -Uri "$baseUrl/$($_.href.TrimStart('/'))"
                    $resultLinks = $html.Links | Where-Object {
                        if (-not $_.href) { return $false }
                        return ($_.href -like "/package/*$extName*")
                    }
                    if ($resultLinks.Count -eq 0) {
                        return $false
                    }
                    $linksMatchnigExtName += $resultLinks
                    return $true
                }
            }
            
            Write-Host "`nMatching '$extName' extension:"
            $index = 0
            $linksMatchnigExtName | ForEach-Object {
                $extItem = $_.href -replace "/package/", ""
                Write-Host "[$index] $extItem"
                $index++
            }
            $extIndex = Read-Host "`nInsert the [number] you want to install"
            $extIndex = $extIndex.Trim()
            if ([string]::IsNullOrWhiteSpace($extIndex)) {
                Write-Host "`nInstallation cancelled"
                return -1
            }
            
            $chosenItem = $linksMatchnigExtName[$extIndex]
            if (-not $chosenItem) {
                Write-Host "`nYou chose the wrong index: $extIndex" -ForegroundColor DarkYellow
                return -1
            }
            $extName = $chosenItem.href -replace "/package/", ""
            $html = Invoke-WebRequest -Uri "$baseUrl/package/$extName"
        }
        
        $links = $html.Links | Where-Object {
            $_.href -match "/package/$extName/([^/]+)/windows$"
        }
        if ($links.Count -eq 0) {
            Write-Host "`No versions found for $extName" -ForegroundColor DarkYellow
            return -1
        }
        
        $currentVersion = (Get-Current-PHP-Version).version -replace '^(\d+\.\d+)\..*$', '$1'
        $pachagesGroupLinks = @()
        $links | ForEach-Object {
            $extVersion = $_.href -replace "/package/$extName/", "" -replace "/windows", ""
            try {
                $html = Invoke-WebRequest -Uri "$baseUrl/package/$extName/$extVersion/windows"
                $packageLinks = $html.Links | Where-Object {
                    $packageName = $_.href -replace "https://downloads.php.net/~windows/pecl/releases/$extName/$extVersion/", ""
                    if ($packageName -match "^php_$extName-$extVersion-(\d+\.\d+)-.+\.zip$") {
                        $phpVersion = $matches[1]
                        return ($phpVersion -eq $currentVersion)
                    }
                    return $false
                }
                
                if ($packageLinks -and $packageLinks.Count -gt 0) {
                    Write-Host "`n$extName v$extVersion :"
                    $index = $pachagesGroupLinks.Count
                    foreach ($link in $packageLinks) {
                        $link | Add-Member -NotePropertyName "extVersion" -NotePropertyValue $extVersion -Force
                        $pachagesGroupLinks += $link
                        $text = ($link.outerHTML -replace '<.*?>|.zip','').Trim()
                        Write-Host " [$index] $text"
                        $index++
                    }
                }
            } catch {
                $logged = Log-Data -data @{
                    header = "$($MyInvocation.MyCommand.Name) - Failed to find packages for $extName v$extVersion"
                    exception = $_
                }
            }
        }
        
        if ($pachagesGroupLinks.Count -eq 0) {
            Write-Host "`nNo packages found for $extName" -ForegroundColor DarkYellow
            return -1
        }

        $packageIndex = Read-Host "`nInsert the [number] you want to install"
        $packageIndex = $packageIndex.Trim()
        if ([string]::IsNullOrWhiteSpace($packageIndex)) {
            Write-Host "`nInstallation cancelled"
            return -1
        }
        
        $chosenItem = $pachagesGroupLinks[$packageIndex]
        if (-not $chosenItem) {
            Write-Host "`nYou chose the wrong index: $packageIndex" -ForegroundColor DarkYellow
            return -1
        }
        
        Invoke-WebRequest -Uri $chosenItem.href -OutFile "$STORAGE_PATH\php"
        $fileNamePath = ($chosenItem.href -replace "https://downloads.php.net/~windows/pecl/releases/$extName/$($chosenItem.extVersion)/|.zip",'').Trim()
        Extract-Zip -zipPath "$STORAGE_PATH\php\$fileNamePath.zip" -extractPath "$STORAGE_PATH\php\$fileNamePath"
        Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath.zip"
        $files = Get-ChildItem -Path "$STORAGE_PATH\php\$fileNamePath"
        $extFile = $files | Where-Object {
            ($_.Name -match "($extName|php_$extName).dll")
        }
        if (-not $extFile) {
            Write-Host "`nFailed to find $extName" -ForegroundColor DarkYellow
            return -1
        }
        $phpPath = ($iniPath | Split-Path -Parent)
        if (Test-Path "$phpPath\ext\$($extFile.Name)") {
            $response = Read-Host "`n$($extFile.Name) already exists. Would you like to overwrite it? (y/n)"
            $response = $response.Trim()
            if ($response -ne "y" -and $response -ne "Y") {
                Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath" -Force -Recurse
                Write-Host "`nInstallation cancelled"
                return -1
            }
        }
        Move-Item -Path $extFile.FullName -Destination "$phpPath\ext"
        Remove-Item -Path "$STORAGE_PATH\php\$fileNamePath" -Force -Recurse
        $code = Add-Missing-PHPExtension -iniPath $iniPath -extName $extName -enable $false
        if ($code -ne 0) {
            Write-Host "`nFailed to add $extName" -ForegroundColor DarkYellow
            return -1
        }
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to install extension '$extName'"
            exception = $_
        }
        return -1
    }
}

function Install-IniExtension {
    param ($iniPath, $extName)
    
    try {
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to check status"
            return -1
        }
        
        if ($extName -like "*xdebug*") {
            $code = Install-XDebug-Extension -iniPath $iniPath
        } else {
            $code = Install-Extension -iniPath $iniPath -extName $extName
        }
        
        if ($code -ne 0) {
            throw "`nFailed to install $extName"
        }
        
        Write-Host "`n$extName installed successfully"        
        return 0
    } catch {
        Write-Host "`nFailed to install $extName" -ForegroundColor DarkYellow
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to install '$extName'"
            exception = $_
        }
        return -1
    }
}

function Get-PHPExtensions-From-Source {
    $baseUrl = "https://pecl.php.net"
    $availableExtensions = @{}
    try {
        $html_cat = Invoke-WebRequest -Uri "$baseUrl/packages.php"
        $resultCat = $html_cat.Links | Where-Object {
            if (-not $_.href) { return $false }
            if ($_.href -match '^/packages\.php\?catpid=\d+&amp;catname=[A-Za-z+]+$') {
                $extCategory = ($_.outerHTML -replace '<[^>]*>', '').Trim()
                $availableExtensions[$extCategory] = @()
                
                # fetch the extensions from the category
                $html = Invoke-WebRequest -Uri "$baseUrl/$($_.href.TrimStart('/'))"
                $resultLinks = $html.Links | Where-Object {
                    if (-not $_.href) { return $false }
                    if ($_.href -match '^/package/[A-Za-z0-9_]+$') {
                        $extName = ($_.href -replace '/package/', '').Trim()
                        $_ | Add-Member -NotePropertyName "extName" -NotePropertyValue $extName -Force
                        $_ | Add-Member -NotePropertyName "extCategory" -NotePropertyValue $extCategory -Force
                        $availableExtensions[$extCategory] += $_
                        return $true
                    }
                }
                if ($availableExtensions[$extCategory].Count -eq 0) {
                    $availableExtensions.Remove($extCategory)
                }
                return $true
            }
            return $false
        }
        $dataToCache = [ordered] @{}
        ($availableExtensions.GetEnumerator() | Sort-Object Key | ForEach-Object { $dataToCache[$_.Key] = $_.Value })
        $cached = Cache-Data -cacheFileName "available_extensions" -data $dataToCache -depth 3
        
        return $availableExtensions
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get PHP extensions from source"
            exception = $_
        }
        return @{}
    }
}

function List-PHP-Extensions {
    param ($iniPath, $available = $false, $term = $null)
    
    try {
        if (-not $available) {
            $extensions = Get-PHPExtensionsStatus -PhpIniPath $iniPath
            if ($extensions.Count -eq 0) {
                Write-Host "`nNo extensions found"
                return -1
            }
            $searchResult = $extensions
            if ($term) {
                $searchResult = $extensions | Where-Object { $_.Extension -like "*$term*" }
            }
            if ($searchResult.Count -eq 0) {
                $msg = "`nNo extensions found"
                if ($term) {
                    $msg += " matching '$term'"
                }
                Write-Host $msg -ForegroundColor DarkYellow
                return -1
            }
            Display-Extensions-States -extensions $extensions
            Display-Installed-Extensions -extensions $searchResult
        } else {
            Write-Host "`nLoading available extensions..."
            
            $cacheFile = "$DATA_PATH\available_extensions.json"
            $useCache = $false
            
            if (Test-Path $cacheFile) {
                $fileAgeHours = (New-TimeSpan -Start (Get-Item $cacheFile).LastWriteTime -End (Get-Date)).TotalHours
                $useCache = ($fileAgeHours -lt $CacheMaxHours)
            }
            
            if ($useCache) {
                $availableExtensions = Get-Data-From-Cache -cacheFileName "available_extensions"
                if ($availableExtensions.Count -eq 0) {
                    $availableExtensions = Get-PHPExtensions-From-Source
                }
            } else {
                $availableExtensions = Get-PHPExtensions-From-Source
            }

            if ($availableExtensions.Count -eq 0) {
                Write-Host "`nNo extensions found"
                return -1
            }
            
            $availableExtensionsPartialList = @{}
            $availableExtensions.GetEnumerator() | ForEach-Object {
                $searchResult = $_.Value
                if ($term) {
                    if ($_.Key -notlike "*$term*") {
                        # Search the list if the category doesn't match
                        $searchResult = $searchResult | Where-Object {
                            $_.extName -like "*$term*"
                        }
                    }
                }
                if ($searchResult.Count -gt 0) {
                    $availableExtensionsPartialList[$_.Key] = $searchResult | Select-Object -Last 10
                }
            }
            
            if ($availableExtensionsPartialList.Count -eq 0) {
                $msg = "`nNo extensions found"
                if ($term) {
                    $msg += " matching '$term'"
                }
                Write-Host $msg -ForegroundColor DarkYellow
                return -1
            }
            
            $maxKeyLength = ($availableExtensionsPartialList.Keys | Measure-Object -Maximum Length).Maximum
            $maxLineLength = $maxKeyLength + 5   # adjust padding
            Write-Host "`nAvailable Extensions by Category:"
            Write-Host    "--------------------------------"
            $availableExtensionsPartialList.GetEnumerator() | Sort-Object Key | ForEach-Object {
                $key  = $_.Key
                $vals = ($_.Value | ForEach-Object { $_.extName }) -join ", "
                $dotsCount = $maxLineLength - $key.Length
                if ($dotsCount -lt 0) { $dotsCount = 0 }
                $dots = '.' * $dotsCount

                Write-Host "$key $dots $vals"
            }
            
            Write-Host "`nThis is a partial list. For a complete list, visit: https://pecl.php.net/packages.php"
        }
        
        return 0
    } catch {
        Write-Host "`nFailed to list extensions"
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to list extensions"
            exception = $_
        }
        return -1
    }
}

function Invoke-PVMIniAction {
    param ( $action, $params )

    try {
        $exitCode = 1
        
        $currentPhpVersion = Get-Current-PHP-Version
        
        if (-not $currentPhpVersion -or -not $currentPhpVersion.version -or -not $currentPhpVersion.path) {
            Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }
        
        $iniPath = "$($currentPhpVersion.path)\php.ini"
        if (-not (Test-Path $iniPath)) {
            Write-Host "php.ini not found at: $($currentPhpVersion.path)"
            return -1
        }

        switch ($action) {
            "info" {
                $exitCode = Get-PHP-Info
            }
            "get" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one setting name ('pvm ini get memory_limit)."
                    return -1
                }
                
                Write-Host "`nRetrieving ini setting..."
                foreach ($extName in $params) {
                    $exitCode = Get-IniSetting -iniPath $iniPath -key $extName
                }
            }
            "set" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one 'key=value' (pvm ini set memory_limit=512M)."
                    return -1
                }

                Write-Host "`nSetting ini value..."
                foreach ($keyValue in $params) {
                    $exitCode = Set-IniSetting -iniPath $iniPath -keyValue $keyValue
                }
            }
            "enable" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini enable curl)."
                    return -1
                }
                
                Write-Host "`nEnabling extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Enable-IniExtension -iniPath $iniPath -extName $extName
                }
            }
            "disable" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini disable xdebug)."
                    return -1
                }
                
                Write-Host "`nDisabling extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Disable-IniExtension -iniPath $iniPath -extName $extName
                }
            }
            "status" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini status opcache)."
                    return -1
                }
                
                Write-Host "`nChecking status of extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Get-IniExtensionStatus -iniPath $iniPath -extName $extName
                }
            }
            "restore" {
                $exitCode = Restore-IniBackup -iniPath $iniPath
            }
            "install" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini install xdebug)."
                    return -1
                }
                
                Write-Host "`nInstalling extension(s): $($remainingArgs -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Install-IniExtension -iniPath $iniPath -extName $extName
                }
            }
            "list" {
                $term = ($params | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
                $exitCode = List-PHP-Extensions -iniPath $iniPath -available ($params -contains "available") -term $term
            }
            default {
                Write-Host "`nUnknown action '$action' use one of following: 'info', 'get, 'set', 'enable', 'disable', 'status', 'install', 'list' or 'restore'."
            }
        }
        
        return $exitCode
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to invoke ini action '$action'"
            exception = $_
        }
        Write-Host "`nFailed to perform action '$action' on ini settings." -ForegroundColor Red
        return -1
    }
}