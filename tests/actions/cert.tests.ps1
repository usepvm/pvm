BeforeAll {
    $script:TEST_DRIVE = $Global:CurrentTestDrive
    $script:certDirectory = $Global:PVMConfig.paths.directories.cert
    $script:phpDirectory = "$script:TEST_DRIVE\php"
    $script:phpIniPath = "$script:phpDirectory\php.ini"
    $script:baseBundlePath = "$script:certDirectory\cacert.pem"
    $script:localCertificateDirectory = "$script:certDirectory\local"
    $script:trustBundlePath = "$script:certDirectory\cacert-local.pem"
    $script:generatorDirectory = "$script:TEST_DRIVE\generator"

    $null = New-Directory -path $script:phpDirectory
    $null = New-Directory -path $script:certDirectory
    $null = New-Directory -path $script:generatorDirectory

    $script:pem = { param ($name) "-----BEGIN CERTIFICATE-----`n$name`n-----END CERTIFICATE-----" }
    $script:resetIni = {
        @(
            ';curl.cainfo ='
            '[openssl]'
            ';openssl.cafile ='
            ';openssl.capath ='
        ) | Set-ContentWrapper -path $script:phpIniPath
        Remove-Item "$script:phpIniPath.bak" -Force -ErrorAction SilentlyContinue
    }
    $script:resetCertDirectory = {
        Remove-Item "$script:certDirectory\*" -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Directory -path $script:certDirectory
    }

    Mock Show-Error { }
    Mock Show-Message { }
    Mock Show-Success { }
    Mock Show-Warning { }
    Mock Show-Info { }
    Mock Add-LogEntry { return 0 }
}

Describe "Get-CertBundlePath" {
    It "Returns the base bundle path by default" {
        Get-CertBundlePath | Should -Be "$script:certDirectory\cacert.pem"
    }

    It "Returns the base bundle path when local certificates are excluded" {
        Get-CertBundlePath -includeLocalCertificates $false | Should -Be "$script:certDirectory\cacert.pem"
    }

    It "Returns the trust bundle path when local certificates are included" {
        Get-CertBundlePath -includeLocalCertificates $true | Should -Be "$script:certDirectory\cacert-local.pem"
    }
}

Describe "Set-PHPCertificateBundle" {
    BeforeEach {
        & $script:resetIni
    }

    It "Enables curl.cainfo and openssl.cafile and keeps unrelated lines" {
        $bundle = 'C:\Program Files\PVM\cert\cacert.pem'

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $bundle

        $result | Should -Be 0
        $content = Get-ContentWrapper -path $script:phpIniPath
        $content | Should -Contain "curl.cainfo = '$bundle'"
        $content | Should -Contain "openssl.cafile = '$bundle'"
        $content | Should -Contain ';openssl.capath ='
        $content | Should -Contain '[openssl]'
        Test-Path "$script:phpIniPath.bak" | Should -BeTrue
    }

    It "Appends CA settings when the ini does not contain them" {
        '[PHP]' | Set-ContentWrapper -path $script:phpIniPath

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $script:baseBundlePath

        $result | Should -Be 0
        $content = Get-ContentWrapper -path $script:phpIniPath
        $content | Should -Contain "curl.cainfo = '$script:baseBundlePath'"
        $content | Should -Contain "openssl.cafile = '$script:baseBundlePath'"
    }

    It "Replaces already active settings" {
        @(
            'curl.cainfo = "C:/old/cacert.pem"'
            'openssl.cafile = "C:/old/cacert.pem"'
        ) | Set-ContentWrapper -path $script:phpIniPath

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $script:baseBundlePath

        $result | Should -Be 0
        $content = @(Get-ContentWrapper -path $script:phpIniPath)
        $content | Should -Not -Contain 'curl.cainfo = "C:/old/cacert.pem"'
        $content | Should -Contain "curl.cainfo = '$script:baseBundlePath'"
        @($content | Where-Object { $_ -match '^curl\.cainfo' }).Count | Should -Be 1
    }

    It "Replaces every matching line when a setting appears more than once" {
        @(
            ';curl.cainfo ='
            'curl.cainfo = "C:/old.pem"'
            ';openssl.cafile ='
        ) | Set-ContentWrapper -path $script:phpIniPath

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $script:baseBundlePath

        $result | Should -Be 0
        $content = @(Get-ContentWrapper -path $script:phpIniPath)
        @($content | Where-Object { $_ -eq "curl.cainfo = '$script:baseBundlePath'" }).Count | Should -Be 2
    }

    It "Fails when php.ini does not exist" {
        Remove-Item $script:phpIniPath -Force

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $script:baseBundlePath

        $result | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like '*php.ini not found*' }
    }

    It "Fails when php.ini is empty" {
        '' | Set-Content -LiteralPath $script:phpIniPath -NoNewline

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $script:baseBundlePath

        $result | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like '*Failed to read php.ini*' }
    }

    It "Fails and leaves php.ini untouched when the backup fails" {
        Mock Backup-IniFile { return -1 }
        $before = Get-ContentWrapper -path $script:phpIniPath

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $script:baseBundlePath

        $result | Should -Be -1
        Get-ContentWrapper -path $script:phpIniPath | Should -Be $before
        Should -Invoke Show-Error -ParameterFilter { $message -like '*back up php.ini*' }
    }

    It "Logs and fails when an exception is thrown" {
        Mock Get-ContentWrapper { throw 'boom' }

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $script:baseBundlePath

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
        Should -Invoke Show-Error -ParameterFilter { $message -like '*boom*' }
    }

    It "Fails when the written settings cannot be verified" {
        Mock Set-ContentWrapper { }

        $result = Set-PHPCertificateBundle -iniPath $script:phpIniPath -bundlePath $script:baseBundlePath

        $result | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like '*Failed to configure curl.cainfo in php.ini*' }
    }
}

