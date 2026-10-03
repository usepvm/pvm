
function Get-CertBundlePath {
    param ($includeLocalCertificates = $false)

    $certDirectory = $Global:PVMConfig.paths.directories.cert
    if ($includeLocalCertificates) {
        return "$certDirectory\cacert-local.pem"
    }

    return "$certDirectory\cacert.pem"
}

function Set-PHPCertificateBundle {
    param ($iniPath, $bundlePath)

    try {
        if (Test-FileNotExists -path $iniPath) {
            Show-Error -message "`nphp.ini not found at: $iniPath"
            return -1
        }

        $lines = @(Get-ContentWrapper -path $iniPath)
        if ($lines.Count -eq 0) {
            Show-Error -message "`nFailed to read php.ini at: $iniPath"
            return -1
        }

        $settings = @('curl.cainfo', 'openssl.cafile')
        foreach ($setting in $settings) {
            $pattern = '^\s*;?\s*' + [regex]::Escape($setting) + '\s*='
            $matchingLineNumbers = @(
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match $pattern) { $i }
                }
            )

            if ($matchingLineNumbers.Count -eq 0) {
                $lines += "$setting = '$bundlePath'"
            } else {
                foreach ($lineNumber in $matchingLineNumbers) {
                    $lines[$lineNumber] = "$setting = '$bundlePath'"
                }
            }
        }

        if ((Backup-IniFile -iniPath $iniPath) -ne 0) {
            Show-Error -message "`nFailed to back up php.ini before changing CA settings."
            return -1
        }

        Set-ContentWrapper -path $iniPath -value $lines

        foreach ($setting in $settings) {
            $configured = @(Get-ContentWrapper -path $iniPath | Where-Object {
                $_ -match ('^\s*' + [regex]::Escape($setting) + "\s*=\s*'" + [regex]::Escape($bundlePath) + "'\s*$")
            })
            if ($configured.Count -eq 0) {
                Show-Error -message "`nFailed to configure $setting in php.ini."
                return -1
            }
        }

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to configure PHP CA bundle"; exception = $_ }
        Show-Error -message "`nFailed to configure PHP CA bundle: $($_.Exception.Message)"
        return -1
    }
}

function Get-LocalCertificateFiles {
    param ($localCertificateDirectory)

    if (Test-DirectoryNotExists -path $localCertificateDirectory) {
        return @()
    }

    return @(Get-ChildItemWrapper -path "$localCertificateDirectory\*.crt.pem" -file)
}

function Write-PHPCertificateTrustBundle {
    param ($baseBundlePath, $trustBundlePath, $localCertificateFiles)

    try {
        $contents = [System.IO.File]::ReadAllText($baseBundlePath)
        foreach ($certificateFile in $localCertificateFiles) {
            $certificate = [System.IO.File]::ReadAllText($certificateFile.FullName)
            if ($certificate -notmatch '-----BEGIN CERTIFICATE-----') {
                throw "Local certificate is not valid PEM: $($certificateFile.FullName)"
            }
            $contents += "`r`n$certificate"
        }

        [System.IO.File]::WriteAllText($trustBundlePath, $contents, [System.Text.Encoding]::ASCII)
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create PHP CA trust bundle"; exception = $_ }
        Show-Error -message "`nFailed to create PHP CA trust bundle: $($_.Exception.Message)"
        return -1
    }
}

function Set-ActivePHPTrustBundle {
    param ($bundlePath)

    $currentPhpVersion = Get-CurrentPHPVersion
    if (-not $currentPhpVersion -or -not $currentPhpVersion.path) {
        Show-Error -message "`nFailed to get current PHP version."
        return -1
    }

    $iniPath = "$($currentPhpVersion.path)\php.ini"
    return Set-PHPCertificateBundle -iniPath $iniPath -bundlePath $bundlePath
}

