
function Set-IniSetting-Direct {
    param ($iniPath, $settingName, $value, $enabled = $true)
    
    try {
        $lines = [string[]](Get-Content $iniPath)
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
        
        Set-Content $iniPath $lines -Encoding UTF8
        return 0
    } catch {
        return -1
    }
}

function Enable-IniExtension-Direct {
    param ($iniPath, $extName, $extType = "extension")
    
    try {
        # Normalize extension name - remove php_ prefix and .dll suffix if present
        $extName = $extName -replace '^php_', '' -replace '\.dll$', ''
        $extFileName = "php_$extName.dll"
        
        $lines = [string[]](Get-Content $iniPath)
        $modified = $false
        
        # Check for extension in multiple formats:
        # 1. extension=php_openssl.dll (full filename, may have path)
        # 2. extension=openssl (just the name without php_ prefix and .dll suffix)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $isMatch = $false
            
            # Match extension or zend_extension lines (commented or not)
            $pattern = if ($extType -eq "zend_extension") {
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
            $newLine = if ($extType -eq "zend_extension") {
                "zend_extension=$extFileName"
            } else {
                "extension=$extFileName"
            }
            $lines += $newLine
        }
        
        Set-Content $iniPath $lines -Encoding UTF8
        return 0
    } catch {
        return -1
    }
}

function Disable-IniExtension-Direct {
    param ($iniPath, $extName, $extType = "extension")
    
    try {
        # Normalize extension name - remove php_ prefix and .dll suffix if present
        $extName = $extName -replace '^php_', '' -replace '\.dll$', ''
        $extFileName = "php_$extName.dll"
        
        $lines = [string[]](Get-Content $iniPath)
        $modified = $false
        
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
            $pattern = if ($extType -eq "zend_extension") {
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
                $modified = $true
                break
            }
        }
        
        Set-Content $iniPath $lines -Encoding UTF8
        return 0
    } catch {
        return -1
    }
}

function Get-Popular-PHP-Settings {
    # Return list of popular/common PHP settings that should be included in profiles
    return @(
        "memory_limit", "max_execution_time", "max_input_time",
        "post_max_size", "upload_max_filesize", "max_file_uploads",
        "display_errors", "error_reporting", "log_errors",
        "opcache.enable", "opcache.enable_cli", "opcache.memory_consumption", "opcache.max_accelerated_files"
    )
}

function Get-Popular-PHP-Extensions {
    # Return list of popular/common PHP extensions that should be included in profiles
    return @(
        "curl", "fileinfo", "gd", "gettext", "intl", "mbstring", "exif", "openssl",
        "mysqli", "pdo_mysql", "pdo_pgsql", "pdo_sqlite", "pgsql",
        "sodium", "sqlite3", "zip", "opcache", "xdebug"  
    )
}

