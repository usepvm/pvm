
function Resolve-Alias {
    param ($alias)

    if ([string]::IsNullOrWhiteSpace($alias)) {
        return $null
    }

    $alias = $alias.Trim().ToLower()
    $aliases = Get-Aliases

    if ($null -eq $aliases -or $aliases.Count -eq 0) {
        return $alias
    }

    if ($aliases.Contains($alias)) {
        return $aliases[$alias]
    }

    return $alias
}

function Resolve-FlagCommand {
    param ($arguments)

    $flagMap = Get-FlagMap

    $flag = $arguments | Where-Object { $flagMap.Contains($_) } | Select-Object -First 1

    if ($flag) {
        return $flagMap[$flag]
    }

    return $null
}

function Resolve-BuildType {
    param ($arguments, $choseDefault = $false)

    $buildType = $arguments | Where-Object { @('ts', 'nts') -contains $_ } | Select-Object -First 1

    if ($null -eq $buildType -and $choseDefault) {
        $buildType = 'ts';
    }

    if ($null -ne $buildType) {
        $buildType = $buildType.ToLower()
    }

    return $buildType
}

function Resolve-Arch {
    param ($arguments, $choseDefault = $false)

    $arch = $arguments | Where-Object { @('x86', 'x64') -contains $_ } | Select-Object -First 1

    if ($null -eq $arch -and $choseDefault) {
        $arch = if (Test-OS64Bit) { 'x64' } else { 'x86' }
    }

    if ($null -ne $arch) {
        $arch = $arch.ToLower()
    }

    return $arch
}
