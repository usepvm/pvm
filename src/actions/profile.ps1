
function Set-IniSetting-Direct {
    param ($iniPath, $settingName, $value, $enabled = $true)

    try {
        $lines = [string[]](Get-Content -Path $iniPath)
        $modified = $false
        $escapedName = [regex]::Escape($settingName)
        $exactPattern = "^[#;]?\s*$escapedName\s*=\s*(.*)$"

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match $exactPattern) {
                $newLine = if ($enabled) {
                    "$settingName = $value"
                } else {
                    ";$settingName = $value"
                }
                $lines[$i] = $newLine
                $modified = $true
                break
            }
        }

        if (-not $modified) {
            # Setting doesn't exist, add it at the end
            $newLine = if ($enabled) {
                "$settingName = $value"
            } else {
                ";$settingName = $value"
            }
            $lines += $newLine
        }

        Set-Content -Path $iniPath $lines -Encoding UTF8
        return 0
    } catch {
        return -1
    }
}

function Enable-IniExtension-Direct {
    param ($iniPath, $extName, $extType = 'extension')

    try {
        # Normalize extension name - remove php_ prefix and .dll suffix if present
        $extName = $extName -replace '^php_', '' -replace '\.dll$', ''
        $extFileName = "php_$extName.dll"

        $lines = [string[]](Get-Content -Path $iniPath)
        $modified = $false

        # Check for extension in multiple formats:
        # 1. extension=php_openssl.dll (full filename, may have path)
        # 2. extension=openssl (just the name without php_ prefix and .dll suffix)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $isMatch = $false

            # Match extension or zend_extension lines (commented or not)
            $pattern = if ($extType -eq 'zend_extension') {
                "^[#;]?\s*zend_extension\s*=\s*([`"']?)([^\s`"';]*)\1\s*(;.*)?$"
            } else {
                "^[#;]?\s*extension\s*=\s*([`"']?)([^\s`"';]*)\1\s*(;.*)?$"
            }

            if ($line -match $pattern) {
                $foundExt = $matches[2].Trim()
                # Extract just the filename if there's a path
                $foundExtFileName = [System.IO.Path]::GetFileName($foundExt)
                # Normalize: remove php_ prefix and .dll suffix to get base name
                $foundExtBaseName = $foundExtFileName -replace '^php_', '' -replace '\.dll$', ''

                # Also check the original value (for cases like extension=openssl)
                $foundExtBaseNameOriginal = $foundExt -replace '^php_', '' -replace '\.dll$', ''

                # Match if the normalized base name matches (handles both formats)
                if ($foundExtBaseName -eq $extName -or $foundExtBaseNameOriginal -eq $extName) {
                    $isMatch = $true
                }
            }

            if ($isMatch) {
                # Uncomment the line (remove leading ; or #)
                $lines[$i] = $line -replace '^[#;]\s*', ''
                $modified = $true
                break
            }
        }

        if (-not $modified) {
            # Extension doesn't exist, add it at the end
            $newLine = if ($extType -eq 'zend_extension') {
                "zend_extension=$extFileName"
            } else {
                "extension=$extFileName"
            }
            $lines += $newLine
        }

        Set-Content -Path $iniPath $lines -Encoding UTF8
        return 0
    } catch {
        return -1
    }
}

function Disable-IniExtension-Direct {
    param ($iniPath, $extName, $extType = 'extension')

    try {
        # Normalize extension name - remove php_ prefix and .dll suffix if present
        $extName = $extName -replace '^php_', '' -replace '\.dll$', ''

        $lines = [string[]](Get-Content -Path $iniPath)

        # Check for extension in multiple formats (only enabled/not commented lines):
        # 1. extension=php_openssl.dll (full filename, may have path)
        # 2. extension=openssl (just the name without php_ prefix and .dll suffix)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            # Skip commented lines
            if ($line -match '^\s*[#;]') {
                continue
            }

            $isMatch = $false

            # Match extension or zend_extension lines (must be enabled/not commented)
            $pattern = if ($extType -eq 'zend_extension') {
                "^\s*zend_extension\s*=\s*([`"']?)([^\s`"';]*)\1\s*(;.*)?$"
            } else {
                "^\s*extension\s*=\s*([`"']?)([^\s`"';]*)\1\s*(;.*)?$"
            }

            if ($line -match $pattern) {
                $foundExt = $matches[2].Trim()
                # Extract just the filename if there's a path
                $foundExtFileName = [System.IO.Path]::GetFileName($foundExt)
                # Normalize: remove php_ prefix and .dll suffix to get base name
                $foundExtBaseName = $foundExtFileName -replace '^php_', '' -replace '\.dll$', ''

                # Also check the original value (for cases like extension=openssl)
                $foundExtBaseNameOriginal = $foundExt -replace '^php_', '' -replace '\.dll$', ''

                # Match if the normalized base name matches (handles both formats)
                if ($foundExtBaseName -eq $extName -or $foundExtBaseNameOriginal -eq $extName) {
                    $isMatch = $true
                }
            }

            if ($isMatch) {
                # Comment out the line
                $lines[$i] = ";$line"
                break
            }
        }

        Set-Content -Path $iniPath $lines -Encoding UTF8
        return 0
    } catch {
        return -1
    }
}

