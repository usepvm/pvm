

function Get-XDebug-FROM-URL {
    param ($url, $version)

    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links

         # Filter the links to find versions that match the given version
        $sysArch = if ($env:PROCESSOR_ARCHITECTURE -eq 'AMD64') { 'x86_64' } else { '' }
        $filteredLinks = $links | Where-Object {
            $_.href -match "php_xdebug-[\d\.a-zA-Z]+-$version-.*$sysArch\.dll"
        }

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $filteredLinks = $filteredLinks | ForEach-Object {
            $fileName = $_.href -split "/"
            $fileName = $fileName[$fileName.Count - 1]
            $xDebugVersion = "2.0"
            if ($_.href -match "php_xdebug-([\d\.]+)") {
                $xDebugVersion = $matches[1]
            }
            $formattedList += @{ href = $_.href; version = $version; xDebugVersion = $xDebugVersion; fileName = $fileName; outerHTML = $_.outerHTML }
        }

        return $formattedList
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to fetch xdebug versions from $url"
            exception = $_
        }
        return @()
    }

}

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
        
        $pattern = "^[#;]?\s*([^=\s]*{0}[^=\s]*)\s*=\s*(.*)" -f [regex]::Escape($key)
        $lines = Get-Content $iniPath

        $result = @()
        foreach ($line in $lines) {
            if ($line -match $pattern) {
                $item = @{
                    extensionName = $matches[1].Trim()
                    value = $matches[2].Trim()
                    enabled = 'Enabled'
                    color = 'DarkGreen'
                }
                
                if ($matches[0] -match '^[#;]') {
                    $item.enabled = 'Disabled'
                    $item.color = 'DarkYellow'
                }
                
                $result += $item
            }
        }
        
        if ($result.Count -eq 0) {
            Write-Host "- The setting key '$key' is not found." -ForegroundColor DarkGray
            return -1
        }

        $maxLineLength = ($result.extensionName | Measure-Object -Maximum Length).Maximum + 10
        $result | ForEach-Object {
            $name = "$($_.extensionName) ".PadRight($maxLineLength, '.')
            $value = if ($_.value -eq '') { '(not set)' } else { $_.value }
            
            Write-Host "- $name $value " -NoNewline
            Write-Host "$($_.enabled)" -ForegroundColor $_.color
        }
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to get ini setting '$key'"
            exception = $_
        }
        return -1
    }
}


