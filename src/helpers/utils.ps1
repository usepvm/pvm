
# ============================================================================
# SYSTEM INFORMATION
# ============================================================================

function Test-OS64Bit {
    return [System.Environment]::Is64BitOperatingSystem
}

function Get-ConsoleWidth {
    return $Host.UI.RawUI.WindowSize.Width
}

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    return $isAdmin
}

function Test-NotAdmin {
    return -not (Test-Admin)
}

# ============================================================================
# DATA CONVERSION
# ============================================================================

function Convert-MegabytesToBytes {
    param ($megabytes)

    $megabytes = [int]$megabytes

    if ($megabytes -le 0) {
        return 0
    }

    return [int64]($megabytes * 1MB)
}

function Convert-BytesToMegabytes {
    param ($bytes)

    if ($bytes -le 0) {
        return 0
    }

    return [math]::Round($bytes / 1MB, 2)
}

# ============================================================================
# VALIDATION AND TESTING
# ============================================================================

function Test-YesResponse {
    param ($response)

    return ($response -eq 'y' -or $response -eq 'Y')
}

function Test-NoResponse {
    param ($response)

    return -not (Test-YesResponse -response $response)
}

function Test-IsNotQuiet {
    param ($verbosity)

    return ($verbosity -ne 'None')
}

# ============================================================================
# STRING AND URL PARSING
# ============================================================================

function Get-BaseUrl {
    param ($url)

    return ([System.Uri]$url).Host
}

function ConvertTo-EnvEntries {
    param ($value, [switch]$removeDuplicates)

    if ($removeDuplicates) {
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    $rebuiltValue = foreach ($item in $value -split ';') {
        $trimmedItem = $item.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedItem)) { continue }
        if ($removeDuplicates -and -not $seen.Add($trimmedItem)) { continue }

        $trimmedItem
    }

    return ($rebuiltValue -join ';')
}

function Format-EnvContent {
    param ($value)

   return ConvertTo-EnvEntries -value $value
}

function Remove-PathDuplicates {
    param ($path)

    return ConvertTo-EnvEntries -value $path -RemoveDuplicates
}

# ============================================================================
# OBJECT UTILITIES
# ============================================================================

function Copy-ObjectDeep {
    param($object)

    if ($null -eq $object) {
        return $null
    }

    if ($object -is [System.Collections.Specialized.OrderedDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $object.Keys) {
            $copy[$key] = Copy-ObjectDeep -object $object[$key]
        }
        return $copy
    }

    if ($object -is [hashtable]) {
        $copy = @{}
        foreach ($key in $object.Keys) {
            $copy[$key] = Copy-ObjectDeep -object $object[$key]
        }
        return $copy
    }

    if ($object -is [array]) {
        return @($object | ForEach-Object -Process { Copy-ObjectDeep -object $_ })
    }

    if ($object -is [scriptblock]) {
        # Recreate a new scriptblock
        return [scriptblock]::Create($object.ToString())
    }

    if ($object -is [System.Management.Automation.PSCustomObject]) {
        $copy = [PSCustomObject]@{}
        foreach ($prop in $object.PSObject.Properties) {
            $copy | Add-Member -MemberType NoteProperty -Name $prop.Name -Value (Copy-ObjectDeep -object $prop.Value)
        }
        return $copy
    }

    return $object
}

# ============================================================================
# TIME FORMATTING
# ============================================================================

function Format-Seconds {
    param ($totalSeconds)

    try {
        if ($null -ne $totalSeconds) {
            $totalSeconds = [Single] $totalSeconds
        }

        if ($null -eq $totalSeconds -or $totalSeconds -lt 0) {
            $totalSeconds = 0
        }

        if ($totalSeconds -lt 60) {
            $rounded = [math]::Round($totalSeconds, 1)
            return '{0}s' -f $rounded
        }

        $hours = [int][math]::Floor($totalSeconds / 3600)
        $minutes = [int][math]::Floor(($totalSeconds % 3600) / 60)
        $seconds = [int][math]::Floor($totalSeconds % 60)

        if ($hours -gt 0) {
            return '{0:D2}:{1:D2}:{2:D2}' -f $hours, $minutes, $seconds
        }

        return '{0:D2}:{1:D2}' -f $minutes, $seconds
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to format seconds"; exception = $_ }
        return -1
    }
}

# ============================================================================
# BINARY ANALYSIS
# ============================================================================

function Get-BinaryArchitectureFromDLL {
    param ($path)

    if (Test-FileNotExists -path $path) {
        return 'Unknown'
    }

    $bytes = [System.IO.File]::ReadAllBytes($path)

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)

    $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)

    switch ($machine) {
        0x8664 { 'x64' }
        0x014c { 'x86' }
        default { 'Unknown' }
    }
}
