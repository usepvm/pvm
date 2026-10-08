
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
    param ($path, [Parameter(ValueFromPipeline)]$value)

    process {
        try {
            Add-Content -LiteralPath $path -Value $value -Encoding UTF8 -ErrorAction Stop
            return 0
        } catch {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to add content to '$path'"; exception = $_ }
            return -1
        }
    }
}

function Set-ContentWrapper {
    param ($path, [Parameter(ValueFromPipeline)]$value)

    begin {
        $values = [System.Collections.Generic.List[object]]::new()
    } process {
        $values.Add($value)
    } end {
        try {
            Set-Content -LiteralPath $path -Value $values -Encoding UTF8 -ErrorAction Stop
            return 0
        } catch {
            $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to set content to '$path'"; exception = $_ }
            return -1
        }
    }
}

function Invoke-WebRequestWrapper {
    param ($uri, $outFile = $null, $useBasicParsing = $true, $method = 'Default')

    try {
        $uri = $uri.Trim()

        $params = @{
            Uri = $uri
            UseBasicParsing = $useBasicParsing
            Method = $method
            ErrorAction = 'Stop'
        }

        if ($null -ne $outFile) {
            $params.OutFile = $outFile
        }

        return Invoke-WebRequest @params
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to make request to $uri"; exception = $_ }
        return $null
    }
}

function Move-ItemWrapper {
    param ($path, $destination)

    try {
        Move-Item -LiteralPath $path -Destination $destination -Force -ErrorAction Stop
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to move '$path' to '$destination'"; exception = $_ }
        return -1
    }
}

function Copy-ItemWrapper {
    param ($path, $destination)

    try {
        Copy-Item -LiteralPath $path -Destination $destination -Force -ErrorAction Stop
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to copy '$path' to '$destination'"; exception = $_ }
        return -1
    }
}

function Remove-ItemWrapper {
    param ($path)

    try {
        if (Test-PathNotExists -path $path) {
            return 0
        }

        Remove-Item -LiteralPath $path -Force -Recurse -ErrorAction Stop
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to remove '$path'"; exception = $_ }
        return -1
    }
}

function Clear-ContentWrapper {
    param ($path)

    try {
        Clear-Content -LiteralPath $path -ErrorAction Stop
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to clear content at '$path'"; exception = $_ }
        return -1
    }
}

function Get-ItemWrapper {
    param ($path)

    return Get-Item -Path $path -Force -ErrorAction SilentlyContinue
}

function Get-ChildItemWrapper {
    param ($path, [switch]$recurse, [switch]$force, $filter = $null, [switch]$file, [switch]$directory)

    $params = @{
        Path        = $path
        Recurse     = $recurse
        Force       = $force
        File        = $file
        Directory   = $directory
        ErrorAction = 'SilentlyContinue'
    }

    if (-not [string]::IsNullOrEmpty($filter)) {
        $params['Filter'] = $filter
    }

    return Get-ChildItem @params
}

function Get-ContentWrapper {
    param ($path, [switch]$raw)

    return Get-Content -Path $path -Raw:$raw -ErrorAction SilentlyContinue
}

function New-ItemWrapper {
    param ($type, $path, $target = $null)

    $params = @{
        ItemType = $type
        Path = $path
        Force = $true
        ErrorAction = 'Stop'
    }

    if ($null -ne $target) {
        $params['Target'] = $target
    }

    try {
        return New-Item @params
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create item '$path'"; exception = $_ }
        return -1
    }
}

function Test-PathWrapper {
    param ($path, $pathType = $null)

    $params = @{ Path = $path }

    if ($null -ne $pathType) {
        $params['PathType'] = $pathType
    }

    return (Test-Path @params)
}
