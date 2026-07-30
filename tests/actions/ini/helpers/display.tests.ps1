
BeforeAll {
    Mock Show-Message {}
    Mock Show-Error {}
    Mock Write-Color {}
}

Describe "Show-ExtensionsStates" {
    It "Displays correct counts when all extensions are enabled" {
        $extensions = @(
            @{ Extension = 'curl'; Enabled = $true }
            @{ Extension = 'opcache'; Enabled = $true }
        )
        Show-ExtensionsStates -extensions $extensions
        Should -Invoke Show-Message -Times 1 -ParameterFilter {
            $message -match 'Enabled: 2' -and
            $message -match 'Disabled: 0' -and
            $message -match 'Total: 2'
        }
    }

    It "Displays correct counts when all extensions are disabled" {
        $extensions = @(
            @{ Extension = 'xdebug'; Enabled = $false }
        )
        Show-ExtensionsStates -extensions $extensions
        Should -Invoke Show-Message -Times 1 -ParameterFilter {
            $message -match 'Enabled: 0' -and
            $message -match 'Disabled: 1' -and
            $message -match 'Total: 1'
        }
    }

    It "Displays correct counts with mixed enabled and disabled extensions" {
        $extensions = @(
            @{ Extension = 'curl'; Enabled = $true }
            @{ Extension = 'xdebug'; Enabled = $false }
            @{ Extension = 'opcache'; Enabled = $true }
        )
        Show-ExtensionsStates -extensions $extensions
        Should -Invoke Show-Message -Times 1 -ParameterFilter {
            $message -match 'Enabled: 2' -and
            $message -match 'Disabled: 1' -and
            $message -match 'Total: 3'
        }
    }
}

Describe "Show-InstalledExtensions" {
    It "Displays message when extensions array is empty" {
        $extensions = @()
        Show-InstalledExtensions -extensions $extensions
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq '  No extensions found.'
        }
    }

    It "Displays extensions when array is not empty" {
        $extensions = @(
            @{ Extension = 'curl'; Enabled = $true }
            @{ Extension = 'opcache'; comment = 'Available (not configured)'; Enabled = $false }
        )
        Show-InstalledExtensions -extensions $extensions
        Should -Invoke Show-Message -Times 2
        Should -Invoke Write-Color -Times 2
    }
}

Describe "Show-SettingsStates" {
    It "Displays correct counts when all settings are enabled" {
        $settings = @(
            @{ Name = 'display_errors'; Value = 'On'; Enabled = $true }
            @{ Name = 'short_open_tag'; Value = 'Off'; Enabled = $true }
        )
        Show-SettingsStates -settings $settings
        Should -Invoke Show-Message -Times 1 -ParameterFilter {
            $message -match 'Enabled: 2' -and
            $message -match 'Disabled: 0' -and
            $message -match 'Total: 2'
        }
    }

    It "Displays correct counts when all settings are disabled" {
        $settings = @(
            @{ Name = 'display_errors'; Value = 'Off'; Enabled = $false }
        )
        Show-SettingsStates -settings $settings
        Should -Invoke Show-Message -Times 1 -ParameterFilter {
            $message -match 'Enabled: 0' -and
            $message -match 'Disabled: 1' -and
            $message -match 'Total: 1'
        }
    }

    It "Displays correct counts with mixed enabled and disabled settings" {
        $settings = @(
            @{ Name = 'display_errors'; Value = 'On'; Enabled = $true }
            @{ Name = 'short_open_tag'; Value = 'Off'; Enabled = $false }
            @{ Name = 'error_reporting'; Value = 'E_ALL'; Enabled = $true }
        )
        Show-SettingsStates -settings $settings
        Should -Invoke Show-Message -Times 1 -ParameterFilter {
            $message -match 'Enabled: 2' -and
            $message -match 'Disabled: 1' -and
            $message -match 'Total: 3'
        }
    }
}

Describe "Show-Settings" {
    It "Displays message when settings array is empty" {
        $settings = @()
        Show-Settings -settings $settings
        Should -Invoke Show-Error -Times 1 -ParameterFilter {
            $message -eq '  No settings found.'
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
        Should -Invoke Show-Message -Times 2
        Should -Invoke Write-Color -Times 2
    }
}
