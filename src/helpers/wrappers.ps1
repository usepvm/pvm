
function Write-HostWrapper {
    param ([Parameter(ValueFromPipeline)]$object, $foregroundColor = $null, [switch]$noNewLine)

    process {
        if ($Global:PVMSubprocess.enabled) {
            $Global:PVMSubprocess.structuredOutput += @{
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
    param ($prompt = $null)

    $response = Read-Host -Prompt $prompt

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $null
    }

    return $response.Trim()
}

function Add-ContentWrapper {
    param ($path, [Parameter(ValueFromPipeline)]$value)

    process {
        Add-Content -Path $path -Value $value -Encoding UTF8
    }
}

function Set-ContentWrapper {
    param ($path, [Parameter(ValueFromPipeline)]$value)

    begin {
        $values = @()
    } process {
        $values += $Value
    } end {
        Set-Content -Path $Path -Value $values -Encoding UTF8
    }
}

function Invoke-WebRequestWrapper {
    param ($uri, $outFile = $null, $useBasicParsing = $true)

    $uri = $uri.Trim()

    $params = @{
        Uri = $uri
        UseBasicParsing = $useBasicParsing
    }

    if ($outFile) {
        $params.OutFile = $outFile
    }

    return Invoke-WebRequest @params
}

function Move-ItemWrapper {
    param ($path, $destination)

    Move-Item -Path $path -Destination $destination -Force
}

function Copy-ItemWrapper {
    param ($path, $destination)

    Copy-Item -Path $path -Destination $destination -Force
}

function Remove-ItemWrapper {
    param ($path)

    Remove-Item -Path $path -Force -Recurse -ErrorAction SilentlyContinue
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
    param ($type, $path, $target)

    $params = @{
        ItemType = $type
        Path     = $path
        Force    = $true
    }

    if ($null -ne $target) {
        $params['Target'] = $target
    }

    New-Item @params | Out-Null
}
