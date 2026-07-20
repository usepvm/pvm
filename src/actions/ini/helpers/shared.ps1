
function Backup-IniFile {
    param ($iniPath)

    try {
        $backup = "$iniPath.bak"
        if (Test-FileNotExists -path $backup) {
            Copy-Item -Path $iniPath $backup
        }
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to backup ini file"; exception = $_ }
        return -1
    }
}

function Get-AllPHPExtensionsStatus {
    param ($iniPath, $includeIniOnly = $false)

    $enabledPattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?(?<ext>[^\s`"';]*)\2\s*(;.*)?$"
    $disabledPattern = "^\s*;\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?(?<ext>[^\s`"';]*)\2\s*(;.*)?$"
    $null = Backup-IniFile -iniPath $iniPath
    $lines = Get-Content -Path $iniPath

    $matchesList = @()
    $matchesInExt = @()

    # helper to normalize extension identifiers for comparison
    $normalizeId = {
        param ($n)
        if (-not $n) { return '' }
        $s = $n.ToString()
        $s = $s.Trim('"', "'")
        $s = [System.IO.Path]::GetFileName($s)
        $s = $s -replace '^php_', '' -replace '\.dll$', ''
        return $s.ToLower()
    }

    # Step 1: All dlls in ext directory
    $phpDirectory = Split-Path -Path $iniPath -Parent
    $extDirectory = "$phpDirectory\ext"

    if (Test-DirectoryExists -path $extDirectory) {
        $dllFiles = Get-ChildItem -Path $extDirectory -Filter '*.dll' -File -ErrorAction SilentlyContinue
        foreach ($file in $dllFiles) {
            $fileId = & $normalizeId $file.BaseName
            if (-not $fileId) { continue }
            $matchesInExt += @{
                name     = $file.BaseName
                id       = $fileId
                fullPath = $file.FullName
                fileName = $file.Name
            }
        }
    }

    # Step 2: Full ini scan
    $lineNumber = 1
    $iniMatches = @{}

    foreach ($line in $lines) {
        if ($line -match $enabledPattern) {
            $displayName = $matches['ext'].Trim('"', "'")
            $id = & $normalizeId $displayName
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
            $id = & $normalizeId $displayName
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
            }
        } else {
            $isZendExtension = Get-ZendExtensionsList | Where-Object { $extMatch.name -like "*$_*" }
            $extensionLine = if ($isZendExtension) { ";zend_extension=$($extMatch.name).dll" } else { ";extension=$($extMatch.name).dll" }

            try {
                $lines += $extensionLine
                Set-Content -Path $iniPath -Value $lines -Encoding UTF8
                $matchesList += @{
                    name       = $extMatch.name
                    id         = $id
                    status     = 'Disabled'
                    enabled    = $false
                    color      = 'DarkYellow'
                    line       = $extensionLine
                    lineNumber = $lines.Count
                    source     = 'ext,ini'
                    fullPath   = $extMatch.fullPath
                    fileName   = $extMatch.fileName
                }
            } catch {
                $matchesList += @{
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
                }
            }
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
    param ($iniPath, $extName, $includeIniOnly = $false)

    if ([string]::IsNullOrWhiteSpace($extName)) {
        return @()
    }

    $searchId = $extName.Trim('"', "'").ToLower() -replace '^php_', '' -replace '\.dll$', ''

    return Get-AllPHPExtensionsStatus -iniPath $iniPath -includeIniOnly $includeIniOnly | Where-Object {
        $_.name -like "*$extName*" -or $_.id -like "*$searchId*"
    }
}

function Get-AllPHPSettings {
    param ($iniPath)

    $pattern = '^(?<comment>[#;])?\s*(?<key>[^=\s]+)\s*=\s*(?<value>.*)$'

    $lines = Get-Content -Path $iniPath
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

    return @(Get-AllPHPSettings -iniPath $iniPath) | Where-Object {
        $_.name -like "*$searchKey*"
    }
}