Describe "Get-LocalCertificateFiles" {
    BeforeEach {
        & $script:resetCertDirectory
    }

    It "Returns an empty array when the directory does not exist" {
        $result = @(Get-LocalCertificateFiles -localCertificateDirectory "$script:certDirectory\missing")

        $result.Count | Should -Be 0
    }

    It "Returns an empty array when the directory has no certificates" {
        $null = New-Directory -path $script:localCertificateDirectory

        @(Get-LocalCertificateFiles -localCertificateDirectory $script:localCertificateDirectory).Count | Should -Be 0
    }

    It "Returns only *.crt.pem files" {
        $null = New-Directory -path $script:localCertificateDirectory
        (& $script:pem 'A') | Set-ContentWrapper -path "$script:localCertificateDirectory\a.test.crt.pem"
        (& $script:pem 'B') | Set-ContentWrapper -path "$script:localCertificateDirectory\b.test.crt.pem"
        'KEY' | Set-ContentWrapper -path "$script:localCertificateDirectory\a.test.key.pem"
        'TXT' | Set-ContentWrapper -path "$script:localCertificateDirectory\notes.txt"

        $result = @(Get-LocalCertificateFiles -localCertificateDirectory $script:localCertificateDirectory)

        $result.Count | Should -Be 2
        ($result.Name | Sort-Object) | Should -Be @('a.test.crt.pem', 'b.test.crt.pem')
    }
}

