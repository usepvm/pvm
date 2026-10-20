
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

    $flag = $arguments | Where-Object -FilterScript { $flagMap.Contains($_) } | Select-Object -First 1

    if ($flag) {
        return $flagMap[$flag]
    }

    return $null
}

function Get-ArgumentOptionSelection {
    param ($arguments, [string[]]$options)

    $values = @(
        @($arguments) |
            Where-Object -FilterScript { $options -contains $_ } |
            ForEach-Object -Process { $_.ToLowerInvariant() } |
            Select-Object -Unique
    )

    return [pscustomobject]@{
        value      = if ($values.Count -eq 1) { $values[0] } else { $null }
        conflicts  = if ($values.Count -gt 1) { $values } else { @() }
    }
}

function Get-ArgumentOptionConflicts {
    param ($arguments)

    $selections = @(
        [pscustomobject]@{
            name = 'architecture'
            selection = Get-ArgumentOptionSelection -arguments $arguments -options @('x86', 'x64')
        }
        [pscustomobject]@{
            name = 'build type'
            selection = Get-ArgumentOptionSelection -arguments $arguments -options @('ts', 'nts')
        }
    )

    return @(
        $selections | Where-Object -FilterScript { $_.selection.conflicts.Count -gt 0 } |
            ForEach-Object -Process {
                [pscustomobject]@{
                    name = $_.name
                    values = $_.selection.conflicts
                }
            }
    )
}

function Resolve-BuildType {
    param ($arguments, $choseDefault = $false)

    $selection = Get-ArgumentOptionSelection -arguments $arguments -options @('ts', 'nts')
    $buildType = $selection.value

    if ($null -eq $buildType -and $choseDefault) {
        if ($selection.conflicts.Count -eq 0) {
            $buildType = 'ts'
        }
    }

    return $buildType
}

function Resolve-Arch {
    param ($arguments, $choseDefault = $false)

    $selection = Get-ArgumentOptionSelection -arguments $arguments -options @('x86', 'x64')
    $arch = $selection.value

    if ($null -eq $arch -and $choseDefault) {
        if ($selection.conflicts.Count -eq 0) {
            $arch = if (Test-OS64Bit) { 'x64' } else { 'x86' }
        }
    }

    return $arch
}

function Resolve-VersionsFromArguments {
    param ($arguments)

    $versions = $arguments | Where-Object -FilterScript { $_ -match '^\d+(\.\d+){0,2}$' }

    return $versions
}