function Save-PHP-Profile {
    param($profileName, $description = $null)
    
    try {
        $currentPhpVersion = Get-Current-PHP-Version
        
        if (-not $currentPhpVersion -or -not $currentPhpVersion.version -or -not $currentPhpVersion.path) {
            Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }
        
        $iniPath = "$($currentPhpVersion.path)\php.ini"
        if (-not (Test-Path $iniPath)) {
            Write-Host "`nphp.ini not found at: $($currentPhpVersion.path)" -ForegroundColor DarkYellow
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
        $created = Make-Directory -path $PROFILES_PATH
        if ($created -ne 0) {
            Write-Host "`nFailed to create profiles directory." -ForegroundColor DarkYellow
            return -1
        }
        
        $profilePath = "$PROFILES_PATH\$profileName.json"
        $jsonContent = $userProfile | ConvertTo-Json -Depth 10
        Set-Content -Path $profilePath -Value $jsonContent -Encoding UTF8
        
        Write-Host "`nProfile '$profileName' saved successfully." -ForegroundColor DarkGreen
        Write-Host "  Settings: $($userProfile.settings.Count) (popular/common only)" -ForegroundColor Gray
        Write-Host "  Extensions: $($userProfile.extensions.Count) (popular/common only)" -ForegroundColor Gray
        Write-Host "  Location: $profilePath" -ForegroundColor Gray
        Write-Host "`nNote: Only popular/common settings and extensions are saved." -ForegroundColor DarkCyan
        Write-Host "      You can manually add other settings/extensions using 'pvm ini' commands." -ForegroundColor DarkCyan
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to save profile '$profileName'"
            exception = $_
        }
        Write-Host "`nFailed to save profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Load-PHP-Profile {
    param($profileName)
    
    try {
        $currentPhpVersion = Get-Current-PHP-Version
        
        if (-not $currentPhpVersion -or -not $currentPhpVersion.version -or -not $currentPhpVersion.path) {
            Write-Host "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }
        
        $iniPath = "$($currentPhpVersion.path)\php.ini"
        if (-not (Test-Path $iniPath)) {
            Write-Host "`nphp.ini not found at: $($currentPhpVersion.path)" -ForegroundColor DarkYellow
            return -1
        }
        
        # Load profile JSON
        $profilePath = "$PROFILES_PATH\$profileName.json"
        if (-not (Test-Path $profilePath)) {
            Write-Host "`nProfile '$profileName' not found." -ForegroundColor DarkYellow
            Write-Host "  Use 'pvm profile list' to see available profiles." -ForegroundColor Gray
            return -1
        }
        
        $jsonContent = Get-Content $profilePath -Raw | ConvertFrom-Json
        
        Write-Host "`nLoading profile '$($jsonContent.name)'..." -ForegroundColor Cyan
        if ($jsonContent.description) {
            Write-Host "  Description: $($jsonContent.description)" -ForegroundColor Gray
        }
        Write-Host "  Created: $($jsonContent.created)" -ForegroundColor Gray
        
        # Backup ini file before applying changes
        Backup-IniFile $iniPath
        
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
                $extType = if ($ext.type) { $ext.type } else { "extension" }
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
        
        Write-Host "`nProfile applied successfully:" -ForegroundColor DarkGreen
        Write-Host "  Settings applied: $settingsApplied" -ForegroundColor Gray
        if ($settingsSkipped -gt 0) {
            Write-Host "  Settings skipped: $settingsSkipped" -ForegroundColor DarkYellow
        }
        if ($settingsIgnored -gt 0) {
            Write-Host "  Settings ignored (not popular): $settingsIgnored" -ForegroundColor DarkCyan
        }
        Write-Host "  Extensions enabled: $extensionsEnabled" -ForegroundColor Gray
        Write-Host "  Extensions disabled: $extensionsDisabled" -ForegroundColor Gray
        if ($extensionsSkipped -gt 0) {
            Write-Host "  Extensions skipped: $extensionsSkipped" -ForegroundColor DarkYellow
        }
        if ($extensionsIgnored -gt 0) {
            Write-Host "  Extensions ignored (not popular): $extensionsIgnored" -ForegroundColor DarkCyan
        }
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to load profile '$profileName'"
            exception = $_
        }
        Write-Host "`nFailed to load profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function List-PHP-Profiles {
    try {
        if (-not (Test-Path $PROFILES_PATH)) {
            Write-Host "`nNo profiles directory found. Create a profile with 'pvm profile save <name>'." -ForegroundColor DarkYellow
            return -1
        }
        
        $profileFiles = Get-ChildItem -Path $PROFILES_PATH -Filter "*.json" -ErrorAction SilentlyContinue
        
        if ($profileFiles.Count -eq 0) {
            Write-Host "`nNo profiles found. Create a profile with 'pvm profile save <name>'." -ForegroundColor DarkYellow
            return -1
        }
        
        Write-Host "`nAvailable Profiles:" -ForegroundColor Cyan
        Write-Host "-------------------"
        
        $profiles = @()
        foreach ($file in $profileFiles) {
            try {
                $userProfile = Get-Content $file.FullName -Raw | ConvertFrom-Json
                $settingsCount = if ($userProfile.settings) { ($userProfile.settings.PSObject.Properties | Measure-Object).Count } else { 0 }
                $extensionsCount = if ($userProfile.extensions) { ($userProfile.extensions.PSObject.Properties | Measure-Object).Count } else { 0 }
                $profiles += [PSCustomObject]@{
                    Name = $userProfile.name
                    Description = if ($userProfile.description) { $userProfile.description } else { "(no description)" }
                    Created = $userProfile.created
                    PHPVersion = $userProfile.phpVersion
                    Settings = $settingsCount
                    Extensions = $extensionsCount
                    File = $file.Name
                }
            } catch {
                Write-Host "  Warning: Failed to parse $($file.Name)" -ForegroundColor DarkYellow
            }
        }
        
        $maxNameLength = ($profiles.Name | Measure-Object -Maximum Length).Maximum + 10

        foreach ($userProfile in $profiles) {
            Write-Host " Name ".PadRight($maxNameLength, '.')  $($userProfile.Name)
            Write-Host "   Description ".PadRight($maxNameLength, '.')  $($userProfile.Description)
            Write-Host "   Created ".PadRight($maxNameLength, '.')  $($userProfile.Created)
            Write-Host "   PHP ".PadRight($maxNameLength, '.')  $($userProfile.PHPVersion)
            Write-Host "   Settings ".PadRight($maxNameLength, '.')  $($userProfile.Settings)
            Write-Host "   Extensions ".PadRight($maxNameLength, '.')  $($userProfile.Extensions)
            Write-Host "   Path ".PadRight($maxNameLength, '.')  "$PROFILES_PATH\$($userProfile.File)`n"
        }
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to list profiles"
            exception = $_
        }
        Write-Host "`nFailed to list profiles: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Show-PHP-Profile {
    param($profileName)
    
    try {
        $profilePath = "$PROFILES_PATH\$profileName.json"
        if (-not (Test-Path $profilePath)) {
            Write-Host "`nProfile '$profileName' not found." -ForegroundColor DarkYellow
            Write-Host "  Use 'pvm profile list' to see available profiles." -ForegroundColor Gray
            return -1
        }
        
        $userProfile = Get-Content $profilePath -Raw | ConvertFrom-Json
        
        $dt = [datetime]$userProfile.Created
        $utc = $dt.ToUniversalTime()
        $createdAtFormatted = $utc.ToString("dd/MM/yyyy HH:mm:ss")

        Write-Host "`nProfile: $($userProfile.name)" -ForegroundColor Cyan
        Write-Host "========================="
        Write-Host "Description: $($userProfile.description)" -ForegroundColor White
        Write-Host "Created: $createdAtFormatted" -ForegroundColor White
        Write-Host "PHP Version: $($userProfile.phpVersion)" -ForegroundColor White
        Write-Host "PATH: $profilePath" -ForegroundColor White
        
        $settingsCount = if ($userProfile.settings) { ($userProfile.settings.PSObject.Properties | Measure-Object).Count } else { 0 }
        Write-Host "`nSettings ($settingsCount):" -ForegroundColor Cyan
        if ($settingsCount -eq 0) {
            Write-Host "  (none)" -ForegroundColor Gray
        } else {
            $maxNameLength = ($userProfile.settings.PSObject.Properties.Name | Measure-Object -Maximum Length).Maximum + 10
            foreach ($settingName in ($userProfile.settings.PSObject.Properties.Name | Sort-Object)) {
                $setting = $userProfile.settings.$settingName
                $name = "$settingName ".PadRight($maxNameLength, '.')
                $status = if ($setting.enabled) { "Enabled" } else { "Disabled" }
                $color = if ($setting.enabled) { "DarkGreen" } else { "DarkYellow" }
                Write-Host "  $name $($setting.value) " -NoNewline
                Write-Host $status -ForegroundColor $color
            }
        }
        
        $extensionsCount = if ($userProfile.extensions) { ($userProfile.extensions.PSObject.Properties | Measure-Object).Count } else { 0 }
        Write-Host "`nExtensions ($extensionsCount):" -ForegroundColor Cyan
        if ($extensionsCount -eq 0) {
            Write-Host "  (none)" -ForegroundColor Gray
        } else {
            $maxNameLength = ($userProfile.extensions.PSObject.Properties.Name | Measure-Object -Maximum Length).Maximum + 21
            foreach ($extName in ($userProfile.extensions.PSObject.Properties.Name | Sort-Object)) {
                $ext = $userProfile.extensions.$extName
                $name = "$extName ".PadRight($maxNameLength, '.')
                $status = if ($ext.enabled) { "Enabled" } else { "Disabled" }
                $color = if ($ext.enabled) { "DarkGreen" } else { "DarkYellow" }
                $type = $ext.type
                Write-Host "  $name $type " -NoNewline
                Write-Host $status -ForegroundColor $color
            }
        }
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to show profile '$profileName'"
            exception = $_
        }
        Write-Host "`nFailed to show profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Delete-PHP-Profile {
    param($profileName)
    
    try {
        $profilePath = "$PROFILES_PATH\$profileName.json"
        
        if (-not (Test-Path $profilePath)) {
            Write-Host "`nProfile '$profileName' not found." -ForegroundColor DarkYellow
            return -1
        }
        
        $response = Read-Host "`nAre you sure you want to delete profile '$profileName'? (y/n)"
        $response = $response.Trim()
        
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Host "`nDeletion cancelled." -ForegroundColor Gray
            return -1
        }
        
        Remove-Item -Path $profilePath -Force
        Write-Host "`nProfile '$profileName' deleted successfully." -ForegroundColor DarkGreen
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to delete profile '$profileName'"
            exception = $_
        }
        Write-Host "`nFailed to delete profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Export-PHP-Profile {
    param($profileName, $exportPath = $null)
    
    try {
        $profilePath = "$PROFILES_PATH\$profileName.json"
        
        if (-not (Test-Path $profilePath)) {
            Write-Host "`nProfile '$profileName' not found." -ForegroundColor DarkYellow
            return -1
        }
        
        if (-not $exportPath) {
            $exportPath = "$(Get-Location)\$profileName.json"
        }
        
        Copy-Item -Path $profilePath -Destination $exportPath -Force
        Write-Host "`nProfile '$profileName' exported to: $exportPath" -ForegroundColor DarkGreen
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to export profile '$profileName'"
            exception = $_
        }
        Write-Host "`nFailed to export profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}

function Import-PHP-Profile {
    param($importPath, $profileName = $null)
    
    try {
        if (-not (Test-Path $importPath)) {
            Write-Host "`nFile not found: $importPath" -ForegroundColor DarkYellow
            return -1
        }
        
        # Validate JSON structure
        try {
            $userProfile = Get-Content $importPath -Raw | ConvertFrom-Json
            if (-not $userProfile.name -or -not $userProfile.settings -or -not $userProfile.extensions) {
                Write-Host "`nInvalid profile format. Profile must contain 'name', 'settings', and 'extensions'." -ForegroundColor DarkYellow
                return -1
            }
        } catch {
            Write-Host "`nInvalid JSON file: $($_.Exception.Message)" -ForegroundColor DarkYellow
            return -1
        }
        
        # Use provided name or name from profile
        $finalName = if ($profileName) { $profileName } else { $userProfile.name }
        
        $created = Make-Directory -path $PROFILES_PATH
        if ($created -ne 0) {
            Write-Host "`nFailed to create profiles directory." -ForegroundColor DarkYellow
            return -1
        }
        
        $targetPath = "$PROFILES_PATH\$finalName.json"
        
        # Update profile name if different
        if ($finalName -ne $userProfile.name) {
            $userProfile.name = $finalName
            $jsonContent = $userProfile | ConvertTo-Json -Depth 10
            Set-Content -Path $targetPath -Value $jsonContent -Encoding UTF8
        } else {
            Copy-Item -Path $importPath -Destination $targetPath -Force
        }
        
        Write-Host "`nProfile imported successfully as '$finalName'." -ForegroundColor DarkGreen
        Write-Host "  Use 'pvm profile load $finalName' to apply it." -ForegroundColor Gray
        
        return 0
    } catch {
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to import profile from '$importPath'"
            exception = $_
        }
        Write-Host "`nFailed to import profile: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return -1
    }
}



