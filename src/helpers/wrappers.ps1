
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
