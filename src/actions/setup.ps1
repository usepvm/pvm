


function Setup-PVM {

    try {
        $path = Get-EnvVar-ByName -name "Path"
        if ($null -eq $path) {
            $path = ''
        }
        $newPath = $path
        $pathItems = $path.ToLower() -split ';'

        if ($null -eq (Get-EnvVar-ByName -name $PHP_CURRENT_ENV_NAME)) {
            $output = Set-EnvVar -name $PHP_CURRENT_ENV_NAME -value $PHP_CURRENT_VERSION_PATH
        }
        $parent = Split-Path $PHP_CURRENT_VERSION_PATH
        if (-not (Is-Directory-Exists -path $parent)) {
            $created = Make-Directory -path $parent
        }
        
        if (($pathItems -notcontains $PHP_CURRENT_VERSION_PATH.ToLower()) -and ($pathItems -notcontains "%$($PHP_CURRENT_ENV_NAME.ToLower())%")) {
            $newPath += ";%$PHP_CURRENT_ENV_NAME%"
        } 

        if (($pathItems -notcontains $PVMRoot.ToLower()) -and ($pathItems -notcontains "%pvm%")) {
            $newPath += ";%pvm%"
        }
        if ($null -eq (Get-EnvVar-ByName -name "pvm")) {
            $output = Set-EnvVar -name "pvm" -value $PVMRoot
        }
        
        $result = @{ code = 0; message = "PVM environment has been set up."; color = "DarkGreen"}
        if ($newPath -ne $path) {
            $output = Set-EnvVar -name "Path" -value $newPath
            $result.code = $output
        }

        return $result
    } catch {
        
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name): Failed to set up PVM environment"
            file = $($_.InvocationInfo.ScriptName)
            line = $($_.InvocationInfo.ScriptLineNumber)
            message = $_.Exception.Message
            positionMessage = $_.InvocationInfo.PositionMessage
        }
        return @{ code = -1; message = "Failed to set up PVM environment."; color = "DarkYellow"}
    }
}
