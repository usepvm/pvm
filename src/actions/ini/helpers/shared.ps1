
function ConvertTo-ExtensionId {
    param ($name)

    if ([string]::IsNullOrWhiteSpace($name)) { return '' }

    $s = $name.ToString()
    $s = $s.Trim('"', "'")
    $s = [System.IO.Path]::GetFileName($s)
    $s = $s -replace '^php_', '' -replace '\.dll$', '' -replace '-[\d\.]+.*$', ''
    return $s.ToLower()
}

function Backup-IniFile {
    param ($iniPath)

    try {
        $phpDirectory = Split-Path -Path $iniPath -Parent
        $iniBackupPath = "$phpDirectory\$($Global:PVMConfig.constants.INI_BACKUP_DIR_NAME)"

        $created = New-Directory -path $iniBackupPath
        if ($created -ne 0) {
            return -1
        }

        $now = Get-Date -Format 'yyyy-MM-dd_HH-mm'
        $backup = "$iniBackupPath\php.ini_$($now).bak"
        if (Test-FileNotExists -path $backup) {
            Copy-ItemWrapper -path $iniPath -destination $backup
        }

        $null = Clear-IniBackups -iniBackupPath $iniBackupPath

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to backup ini file"; exception = $_ }
        return -1
    }
}

function Clear-IniBackups {
    param ($iniBackupPath)

    try {
        if (Test-DirectoryNotExists -path $iniBackupPath) {
            return -1
        }

        $backupFiles = Get-ChildItemWrapper -path $iniBackupPath -filter 'php.ini_*.bak' -file

        if (-not $backupFiles -or $backupFiles.Count -eq 0) {
            return -1
        }

        $cutoffDate = (Get-Date).AddDays(-$Global:PVMConfig.env.INI_BACKUP_MAX_DAYS)

        $sortedFiles = $backupFiles | Sort-Object -Property CreationTime -Descending
        $filesToDelete = @()

        for ($i = 0; $i -lt $sortedFiles.Count; $i++) {
            $file = $sortedFiles[$i]

            if ($i -ge $Global:PVMConfig.env.INI_BACKUP_KEEP_COUNT -and $file.CreationTime -lt $cutoffDate) {
                $filesToDelete += $file
            }
        }

        foreach ($file in $filesToDelete) {
            Remove-ItemWrapper -path $file.FullName
        }

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to cleanup ini backups"; exception = $_ }
        return -1
    }
}

