
function Write-HostWrapper {
    param ([Parameter(ValueFromPipeline)]$object, $foregroundColor = $null, [switch]$noNewLine)

    process {
        if ($Global:PVMConfig.subprocess.enabled) {
            $Global:PVMConfig.subprocess.structuredOutput += @{
                message = $object
                color = $foregroundColor
                noNewLine = $noNewLine.IsPresent
            }
        } else {
            $params = @{
                Object    = $object
                NoNewline = $noNewLine
            }

            if ($null -ne $foregroundColor) {
                $params['ForegroundColor'] = $foregroundColor
            }

            Write-Host @params
        }
    }
}

function Read-HostWrapper {
    param ($prompt = $null, [switch]$notifyUser)

    if ($notifyUser) {
        Invoke-PromptSound
    }

    $response = Read-Host -Prompt $prompt

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $null
    }

    return $response.Trim()
}

function Add-ContentWrapper {
    param ($path, [Parameter(ValueFromPipeline)]$value, [switch]$disallowOutsideRoot)

    process {
        try {
            if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $path)) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
                return -1
            }

            Add-Content -Path $path -Value $value -Encoding UTF8 -ErrorAction Stop
            return 0
        } catch {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to add content to '$path'"; exception = $_ }
            return -1
        }
    }
}

function Set-ContentWrapper {
    param ($path, [Parameter(ValueFromPipeline)]$value, [switch]$disallowOutsideRoot)

    begin {
        $values = [System.Collections.Generic.List[object]]::new()
    } process {
        $values.Add($value)
    } end {
        try {
            if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $path)) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
                return -1
            }

            Set-Content -Path $path -Value $values -Encoding UTF8 -ErrorAction Stop
            return 0
        } catch {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set content to '$path'"; exception = $_ }
            return -1
        }
    }
}

function Invoke-WebRequestWrapper {
    param ($uri, $outFile = $null, $useBasicParsing = $true, $method = 'Default', [switch]$disallowOutsideRoot)

    try {
        $uri = $uri.Trim()

        $params = @{
            Uri = $uri
            UseBasicParsing = $useBasicParsing
            Method = $method
            ErrorAction = 'Stop'
        }

        if ($null -ne $outFile) {
            if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $outFile)) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$outFile'"; exception = "Path is invalid or not under project root" }
                return $null
            }

            $params.OutFile = $outFile
        }

        return Invoke-WebRequest @params
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to make request to $uri"; exception = $_ }
        return $null
    }
}

function Move-ItemWrapper {
    param ($path, $destination, [switch]$disallowOutsideRoot)

    try {
        if ($disallowOutsideRoot) {
            if (Test-PathInvalidOrNotUnderProjectRoot -path $path) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
                return -1
            }
            if (Test-PathInvalidOrNotUnderProjectRoot -path $destination) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$destination'"; exception = "Path is invalid or not under project root" }
                return -1
            }
        }
        Move-Item -Path $path -Destination $destination -Force -ErrorAction Stop
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to move '$path' to '$destination'"; exception = $_ }
        return -1
    }
}

function Copy-ItemWrapper {
    param ($path, $destination, [switch]$disallowOutsideRoot)

    try {
        if ($disallowOutsideRoot) {
            if (Test-PathInvalidOrNotUnderProjectRoot -path $path) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
                return -1
            }
            if (Test-PathInvalidOrNotUnderProjectRoot -path $destination) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$destination'"; exception = "Path is invalid or not under project root" }
                return -1
            }
        }

        Copy-Item -Path $path -Destination $destination -Force -ErrorAction Stop
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to copy '$path' to '$destination'"; exception = $_ }
        return -1
    }
}

function Remove-ItemWrapper {
    param ($path, [switch]$disallowOutsideRoot)

    try {
        if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $path)) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
            return -1
        }

        Remove-Item -Path $path -Force -Recurse -ErrorAction Stop
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to remove '$path'"; exception = $_ }
        return -1
    }
}

function Clear-ContentWrapper {
    param ($path, [switch]$disallowOutsideRoot)

    try {
        if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $path)) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
            return -1
        }

        Clear-Content -Path $path -ErrorAction Stop
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to clear content at '$path'"; exception = $_ }
        return -1
    }
}

function Get-ItemWrapper {
    param ($path)

    try {
        return Get-Item -Path $path -Force -ErrorAction Stop
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get item for '$path'"; exception = $_ }
        return $null
    }
}

function Get-ChildItemWrapper {
    param ($path, [switch]$recurse, [switch]$force, $filter = $null, [switch]$file, [switch]$directory)

    try {
        $params = @{
            Path        = $path
            Recurse     = $recurse
            Force       = $force
            File        = $file
            Directory   = $directory
            ErrorAction = 'Stop'
        }

        if (-not [string]::IsNullOrEmpty($filter)) {
            $params['Filter'] = $filter
        }

        return Get-ChildItem @params
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get items for '$path'"; exception = $_ }
        return $null
    }
}

function Get-ContentWrapper {
    param ($path, [switch]$raw)

    try {
        return Get-Content -Path $path -Raw:$raw -ErrorAction Stop
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to get content for '$path'"; exception = $_ }
        return $null
    }
}

function New-ItemWrapper {
    param ($type, $path, $target = $null, [switch]$disallowOutsideRoot)

    try {
        if ($disallowOutsideRoot) {
            if (Test-PathInvalidOrNotUnderProjectRoot -path $path) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
                return $null
            }
            if ($null -ne $target -and (Test-PathInvalidOrNotUnderProjectRoot -path $target)) {
                $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$target'"; exception = "Path is invalid or not under project root" }
                return $null
            }
        }

        $params = @{
            ItemType = $type
            Path = $path
            Force = $true
            ErrorAction = 'Stop'
        }

        if ($null -ne $target) {
            $params['Target'] = $target
        }

        return New-Item @params
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create item '$path'"; exception = $_ }
        return $null
    }
}

function Test-PathWrapper {
    param ($path, $pathType = $null)

    try {
        $params = @{ Path = $path }

        if ($null -ne $pathType) {
            $params['PathType'] = $pathType
        }

        return (Test-Path @params)
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to test path for '$path'"; exception = $_ }
        return $false
    }
}
