


function Setup-PVM {

    try {
        $path = Get-EnvVar-ByName -name "Path"
        if ($null -eq $path) {
            $path = ''
        }
        $newPath = $path
        $pathItems = $path.ToLower() -split ';'

        $parent = Split-Path $PHP_CURRENT_VERSION_PATH
        if (-not (Is-Directory-Exists -path $parent)) {
            $created = Make-Directory -path $parent
        }
        
        if ($pathItems -notcontains $PHP_CURRENT_VERSION_PATH.ToLower()) {
            $newPath += ";$PHP_CURRENT_VERSION_PATH"
        } 

        if ($pathItems -notcontains $PVMRoot.ToLower()) {
            $newPath += ";$PVMRoot"
        }
        
        $result = @{ code = 0; message = "PVM environment has been set up."; color = "DarkGreen"}
        if ($newPath -ne $path) {
            $output = Set-EnvVar -name "Path" -value $newPath
            $result.code = $output
        }

        return $result
    } catch {
        
        $logged = Log-Data -data @{
            header = "$($MyInvocation.MyCommand.Name) - Failed to set up PVM environment"
            exception = $_
        }
        return @{ code = -1; message = "Failed to set up PVM environment."; color = "DarkYellow"}
    }
}