Describe "Write-PHPCertificateTrustBundle" {
    BeforeEach {
        & $script:resetCertDirectory
        $null = New-Directory -path $script:localCertificateDirectory
        (& $script:pem 'PUBLICCERT') | Set-ContentWrapper -path $script:baseBundlePath
        (& $script:pem 'LOCALCERT') | Set-ContentWrapper -path "$script:localCertificateDirectory\localhost.crt.pem"
    }

    It "Preserves public CAs and appends local certificates" {
        $localFiles = Get-LocalCertificateFiles -localCertificateDirectory $script:localCertificateDirectory

        $result = Write-PHPCertificateTrustBundle -baseBundlePath $script:baseBundlePath -trustBundlePath $script:trustBundlePath -localCertificateFiles $localFiles

        $result | Should -Be 0
        $content = [System.IO.File]::ReadAllText($script:trustBundlePath)
        $content | Should -Match 'PUBLICCERT'
        $content | Should -Match 'LOCALCERT'
        $content.IndexOf('PUBLICCERT') | Should -BeLessThan $content.IndexOf('LOCALCERT')
    }

    It "Appends multiple local certificates" {
        (& $script:pem 'SECONDCERT') | Set-ContentWrapper -path "$script:localCertificateDirectory\second.crt.pem"
        $localFiles = Get-LocalCertificateFiles -localCertificateDirectory $script:localCertificateDirectory

        $result = Write-PHPCertificateTrustBundle -baseBundlePath $script:baseBundlePath -trustBundlePath $script:trustBundlePath -localCertificateFiles $localFiles

        $result | Should -Be 0
        $content = [System.IO.File]::ReadAllText($script:trustBundlePath)
        $content | Should -Match 'LOCALCERT'
        $content | Should -Match 'SECONDCERT'
    }

    It "Writes only the base bundle when there are no local certificates" {
        $result = Write-PHPCertificateTrustBundle -baseBundlePath $script:baseBundlePath -trustBundlePath $script:trustBundlePath -localCertificateFiles @()

        $result | Should -Be 0
        $content = [System.IO.File]::ReadAllText($script:trustBundlePath)
        $content | Should -Match 'PUBLICCERT'
        $content | Should -Not -Match 'LOCALCERT'
    }

    It "Rejects a local certificate that is not PEM and writes no bundle" {
        'not a certificate' | Set-ContentWrapper -path "$script:localCertificateDirectory\bad.crt.pem"
        $localFiles = Get-LocalCertificateFiles -localCertificateDirectory $script:localCertificateDirectory

        $result = Write-PHPCertificateTrustBundle -baseBundlePath $script:baseBundlePath -trustBundlePath $script:trustBundlePath -localCertificateFiles $localFiles

        $result | Should -Be -1
        Test-Path -LiteralPath $script:trustBundlePath | Should -BeFalse
        Should -Invoke Add-LogEntry -Times 1
        Should -Invoke Show-Error -ParameterFilter { $message -like '*not valid PEM*' }
    }

    It "Fails when the base bundle does not exist" {
        Remove-Item $script:baseBundlePath -Force

        $result = Write-PHPCertificateTrustBundle -baseBundlePath $script:baseBundlePath -trustBundlePath $script:trustBundlePath -localCertificateFiles @()

        $result | Should -Be -1
        Test-Path -LiteralPath $script:trustBundlePath | Should -BeFalse
    }
}

Describe "Set-ActivePHPTrustBundle" {
    It "Fails when there is no current PHP version" {
        Mock Get-CurrentPHPVersion { return $null }
        Mock Set-PHPCertificateBundle { return 0 }

        $result = Set-ActivePHPTrustBundle -bundlePath $script:trustBundlePath

        $result | Should -Be -1
        Should -Invoke Set-PHPCertificateBundle -Times 0
        Should -Invoke Show-Error -ParameterFilter { $message -like '*current PHP version*' }
    }

    It "Fails when the current PHP version has no path" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.3.0'; path = $null } }
        Mock Set-PHPCertificateBundle { return 0 }

        $result = Set-ActivePHPTrustBundle -bundlePath $script:trustBundlePath

        $result | Should -Be -1
        Should -Invoke Set-PHPCertificateBundle -Times 0
    }

    It "Configures php.ini of the current PHP version" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.3.0'; path = $script:phpDirectory } }
        Mock Set-PHPCertificateBundle { return 0 }

        $result = Set-ActivePHPTrustBundle -bundlePath $script:trustBundlePath

        $result | Should -Be 0
        Should -Invoke Set-PHPCertificateBundle -Times 1 -ParameterFilter {
            $iniPath -eq "$script:phpDirectory\php.ini" -and $bundlePath -eq $script:trustBundlePath
        }
    }

    It "Propagates a failure from Set-PHPCertificateBundle" {
        Mock Get-CurrentPHPVersion { return @{ version = '8.3.0'; path = $script:phpDirectory } }
        Mock Set-PHPCertificateBundle { return -1 }

        $result = Set-ActivePHPTrustBundle -bundlePath $script:trustBundlePath

        $result | Should -Be -1
    }
}

