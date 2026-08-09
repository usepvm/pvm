
function Write-HostWrapper {
    param ($object, $foregroundColor = $null, [switch]$noNewLine)

    $params = @{
        Object    = $object
        NoNewline = $noNewLine
    }

    if ($null -ne $foregroundColor) {
        $params['ForegroundColor'] = $foregroundColor
    }

    Write-Host @params
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
    param ($path, $value)

    Add-Content -Path $path -Value $value -Encoding UTF8
}

function Set-ContentWrapper {
    param ($path, $value)

    Set-Content -Path $path -Value $value -Encoding UTF8
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

function Copy-ItemWrapper {
    param ($path, $destination)

    Copy-Item -Path $path -Destination $destination -Force
}

function Remove-ItemWrapper {
    param ($path)

    Remove-Item -Path $path -Force -Recurse -ErrorAction SilentlyContinue
}