function Get-Popular-PHP-Settings {
    try {
        # Return list of popular/common PHP settings that should be included in profiles
        if (Is-File-Exists -path $PVMConfig.paths.profileTemplate) {
            $data = (Get-Content -Path $PVMConfig.paths.profileTemplate -Raw | ConvertFrom-Json)
            if ($null -ne $data.settings -and $data.settings.Count -gt 0) {
                return $data.settings
            }
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get popular PHP settings"; exception = $_ }
    }

    return $PVMConfig.defaults.settings
}

function Get-Popular-PHP-Extensions {
    try {
        # Return list of popular/common PHP extensions that should be included in profiles
        if (Is-File-Exists -path $PVMConfig.paths.profileTemplate) {
            $data = (Get-Content -Path $PVMConfig.paths.profileTemplate -Raw | ConvertFrom-Json)
            if ($null -ne $data.extensions -and $data.extensions.Count -gt 0) {
                return $data.extensions
            }
        }
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get popular PHP extensions"; exception = $_ }
    }

    return $PVMConfig.defaults.extensions
}

function Save-PHP-Profile {
    param ($profileName, $description = $null)

    try {
        $currentPhpVersion = Get-Current-PHP-Version

        if (-not $currentPhpVersion -or -not $currentPhpVersion.version -or -not $currentPhpVersion.path) {
            Write-Host -Object "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }

        $iniPath = "$($currentPhpVersion.path)\php.ini"
        if (Is-File-Not-Exists -path $iniPath) {
            Write-Host -Object "`nphp.ini not found at: $($currentPhpVersion.path)" -ForegroundColor DarkYellow
            return -1
        }

        # Get current PHP configuration
        $phpIniData = Get-PHP-Data -PhpIniPath $iniPath

        # Build profile structure
        $userProfile = [ordered]@{
            name = $profileName
            description = if ($description) { $description } else { "Profile saved on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" }
            created = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
            phpVersion = $currentPhpVersion.version
            settings = [ordered]@{}
            extensions = [ordered]@{}
        }

        # Get popular settings and extensions lists
        $popularSettings = Get-Popular-PHP-Settings
        $popularExtensions = Get-Popular-PHP-Extensions

        # Extract only popular settings
        foreach ($setting in $phpIniData.settings) {
            if ($popularSettings -contains $setting.Name) {
                $userProfile.settings[$setting.Name] = @{
                    value = $setting.Value
                    enabled = $setting.Enabled
                }
            }
        }

        # Extract only popular extensions
        foreach ($ext in $phpIniData.extensions) {
            $extName = $ext.Extension -replace '^php_', '' -replace '\.dll$', ''
            if ($popularExtensions -contains $extName) {
                $userProfile.extensions[$extName] = @{
                    enabled = $ext.Enabled
                    type = $ext.Type  # "extension" or "zend_extension"
                }
            }
        }

        # Save to JSON file
        $created = Make-Directory -path $PVMConfig.paths.profiles
        if ($created -ne 0) {
            Write-Host -Object "`nFailed to create profiles directory." -ForegroundColor DarkYellow
            return -1
        }

        $profilePath = "$($PVMConfig.paths.profiles)\$profileName.json"
        $jsonContent = $userProfile | ConvertTo-Json -Depth 10
        Set-Content -Path $profilePath -Value $jsonContent -Encoding UTF8

        Write-Host -Object "`nProfile '$profileName' saved successfully." -ForegroundColor DarkGreen
        Write-Host -Object "  Settings: $($userProfile.settings.Count) (popular/common only)" -ForegroundColor Gray
        Write-Host -Object "  Extensions: $($userProfile.extensions.Count) (popular/common only)" -ForegroundColor Gray
        Write-Host -Object "  Location: $profilePath" -ForegroundColor Gray
        Write-Host -Object "`nNote: Only popular/common settings and extensions are saved." -ForegroundColor DarkCyan
        Write-Host -Object "      You can manually add other settings/extensions using 'pvm ini' commands." -ForegroundColor DarkCyan

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to save profile '$profileName'"; exception = $_ }
        Write-Host -Object "`nFailed to save profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Load-PHP-Profile {
    param ($profileName)

    try {
        $currentPhpVersion = Get-Current-PHP-Version

        if (-not $currentPhpVersion -or -not $currentPhpVersion.version -or -not $currentPhpVersion.path) {
            Write-Host -Object "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }

        $iniPath = "$($currentPhpVersion.path)\php.ini"
        if (Is-File-Not-Exists -path $iniPath) {
            Write-Host -Object "`nphp.ini not found at: $($currentPhpVersion.path)" -ForegroundColor DarkYellow
            return -1
        }

        # Load profile JSON
        $profilePath = "$($PVMConfig.paths.profiles)\$profileName.json"
        if (Is-File-Not-Exists -path $profilePath) {
            Write-Host -Object "`nProfile '$profileName' not found." -ForegroundColor DarkYellow
            Write-Host -Object "  Use 'pvm profile list' to see available profiles." -ForegroundColor Gray
            return -1
        }

        $jsonContent = Get-Content -Path $profilePath -Raw | ConvertFrom-Json

        Write-Host -Object "`nLoading profile '$($jsonContent.name)'..." -ForegroundColor Cyan
        if ($jsonContent.description) {
            Write-Host -Object "  Description: $($jsonContent.description)" -ForegroundColor Gray
        }
        Write-Host -Object "  Created: $($jsonContent.created)" -ForegroundColor Gray

        # Backup ini file before applying changes
        Backup-IniFile -iniPath $iniPath

        # Get popular lists to validate profile contents
        $popularSettings = Get-Popular-PHP-Settings
        $popularExtensions = Get-Popular-PHP-Extensions

        # Apply only popular settings (filter out any non-popular ones that might be in old profiles)
        # Use direct functions for exact name matching (no fuzzy matching or user interaction)
        $settingsApplied = 0
        $settingsSkipped = 0
        $settingsIgnored = 0
        foreach ($settingName in $jsonContent.settings.PSObject.Properties.Name) {
            if ($popularSettings -contains $settingName) {
                $setting = $jsonContent.settings.$settingName
                $result = Set-IniSetting-Direct -iniPath $iniPath -settingName $settingName -value $setting.value -enabled $setting.enabled
                if ($result -eq 0) {
                    $settingsApplied++
                } else {
                    $settingsSkipped++
                }
            } else {
                $settingsIgnored++
            }
        }

        # Apply only popular extensions (filter out any non-popular ones that might be in old profiles)
        # Use direct functions for exact name matching (no fuzzy matching or user interaction)
        $extensionsEnabled = 0
        $extensionsDisabled = 0
        $extensionsSkipped = 0
        $extensionsIgnored = 0
        foreach ($extName in $jsonContent.extensions.PSObject.Properties.Name) {
            if ($popularExtensions -contains $extName) {
                $ext = $jsonContent.extensions.$extName
                $extType = if ($ext.type) { $ext.type } else { 'extension' }
                if ($ext.enabled) {
                    $result = Enable-IniExtension-Direct -iniPath $iniPath -extName $extName -extType $extType
                    if ($result -eq 0) {
                        $extensionsEnabled++
                    } else {
                        $extensionsSkipped++
                    }
                } else {
                    $result = Disable-IniExtension-Direct -iniPath $iniPath -extName $extName -extType $extType
                    if ($result -eq 0) {
                        $extensionsDisabled++
                    } else {
                        $extensionsSkipped++
                    }
                }
            } else {
                $extensionsIgnored++
            }
        }

        Write-Host -Object "`nProfile applied successfully:" -ForegroundColor DarkGreen
        Write-Host -Object "  Settings applied: $settingsApplied" -ForegroundColor Gray
        if ($settingsSkipped -gt 0) {
            Write-Host -Object "  Settings skipped: $settingsSkipped" -ForegroundColor DarkYellow
        }
        if ($settingsIgnored -gt 0) {
            Write-Host -Object "  Settings ignored (not popular): $settingsIgnored" -ForegroundColor DarkCyan
        }
        Write-Host -Object "  Extensions enabled: $extensionsEnabled" -ForegroundColor Gray
        Write-Host -Object "  Extensions disabled: $extensionsDisabled" -ForegroundColor Gray
        if ($extensionsSkipped -gt 0) {
            Write-Host -Object "  Extensions skipped: $extensionsSkipped" -ForegroundColor DarkYellow
        }
        if ($extensionsIgnored -gt 0) {
            Write-Host -Object "  Extensions ignored (not popular): $extensionsIgnored" -ForegroundColor DarkCyan
        }

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to load profile '$profileName'"; exception = $_ }
        Write-Host -Object "`nFailed to load profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Get-Profile-Files {
    try {
        if (Is-Directory-Not-Exists -path $PVMConfig.paths.profiles) {
            return $null
        }
        
        $files = Get-ChildItem -Path $PVMConfig.paths.profiles -Filter '*.json' -ErrorAction SilentlyContinue
        
        return $files
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get profile files"; exception = $_ }
        return $null
    }
}

function List-PHP-Profiles {
    try {
        if (Is-Directory-Not-Exists -path $PVMConfig.paths.profiles) {
            Write-Host -Object "`nNo profiles directory found. Create a profile with 'pvm profile save <name>'." -ForegroundColor DarkYellow
            return -1
        }

        $profileFiles = Get-Profile-Files

        if ($profileFiles.Count -eq 0) {
            Write-Host -Object "`nNo profiles found. Create a profile with 'pvm profile save <name>'." -ForegroundColor DarkYellow
            return -1
        }

        Write-Host -Object "`nAvailable Profiles:" -ForegroundColor Cyan
        Write-Host -Object '-------------------'

        $profiles = @()
        foreach ($file in $profileFiles) {
            try {
                $userProfile = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                $settingsCount = if ($userProfile.settings) { ($userProfile.settings.PSObject.Properties | Measure-Object).Count } else { 0 }
                $extensionsCount = if ($userProfile.extensions) { ($userProfile.extensions.PSObject.Properties | Measure-Object).Count } else { 0 }
                $profiles += @{
                    Name = $userProfile.name
                    Description = if ($userProfile.description) { $userProfile.description } else { '(no description)' }
                    Created = $userProfile.created
                    PHPVersion = $userProfile.phpVersion
                    Settings = $settingsCount
                    Extensions = $extensionsCount
                    File = $file.Name
                }
            } catch {
                Write-Host -Object "  Warning: Failed to parse $($file.Name)" -ForegroundColor DarkYellow
            }
        }

        $maxNameLength = ($profiles.Name | Measure-Object -Maximum Length).Maximum + $PVMConfig.env.MIN_PAD_RIGHT_LENGTH

        foreach ($userProfile in $profiles) {
            Write-Host -Object (' Name '.PadRight($maxNameLength, '.') + " $($userProfile.Name)")
            Write-Host -Object ('   Description '.PadRight($maxNameLength, '.') + " $($userProfile.Description)")
            Write-Host -Object ('   Created '.PadRight($maxNameLength, '.') + " $($userProfile.Created)")
            Write-Host -Object ('   PHP '.PadRight($maxNameLength, '.') + " $($userProfile.PHPVersion)")
            Write-Host -Object ('   Settings '.PadRight($maxNameLength, '.') + " $($userProfile.Settings)")
            Write-Host -Object ('   Extensions '.PadRight($maxNameLength, '.') + " $($userProfile.Extensions)")
            Write-Host -Object ('   Path '.PadRight($maxNameLength, '.') + " $($PVMConfig.paths.profiles)\$($userProfile.File)`n")
        }

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to list profiles"; exception = $_ }
        Write-Host -Object "`nFailed to list profiles: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Show-PHP-Profile {
    param ($profileName)

    try {
        $profilePath = "$($PVMConfig.paths.profiles)\$profileName.json"
        if (Is-File-Not-Exists -path $profilePath) {
            Write-Host -Object "`nProfile '$profileName' not found." -ForegroundColor DarkYellow
            Write-Host -Object "  Use 'pvm profile list' to see available profiles." -ForegroundColor Gray
            return -1
        }

        $userProfile = Get-Content -Path $profilePath -Raw | ConvertFrom-Json

        $dt = [datetime]$userProfile.Created
        $utc = $dt.ToUniversalTime()
        $createdAtFormatted = $utc.ToString('dd/MM/yyyy HH:mm:ss')

        Write-Host -Object "`nProfile: $($userProfile.name)" -ForegroundColor Cyan
        Write-Host -Object '========================='
        Write-Host -Object "Description: $($userProfile.description)" -ForegroundColor White
        Write-Host -Object "Created: $createdAtFormatted" -ForegroundColor White
        Write-Host -Object "PHP Version: $($userProfile.phpVersion)" -ForegroundColor White
        Write-Host -Object "PATH: $profilePath" -ForegroundColor White

        $settingsCount = if ($userProfile.settings) { ($userProfile.settings.PSObject.Properties | Measure-Object).Count } else { 0 }
        $maxNameLength = [Math]::Max(
            ($userProfile.settings.PSObject.Properties.Name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 2),
            ($userProfile.extensions.PSObject.Properties.Name | Measure-Object -Maximum Length).Maximum + ($PVMConfig.env.MIN_PAD_RIGHT_LENGTH * 3)
        )

        Write-Host -Object "`nSettings ($settingsCount):" -ForegroundColor Cyan
        if ($settingsCount -eq 0) {
            Write-Host -Object '  (none)' -ForegroundColor Gray
        } else {
            foreach ($settingName in ($userProfile.settings.PSObject.Properties.Name | Sort-Object)) {
                $setting = $userProfile.settings.$settingName
                $name = "$settingName ".PadRight($maxNameLength, '.')
                $status = if ($setting.enabled) { 'Enabled' } else { 'Disabled' }
                $color = if ($setting.enabled) { 'DarkGreen' } else { 'DarkYellow' }
                Write-Host -Object "  $name $($setting.value) " -NoNewline
                Write-Host -Object $status -ForegroundColor $color
            }
        }

        $extensionsCount = if ($userProfile.extensions) { ($userProfile.extensions.PSObject.Properties | Measure-Object).Count } else { 0 }
        Write-Host -Object "`nExtensions ($extensionsCount):" -ForegroundColor Cyan
        if ($extensionsCount -eq 0) {
            Write-Host -Object '  (none)' -ForegroundColor Gray
        } else {
            foreach ($extName in ($userProfile.extensions.PSObject.Properties.Name | Sort-Object)) {
                $ext = $userProfile.extensions.$extName
                $name = "$extName ".PadRight($maxNameLength, '.')
                $status = if ($ext.enabled) { 'Enabled' } else { 'Disabled' }
                $color = if ($ext.enabled) { 'DarkGreen' } else { 'DarkYellow' }
                $type = $ext.type
                Write-Host -Object "  $name $type " -NoNewline
                Write-Host -Object $status -ForegroundColor $color
            }
        }

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to show profile '$profileName'"; exception = $_ }
        Write-Host -Object "`nFailed to show profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Delete-PHP-Profile {
    param ($profileName)

    try {
        $profilePath = "$($PVMConfig.paths.profiles)\$profileName.json"

        if (Is-File-Not-Exists -path $profilePath) {
            Write-Host -Object "`nProfile '$profileName' not found." -ForegroundColor DarkYellow
            return -1
        }

        $response = Read-Host -Prompt "`nAre you sure you want to delete profile '$profileName'? (y/n)"
        $response = $response.Trim()

        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Host -Object "`nDeletion cancelled." -ForegroundColor Gray
            return -1
        }

        Remove-Item -Path $profilePath -Force
        Write-Host -Object "`nProfile '$profileName' deleted successfully." -ForegroundColor DarkGreen

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to delete profile '$profileName'"; exception = $_ }
        Write-Host -Object "`nFailed to delete profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Export-PHP-Profile {
    param ($profileName, $exportPath = $null)

    try {
        $profilePath = "$($PVMConfig.paths.profiles)\$profileName.json"

        if (Is-File-Not-Exists -path $profilePath) {
            Write-Host -Object "`nProfile '$profileName' not found." -ForegroundColor DarkYellow
            return -1
        }

        if (-not $exportPath) {
            $exportPath = "$(Get-Location)\$profileName.json"
        }

        Copy-Item -Path $profilePath -Destination $exportPath -Force
        Write-Host -Object "`nProfile '$profileName' exported to: $exportPath" -ForegroundColor DarkGreen

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to export profile '$profileName'"; exception = $_ }
        Write-Host -Object "`nFailed to export profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Import-PHP-Profile {
    param ($importPath, $profileName = $null)

    try {
        if (Is-File-Not-Exists -path $importPath) {
            Write-Host -Object "`nFile not found: $importPath" -ForegroundColor DarkYellow
            return -1
        }

        # Validate JSON structure
        try {
            $userProfile = Get-Content -Path $importPath -Raw | ConvertFrom-Json
            if (-not $userProfile.name -or -not $userProfile.settings -or -not $userProfile.extensions) {
                Write-Host -Object "`nInvalid profile format. Profile must contain 'name', 'settings', and 'extensions'." -ForegroundColor DarkYellow
                return -1
            }
        } catch {
            Write-Host -Object "`nInvalid JSON file: $($_.Exception.Message)" -ForegroundColor DarkYellow
            return -1
        }

        # Use provided name or name from profile
        $finalName = if ($profileName) { $profileName } else { $userProfile.name }

        $created = Make-Directory -path $PVMConfig.paths.profiles
        if ($created -ne 0) {
            Write-Host -Object "`nFailed to create profiles directory." -ForegroundColor DarkYellow
            return -1
        }

        $targetPath = "$($PVMConfig.paths.profiles)\$finalName.json"

        # Update profile name if different
        if ($finalName -ne $userProfile.name) {
            $userProfile.name = $finalName
            $jsonContent = $userProfile | ConvertTo-Json -Depth 10
            Set-Content -Path $targetPath -Value $jsonContent -Encoding UTF8
        } else {
            Copy-Item -Path $importPath -Destination $targetPath -Force
        }

        Write-Host -Object "`nProfile imported successfully as '$finalName'." -ForegroundColor DarkGreen
        Write-Host -Object "  Use 'pvm profile load $finalName' to apply it." -ForegroundColor Gray

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to import profile from '$importPath'"; exception = $_ }
        Write-Host -Object "`nFailed to import profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Create-Example-PHP-Profile {
    try {
        $exampleProfile = [ordered]@{
            name = "example-profile"
            description = "Dev"
            created = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            phpVersion = "8.2.30"
            settings = [ordered]@{
                max_execution_time = @{ value = "300"; enabled = $true }
                max_input_time = @{ value = "300"; enabled = $true }
                memory_limit = @{ value = "2G"; enabled = $true }
                error_reporting = @{ value = "E_ALL"; enabled = $true }
                display_errors = @{ value = "On"; enabled = $true }
                log_errors = @{ value = "On"; enabled = $true }
                post_max_size = @{ value = "40M"; enabled = $true }
                upload_max_filesize = @{ value = "30M"; enabled = $true }
                max_file_uploads = @{ value = "40"; enabled = $true }
                'opcache.enable' = @{ value = "1"; enabled = $true }
                'opcache.enable_cli' = @{ value = "1"; enabled = $true }
                'opcache.memory_consumption' = @{ value = "1G"; enabled = $true }
                'opcache.max_accelerated_files' = @{ value = "10000"; enabled = $true }
            }
            extensions = [ordered]@{
                curl = @{ enabled = $true; type = "extension" }
                fileinfo = @{ enabled = $true; type = "extension" }
                gd = @{ enabled = $true; type = "extension" }
                gettext = @{ enabled = $true; type = "extension" }
                intl = @{ enabled = $true; type = "extension" }
                mbstring = @{ enabled = $true; type = "extension" }
                exif = @{ enabled = $true; type = "extension" }
                mysqli = @{ enabled = $false; type = "extension" }
                openssl = @{ enabled = $true; type = "extension" }
                pdo_mysql = @{ enabled = $true; type = "extension" }
                pdo_pgsql = @{ enabled = $false; type = "extension" }
                pdo_sqlite = @{ enabled = $false; type = "extension" }
                pgsql = @{ enabled = $false; type = "extension" }
                sodium = @{ enabled = $false; type = "extension" }
                sqlite3 = @{ enabled = $false; type = "extension" }
                zip = @{ enabled = $true; type = "extension" }
                opcache = @{ enabled = $true; type = "zend_extension" }
                xdebug = @{ enabled = $false; type = "zend_extension" }
            }
        }

        $jsonContent = $exampleProfile | ConvertTo-Json -Depth 10
        Set-Content -Path "$($PVMConfig.paths.profiles)\example-profile.json" -Value $jsonContent -Encoding UTF8

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create example profile"; exception = $_ }
        return -1
    }
}

function Create-Profile-Template {
    try {
        $profileTemplate = [ordered]@{
            extensions = $PVMConfig.defaults.extensions
            settings = $PVMConfig.defaults.settings
        }

        $jsonContent = $profileTemplate | ConvertTo-Json -Depth 10
        Set-Content -Path $PVMConfig.paths.profileTemplate -Value $jsonContent -Encoding UTF8

        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create profile template"; exception = $_ }
        return -1
    }
}