function Update-PHPCertificateBundle {
    try {
        $currentPhpVersion = Get-CurrentPHPVersion
        if (-not $currentPhpVersion -or -not $currentPhpVersion.path) {
            Show-Error -message "`nFailed to get current PHP version."
            return -1
        }

        $certDirectory = $Global:PVMConfig.paths.directories.cert
        $created = New-Directory -path $certDirectory
        if ($created -ne 0) {
            Show-Error -message "`nFailed to create certificate directory: $certDirectory"
            return -1
        }

        $baseBundlePath = Get-CertBundlePath
        $downloadPath = "$baseBundlePath.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            $null = Invoke-WebRequestWrapper -uri $Global:PVMConfig.links.curlCaBundle -outFile $downloadPath
            $content = [System.IO.File]::ReadAllText($downloadPath)
            if ($content -notmatch '-----BEGIN CERTIFICATE-----' -or $content -notmatch '-----END CERTIFICATE-----') {
                throw 'The downloaded CA bundle does not contain PEM certificates.'
            }

            Move-ItemWrapper -path $downloadPath -destination $baseBundlePath
        } finally {
            if (Test-FileExists -path $downloadPath) {
                Remove-ItemWrapper -path $downloadPath
            }
        }

        $localCertificateDirectory = "$certDirectory\local"
        $localCertificates = Get-LocalCertificateFiles -localCertificateDirectory $localCertificateDirectory
        $bundlePath = $baseBundlePath
        if ($localCertificates.Count -gt 0) {
            $bundlePath = Get-CertBundlePath -includeLocalCertificates $true
            $code = Write-PHPCertificateTrustBundle -baseBundlePath $baseBundlePath -trustBundlePath $bundlePath -localCertificateFiles $localCertificates
            if ($code -ne 0) {
                return -1
            }
        }

        $code = Set-PHPCertificateBundle -iniPath "$($currentPhpVersion.path)\php.ini" -bundlePath $bundlePath
        if ($code -ne 0) {
            return -1
        }

        Show-Success -message "`nDownloaded the trusted CA bundle to: $bundlePath"
        Show-Message -message "Configured curl.cainfo and openssl.cafile for PHP $($currentPhpVersion.version)."
        Show-Info -message "This enables HTTPS support for Composer, API calls, and secure HTTP requests."
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to download PHP CA bundle"; exception = $_ }
        Show-Error -message "`nFailed to download or configure the PHP CA bundle: $($_.Exception.Message)"
        return -1
    }
}

