
function Is-OS-64Bit {
    return [System.Environment]::Is64BitOperatingSystem
}

function Get-All-EnvVars-Core {
    return [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Machine)
}

function Get-All-EnvVars {
    try {
        return Get-All-EnvVars-Core
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get all environment variables"; exception = $_ }
        return $null
    }
}

function Get-EnvVar-ByName-Core {
    param ($name)

    return [System.Environment]::GetEnvironmentVariable($name, [System.EnvironmentVariableTarget]::Machine)
}

function Get-EnvVar-ByName {
    param ($name, $optimized = $false)

    try {
        if ([string]::IsNullOrWhiteSpace($name)) {
            return $null
        }
        $name = $name.Trim()
        $value = Get-EnvVar-ByName-Core -name $name

        if ($optimized -eq $true) {
            $value = Get-Optimized-Env -name $name -value $value
        }

        return $value
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get environment variable '$name'"; exception = $_ }
        return $null
    }
}

function Set-EnvVar-Core {
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

        if (Is-Not-Admin) {
            $command = "[System.Environment]::SetEnvironmentVariable('$name', '$value', [System.EnvironmentVariableTarget]::Machine)"
            return (Run-PS-Command -command $command)
        }

        # We already have admin rights, proceed normally
        Set-EnvVar-Core -name $name -value $value
        return 0
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set environment variable '$name'"; exception = $_ }
        return -1
    }
}

function Get-Optimized-Env {
    param ($name, $value)

    $envVars = Get-All-EnvVars

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

    $value = Reconstruct-EnvContent -value $value

    return $value
}

function Reconstruct-EnvContent {
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
        $path = Get-EnvVar-ByName -name 'Path' -optimized $true
        if ($null -eq $path) {
            $path = ''
        }

        $oldPath = $path
        $path = Remove-PathDuplicates -path $path

        # Saving Path to log
        $outputLog = Log-Data -data @{
            logPath = $PVMConfig.paths.pathVarBackup
            header  = "Original PATH`n$oldPath"
        }
        if ($outputLog -eq 0) {
            Print-Host -message "`nOriginal Path saved to '$($PVMConfig.paths.pathVarBackup)'"
        }

        $output = 0
        if ($path -ne $oldPath) {
            $output = Set-EnvVar -name 'Path' -value $path
            if ($output -eq 0) {
                Print-Success -message "`nPath optimized successfully"
            }
        }

        return $output
    } catch {
        $null = Log-Data -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to optimize system PATH variable"; exception = $_ }
        return -1
    }
}

function Run-PS-Command {
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

function Is-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    return $isAdmin
}

function Is-Not-Admin {
    return -not (Is-Admin)
}
