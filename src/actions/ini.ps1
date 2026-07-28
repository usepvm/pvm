
function Invoke-IniAction {
    param ($action, $params)

    try {
        $exitCode = 0

        $currentPhpVersion = Get-CurrentPHPVersion

        if (-not $currentPhpVersion -or -not $currentPhpVersion.version -or -not $currentPhpVersion.path) {
            Show-Error -message "`nFailed to get current PHP version."
            return -1
        }

        $iniPath = "$($currentPhpVersion.path)\php.ini"
        if (Test-FileNotExists -path $iniPath) {
            Show-Error -message "php.ini not found at: $($currentPhpVersion.path)"
            return -1
        }

        $action = Resolve-Alias -alias $action.ToLower()

        switch ($action.ToLower()) {
            'info' {
                $term = ($params | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
                $exitCode = Get-PHPInfo -term $term -extensions ($params -contains 'extensions') -settings ($params -contains 'settings')
            }
            'get' {
                if ($params.Count -eq 0) {
                    Show-Warning -message "`nPlease specify at least one setting name ('pvm ini get memory_limit)."
                    return -1
                }

                Show-Message -message "`nRetrieving ini setting..."

                $exitCode = Get-IniSetting -iniPath $iniPath -keys @($params)
            }
            'set' {
                if ($params.Count -eq 0) {
                    Show-Warning -message "`nPlease specify at least one 'key=value' (pvm ini set memory_limit=512M)."
                    return -1
                }

                Show-Message -message "`nSetting ini value..."
                $enable = (-not ($params -contains '--disable'))
                $params = $params | Where-Object { $_ -notmatch '^--disable$' }

                $exitCode = Set-IniSetting -iniPath $iniPath -key @($params) -enable $enable
            }
            'enable' {
                if ($params.Count -eq 0) {
                    Show-Warning -message "`nPlease specify at least one extension (pvm ini enable curl)."
                    return -1
                }

                Show-Message -message "`nEnabling extension(s): $($params -join ', ')"

                $exitCode = Enable-IniExtension -iniPath $iniPath -extNames @($params)
            }
            'disable' {
                if ($params.Count -eq 0) {
                    Show-Warning -message "`nPlease specify at least one extension (pvm ini disable xdebug)."
                    return -1
                }

                Show-Message -message "`nDisabling extension(s): $($params -join ', ')"

                $exitCode = Disable-IniExtension -iniPath $iniPath -extNames @($params)
            }
            'status' {
                if ($params.Count -eq 0) {
                    Show-Warning -message "`nPlease specify at least one extension (pvm ini status opcache)."
                    return -1
                }

                Show-Message -message "`nChecking status of extension(s): $($params -join ', ')"

                $exitCode = Get-IniExtensionStatus -iniPath $iniPath -extNames @($params)
            }
            'restore' {
                $exitCode = Restore-IniBackup -iniPath $iniPath
            }
            'add' {
                if ($params.Count -eq 0) {
                    Show-Warning -message "`nPlease specify at least one extension (pvm ini add xdebug)."
                    return -1
                }

                Show-Message -message "`nInstalling extension(s): $($params -join ', ')"

                $skipConfirmation = [bool]($params | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
                $params = $params | Where-Object { @('-y', '--yes') -notcontains $_ }

                $exitCode = Install-IniExtension -iniPath $iniPath -extNames @($params) -skipConfirmation $skipConfirmation
            }
            'remove' {
                if ($params.Count -eq 0) {
                    Show-Warning -message "`nPlease specify at least one extension (pvm ini remove xdebug)."
                    return -1
                }

                Show-Message -message "`nUninstalling extension(s): $($params -join ', ')"

                $skipConfirmation = [bool]($params | Where-Object { @('-y', '--yes') -contains $_ } | Select-Object -First 1)
                $params = $params | Where-Object { @('-y', '--yes') -notcontains $_ }

                $exitCode = Uninstall-Extension -iniPath $iniPath -extNames @($params) -skipConfirmation $skipConfirmation
            }
            'ext' {
                $term = ($params | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
                $exitCode = Show-PHPExtensions -iniPath $iniPath -available ($params -contains 'available') -term $term
            }
            default {
                Show-Error -message "`nUnknown action '$action' use one of following: 'info', 'set', 'get', 'status', 'enable', 'disable', 'add', 'remove', 'ext' or 'restore'."
            }
        }

        return $exitCode
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to invoke ini action '$action'"; exception = $_ }
        Show-Error -message "`nFailed to perform action '$action' on ini settings."
        return -1
    }
}
