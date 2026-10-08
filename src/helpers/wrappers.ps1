
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
        if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $path)) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
            return
        }

        Add-Content -Path $path -Value $value -Encoding UTF8
    }
}

function Set-ContentWrapper {
    param ($path, [Parameter(ValueFromPipeline)]$value, [switch]$disallowOutsideRoot)

    begin {
        $values = @()
    } process {
        $values += $Value
    } end {
        if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $path)) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
            return
        }

        Set-Content -Path $path -Value $values -Encoding UTF8
    }
}

function Invoke-WebRequestWrapper {
    param ($uri, $outFile = $null, $useBasicParsing = $true, $method = 'Default', [switch]$disallowOutsideRoot)

    $uri = $uri.Trim()

    $params = @{
        Uri = $uri
        UseBasicParsing = $useBasicParsing
        Method = $method
    }

    if ($null -ne $outFile) {
        if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $outFile)) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$outFile'"; exception = "Path is invalid or not under project root" }
            return
        }

        $params.OutFile = $outFile
    }

    return Invoke-WebRequest @params
}

function Move-ItemWrapper {
    param ($path, $destination, [switch]$disallowOutsideRoot)

    if ($disallowOutsideRoot) {
        if (Test-PathInvalidOrNotUnderProjectRoot -path $path) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
            return
        }
        if (Test-PathInvalidOrNotUnderProjectRoot -path $destination) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$destination'"; exception = "Path is invalid or not under project root" }
            return
        }
    }
    Move-Item -Path $path -Destination $destination -Force
}

function Copy-ItemWrapper {
    param ($path, $destination, [switch]$disallowOutsideRoot)

    if ($disallowOutsideRoot) {
        if (Test-PathInvalidOrNotUnderProjectRoot -path $path) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
            return
        }
        if (Test-PathInvalidOrNotUnderProjectRoot -path $destination) {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$destination'"; exception = "Path is invalid or not under project root" }
            return
        }
    }

    Copy-Item -Path $path -Destination $destination -Force
}

function Remove-ItemWrapper {
    param ($path, [switch]$disallowOutsideRoot)

    if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $path)) {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
        return
    }

    Remove-Item -Path $path -Force -Recurse -ErrorAction SilentlyContinue
}

function Clear-ContentWrapper {
    param ($path, [switch]$disallowOutsideRoot)

    if ($disallowOutsideRoot -and (Test-PathInvalidOrNotUnderProjectRoot -path $path)) {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Path validation failed for '$path'"; exception = "Path is invalid or not under project root" }
        return
    }

    Clear-Content -Path $path
}

function Get-ItemWrapper {
    param ($path)

    return Get-Item -Path $path -Force -ErrorAction SilentlyContinue
}

function Get-ChildItemWrapper {
    param ($path, [switch]$recurse, [switch]$force, $filter = $null, [switch]$file, [switch]$directory)

    return Get-ChildItem -Path $path -Recurse:$recurse -Force:$force -Filter $filter -File:$file -Directory:$directory -ErrorAction SilentlyContinue
}

function Get-ContentWrapper {
    param ($path, [switch]$raw)

    return Get-Content -path $path -Raw:$raw -ErrorAction SilentlyContinue
}

function New-ItemWrapper {
    param ($type, $path, $target = $null, [switch]$disallowOutsideRoot)

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
        Path     = $path
        Force    = $true
    }

    if ($null -ne $target) {
        $params['Target'] = $target
    }

    return New-Item @params
}

function Test-PathWrapper {
    param ($path, $pathType = $null)

    $params = @{ Path = $path }

    if ($null -ne $pathType) {
        $params['PathType'] = $pathType
    }

    return (Test-Path @params)
}
