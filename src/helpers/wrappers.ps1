
function Read-Host-Wrapper {
    param ($prompt = $null)

    $response = Read-Host -Prompt $prompt

    if ([string]::IsNullOrWhiteSpace($response)) {
        return $null
    }

    return $response.Trim()
}

function Add-Content-Wrapper {
    param ($path, $value)

    Add-Content -Path $path -Value $value -Encoding UTF8
}

function Set-Content-Wrapper {
    param ($path, $value)

    Set-Content -Path $path -Value $value -Encoding UTF8
}

function Get-WebResponse {
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