function Get-AllPHPExtensionsStatus {
    param ($iniPath, $includeIniOnly = $false, $addToIniFileIfMissing = $true)

    $enabledPattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?(?<ext>[^\s`"';]*)\2\s*(;.*)?$"
    $disabledPattern = "^\s*;\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?(?<ext>[^\s`"';]*)\2\s*(;.*)?$"
    $null = Backup-IniFile -iniPath $iniPath

    $matchesInExt = @()

    # Step 1: All dlls in ext directory
    $phpDirectory = Split-Path -Path $iniPath -Parent
    $extDirectory = "$phpDirectory\ext"

    if (Test-DirectoryExists -path $extDirectory) {
        $dllFiles = Get-ChildItemWrapper -path $extDirectory -filter '*.dll' -file
        foreach ($file in $dllFiles) {
            $fileId = ConvertTo-ExtensionId -name $file.BaseName
            if (-not $fileId) { continue }
            $matchesInExt += @{
                name     = $file.BaseName
                id       = $fileId
                fullPath = $file.FullName
                fileName = $file.Name
                version  = $file.VersionInfo.ProductVersion
                copyRight = $file.VersionInfo.LegalCopyright
            }
        }
    }

    # Step 2: Full ini scan
    $lineNumber = 1
    $iniMatches = @{}

    $lines = Get-ContentWrapper -path $iniPath
    foreach ($line in $lines) {
        if ($line -match $enabledPattern) {
            $displayName = $matches['ext'].Trim('"', "'")
            $id = ConvertTo-ExtensionId -name $displayName
            if (-not $id) { $lineNumber++; continue }
            $iniMatches[$id] = @{
                name       = $displayName
                status     = 'Enabled'
                enabled    = $true
                color      = 'DarkGreen'
                line       = $line
                lineNumber = $lineNumber
            }
        }
        if ($line -match $disabledPattern) {
            $displayName = $matches['ext'].Trim('"', "'")
            $id = ConvertTo-ExtensionId -name $displayName
            if (-not $id) { $lineNumber++; continue }
            $iniMatches[$id] = @{
                name       = $displayName
                status     = 'Disabled'
                enabled    = $false
                color      = 'DarkYellow'
                line       = $line
                lineNumber = $lineNumber
            }
        }
        $lineNumber++
    }

    # Step 3: Merge ext+ini
    $coveredIds = @{}
    $matchesList = @()
    foreach ($extMatch in $matchesInExt) {
        $id = $extMatch.id
        $coveredIds[$id] = $true

        if ($iniMatches.ContainsKey($id)) {
            $matchesList += @{
                name       = $iniMatches[$id].name
                id         = $id
                status     = $iniMatches[$id].status
                enabled    = $iniMatches[$id].enabled
                color      = $iniMatches[$id].color
                line       = $iniMatches[$id].line
                lineNumber = $iniMatches[$id].lineNumber
                source     = 'ext,ini'
                fullPath   = $extMatch.fullPath
                fileName   = $extMatch.fileName
                version    = $extMatch.version
                copyRight  = $extMatch.copyRight
            }
        } else {
            $isZendExtension = Get-ZendExtensionsList | Where-Object -FilterScript { $extMatch.name -like "*$_*" }
            $extensionLine = if ($isZendExtension) { ";zend_extension=$($extMatch.name).dll" } else { ";extension=$($extMatch.name).dll" }

            $entry = @{
                name       = $extMatch.name
                id         = $id
                status     = 'Disabled'
                enabled    = $false
                comment    = 'Available (not configured)'
                color      = 'DarkCyan'
                line       = "Found in ext directory: $($extMatch.fullPath)"
                lineNumber = 0
                source     = 'ext'
                fullPath   = $extMatch.fullPath
                fileName   = $extMatch.fileName
                version    = $extMatch.version
                copyRight  = $extMatch.copyRight
            }

            if ($addToIniFileIfMissing) {
                try {
                    $lines += $extensionLine
                    Set-ContentWrapper -path $iniPath -value $lines
                    $entry.color      = 'DarkYellow'
                    $entry.line       = $extensionLine
                    $entry.lineNumber = $lines.Count
                    $entry.source     = 'ext,ini'
                    $entry.Remove('comment')
                } catch {}
            }

            $matchesList += $entry
        }
    }

    if ($includeIniOnly) {
        # Step 4: ini-only entries
        foreach ($id in $iniMatches.Keys) {
            if ($coveredIds.ContainsKey($id)) { continue }
            $entry = $iniMatches[$id]
            $matchesList += @{
                name       = $entry.name
                id         = $id
                status     = $entry.status
                enabled    = $entry.enabled
                comment    = 'DLL file not found'
                color      = $entry.color
                line       = $entry.line
                lineNumber = $entry.lineNumber
                source     = 'ini'
                fullPath   = $null
                fileName   = $null
            }
        }
    }

    return $matchesList
}

function Get-MatchingPHPExtensionsStatus {
    param ($iniPath, $extName, $includeIniOnly = $false, $addToIniFileIfMissing = $true)

    if ([string]::IsNullOrWhiteSpace($extName)) {
        return @()
    }

    $searchId = ConvertTo-ExtensionId -name $extName

    $allExtensions = @(Get-AllPHPExtensionsStatus -iniPath $iniPath -includeIniOnly $includeIniOnly -addToIniFileIfMissing $addToIniFileIfMissing)
    $extensionsMatches = $allExtensions | Where-Object -FilterScript {
        $_.name -like "*$extName*" -or $_.id -like "*$searchId*"
    }

    return $extensionsMatches
}

function Get-AllPHPSettings {
    param ($iniPath)

    $pattern = '^(?<comment>[#;])?\s*(?<key>[^=\s]+)\s*=\s*(?<value>.*)$'

    $lines = Get-ContentWrapper -path $iniPath
    $results = @()
    $lineNo = 0

    foreach ($line in $lines) {
        if ($line -match $pattern) {
            $isEnabled = -not $matches['comment']
            $results += @{
                name    = $matches['key'].Trim()
                value   = $matches['value'].Trim()
                enabled = $isEnabled
                status  = if ($isEnabled) { 'Enabled' } else { 'Disabled' }
                color   = if ($isEnabled) { 'DarkGreen' } else { 'DarkYellow' }
                line    = $line
                lineNo  = $lineNo
            }
        }
        $lineNo++
    }

    return $results
}

function Get-MatchingPHPSettings {
    param ($iniPath, $searchKey = '')

    if (-not $searchKey) {
        return @()
    }

    $allSettings = @(Get-AllPHPSettings -iniPath $iniPath)
    $settingsMatches = $allSettings | Where-Object -FilterScript {
        $_.name -like "*$searchKey*"
    }

    return $settingsMatches
}