Describe "Update-PHPCertificateBundle" {
    BeforeEach {
        & $script:resetCertDirectory
        & $script:resetIni

        Mock Get-CurrentPHPVersion {
            return @{ version = '8.3.0'; path = $script:phpDirectory }
        }
        Mock Invoke-WebRequestWrapper {
            param ($uri, $outFile)
            [System.IO.File]::WriteAllText($outFile, "-----BEGIN CERTIFICATE-----`nPUBLICCERT`n-----END CERTIFICATE-----")
        }
    }

    It "Downloads the public bundle and configures the active PHP version" {
        $result = Update-PHPCertificateBundle

        $result | Should -Be 0
        [System.IO.File]::ReadAllText($script:baseBundlePath) | Should -Match 'PUBLICCERT'
        (Get-ContentWrapper -path $script:phpIniPath) | Should -Contain "openssl.cafile = '$script:baseBundlePath'"
        (Get-ContentWrapper -path $script:phpIniPath) | Should -Contain "curl.cainfo = '$script:baseBundlePath'"
        Should -Invoke Invoke-WebRequestWrapper -Times 1 -ParameterFilter {
            $uri -eq $Global:PVMConfig.links.curlCaBundle
        }
        Should -Invoke Show-Success -Times 1
    }

    It "Leaves no temporary download files behind" {
        $result = Update-PHPCertificateBundle

        $result | Should -Be 0
        @(Get-ChildItem -Path $script:certDirectory -Filter '*.tmp' -Force).Count | Should -Be 0
    }

    It "Uses the trust bundle when local certificates exist" {
        $null = New-Directory -path $script:localCertificateDirectory
        (& $script:pem 'LOCALCERT') | Set-ContentWrapper -path "$script:localCertificateDirectory\myapp.test.crt.pem"

        $result = Update-PHPCertificateBundle

        $result | Should -Be 0
        $content = [System.IO.File]::ReadAllText($script:trustBundlePath)
        $content | Should -Match 'PUBLICCERT'
        $content | Should -Match 'LOCALCERT'
        (Get-ContentWrapper -path $script:phpIniPath) | Should -Contain "openssl.cafile = '$script:trustBundlePath'"
    }

    It "Fails when there is no current PHP version" {
        Mock Get-CurrentPHPVersion { return $null }

        $result = Update-PHPCertificateBundle

        $result | Should -Be -1
        Should -Invoke Invoke-WebRequestWrapper -Times 0
    }

    It "Fails when the certificate directory cannot be created" {
        Mock New-Directory { return -1 }

        $result = Update-PHPCertificateBundle

        $result | Should -Be -1
        Should -Invoke Invoke-WebRequestWrapper -Times 0
        Should -Invoke Show-Error -ParameterFilter { $message -like '*certificate directory*' }
    }

    It "Rejects a download without PEM certificate markers" {
        Mock Invoke-WebRequestWrapper {
            param ($uri, $outFile)
            [System.IO.File]::WriteAllText($outFile, 'not a PEM bundle')
        }

        $result = Update-PHPCertificateBundle

        $result | Should -Be -1
        Test-Path -LiteralPath $script:baseBundlePath | Should -BeFalse
        @(Get-ChildItem -Path $script:certDirectory -Filter '*.tmp' -Force).Count | Should -Be 0
    }

    It "Rejects a download with only a BEGIN marker" {
        Mock Invoke-WebRequestWrapper {
            param ($uri, $outFile)
            [System.IO.File]::WriteAllText($outFile, '-----BEGIN CERTIFICATE-----')
        }

        $result = Update-PHPCertificateBundle

        $result | Should -Be -1
        Test-Path -LiteralPath $script:baseBundlePath | Should -BeFalse
    }

    It "Fails and cleans up when the download throws" {
        Mock Invoke-WebRequestWrapper { throw 'network down' }

        $result = Update-PHPCertificateBundle

        $result | Should -Be -1
        Test-Path -LiteralPath $script:baseBundlePath | Should -BeFalse
        Should -Invoke Add-LogEntry -Times 1
        Should -Invoke Show-Error -ParameterFilter { $message -like '*network down*' }
    }

    It "Fails when the trust bundle cannot be written" {
        $null = New-Directory -path $script:localCertificateDirectory
        (& $script:pem 'LOCALCERT') | Set-ContentWrapper -path "$script:localCertificateDirectory\myapp.test.crt.pem"
        Mock Write-PHPCertificateTrustBundle { return -1 }

        $result = Update-PHPCertificateBundle

        $result | Should -Be -1
        Should -Invoke Show-Success -Times 0
    }

    It "Fails when php.ini cannot be configured" {
        Mock Set-PHPCertificateBundle { return -1 }

        $result = Update-PHPCertificateBundle

        $result | Should -Be -1
        Should -Invoke Show-Success -Times 0
    }
}

