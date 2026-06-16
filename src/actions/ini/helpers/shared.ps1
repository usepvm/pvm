
function Backup-IniFile {
    param ($iniPath)

    try {
        $backup = "$iniPath.bak"
        if (Is-File-Not-Exists -path $backup) {
            Copy-Item -Path $iniPath $backup
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to backup ini file"; exception = $_ }
        return -1
    }
}

function Get-Matching-PHPExtensionsStatus {
    param ($iniPath, $extName)

    $enabledPattern = "^\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?(?<ext>[^\s`"';]*$extName[^\s`"';]*)\2\s*(;.*)?$"
    $disabledPattern = "^\s*;\s*(zend_)?extension\s*=\s*([`"']?)([^\s`"';]*[/\\])?(?<ext>[^\s`"';]*$extName[^\s`"';]*)\2\s*(;.*)?$"
    Backup-IniFile -iniPath $iniPath
    $lines = Get-Content -Path $iniPath

    $matchesList = @()
    $matchesInExt = @()

    # helper to normalize extension identifiers for comparison
    $normalizeId = {
        param ($n)
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
    $extDirectory = "$phpDirectory\ext"

    if (Is-Directory-Exists -path $extDirectory) {
        $dllPattern = if ($searchId) { "*$searchId*.dll" } else { '*.dll' }
        $dllFiles = Get-ChildItem -Path $extDirectory -Filter $dllPattern -File -ErrorAction SilentlyContinue
        foreach ($file in $dllFiles) {
            $fileId = & $normalizeId $file.BaseName
            if (-not $fileId) { continue }

            $matchesInExt += @{
                name = $file.BaseName
                id = $fileId
                fullPath = $file.FullName
                fileName = $file.Name
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
                status = 'Enabled'
                color = 'DarkGreen'
                line = $line
                lineNumber = $lineNumber
                source = 'ini'
            }
        }
        if ($line -match $disabledPattern) {
            $rawExt = $matches['ext']
            $displayName = ($rawExt).Trim('"', "'")
            $id = & $normalizeId $displayName
            if (-not $id) { $lineNumber++; continue }

            $iniMatches[$id] = @{
                name = $displayName
                status = 'Disabled'
                color = 'DarkYellow'
                line = $line
                lineNumber = $lineNumber
                source = 'ini'
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
                source = 'ext,ini'
                fullPath = $extMatch.fullPath
                fileName = $extMatch.fileName
            }
        } else {
            # Extension exists in ext but not configured in ini - add it as disabled
            $isZendExtension = Get-Zend-Extensions-List | Where-Object { $extMatch.name -like "*$_*" }
            $extensionLine = if ($isZendExtension) { ";zend_extension=$($extMatch.name).dll" } else { ";extension=$($extMatch.name).dll" }

            try {
                $lines += $extensionLine
                Set-Content -Path $iniPath $lines -Encoding UTF8

                $matchesList += @{
                    name = $extMatch.name
                    id = $id
                    status = 'Disabled'
                    color = 'DarkYellow'
                    line = $extensionLine
                    lineNumber = $lines.Count
                    source = 'ext,ini'
                    fullPath = $extMatch.fullPath
                    fileName = $extMatch.fileName
                }
            } catch {
                # If adding fails, still return it as available
                $matchesList += @{
                    name = $extMatch.name
                    id = $id
                    status = 'Available (not configured)'
                    color = 'DarkCyan'
                    line = 'Found in ext directory: $($extMatch.fullPath)'
                    lineNumber = 0
                    source = 'ext'
                    fullPath = $extMatch.fullPath
                    fileName = $extMatch.fileName
                }
            }
        }
    }

    return $matchesList
}