function Invoke-LocalCertificateGenerator {
    param ($phpExecutable, $hostName, $subjectAltName, $certificatePath, $privateKeyPath, $temporaryDirectory)

    $configPath = "$temporaryDirectory\openssl.cnf"
    $scriptPath = "$temporaryDirectory\generate-certificate.php"
    $config = @(
        '[ req ]'
        'distinguished_name = req_distinguished_name'
        'req_extensions = v3_req'
        'x509_extensions = v3_req'
        'prompt = no'
        '[ req_distinguished_name ]'
        "CN = $hostName"
        'O = PVM Local Development'
        '[ v3_req ]'
        'basicConstraints = critical,CA:FALSE'
        'keyUsage = critical,digitalSignature,keyEncipherment'
        'extendedKeyUsage = serverAuth'
        "subjectAltName = $subjectAltName"
    ) -join "`n"
    $script = @(
        '<?php'
        '$hostName = $argv[1];'
        '$certificatePath = $argv[2];'
        '$privateKeyPath = $argv[3];'
        '$configPath = $argv[4];'
        '$options = ['
        "    'config' => `$configPath,"
        "    'private_key_type' => OPENSSL_KEYTYPE_RSA,"
        "    'private_key_bits' => 2048,"
        '];'
        '$privateKey = openssl_pkey_new($options);'
        'if ($privateKey === false) {'
            'fwrite(STDERR, "OpenSSL could not generate a private key.\n");'
            'exit(1);'
        '}'
        '$request = openssl_csr_new('
        "    ['commonName' => `$hostName, 'organizationName' => 'PVM Local Development'],"
        '    $privateKey,'
        "    ['config' => `$configPath, 'digest_alg' => 'sha256', 'req_extensions' => 'v3_req']"
        ');'
        'if ($request === false) {'
        '    fwrite(STDERR, "OpenSSL could not create the certificate request.\n");'
        '    exit(1);'
        '}'
        '$certificate = openssl_csr_sign('
        '    $request,'
        '    null,'
        '    $privateKey,'
        '    825,'
        "    ['config' => `$configPath, 'digest_alg' => 'sha256', 'x509_extensions' => 'v3_req']"
        ');'
        'if ($certificate === false'
        "    || !openssl_pkey_export(`$privateKey, `$privateKeyPem, null, ['config' => `$configPath])"
        '    || !openssl_x509_export($certificate, $certificatePem)'
        '    || file_put_contents($privateKeyPath, $privateKeyPem, LOCK_EX) === false'
        '    || file_put_contents($certificatePath, $certificatePem, LOCK_EX) === false) {'
        '    fwrite(STDERR, "OpenSSL could not write the certificate and private key.\n");'
        '    exit(1);'
        '}'
    ) -join "`n"

    try {
        [System.IO.File]::WriteAllText($configPath, $config, [System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText($scriptPath, $script, [System.Text.Encoding]::ASCII)
        $output = & $phpExecutable $scriptPath $hostName $certificatePath $privateKeyPath $configPath 2>&1
        if ($LASTEXITCODE -ne 0) {
            Show-Error -message "`nPHP certificate generation failed: $($output -join "`n")"
            return -1
        }

        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to invoke PHP OpenSSL"; exception = $_ }
        Show-Error -message "`nFailed to invoke PHP OpenSSL: $($_.Exception.Message)"
        return -1
    }
}

function New-LocalPHPCertificate {
    param ($hostName)

    try {
        if ([string]::IsNullOrWhiteSpace($hostName)) {
            $hostName = 'localhost'
        }

        $ipAddress = $null
        if ([System.Net.IPAddress]::TryParse($hostName, [ref]$ipAddress)) {
            $subjectAltName = "DNS:localhost,IP:$hostName"
        } elseif ($hostName -match '^(?=.{1,253}$)(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)(?:\.(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?))*$') {
            $subjectAltName = if ($hostName -eq 'localhost') { 'DNS:localhost,IP:127.0.0.1' } else { "DNS:$hostName,DNS:localhost,IP:127.0.0.1" }
        } else {
            Show-Error -message "`nInvalid hostname. Use a DNS hostname or IP address."
            return -1
        }

        $currentPhpVersion = Get-CurrentPHPVersion
        if (-not $currentPhpVersion -or -not $currentPhpVersion.path) {
            Show-Error -message "`nFailed to get current PHP version."
            return -1
        }

        $baseBundlePath = Get-CertBundlePath
        if (Test-FileNotExists -path $baseBundlePath) {
            Show-Error -message "`nRun 'pvm cert bundle' first to download the trusted public CA bundle."
            return -1
        }

        $phpExecutable = "$($currentPhpVersion.path)\php.exe"
        if (Test-FileNotExists -path $phpExecutable) {
            Show-Error -message "`nPHP executable not found: $phpExecutable"
            return -1
        }

        $localCertificateDirectory = "$($Global:PVMConfig.paths.directories.cert)\local"
        $created = New-Directory -path $localCertificateDirectory
        if ($created -ne 0) {
            Show-Error -message "`nFailed to create local certificate directory: $localCertificateDirectory"
            return -1
        }

        $safeHostName = $hostName -replace '[^a-zA-Z0-9._-]', '_'
        $certificatePath = "$localCertificateDirectory\$safeHostName.crt.pem"
        $privateKeyPath = "$localCertificateDirectory\$safeHostName.key.pem"
        if ((Test-FileExists -path $certificatePath) -or (Test-FileExists -path $privateKeyPath)) {
            Show-Error -message "`nCertificate files already exist for '$hostName'; refusing to overwrite them."
            return -1
        }

        $temporaryDirectory = "$($Global:PVMConfig.paths.directories.cert)\pvm-cert-$([guid]::NewGuid().ToString('N'))"
        $created = New-Directory -path $temporaryDirectory
        if ($created -ne 0) {
            Show-Error -message "`nFailed to create temporary directory: $temporaryDirectory"
            return -1
        }

        try {
            $code = Invoke-LocalCertificateGenerator -phpExecutable $phpExecutable -hostName $hostName -subjectAltName $subjectAltName -certificatePath $certificatePath -privateKeyPath $privateKeyPath -temporaryDirectory $temporaryDirectory
            if ($code -ne 0) {
                if (Test-FileExists -path $certificatePath) { Remove-ItemWrapper -path $certificatePath }
                if (Test-FileExists -path $privateKeyPath) { Remove-ItemWrapper -path $privateKeyPath }
                return -1
            }
            if ((Test-FileNotExists -path $certificatePath) -or (Test-FileNotExists -path $privateKeyPath)) {
                if (Test-FileExists -path $certificatePath) { Remove-ItemWrapper -path $certificatePath }
                if (Test-FileExists -path $privateKeyPath) { Remove-ItemWrapper -path $privateKeyPath }
                Show-Error -message "`nPHP did not create both the certificate and private key."
                return -1
            }
        } finally {
            if (Test-DirectoryExists -path $temporaryDirectory) {
                Remove-ItemWrapper -path $temporaryDirectory
            }
        }

        $trustBundlePath = Get-CertBundlePath -includeLocalCertificates $true
        $localCertificates = Get-LocalCertificateFiles -localCertificateDirectory $localCertificateDirectory

        $code = Write-PHPCertificateTrustBundle -baseBundlePath $baseBundlePath -trustBundlePath $trustBundlePath -localCertificateFiles $localCertificates
        if ($code -ne 0) {
            return -1
        }

        $code = Set-ActivePHPTrustBundle -bundlePath $trustBundlePath
        if ($code -ne 0) {
            return -1
        }

        Show-Success -message "`nCreated self-signed local certificate for '$hostName'."
        Show-Message -message "- Certificate: $certificatePath"
        Show-Message -message "- Private key: $privateKeyPath"
        Show-Message -message "- Added to PHP trust bundle: $trustBundlePath"
        Show-Warning -message 'This certificate is for local development only; do not use it in production.'
        Show-Info -message "Note: This is an optional feature for local HTTPS testing. Most users only need 'pvm cert bundle'."
        return 0
    } catch {
        $null = Add-LogEntry -data @{ header = "$($MyInvocation.MyCommand.Name) - Failed to create local PHP certificate"; exception = $_ }
        Show-Error -message "`nFailed to create local certificate: $($_.Exception.Message)"
        return -1
    }
}