Describe "Invoke-LocalCertificateGenerator" {
    BeforeEach {
        $script:genTemp = "$script:generatorDirectory\tmp"
        Remove-Item $script:genTemp -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Directory -path $script:genTemp

        $script:okPhp = "$script:generatorDirectory\php-ok.cmd"
        $script:failPhp = "$script:generatorDirectory\php-fail.cmd"
        Set-Content -LiteralPath $script:okPhp -Value '@exit /b 0'
        Set-Content -LiteralPath $script:failPhp -Value @('@echo boom', '@exit /b 1')
    }

    It "Writes the OpenSSL config and PHP script and returns 0 on success" {
        $result = Invoke-LocalCertificateGenerator -phpExecutable $script:okPhp -hostName 'myapp.test' -subjectAltName 'DNS:myapp.test,DNS:localhost,IP:127.0.0.1' -certificatePath "$script:genTemp\c.pem" -privateKeyPath "$script:genTemp\k.pem" -temporaryDirectory $script:genTemp

        $result | Should -Be 0
        $config = [System.IO.File]::ReadAllText("$script:genTemp\openssl.cnf")
        $config | Should -Match 'CN = myapp\.test'
        $config | Should -Match 'subjectAltName = DNS:myapp\.test,DNS:localhost,IP:127\.0\.0\.1'
        $config | Should -Match 'CA:FALSE'
        $config | Should -Match 'extendedKeyUsage = serverAuth'
        $script = [System.IO.File]::ReadAllText("$script:genTemp\generate-certificate.php")
        $script | Should -Match '^<\?php'
        $script | Should -Match 'openssl_csr_sign'
        $script | Should -Match 'openssl_pkey_export'
    }

    It "Fails and reports the output when PHP exits with an error" {
        $result = Invoke-LocalCertificateGenerator -phpExecutable $script:failPhp -hostName 'myapp.test' -subjectAltName 'DNS:myapp.test' -certificatePath "$script:genTemp\c.pem" -privateKeyPath "$script:genTemp\k.pem" -temporaryDirectory $script:genTemp

        $result | Should -Be -1
        Should -Invoke Show-Error -ParameterFilter { $message -like '*PHP certificate generation failed*boom*' }
    }

    It "Logs and fails when the PHP executable cannot be invoked" {
        $result = Invoke-LocalCertificateGenerator -phpExecutable "$script:generatorDirectory\missing-php.exe" -hostName 'myapp.test' -subjectAltName 'DNS:myapp.test' -certificatePath "$script:genTemp\c.pem" -privateKeyPath "$script:genTemp\k.pem" -temporaryDirectory $script:genTemp

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
    }

    It "Logs and fails when the temporary directory does not exist" {
        $result = Invoke-LocalCertificateGenerator -phpExecutable $script:okPhp -hostName 'myapp.test' -subjectAltName 'DNS:myapp.test' -certificatePath "$script:genTemp\c.pem" -privateKeyPath "$script:genTemp\k.pem" -temporaryDirectory "$script:generatorDirectory\does-not-exist"

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
    }
}

