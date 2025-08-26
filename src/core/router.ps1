
function Invoke-PVMSetup {

    $result = @{ code = 0; message = "PVM is already setup" }
    if (-not (Is-PVM-Setup)) {
        $result = Setup-PVM
    }
    $optimized = Optimize-SystemPath
    if ($optimized -ne 0) {
        Write-Host "`nFailed to optimize system path." -ForegroundColor DarkYellow
    }
    
    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMCurrent {

    $result = Get-Current-PHP-Version
    if (-not $result.version) {
        Write-Host "`nNo PHP version is currently set. Please use 'pvm use <version>' to set a version."
        return 1
    }
    Write-Host "`nRunning version: PHP $($result.version)"
    
    if (-not $result.status) {
        Write-Host "No status information available for the current PHP version." -ForegroundColor Yellow
        return 1
    }
    
    foreach ($ext in $result.status.Keys) {
        if ($result.status[$ext]) {
            Write-Host "- $ext is enabled" -ForegroundColor DarkGreen
        } else {
            Write-Host "- $ext is disabled" -ForegroundColor DarkYellow
        }
    }
    
    Write-Host "`nPath: $($result.path)" -ForegroundColor Gray
    return 0
}

function Invoke-PVMList{
    param($arguments)
    
    if ($arguments -contains "available") {
        $result = Get-Available-PHP-Versions
    } else {
        $result = Display-Installed-PHP-Versions
    }
    
    return $result
}

function Invoke-PVMInstall {
    param($arguments)
    
    $version = $arguments[0]        
    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to install"
        return 1
    }

    $result = Install-PHP -version $version
    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMUninstall {
    param($arguments)
    
    $version = $arguments[0]

    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to uninstall"
        return 1
    }

    $result = Uninstall-PHP -version $version

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMUse {
    param($arguments)
    
    $version = $arguments[0]

    if (-not $version) {
        Write-Host "`nPlease provide a PHP version to use"
        return 1
    }

    if ($version -eq 'auto') {
        $result = Auto-Select-PHP-Version
        if ($result.code -ne 0) {
            Display-Msg-By-ExitCode -result $result
            return 1
        }
        $version = $result.version
    }
    
    $result = Update-PHP-Version -variableName $PHP_CURRENT_ENV_NAME -variableValue $version

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMIni {
    param($arguments)
    
    $action = $arguments[0]
    if (-not $action) {
        Write-Host "`nPlease specify an action for 'pvm ini'. Use 'info', 'set', 'get', 'status', 'enable', 'disable' or 'restore'."
        return 1
    }
    
    $remainingArgs = if ($arguments.Count -gt 1) { $arguments[1..($arguments.Count - 1)] } else { @() }

    $exitCode = Invoke-PVMIniAction -action $action -params $remainingArgs
    return $exitCode
}


function Invoke-PVMTest {
    param($arguments)

    $verbosity = 'Normal'
    $coverage = $false
    $files = $arguments | Where-Object {
        if ($_ -match '^--tag=(.+)$') {
            $tag = $Matches[1]
            return $false
        }
        if ($_ -match '^--coverage$') {
            $coverage = ($_ -eq '--coverage')
            return $false
        }
        if ($_ -match '^--verbosity=(.+)$') {
            $verbosity = $Matches[1]
            return $false
        }
        return $true
    }
    
    $result = Run-Tests -verbosity $verbosity -tests $files -tag $tag -coverage $coverage

    Display-Msg-By-ExitCode -result $result
    return 0
}

function Invoke-PVMLog {
    param($arguments)
    
    
    $pageSizeArg = $arguments | Where-Object { $_ -match '^--pageSize=(.+)$' }
    if ($pageSizeArg) {
        $pageSize = $pageSizeArg -replace '^--pageSize=', ''
    } else {
        $pageSize = $DefaultLogPageSize
    }
    $code = Show-Log -pageSize $pageSize
    return $code
}

function Get-Actions {
    param( $arguments )

    $script:arguments = $arguments
    
    return [ordered]@{
        "setup" = [PSCustomObject]@{
            command = "pvm setup";
            description = "Setup the environment variables and paths for PHP.";
            action = { return Invoke-PVMSetup }}
        "current" = [PSCustomObject]@{
            command = "pvm current";
            description = "Display active version.";
            action = { return Invoke-PVMCurrent }}
        "list" = [PSCustomObject]@{
            command = "pvm list [available]";
            description = "Lists the PHP installations. Type 'available' at the end to see what can be installed.";
            action = { return Invoke-PVMList -arguments $script:arguments }}
        "install" = [PSCustomObject]@{
            command = "pvm install <version>";
            description = "The version must be a specific version.";
            action = { return Invoke-PVMInstall -arguments $script:arguments }}
        "uninstall" = [PSCustomObject]@{
            command = "pvm uninstall <version>";
            description = "The version must be a specific version.";
            action = { return Invoke-PVMUninstall -arguments $script:arguments }}
        "use" = [PSCustomObject]@{
            command = "pvm use <version>|[auto]";
            description = "Switch to use the specified version. use 'auto' to switch to the version specified in the current directory's composer.json or .php-version file.";
            action = { return Invoke-PVMUse -arguments $script:arguments }}
        "info" = [PSCustomObject]@{
            command = "pvm info";
            description = "Display information about the environment.";
            action = { $script:arguments = @('info'); return Invoke-PVMIni -arguments $script:arguments }}
        "ini" = [PSCustomObject]@{
            command = "pvm ini <action> [<args>]";
            description = "Manage PHP ini settings. You can use 'set' or 'get' for a setting value; 'status', 'enable' or 'disable' for an extension, 'info' for a summary or 'restore' the original ini file from backup.";
            action = { return Invoke-PVMIni -arguments $script:arguments }}
        "test" = [PSCustomObject]@{
            command = "pvm test";
            description = "Run tests.";
            action = { return Invoke-PVMTest -arguments $script:arguments }}
        "log" = [PSCustomObject]@{
            command = "pvm log";
            description = "Display the log file.";
            action = { return Invoke-PVMLog -arguments $script:arguments }}
    }
}

function Alias-Handler {
    param($alias)
    
    switch ($alias) {
        "ls" { return "list" }
        "rm" { return "uninstall" }
        "i"  { return "install" }
        Default { return $alias }
    }
}

function Show-Usage {
    Write-Host "`nRunning version : $PVM_VERSION"
    Write-Host "`nUsage:`n"

    $maxLineLength = ($actions.GetEnumerator() | ForEach-Object { $_.Value.command.Length } | Measure-Object -Maximum).Maximum + 10   # Length for command + dots
    $maxDescLength = $Host.UI.RawUI.WindowSize.Width - ($maxLineLength + 20) # Max length per description line
    if ($maxDescLength -lt 100) { $maxDescLength = 100 }

    $actions.GetEnumerator() | ForEach-Object {
        $command = $_.Value.command
        $description = $_.Value.description

        # Dots for first line
        $dotsCount = [Math]::Max($maxLineLength - $command.Length, 0)
        $dots = '.' * $dotsCount

        # First line available space for description
        $descLines = @()

        # Wrap description by spaces without breaking words
        $remaining = $description
        while ($remaining.Length -gt $maxDescLength) {
            $breakPos = $remaining.LastIndexOf(' ', $maxDescLength)
            if ($breakPos -lt 0) { $breakPos = $maxDescLength } # fallback: break mid-word
            $descLines += $remaining.Substring(0, $breakPos)
            $remaining = $remaining.Substring($breakPos).Trim()
        }
        if ($remaining) { $descLines += $remaining }

        # Print first line (command + dots + first part of description)
        Write-Host "  $command $dots $($descLines[0])"

        # Print remaining description lines aligned with first description start
        $indent = (' ' * ($maxLineLength + 4))  # +1 for space after dots
        for ($i = 1; $i -lt $descLines.Count; $i++) {
            Write-Host "$indent$($descLines[$i])"
        }
    }
}