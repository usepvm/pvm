
function Update-PHP-Version {
    param ($variableName, $variableValue)

    try {
        $variableValueContent = Get-EnvVar-ByName -name "php$variableValue"
        if (-not $variableValueContent) {
            $installedVersions = Get-Matching-PHP-Versions -version $variableValue
            if ($installedVersions)  {
                if ($installedVersions.Count -eq 1) {
                    $variableValue = $installedVersions
                } else {
                    Write-Host "`nInstalled versions :"
                    $installedVersions | ForEach-Object { Write-Host " - $_" }
                    $response = Read-Host "`nEnter the exact version to use. (or press Enter to cancel)"
                    if (-not $response) {
                        return @{ code = -1; message = "Operation cancelled."; color = "DarkYellow"}
                    }
                    $variableValue = $response
                }
                $variableValueContent = Get-EnvVar-ByName -name "php$variableValue"
            }
        }
        if (-not $variableValueContent) {
            return @{ code = -1; message = "Version $variableValue was not found!"; color = "DarkYellow"}
        }
        $output = Set-EnvVar -name $variableName -value $variableValueContent
        return @{ code = $output; message = "Now using PHP $variableValue";}
    } catch {
        $logged = Log-Data -logPath $LOG_ERROR_PATH -message "Update-PHP-Version: Failed to update PHP version for '$variableName'" -data $_.Exception.Message
        return @{ code = -1; message = "No matching PHP versions found for '$version', Use 'pvm list' to see installed versions."; color = "DarkYellow"}
    }
}