function Set-IniSetting {
    param ($iniPath, $key, $enable = $true)
    try {
        # Accept: key OR key=value
        if ($key -match '^(?<k>[^=]+)(=(?<v>.*))?$') {
            $searchKey = $matches.k.Trim()
            $inputValue = if ($null -ne $matches.v) { $matches.v.Trim() } else { $null }
        } else {
            Write-Host "Invalid input." -ForegroundColor DarkGray
            return -1
        }

        $pattern = "^[#;]?\s*(?<key>[^=\s]*{0}[^=\s]*)\s*=\s*(?<value>.*)$" -f [regex]::Escape($searchKey)

        $matchesList = @()
        $lines = Get-Content $iniPath

        $index = 0
        foreach ($line in $lines) {
            if ($line -match $pattern) {
                $matchesList += @{
                    Index = $matchesList.Count + 1
                    Key = $matches['key'].Trim()
                    Value = $matches['value'].Trim()
                    Enabled = -not ($line -match '^[#;]')
                    Line = $line
                    LineNo  = $index
                    Color   = if ($line -match '^[#;]') { 'DarkYellow' } else { 'DarkGreen' }
                }
            }
            $index++
        }

        if ($matchesList.Count -eq 0) {
            Write-Host "- No settings match '$searchKey'" -ForegroundColor DarkGray
            return -1
        }

        if ($matchesList.Count -gt 1) {
            Write-Host "`nMultiple settings match '$searchKey':`n" -ForegroundColor Cyan

            $maxLineLength = ($matchesList.Key | Measure-Object -Maximum Length).Maximum + 10
            $matchesList | ForEach-Object {
                $state = if ($_.Enabled) { 'Enabled' } else { 'Disabled' }
                $key = "$($_.Key) ".PadRight($maxLineLength, '.')
                $value = if ($_.value -eq '') { '(not set)' } else { $_.value }
                Write-Host "[$($_.Index)] $key = $value " -NoNewline
                Write-Host $state -ForegroundColor $_.Color
            }

            do {
                $choice = Read-Host "`nSelect a number"
            } until ($choice -match '^\d+$' -and $choice -ge 1 -and $choice -le $matchesList.Count)

            $selected = $matchesList[$choice - 1]
        } else {
            $selected = $matchesList[0]
        }

        if (-not $inputValue) {
            $inputValue = Read-Host "Enter new value for '$($selected.Key)'"
        }

        $newLine = if ($enable) {
            "$($selected.Key) = $inputValue"
        } else {
            ";$($selected.Key) = $inputValue"
        }
        
        Backup-IniFile $iniPath

        $lines[$selected.LineNo] = $newLine
        Set-Content $iniPath $lines -Encoding UTF8

        $status = if ($enable) {'Enabled'} else {'Disabled'}
        $color = if ($enable) {'DarkGreen'} else {'DarkYellow'}

        Write-Host "`n- $($selected.Key) set to '$inputValue' successfully | " -NoNewline -ForegroundColor DarkGreen
        Write-Host $status -ForegroundColor $color

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
    param ($term = $null, $extensions = $false, $settings = $false)

    if (-not $extensions -and -not $settings) {
        $extensions = $true
        $settings = $true
    }
    
    $currentPHPVersion = Get-Current-PHP-Version
    
    if (-not $currentPHPVersion -or -not $currentPHPVersion.version -or -not $currentPHPVersion.path) {
        Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
        return -1
    }
    
    Write-Host "`n- Running PHP version`t: $($currentPHPVersion.version)"
    Write-Host "`n- PHP path`t`t: $($currentPHPVersion.path)"
    $phpIniData = Get-PHP-Data -PhpIniPath "$($currentPHPVersion.path)\php.ini"

    if ($extensions) {
        $extensions = $phpIniData.extensions | Where-Object { $_.Extension -like "*$term*" }
        Display-Extensions-States -extensions $phpIniData.extensions
        Display-Installed-Extensions -extensions $extensions
    }

    if ($settings) {
        $settings = $phpIniData.settings | Where-Object { $_.Name -like "*$term*" }
        Display-Settings-States -settings $phpIniData.settings
        Display-Settings -settings $settings
    }

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
    $MIN_LINE_LENGTH = 60
    $maxNameLength = ($extensions.Extension | Measure-Object -Maximum Length).Maximum
    $maxLineLength = $maxNameLength + 40  # padding
    if ($maxLineLength -lt $MIN_LINE_LENGTH) { $maxLineLength = $MIN_LINE_LENGTH }
    
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


function Display-Settings-States {
    param ($settings)
    
    # Pre-count for summary
    $enabledCount = @($settings | Where-Object Enabled).Count
    $disabledCount = $settings.Count - $enabledCount
    
    Write-Host "`n- Settings`t`t: Enabled: $enabledCount  |  Disabled: $disabledCount  |  Total: $($settings.Count)`n"
}

function Display-Settings {
    param ($settings)
    
    $MIN_LINE_LENGTH = 57
    $maxLineLength = (($settings.Name + $settings.Value) | Measure-Object -Maximum Length).Maximum
    $maxLineLength = $maxLineLength + 40 # padding
    if ($maxLineLength -lt $MIN_LINE_LENGTH) { $maxLineLength = $MIN_LINE_LENGTH }

    $settings |
    Sort-Object @{Expression = { -not $_.Enabled }; Ascending = $true },
                @{Expression = { $_.Name }; Ascending = $true } |
    ForEach-Object {
        $dotsCount = $maxLineLength - ($_.Name.Length + $_.Value.Length)
        if ($dotsCount -lt 0) { $dotsCount = 0 }
        $dots = '.' * $dotsCount

        if ($_.Enabled) {
            $status = "Enabled "
            $color = "DarkGreen"
        } else {
            $status = "Disabled"
            $color = "DarkGray"
        }

        Write-Host "  $($_.Name) $dots $($_.Value) " -NoNewline
        Write-Host $status -ForegroundColor $color
    }
}

function Get-PHP-Data {
    param($PhpIniPath)

    $iniContent = Get-Content $PhpIniPath
    
    $phpIniData = @{
        extensions = @()
        settings   = @()
    }
    
    foreach ($line in $iniContent) {
        # Match both enabled and commented lines
        if ($line -match '^\s*(;)?(zend_extension|extension)\s*=\s*"?([^";]+?)"?\s*(?:;.*)?$') {
            $rawPath = $matches[3]
            $extensionName = [System.IO.Path]::GetFileName($rawPath)
            $phpIniData.extensions += [PSCustomObject]@{
                Section   = "extension"
                Extension = $extensionName
                Type      = $matches[2] # extension or zend_extension
                Enabled   = -not $matches[1]
            }
        } elseif ($line -match '^\s*(;)?([A-Za-z0-9_.]+)\s*=\s*("?[^";]+?"?)\s*(?:;.*)?$') {
            $phpIniData.settings += [PSCustomObject]@{
                Section   = "setting"
                Name      = $matches[2]   # e.g. memory_limit
                Type      = "setting"
                Value     = $matches[3].Trim('"') # strip quotes if present
                Enabled   = -not $matches[1]      # false if line starts with ;
            }
        }
    }

    return $phpIniData
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
            Write-Host "`nExtension '$extName' not found, Loading matching extensions..."
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
            
            if ($linksMatchnigExtName.Count -eq 0) {
                Write-Host "`nExtension '$extName' not found" -ForegroundColor DarkYellow
                return -1
            }
            
            if ($linksMatchnigExtName.Count -eq 1) {
                $chosenItem = $linksMatchnigExtName[0]
            } else {
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
            }

            $extName = $chosenItem.href -replace "/package/", ""
            $html = Invoke-WebRequest -Uri "$baseUrl/package/$extName"
        }
        
        $links = $html.Links | Where-Object {
            $_.href -match "/package/$extName/([^/]+)/windows$"
        }
        if ($links.Count -eq 0) {
            Write-Host "`nNo versions found for $extName" -ForegroundColor DarkYellow
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
        $availableExtensions["XDebug"] = @(
            @{
                href = "https://xdebug.org/download/historical"
                extName = "xdebug"
                extCategory = "XDebug"
            }
        )
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
            $extensions = (Get-PHP-Data -PhpIniPath $iniPath).extensions
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
            
            $MIN_LINE_LENGTH = 50
            $maxKeyLength = ($availableExtensionsPartialList.Keys | Measure-Object -Maximum Length).Maximum
            $maxLineLength = $maxKeyLength + 30   # adjust padding
            if ($maxLineLength -lt $MIN_LINE_LENGTH) { $maxLineLength = $MIN_LINE_LENGTH }
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
            
            $msg = "`nThis is a partial list. For a complete list, visit:"
            $msg += "`nPHP Extensions : https://pecl.php.net/packages.php"
            $msg += "`nXDebug : https://xdebug.org/download/historical"
            Write-Host $msg
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
                $term = ($params | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
                $exitCode = Get-PHP-Info -term $term -extensions ($params -contains "extensions") -settings ($params -contains "settings")
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
                $enable = (-not ($params -contains '--disable'))
                $params = $params | Where-Object { $_ -notmatch '^--disable$' }
                foreach ($key in $params) {
                    $exitCode = Set-IniSetting -iniPath $iniPath -key $key -enable $enable
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