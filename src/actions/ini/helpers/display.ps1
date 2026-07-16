
function Show-Extensions-States {
    param ($extensions)

    # Pre-count for summary
    $enabledCount = @($extensions | Where-Object { $_.enabled }).Count
    $disabledCount = $extensions.Count - $enabledCount

    Show-Host -message "`n- Total Extensions`t`t: Enabled: $enabledCount  |  Disabled: $disabledCount  |  Total: $($extensions.Count)`n"
}

function Show-Installed-Extensions {
    param ($extensions)

    if ($extensions.Count -eq 0) {
        Show-Error -message '  No extensions found.'
        return
    }

    # Calculate max length dynamically
    $maxNameLength = ($extensions | ForEach-Object { $_.name } | Measure-Object -Maximum Length).Maximum
    $maxLineLength = [Math]::Max($PVMConfig.env.MIN_LINE_LENGTH, $maxNameLength + 40)

    $extensions |
    Sort-Object @{Expression = { -not $_.enabled }; Ascending = $true },
    @{Expression = { $_.name }; Ascending = $true } |
    ForEach-Object {
        $label = "  $($_.name) ".PadRight($maxLineLength, '.')
        $status = if ($_.enabled) { 'Enabled' } else { 'Disabled' }
        $color = if ($_.enabled) { 'DarkGreen' } else { 'DarkYellow' }
        if ($_.comment) {
            $status = "$status - $($_.comment)"
        }

        Show-Host -message "$label " -noNewLine
        Write-Color -message $status -foreColor $color
    }
}

function Show-Settings-States {
    param ($settings)

    # Pre-count for summary
    $enabledCount = @($settings | Where-Object { $_.enabled }).Count
    $disabledCount = $settings.Count - $enabledCount

    Show-Host -message "`n- Total Settings`t`t: Enabled: $enabledCount  |  Disabled: $disabledCount  |  Total: $($settings.Count)`n"
}

function Show-Settings {
    param ($settings)

    if ($settings.Count -eq 0) {
        Show-Error -message '  No settings found.'
        return
    }

    $maxLineLength = ($settings | ForEach-Object { $_.name.Length + $_.value.Length } | Measure-Object -Maximum).Maximum
    $maxLineLength = [Math]::Max($PVMConfig.env.MIN_LINE_LENGTH, $maxLineLength + 40)

    $settings |
    Sort-Object @{Expression = { -not $_.enabled }; Ascending = $true },
    @{Expression = { $_.name }; Ascending = $true } |
    ForEach-Object {
        # $value = " $($_.value) "
        $value = if ($_.value -eq '') { '(not set) ' } elseif ($null -eq $_.value) { '' } else { "$($_.value) " }
        $line = "  - $($_.name) ".PadRight($maxLineLength - $value.Length, '.')
        $status = if ($_.enabled) { 'Enabled' } else { 'Disabled' }
        $color = if ($_.enabled) { 'DarkGreen' } else { 'DarkYellow' }
        if ($_.comment) {
            $status = "$status - $($_.comment)"
        }

        Show-Host -message "$line $value" -noNewLine
        Write-Color -message $status -foreColor $color
    }
}
