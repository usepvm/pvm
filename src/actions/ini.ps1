
function Invoke-IniAction {
    param ($action, $params)

    try {
        $exitCode = 1

        $currentPhpVersion = Get-Current-PHP-Version

        if (-not $currentPhpVersion -or -not $currentPhpVersion.version -or -not $currentPhpVersion.path) {
            Write-Host -Object "`nFailed to get current PHP version." -ForegroundColor DarkYellow
            return -1
        }

        $iniPath = "$($currentPhpVersion.path)\php.ini"
        if (Is-File-Not-Exists -path $iniPath) {
            Write-Host -Object "php.ini not found at: $($currentPhpVersion.path)"
            return -1
        }

        switch ($action.ToLower()) {
            'info' {
                $term = ($params | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
                $exitCode = Get-PHP-Info -term $term -extensions ($params -contains 'extensions') -settings ($params -contains 'settings')
            }
            'get' {
                if ($params.Count -eq 0) {
                    Write-Host -Object "`nPlease specify at least one setting name ('pvm ini get memory_limit)."
                    return -1
                }

                Write-Host -Object "`nRetrieving ini setting..."

                $exitCode = Get-IniSetting -iniPath $iniPath -keys @($params)
            }
            'set' {
                if ($params.Count -eq 0) {
                    Write-Host -Object "`nPlease specify at least one 'key=value' (pvm ini set memory_limit=512M)."
                    return -1
                }

                Write-Host -Object "`nSetting ini value..."
                $enable = (-not ($params -contains '--disable'))
                $params = $params | Where-Object { $_ -notmatch '^--disable$' }

                $exitCode = Set-IniSetting -iniPath $iniPath -key @($params) -enable $enable
            }
            'enable' {
                if ($params.Count -eq 0) {
                    Write-Host -Object "`nPlease specify at least one extension (pvm ini enable curl)."
                    return -1
                }

                Write-Host -Object "`nEnabling extension(s): $($params -join ', ')"

                $exitCode = Enable-IniExtension -iniPath $iniPath -extNames @($params)
            }
            'disable' {
                if ($params.Count -eq 0) {
                    Write-Host -Object "`nPlease specify at least one extension (pvm ini disable xdebug)."
                    return -1
                }

                Write-Host -Object "`nDisabling extension(s): $($params -join ', ')"

                $exitCode = Disable-IniExtension -iniPath $iniPath -extNames @($params)
            }
            'status' {
                if ($params.Count -eq 0) {
                    Write-Host -Object "`nPlease specify at least one extension (pvm ini status opcache)."
                    return -1
                }

                Write-Host -Object "`nChecking status of extension(s): $($params -join ', ')"

                $exitCode = Get-IniExtensionStatus -iniPath $iniPath -extNames @($params)
            }
            'restore' {
                $exitCode = Restore-IniBackup -iniPath $iniPath
            }
            'add' {
                if ($params.Count -eq 0) {
                    Write-Host -Object "`nPlease specify at least one extension (pvm ini install xdebug)."
                    return -1
                }

                Write-Host -Object "`nInstalling extension(s): $($params -join ', ')"

                $exitCode = Install-IniExtension -iniPath $iniPath -extNames @($params)
            }
            'remove' {
                if ($params.Count -eq 0) {
                    Write-Host -Object "`nPlease specify at least one extension (pvm ini uninstall xdebug)."
                    return -1
                }

                Write-Host -Object "`nUninstalling extension(s): $($params -join ', ')"

                $exitCode = Uninstall-Extension -iniPath $iniPath -extNames @($params)
            }
            'list' {
                $term = ($params | Where-Object { $_ -match '^--search=(.+)$' }) -replace '^--search=', ''
                $exitCode = List-PHP-Extensions -iniPath $iniPath -available ($params -contains 'available') -term $term
            }
            default {
                Write-Host -Object "`nUnknown action '$action' use one of following: 'info', 'get', 'set', 'enable', 'disable', 'status', 'install', 'list' or 'restore'."
            }
        }

        return $exitCode
    } catch {
        $logged = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to invoke ini action '$action'"; exception = $_ }
        Write-Host -Object "`nFailed to perform action '$action' on ini settings." -ForegroundColor Red
        return -1
    }
}
