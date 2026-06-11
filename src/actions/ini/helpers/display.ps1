
function Display-Extensions-States {
    param ($extensions)

    # Pre-count for summary
    $enabledCount = @($extensions | Where-Object Enabled).Count
    $disabledCount = $extensions.Count - $enabledCount

    Write-Host "`n- Extensions`t`t: Enabled: $enabledCount  |  Disabled: $disabledCount  |  Total: $($extensions.Count)`n"
}

function Display-Installed-Extensions {
    param ($extensions)

    if ($extensions.Count -eq 0) {
        Write-Host '  No extensions found matching the search term.' -ForegroundColor DarkGray
        return
    }

    # Calculate max length dynamically
    $MIN_LINE_LENGTH = 60
    $maxNameLength = ($extensions.Extension | Measure-Object -Maximum Length).Maximum
    $maxLineLength = [Math]::Max($MIN_LINE_LENGTH, $maxNameLength + 40)

    $extensions |
    Sort-Object @{Expression = { -not $_.Enabled }; Ascending = $true },
                @{Expression = { $_.Extension }; Ascending = $true } |
    ForEach-Object {
        $label = "  $($_.Extension) "
        $label = $label.PadRight($maxLineLength, '.')

        if ($_.Enabled) {
            $status = 'Enabled'
            $color = 'DarkGreen'
        } else {
            $status = 'Disabled'
            $color = 'DarkGray'
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

    if ($settings.Count -eq 0) {
        Write-Host '  No settings found matching the search term.' -ForegroundColor DarkGray
        return
    }

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
            $status = 'Enabled'
            $color = 'DarkGreen'
        } else {
            $status = 'Disabled'
            $color = 'DarkGray'
        }

        Write-Host $line -NoNewline
        Write-Host $status -ForegroundColor $color
    }
}