Describe "New-LocalPHPCertificate" {
    BeforeEach {
        & $script:resetCertDirectory
        & $script:resetIni
        $null = New-Directory -path $script:localCertificateDirectory
        Set-ContentWrapper -path "$script:phpDirectory\php.exe" -value 'test executable'
        (& $script:pem 'PUBLICCERT') | Set-ContentWrapper -path $script:baseBundlePath
        $script:capturedTempDir = $null

        Mock Get-CurrentPHPVersion {
            return @{ version = '8.3.0'; path = $script:phpDirectory }
        }
        Mock Invoke-LocalCertificateGenerator {
            param ($phpExecutable, $hostName, $subjectAltName, $certificatePath, $privateKeyPath, $temporaryDirectory)
            $script:capturedTempDir = $temporaryDirectory
            Set-ContentWrapper -path $certificatePath -value "-----BEGIN CERTIFICATE-----`nLOCALCERT`n-----END CERTIFICATE-----"
            Set-ContentWrapper -path $privateKeyPath -value "-----BEGIN PRIVATE KEY-----`nLOCALKEY`n-----END PRIVATE KEY-----"
            return 0
        }
    }

    It "Generates and trusts a local certificate for PHP" {
        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be 0
        Test-Path -LiteralPath "$script:localCertificateDirectory\myapp.test.crt.pem" | Should -BeTrue
        Test-Path -LiteralPath "$script:localCertificateDirectory\myapp.test.key.pem" | Should -BeTrue
        [System.IO.File]::ReadAllText($script:trustBundlePath) | Should -Match 'LOCALCERT'
        [System.IO.File]::ReadAllText($script:trustBundlePath) | Should -Match 'PUBLICCERT'
        (Get-ContentWrapper -path $script:phpIniPath) | Should -Contain "openssl.cafile = '$script:trustBundlePath'"
        Should -Invoke Invoke-LocalCertificateGenerator -Times 1 -ParameterFilter {
            $hostName -eq 'myapp.test' -and
            $subjectAltName -eq 'DNS:myapp.test,DNS:localhost,IP:127.0.0.1' -and
            $phpExecutable -eq "$script:phpDirectory\php.exe"
        }
        Should -Invoke Show-Success -Times 1
        Should -Invoke Show-Warning -Times 1
    }

    It "Defaults to localhost when the hostname is empty" {
        $result = New-LocalPHPCertificate -hostName ''

        $result | Should -Be 0
        Test-Path -LiteralPath "$script:localCertificateDirectory\localhost.crt.pem" | Should -BeTrue
        Should -Invoke Invoke-LocalCertificateGenerator -Times 1 -ParameterFilter {
            $hostName -eq 'localhost' -and $subjectAltName -eq 'DNS:localhost,IP:127.0.0.1'
        }
    }

    It "Uses localhost and 127.0.0.1 as SANs for the localhost hostname" {
        $result = New-LocalPHPCertificate -hostName 'localhost'

        $result | Should -Be 0
        Should -Invoke Invoke-LocalCertificateGenerator -Times 1 -ParameterFilter {
            $subjectAltName -eq 'DNS:localhost,IP:127.0.0.1'
        }
    }

    It "Uses an IP SAN for IP address hosts" {
        $result = New-LocalPHPCertificate -hostName '192.168.1.10'

        $result | Should -Be 0
        Test-Path -LiteralPath "$script:localCertificateDirectory\192.168.1.10.crt.pem" | Should -BeTrue
        Should -Invoke Invoke-LocalCertificateGenerator -Times 1 -ParameterFilter {
            $subjectAltName -eq 'DNS:localhost,IP:192.168.1.10'
        }
    }

    It "Rejects unsafe hostnames" {
        $result = New-LocalPHPCertificate -hostName '../unsafe'

        $result | Should -Be -1
        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
        Should -Invoke Show-Error -ParameterFilter { $message -like '*Invalid hostname*' }
    }

    It "Rejects hostnames with spaces" {
        $result = New-LocalPHPCertificate -hostName 'my app.test'

        $result | Should -Be -1
        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
    }

    It "Fails when there is no current PHP version" {
        Mock Get-CurrentPHPVersion { return $null }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
    }

    It "Fails when the public CA bundle has not been downloaded" {
        Remove-Item $script:baseBundlePath -Force

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
        Should -Invoke Show-Error -ParameterFilter { $message -like "*pvm cert bundle*" }
    }

    It "Fails when php.exe is missing" {
        Remove-Item "$script:phpDirectory\php.exe" -Force

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
        Should -Invoke Show-Error -ParameterFilter { $message -like '*PHP executable not found*' }
    }

    It "Fails when the local certificate directory cannot be created" {
        Mock New-Directory { return -1 }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
    }

    It "Refuses to overwrite an existing certificate" {
        'existing' | Set-ContentWrapper -path "$script:localCertificateDirectory\myapp.test.crt.pem"

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1

        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
        (Get-ContentWrapper -path "$script:localCertificateDirectory\myapp.test.crt.pem") | Should -Be 'existing'
        Should -Invoke Show-Error -ParameterFilter { $message -like '*refusing to overwrite*' }
    }

    It "Refuses to overwrite an existing private key" {
        'existing' | Set-ContentWrapper -path "$script:localCertificateDirectory\myapp.test.key.pem"

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
    }

    It "Fails when the temporary directory cannot be created" {
        Mock New-Directory { return 0 } -ParameterFilter { $path -like '*\local*' }
        Mock New-Directory { return -1 } -ParameterFilter { $path -like '*pvm-cert-*' }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Invoke-LocalCertificateGenerator -Times 0
        Should -Invoke Show-Error -ParameterFilter { $message -like '*temporary directory*' }
    }

    It "Removes partial files when generation fails" {
        Mock Invoke-LocalCertificateGenerator {
            param ($phpExecutable, $hostName, $subjectAltName, $certificatePath, $privateKeyPath, $temporaryDirectory)
            Set-ContentWrapper -path $certificatePath -value 'partial'
            return -1
        }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Test-Path -LiteralPath "$script:localCertificateDirectory\myapp.test.crt.pem" | Should -BeFalse
        Test-Path -LiteralPath "$script:localCertificateDirectory\myapp.test.key.pem" | Should -BeFalse
        Test-Path -LiteralPath $script:trustBundlePath | Should -BeFalse
    }

    It "Fails and removes files when PHP did not create both files" {
        Mock Invoke-LocalCertificateGenerator {
            param ($phpExecutable, $hostName, $subjectAltName, $certificatePath, $privateKeyPath, $temporaryDirectory)
            Set-ContentWrapper -path $certificatePath -value 'only the certificate'
            return 0
        }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Test-Path -LiteralPath "$script:localCertificateDirectory\myapp.test.crt.pem" | Should -BeFalse
        Should -Invoke Show-Error -ParameterFilter { $message -like '*did not create both*' }
    }

    It "Cleans up the temporary directory after success" {
        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be 0
        $script:capturedTempDir | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $script:capturedTempDir | Should -BeFalse
    }

    It "Cleans up the temporary directory after failure" {
        Mock Invoke-LocalCertificateGenerator {
            param ($phpExecutable, $hostName, $subjectAltName, $certificatePath, $privateKeyPath, $temporaryDirectory)
            $script:capturedTempDir = $temporaryDirectory
            return -1
        }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Test-Path -LiteralPath $script:capturedTempDir | Should -BeFalse
    }

    It "Fails when the trust bundle cannot be written" {
        Mock Write-PHPCertificateTrustBundle { return -1 }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Show-Success -Times 0
    }

    It "Fails when the trust bundle cannot be activated" {
        Mock Set-ActivePHPTrustBundle { return -1 }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Show-Success -Times 0
    }

    It "Logs and fails when an unexpected exception is thrown" {
        Mock Get-CurrentPHPVersion { throw 'boom' }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Should -Invoke Add-LogEntry -Times 1
        Should -Invoke Show-Error -ParameterFilter { $message -like '*boom*' }
    }

    It "Removes both files when generation fails after creating them" {
        Mock Invoke-LocalCertificateGenerator {
            param ($phpExecutable, $hostName, $subjectAltName, $certificatePath, $privateKeyPath, $temporaryDirectory)
            Set-ContentWrapper -path $certificatePath -value 'partial cert'
            Set-ContentWrapper -path $privateKeyPath -value 'partial key'
            return -1
        }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Test-Path -LiteralPath "$script:localCertificateDirectory\myapp.test.crt.pem" | Should -BeFalse
        Test-Path -LiteralPath "$script:localCertificateDirectory\myapp.test.key.pem" | Should -BeFalse
    }

    It "Removes the private key when PHP created only the key" {
        Mock Invoke-LocalCertificateGenerator {
            param ($phpExecutable, $hostName, $subjectAltName, $certificatePath, $privateKeyPath, $temporaryDirectory)
            Set-ContentWrapper -path $privateKeyPath -value 'only the key'
            return 0
        }

        $result = New-LocalPHPCertificate -hostName 'myapp.test'

        $result | Should -Be -1
        Test-Path -LiteralPath "$script:localCertificateDirectory\myapp.test.key.pem" | Should -BeFalse
        Should -Invoke Show-Error -ParameterFilter { $message -like '*did not create both*' }
    }
}
