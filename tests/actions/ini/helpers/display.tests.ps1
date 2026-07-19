
BeforeAll {
    Mock Write-Host {}
}

Describe "Show-Extensions-States" {
    It "Displays correct counts when all extensions are enabled" {
        $extensions = @(
            @{ Extension = 'curl'; Enabled = $true }
            @{ Extension = 'opcache'; Enabled = $true }
        )
        Show-Extensions-States -extensions $extensions
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -match 'Enabled: 2' -and
            $Object -match 'Disabled: 0' -and
            $Object -match 'Total: 2'
        }
    }

    It "Displays correct counts when all extensions are disabled" {
        $extensions = @(
            @{ Extension = 'xdebug'; Enabled = $false }
        )
        Show-Extensions-States -extensions $extensions
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -match 'Enabled: 0' -and
            $Object -match 'Disabled: 1' -and
            $Object -match 'Total: 1'
        }
    }

    It "Displays correct counts with mixed enabled and disabled extensions" {
        $extensions = @(
            @{ Extension = 'curl'; Enabled = $true }
            @{ Extension = 'xdebug'; Enabled = $false }
            @{ Extension = 'opcache'; Enabled = $true }
        )
        Show-Extensions-States -extensions $extensions
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -match 'Enabled: 2' -and
            $Object -match 'Disabled: 1' -and
            $Object -match 'Total: 3'
        }
    }
}

Describe "Show-Installed-Extensions" {
    It "Displays message when extensions array is empty" {
        $extensions = @()
        Show-Installed-Extensions -extensions $extensions
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq '  No extensions found.'
        }
    }

    It "Displays extensions when array is not empty" {
        $extensions = @(
            @{ Extension = 'curl'; Enabled = $true }
            @{ Extension = 'opcache'; comment = 'Available (not configured)'; Enabled = $false }
        )
        Show-Installed-Extensions -extensions $extensions
        Should -Invoke Write-Host -Times 2
    }
}

Describe "Show-Settings-States" {
    It "Displays correct counts when all settings are enabled" {
        $settings = @(
            @{ Name = 'display_errors'; Value = 'On'; Enabled = $true }
            @{ Name = 'short_open_tag'; Value = 'Off'; Enabled = $true }
        )
        Show-Settings-States -settings $settings
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -match 'Enabled: 2' -and
            $Object -match 'Disabled: 0' -and
            $Object -match 'Total: 2'
        }
    }

    It "Displays correct counts when all settings are disabled" {
        $settings = @(
            @{ Name = 'display_errors'; Value = 'Off'; Enabled = $false }
        )
        Show-Settings-States -settings $settings
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -match 'Enabled: 0' -and
            $Object -match 'Disabled: 1' -and
            $Object -match 'Total: 1'
        }
    }

    It "Displays correct counts with mixed enabled and disabled settings" {
        $settings = @(
            @{ Name = 'display_errors'; Value = 'On'; Enabled = $true }
            @{ Name = 'short_open_tag'; Value = 'Off'; Enabled = $false }
            @{ Name = 'error_reporting'; Value = 'E_ALL'; Enabled = $true }
        )
        Show-Settings-States -settings $settings
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -match 'Enabled: 2' -and
            $Object -match 'Disabled: 1' -and
            $Object -match 'Total: 3'
        }
    }
}

Describe "Show-Settings" {
    It "Displays message when settings array is empty" {
        $settings = @()
        Show-Settings -settings $settings
        Should -Invoke Write-Host -Times 1 -ParameterFilter {
            $Object -eq '  No settings found.'
        }
    }

    It "Displays settings when array is not empty" {
        $settings = @(
            @{ Name = 'display_errors'; Value = 'On'; Enabled = $true }
            @{ Name = 'short_open_tag'; Value = 'Off'; Enabled = $false }
            @{ Name = 'error_reporting'; Value = $null; Enabled = $false }
            @{ Name = 'error_log'; Value = ''; comment = 'Deprecated' ; Enabled = $false }
        )
        Show-Settings -settings $settings
        Should -Invoke Write-Host -Times 4
    }
}
