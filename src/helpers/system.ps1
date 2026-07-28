
function Test-OS64Bit {
    return [System.Environment]::Is64BitOperatingSystem
}

function Get-AllEnvVarsCore {
    return [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
}

function Get-AllEnvVars {
    try {
        return Get-AllEnvVarsCore
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get all environment variables"; exception = $_ }
        return $null
    }
}

function Get-EnvVarByNameCore {
    param ($name)

    return [System.Environment]::GetEnvironmentVariable($name, [System.EnvironmentVariableTarget]::Machine)
}

function Get-EnvVarByName {
    param ($name, $optimized = $false)

    try {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return $null
        }
        $name = $name.Trim()
        $value = Get-EnvVarByNameCore -name $name

        if ($optimized -eq $true) {
            $value = Get-OptimizedEnv -name $name -value $value
        }

        return $value
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get environment variable '$name'"; exception = $_ }
        return $null
    }
}

function Set-EnvVarCore {
    param ($name, $value)

    [System.Environment]::SetEnvironmentVariable($name, $value, [System.EnvironmentVariableTarget]::Machine)
}

function Set-EnvVar {
    param ($name, $value)

    try {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return -1
        }
        $name = $name.Trim()

        if (Test-NotAdmin) {
            $command = "[System.Environment]::SetEnvironmentVariable('$name', '$value', [System.EnvironmentVariableTarget]::Machine)"
            return (Invoke-PSCommand -command $command)
        }

        # We already have admin rights, proceed normally
        Set-EnvVarCore -name $name -value $value
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set environment variable '$name'"; exception = $_ }
        return -1
    }
}

function Get-OptimizedEnv {
    param ($name, $value)

    $envVars = Get-AllEnvVars

    $envVars.Keys | ForEach-Object {
        $envName = $_
        $envValue = $envVars[$envName]

        if ($name.ToLower() -eq $envName.ToLower()) { return }
        if (-not $envValue) { return }
        if ($value.ToLower() -notlike "*$($envValue.ToLower())*") { return }
        if ($envValue -match '(?i)\\Windows|\\System32') { return }

        $envValue = [regex]::Escape($envValue.TrimEnd(';'))
        $pattern = "(?i)(?<=^|;){0}(?=;|$)" -f $envValue
        $value = [regex]::Replace($value, $pattern, "%$envName%")
    }

    $value = Format-EnvContent -value $value

    return $value
}

function Format-EnvContent {
    param ($value)

    $rebuiltValue = $value -split ';' |
    ForEach-Object { $_.Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    return ($rebuiltValue -join ';')
}

function Remove-PathDuplicates {
    param ($path)

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $entries = $Path -split ';' |
    ForEach-Object { $_.Trim() } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Where-Object { $seen.Add($_) }

    return ($entries -join ';')
}

function Optimize-SystemPath {
    try {
        $path = Get-EnvVarByName -name 'Path' -optimized $true
        if ($null -eq $path) {
            $path = ''
        }

        $oldPath = $path
        $path = Remove-PathDuplicates -path $path

        # Saving Path to log
        $outputLog = Add-LogEntry -data @{
            logPath = $PVMConfig.paths.pathVarBackup
            header  = "Original PATH`n$oldPath"
        }
        if ($outputLog -eq 0) {
            Show-Message -message "`nOriginal Path saved to '$($PVMConfig.paths.pathVarBackup)'"
        }

        $output = 0
        if ($path -ne $oldPath) {
            $output = Set-EnvVar -name 'Path' -value $path
            if ($output -eq 0) {
                Show-Success -message "`nPath optimized successfully"
            }
        }

        return $output
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to optimize system PATH variable"; exception = $_ }
        return -1
    }
}

function Invoke-PSCommand {
    param ($command)

    $process = Start-Process `
        -FilePath 'powershell.exe' `
        -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-Command', $command
        ) `
        -Verb RunAs `
        -PassThru `
        -Wait `
        -WindowStyle Hidden

    return $process.ExitCode
}

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    return $isAdmin
}

function Test-NotAdmin {
    return -not (Test-Admin)
}

function Resolve-PVMEngine {
    param ($shell)

    switch ($shell) {
        'powershell' { return 'powershell.exe' }
        'pwsh' { return 'pwsh.exe' }
        default {
            if (Get-Command pwsh -ErrorAction SilentlyContinue) {
                return 'pwsh.exe'
            }

            return 'powershell.exe'
        }
    }
}

function Split-ShellFromArguments {
    param ($arguments)

    $shell = $null
    $remaining = [System.Collections.Generic.List[string]]::new()

    foreach ($arg in @($arguments)) {
        if ($arg -match '^--shell=(.+)$') {
            $shell = $Matches[1].ToLower()
        } else {
            $remaining.Add($arg)
        }
    }

    return @{
        shell     = $shell
        arguments = $remaining.ToArray()
    }
}

function Invoke-PVMSubprocess {
    param ($command, $arguments = @())

    $shellSplit = Split-ShellFromArguments -arguments $arguments
    $shell = $shellSplit.shell
    $remainingArgs = $shellSplit.arguments

    if ($shell -and $shell -notin @('pwsh', 'powershell')) {
        Show-Error -message "`nInvalid value for --shell: '$shell' (expected 'pwsh' or 'powershell')"
        return @{ output = $null; code = -1 }
    }

    $engine = Resolve-PVMEngine -shell $shell

    if (-not (Get-Command $engine -ErrorAction SilentlyContinue)) {
        Show-Error -message "`nShell '$engine' not found."
        return @{ output = $null; code = -1 }
    }

    $pvmScript = "$PVMRoot\src\pvm.ps1"
    $processArgs = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', $pvmScript
        $command
        '--pvm-subprocess'
    ) + $remainingArgs

    $outputText = & $engine @processArgs | Out-String

    if ($null -ne $LASTEXITCODE) {
        return @{ output = $outputText; code = [int]$LASTEXITCODE }
    }

    return @{ output = $outputText; code = 0 }
}
