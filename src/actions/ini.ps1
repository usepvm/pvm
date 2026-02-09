

function Get-XDebug-FROM-URL {
    param ($url, $version, $arch = $null)

    try {
        $html = Invoke-WebRequest -Uri $url
        $links = $html.Links

        # Filter the links to find versions that match the given version
        if ($null -ne $arch) {
            $arch = if ($arch -eq 'x64') { 'x86_64' } else { '' }
        }
        $filteredLinks = $links | Where-Object {
            if ($arch) {
                return ($_.href -match "php_xdebug-[\d\.a-zA-Z]+-$version-.*$arch\.dll")
            }
            if ($arch -eq '') {
                return ($_.href -match "php_xdebug-[\d\.a-zA-Z]+-$version-.*\.dll" -and $_.href -notmatch "x86_64")
            }
            
            return $_.href -match "php_xdebug-[\d\.a-zA-Z]+-$version-.*\.dll"
        }

        # Return the filtered links (PHP version names)
        $formattedList = @()
        $filteredLinks = $filteredLinks | ForEach-Object {
            $fileName = $_.href -split "/"
            $fileName = $fileName[$fileName.Count - 1]
            $xDebugVersion = "2.0"
            if ($_.href -match "php_xdebug-([^-]+)") {
                $xDebugVersion = $matches[1]
            }
            
            $formattedList += @{
                href = $_.href
                version = $version
                xDebugVersion = $xDebugVersion;
                arch = if ($fileName -match '(x86_64|x64)(?=\.dll$)') { 'x64' } else { 'x86' }
                buildType = if ($fileName -match '(?i)(?:^|-)nts(?:-|\.dll$)') { 'NTS' } else { 'TS' }
                compiler = if ($fileName -match '(?i)\b(vs|vc)\d+\b') { $matches[0].ToUpper() } else { 'unknown' }
                fileName = $fileName;
                outerHTML = $_.outerHTML
            }
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

function Get-Matching-PHPExtensionsStatus {
    param ($iniPath, $extName)
    
    $enabledPattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?(?<ext>[^\s`"';]*$extName[^\s`"';]*)\2\s*(;.*)?$"
    $disabledPattern = "^\s*;\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?(?<ext>[^\s`"';]*$extName[^\s`"';]*)\2\s*(;.*)?$"
    Backup-IniFile $iniPath
    $lines = Get-Content $iniPath

    $matchesList = @()
    $matchesInExt = @()

    # helper to normalize extension identifiers for comparison
    $normalizeId = {
        param($n)
        if (-not $n) { return '' }
        $s = $n.ToString()
        $s = $s.Trim('"', "'") # remove surrounding quotes (single or double)
        $s = [System.IO.Path]::GetFileName($s) # get file name only (strip path)
        $s = $s -replace '^php_', '' -replace '\.dll$', '' # strip php_ prefix and .dll suffix and lowercase
        return $s.ToLower()
    }

    # normalized search id from the provided extName
    $searchId = & $normalizeId $extName

    # Step 1: Check ext directory first for matches
    $phpDirectory = Split-Path -Path $iniPath -Parent
    $extDirectory = Join-Path -Path $phpDirectory -ChildPath "ext"

    if (Test-Path $extDirectory) {
        $dllPattern = if ($searchId) { "*$searchId*.dll" } else { "*.dll" }
        $dllFiles = Get-ChildItem -Path $extDirectory -Filter $dllPattern -File -ErrorAction SilentlyContinue
        foreach ($file in $dllFiles) {
            $fileId = & $normalizeId $file.BaseName
            if (-not $fileId) { continue }

            $matchesInExt += @{ 
                name = $file.BaseName
                id = $fileId
                fullPath = $file.FullName
            }
        }
    }

    if ($matchesInExt.Count -eq 0) {
        return @()
    }

    # Step 2: Search ini file for matching extensions (only if found in ext)
    $lineNumber = 1
    $iniMatches = @{}  # hashtable to track ini entries by id

    foreach ($line in $lines) {
        if ($line -match $enabledPattern) {
            $rawExt = $matches['ext']
            $displayName = ($rawExt).Trim('"', "'")
            $id = & $normalizeId $displayName
            if (-not $id) { $lineNumber++; continue }

            # track ini matches by normalized id
            $iniMatches[$id] = @{
                name = $displayName
                status = "Enabled"
                color = "DarkGreen"
                line = $line
                lineNumber = $lineNumber
                source = "ini"
            }
        }
        if ($line -match $disabledPattern) {
            $rawExt = $matches['ext']
            $displayName = ($rawExt).Trim('"', "'")
            $id = & $normalizeId $displayName
            if (-not $id) { $lineNumber++; continue }

            $iniMatches[$id] = @{
                name = $displayName
                status = "Disabled"
                color = "DarkYellow"
                line = $line
                lineNumber = $lineNumber
                source = "ini"
            }
        }
        $lineNumber++
    }
    # Step 3: Build result list: merge ext files with ini entries (ini status takes precedence if exists)
    foreach ($extMatch in $matchesInExt) {
        $id = $extMatch.id
        
        if ($iniMatches.ContainsKey($id)) {
            # Extension is configured in ini
            $matchesList += @{
                name = $iniMatches[$id].name
                id = $id
                status = $iniMatches[$id].status
                color = $iniMatches[$id].color
                line = $iniMatches[$id].line
                lineNumber = $iniMatches[$id].lineNumber
                source = "ext,ini"
            }
        } else {
            # Extension exists in ext but not configured in ini - add it as disabled
            $isZendExtension = Get-Zend-Extensions-List | Where-Object { $extMatch.name -like "*$_*" }
            $extensionLine = if ($isZendExtension) { ";zend_extension=$($extMatch.name).dll" } else { ";extension=$($extMatch.name).dll" }
            
            try {
                $lines += $extensionLine
                Set-Content $iniPath $lines -Encoding UTF8
                
                $matchesList += @{
                    name = $extMatch.name
                    id = $id
                    status = "Disabled"
                    color = "DarkYellow"
                    line = $extensionLine
                    lineNumber = $lines.Count
                    source = "ext,ini"
                }
            } catch {
                # If adding fails, still return it as available
                $matchesList += @{
                    name = $extMatch.name
                    id = $id
                    status = "Available (not configured)"
                    color = "DarkCyan"
                    line = "Found in ext directory: $($extMatch.fullPath)"
                    lineNumber = 0
                    source = "ext"
                }
            }
        }
    }
    
    return $matchesList
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
            $extensionName = "$($_.extensionName) ".PadRight($maxLineLength, '.')
            $value = if ($_.value -eq '') { '(not set)' } else { $_.value }
            
            Write-Host "- $extensionName $value " -NoNewline
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
                    Index = $matchesList.Length + 1
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

        if ($matchesList.Length -eq 0) {
            Write-Host "- No settings match '$searchKey'" -ForegroundColor DarkGray
            return -1
        }

        if ($matchesList.Length -gt 1) {
            Write-Host "`nMultiple settings match '$searchKey':`n" -ForegroundColor Cyan

            $maxLineLength = ($matchesList.Key | Measure-Object -Maximum Length).Maximum + 10
            $matchesList | ForEach-Object {
                $state = if ($_.Enabled) { 'Enabled' } else { 'Disabled' }
                $key = "$($_.Key) ".PadRight($maxLineLength, '.')
                $value = if ($_.value -eq '') { '(not set)' } else { $_.value }
                Write-Host "[$($_.Index)] $key $value " -NoNewline
                Write-Host $state -ForegroundColor $_.Color
            }

            do {
                $choiceRaw = Read-Host "`nSelect a number"
                $choice = $null

                if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                    Write-Host "Please enter a valid positive number." -ForegroundColor Yellow
                    continue
                }

                if ($choice -lt 1 -or $choice -gt $matchesList.Length) {
                    Write-Host "Number must be between 1 and $($matchesList.Length)." -ForegroundColor Yellow
                    continue
                }

                break
            } while ($true)

            $selected = $matchesList[$choice - 1]
        } else {
            $selected = $($matchesList)
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
        
        $matchesListStatus = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName
        
        if ($matchesListStatus.Length -eq 0) {
            Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray
            
            return -1
        } 
        
        if ($matchesListStatus.Length -gt 1) {
            Write-Host "`nMultiple extensions match '$extName':`n" -ForegroundColor Cyan

            $maxLineLength = ($matchesListStatus.name | Measure-Object -Maximum Length).Maximum + 10
            $index = 1
            $matchesListStatus | ForEach-Object {
                $name = "$($_.name) ".PadRight($maxLineLength, '.')
                Write-Host "[$index] $name " -NoNewline
                Write-Host "$($_.status)" -ForegroundColor $_.color
                $index++
            }

            do {
                $choiceRaw = Read-Host "`nSelect a number"
                $choice = $null

                if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                    Write-Host "Please enter a valid positive number." -ForegroundColor Yellow
                    continue
                }

                if ($choice -lt 1 -or $choice -gt $matchesListStatus.Length) {
                    Write-Host "Number must be between 1 and $($matchesListStatus.Length)." -ForegroundColor Yellow
                    continue
                }

                break
            } while ($true)

            $selected = $matchesListStatus[$choice - 1]
        } else {
            $selected = $($matchesListStatus)
        }
        
        if ($selected.status -eq "Enabled") {
            Write-Host "- '$($selected.name)' enabled successfully." -ForegroundColor DarkGreen
            return 0
        }
        
        $lines = Get-Content $iniPath

        $modified = $false
        $lineNumber = 0
        $newLines = $lines | ForEach-Object {
            $lineNumber++
            if ($_ -eq $selected.line -and $selected.lineNumber -eq $lineNumber -and -not $modified) {
                $modified = $true
                return $_ -replace "^[#;]\s*", ""
            }
            return $_
        }

        if (-not $modified) {
            Write-Host "- '$($selected.name)' enabled successfully." -ForegroundColor DarkGreen
            return 0
        }

        Backup-IniFile $iniPath
        Set-Content $iniPath $newLines -Encoding UTF8
        Write-Host "- '$($selected.name)' enabled successfully." -ForegroundColor DarkGreen

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
        
        $matchesListStatus = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName

        if ($matchesListStatus.Length -eq 0) {
            Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray

            return -1
        }
        
        if ($matchesListStatus.Length -gt 1) {
            Write-Host "`nMultiple extensions match '$extName':`n" -ForegroundColor Cyan

            $maxLineLength = ($matchesListStatus.name | Measure-Object -Maximum Length).Maximum + 10
            $index = 1
            $matchesListStatus | ForEach-Object {
                $name = "$($_.name) ".PadRight($maxLineLength, '.')
                Write-Host "[$index] $name " -NoNewline
                Write-Host "$($_.status)" -ForegroundColor $_.color
                $index++
            }

            do {
                $choiceRaw = Read-Host "`nSelect a number"
                $choice = $null

                if (-not [int]::TryParse($choiceRaw, [ref]$choice)) {
                    Write-Host "Please enter a valid positive number." -ForegroundColor Yellow
                    continue
                }

                if ($choice -lt 1 -or $choice -gt $matchesListStatus.Length) {
                    Write-Host "Number must be between 1 and $($matchesListStatus.Length)." -ForegroundColor Yellow
                    continue
                }

                break
            } while ($true)

            $selected = $matchesListStatus[$choice - 1]
        } else {
            $selected = $($matchesListStatus)
        }
        
        if ($selected.status -eq "Disabled") {
            Write-Host "- '$($selected.name)' disabled successfully." -ForegroundColor DarkGreen
            return 0
        }
        
        $lines = Get-Content $iniPath

        $modified = $false
        $lineNumber = 0
        $updatedLines = $lines | ForEach-Object {
            $lineNumber++
            if ($_ -eq $selected.line -and $selected.lineNumber -eq $lineNumber -and -not $modified -and ($_ -notmatch '^\s*;')) {
                $modified = $true
                return ";$_"
            }
            return $_
        }

        if (-not $modified) {
            Write-Host "- '$($selected.name)' disabled successfully." -ForegroundColor DarkGreen
            return 0
        }
        
        Backup-IniFile $iniPath
        Set-Content $iniPath $updatedLines -Encoding UTF8
        Write-Host "- '$($selected.name)' disabled successfully." -ForegroundColor DarkGreen
        
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

        $matchesListStatus = Get-Matching-PHPExtensionsStatus -iniPath $iniPath -extName $extName
        
        if ($matchesListStatus.Length -eq 0) {
            Write-Host "- $extName`: extension not found" -ForegroundColor DarkGray

            return -1
        }
        
        $maxLineLength = ($matchesListStatus.name | Measure-Object -Maximum Length).Maximum + 10
        $matchesListStatus | ForEach-Object {
            $name = "$($_.name) ".PadRight($maxLineLength, '.')
            Write-Host "- $name " -NoNewline
            Write-Host "$($_.status)" -ForegroundColor $_.color
        }
        
        return 0
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
    $maxLineLength = [Math]::Max($MIN_LINE_LENGTH, $maxNameLength + 40)
    if ($maxLineLength -lt $MIN_LINE_LENGTH) { $maxLineLength = $MIN_LINE_LENGTH }
    
    $extensions |
    Sort-Object @{Expression = { -not $_.Enabled }; Ascending = $true },
                @{Expression = { $_.Extension }; Ascending = $true } |
    ForEach-Object {
        $label = "  $($_.Extension) "
        $label = $label.PadRight($maxLineLength, '.')

        if ($_.Enabled) {
            $status = "Enabled "
            $color = "DarkGreen"
        } else {
            $status = "Disabled"
            $color = "DarkGray"
        }

        Write-Host "$label " -NoNewline
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
    $maxLineLength = [Math]::Max($MIN_LINE_LENGTH, $maxLineLength + 40)

    $settings |
    Sort-Object @{Expression = { -not $_.Enabled }; Ascending = $true },
                @{Expression = { $_.Name }; Ascending = $true } |
    ForEach-Object {
        $label = "  $($_.Name) "
        $value = " $($_.Value) "

        # pad with dots so value always starts at same column
        $line  = $label.PadRight($maxLineLength - $value.Length, '.') + $value

        if ($_.Enabled) {
            $status = "Enabled "
            $color = "DarkGreen"
        } else {
            $status = "Disabled"
            $color = "DarkGray"
        }

        Write-Host $line -NoNewline
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
    param ($iniPath, $arch = $null)
    
    try {
        $currentVersion = (Get-Current-PHP-Version).version -replace '^(\d+\.\d+)\..*$', '$1'
        $xDebugList = Get-XDebug-FROM-URL -url $XDEBUG_HISTORICAL_URL -version $currentVersion -arch $arch

        if ($null -eq $xDebugList -or $xDebugList.Count -eq 0) {
            Write-Host "`nNo match was found, check the '$LOG_ERROR_PATH' for any potentiel errors"
            return -1
        }

        $xDebugListGrouped = [ordered]@{}
        $xDebugList | 
            Group-Object xDebugVersion | 
            Sort-Object `
                @{ Expression = {
                        # extract numeric version
                        [version]($_.Name -replace '(alpha|beta|rc).*','')
                    }; Descending = $true },
                @{ Expression = {
                    # prerelease weight
                    if ($_.Name -match 'alpha') { 1 }
                    elseif ($_.Name -match 'beta') { 2 }
                    elseif ($_.Name -match 'rc') { 3 }
                    else { 4 } # stable
                }; Descending = $true },
                @{ Expression = {
                    # prerelease number (alpha3, rc2, etc)
                    if ($_.Name -match '(alpha|beta|rc)(\d+)') {
                        [int]$matches[2]
                    } else {
                        [int]::MaxValue
                    }
                }; Descending = $true } |
            ForEach-Object {
                $sortedGroup = $_.Group | Sort-Object `
                    @{ Expression = { $_.buildType -eq 'NTS' }; Descending = $true },
                    @{ Expression = {
                        switch ($_.arch) {
                            'x86_64' { 2 }
                            'x64'    { 2 }
                            'x86'    { 1 }
                            default  { 0 }
                        }
                    }; Descending = $true }

                $xDebugListGrouped[$_.Name] = $sortedGroup
            }

        $index = 0
        $xDebugListGrouped.GetEnumerator() | ForEach-Object {
            Write-Host "`nXDebug $($_.Key)"
            $_.Value | ForEach-Object {
                $text = "PHP XDebug $($_.version) $($_.compiler) $($_.buildType) $($_.arch)"
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
        
        Invoke-WebRequest -Uri "$XDEBUG_BASE_URL/$($chosenItem.href.TrimStart('/'))" -OutFile "$STORAGE_PATH\php"
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
        # check existence of previous xdebug
        $iniContent = Get-Content $iniPath
        $dllXDebugExists = $false
        for ($i = 0; $i -lt $iniContent.Count; $i++) {
            if ($iniContent[$i] -match '^(?<comment>;)?\s*zend_extension\s*=.*xdebug.*$') {
                $iniContent[$i] = $iniContent[$i] -replace '^(?<comment>;)?(\s*zend_extension\s*=).*$', "zend_extension='$($chosenItem.fileName)'"
                $dllXDebugExists = $true
            }
        }
        if ($dllXDebugExists) {
            Set-Content -Path $iniPath -Value $iniContent -Encoding UTF8
        } else {
            $xDebugConfig = $xDebugConfig -replace "\ +"
            Add-Content -Path $iniPath -Value $xDebugConfig
        }
        
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
    param ($iniPath, $extName, $arch = $null)
    
    try {
        try {
            $html = Invoke-WebRequest -Uri "$PECL_PACKAGE_ROOT_URL/$extName"
        } catch {
            Write-Host "`nExtension '$extName' not found, Loading matching extensions..."
            # check by match
            $html_cat = Invoke-WebRequest -Uri $PECL_PACKAGES_URL
            $linksMatchnigExtName = @()
            $resultCat = $html_cat.Links | Where-Object {
                if (-not $_.href) { return $false }
                if ($_.href -match '^/packages\.php\?catpid=\d+&amp;catname=[A-Za-z+]+$') {
                    $html = Invoke-WebRequest -Uri "$PECL_BASE_URL/$($_.href.TrimStart('/'))"
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
            $html = Invoke-WebRequest -Uri "$PECL_PACKAGE_ROOT_URL/$extName"
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
                $html = Invoke-WebRequest -Uri "$PECL_PACKAGE_ROOT_URL/$extName/$extVersion/windows"
                $packageLinks = $html.Links | Where-Object {
                    $packageName = $_.href -replace "$PECL_WIN_EXT_DOWNLOAD_URL/$extName/$extVersion/", ""
                    if ($null -eq $arch) {
                        $arch = ''
                    }
                    if ($packageName -match "^php_$extName-$extVersion-(\d+\.\d+)-.+$arch\.zip$") {
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
        $fileNamePath = ($chosenItem.href -replace "$PECL_WIN_EXT_DOWNLOAD_URL/$extName/$($chosenItem.extVersion)/|.zip",'').Trim()
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
    param ($iniPath, $extName, $arch = $null)
    
    try {
        if (-not $extName) {
            Write-Host "`nPlease provide an extension name to check status"
            return -1
        }
        
        if ($extName -like "*xdebug*") {
            $code = Install-XDebug-Extension -iniPath $iniPath -arch $arch
        } else {
            $code = Install-Extension -iniPath $iniPath -extName $extName -arch $arch
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
    $availableExtensions = @{}
    try {
        $html_cat = Invoke-WebRequest -Uri $PECL_PACKAGES_URL
        $resultCat = $html_cat.Links | Where-Object {
            if (-not $_.href) { return $false }
            if ($_.href -match '^/packages\.php\?catpid=\d+&amp;catname=[A-Za-z+]+$') {
                $extCategory = ($_.outerHTML -replace '<[^>]*>', '').Trim()
                $availableExtensions[$extCategory] = @()
                
                # fetch the extensions from the category
                $html = Invoke-WebRequest -Uri "$PECL_BASE_URL/$($_.href.TrimStart('/'))"
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
                href = $XDEBUG_HISTORICAL_URL
                extName = "xdebug"
                extCategory = "XDebug"
            }
        )
        $dataToCache = [ordered] @{}
        $availableExtensions.GetEnumerator() | Sort-Object Key | ForEach-Object { $dataToCache[$_.Key] = $_.Value }
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
            
            $useCache = Can-Use-Cache -cacheFileName 'available_extensions'
            
            if ($useCache) {
                $availableExtensions = Get-Data-From-Cache -cacheFileName "available_extensions"
                if ($availableExtensions.Count -eq 0) {
                    $availableExtensions = Get-PHPExtensions-From-Source
                    $availableExtensions = [pscustomobject] $availableExtensions
                }
            } else {
                $availableExtensions = Get-PHPExtensions-From-Source
                $availableExtensions = [pscustomobject] $availableExtensions
            }

            if ($availableExtensions.Count -eq 0) {
                Write-Host "`nNo extensions found"
                return -1
            }
            
            $availableExtensionsPartialList = @{}
            $availableExtensions.PSObject.Properties | ForEach-Object {
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
                    $availableExtensionsPartialList[$_.Name] = $searchResult | Select-Object -Last 10
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
            $maxLineLength = [Math]::Max($MIN_LINE_LENGTH, $maxKeyLength + 30)

            Write-Host "`nAvailable Extensions by Category:"
            Write-Host    "--------------------------------"
            $availableExtensionsPartialList.GetEnumerator() | Sort-Object Key | ForEach-Object {
                $key  = "$($_.Key) "
                $vals = ($_.Value | ForEach-Object { $_.extName }) -join ", "

                $line  = $key.PadRight($maxLineLength, '.') + " $vals"
                Write-Host $line
            }
            
            $msg = "`nThis is a partial list. For a complete list, visit:"
            $msg += "`nPHP Extensions : $PECL_PACKAGES_URL"
            $msg += "`nXDebug : $XDEBUG_HISTORICAL_URL"
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
    param ( $action, $params, $arch = $null )

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
                
                Write-Host "`nEnabling extension(s): $($params -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Enable-IniExtension -iniPath $iniPath -extName $extName
                }
            }
            "disable" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini disable xdebug)."
                    return -1
                }
                
                Write-Host "`nDisabling extension(s): $($params -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Disable-IniExtension -iniPath $iniPath -extName $extName
                }
            }
            "status" {
                if ($params.Count -eq 0) {
                    Write-Host "`nPlease specify at least one extension (pvm ini status opcache)."
                    return -1
                }
                
                Write-Host "`nChecking status of extension(s): $($params -join ', ')"
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
                
                Write-Host "`nInstalling extension(s): $($params -join ', ')"
                foreach ($extName in $params) {
                    $exitCode = Install-IniExtension -iniPath $iniPath -extName $extName -arch $arch
                }
            }
            "list" {
                $term = ($params | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
                $exitCode = List-PHP-Extensions -iniPath $iniPath -available ($params -contains "available") -term $term
            }
            default {
                Write-Host "`nUnknown action '$action' use one of following: 'info', 'get', 'set', 'enable', 'disable', 'status', 'install', 'list' or 'restore'."
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