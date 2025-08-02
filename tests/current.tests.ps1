# Tests for Get-PHP-Status and Get-Current-PHP-Version functions

Describe "Get-PHP-Status Tests" {
    BeforeAll {
        # Mock dependencies
        Mock Write-Host {}
        Mock Log-Data { return $true }
        
        # Create temporary test directory
        $script:testDir = Join-Path $env:TEMP "PHPStatusTests"
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
        
        # Set up mock LOG_ERROR_PATH variable
        $script:LOG_ERROR_PATH = Join-Path $script:testDir "error.log"
    }
    
    AfterAll {
        # Clean up test directory
        if (Test-Path $script:testDir) {
            Remove-Item -Path $script:testDir -Recurse -Force
        }
    }
    
    Context "When php.ini file exists" {
        BeforeEach {
            $script:phpPath = Join-Path $script:testDir "php"
            New-Item -Path $script:phpPath -ItemType Directory -Force | Out-Null
            $script:phpIniPath = Join-Path $script:phpPath "php.ini"
        }
        
        It "Should detect enabled opcache extension" {
            $iniContent = @(
                "; PHP Configuration",
                "zend_extension=opcache.so",
                "opcache.enable=1"
            )
            $iniContent | Out-File -FilePath $script:phpIniPath -Encoding UTF8
            
            $result = Get-PHP-Status -phpPath $script:phpPath
            
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $false
        }
        
        It "Should detect disabled opcache extension (commented out)" {
            $iniContent = @(
                "; PHP Configuration",
                ";zend_extension=opcache.so",
                "opcache.enable=1"
            )
            $iniContent | Out-File -FilePath $script:phpIniPath -Encoding UTF8
            
            $result = Get-PHP-Status -phpPath $script:phpPath
            
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $false
        }
        
        It "Should detect enabled xdebug extension" {
            $iniContent = @(
                "; PHP Configuration",
                "zend_extension=xdebug.so",
                "xdebug.mode=debug"
            )
            $iniContent | Out-File -FilePath $script:phpIniPath -Encoding UTF8
            
            $result = Get-PHP-Status -phpPath $script:phpPath
            
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $true
        }
        
        It "Should detect both opcache and xdebug when enabled" {
            $iniContent = @(
                "; PHP Configuration",
                "zend_extension=opcache.so",
                "zend_extension=xdebug.so",
                "opcache.enable=1",
                "xdebug.mode=debug"
            )
            $iniContent | Out-File -FilePath $script:phpIniPath -Encoding UTF8
            
            $result = Get-PHP-Status -phpPath $script:phpPath
            
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $true
        }
        
        It "Should handle different path formats for extensions" {
            $iniContent = @(
                "; PHP Configuration",
                "zend_extension=C:\php\ext\opcache.dll",
                "zend_extension=/usr/lib/php/modules/xdebug.so"
            )
            $iniContent | Out-File -FilePath $script:phpIniPath -Encoding UTF8
            
            $result = Get-PHP-Status -phpPath $script:phpPath
            
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $true
        }
        
        It "Should handle whitespace variations in ini file" {
            $iniContent = @(
                "; PHP Configuration",
                "  zend_extension  =  opcache.so  ",
                "	;	zend_extension	=	xdebug.so	"
            )
            $iniContent | Out-File -FilePath $script:phpIniPath -Encoding UTF8
            
            $result = Get-PHP-Status -phpPath $script:phpPath
            
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $false
        }
        
        It "Should ignore non-matching lines" {
            $iniContent = @(
                "; PHP Configuration",
                "extension=mysqli.so",
                "some_other_setting=value",
                "zend_extension=opcache.so"
            )
            $iniContent | Out-File -FilePath $script:phpIniPath -Encoding UTF8
            
            $result = Get-PHP-Status -phpPath $script:phpPath
            
            $result.opcache | Should -Be $true
            $result.xdebug | Should -Be $false
        }
    }
    
    Context "When php.ini file does not exist" {
        It "Should return -1 and display error message" {
            $nonExistentPath = Join-Path $script:testDir "nonexistent"
            
            $result = Get-PHP-Status -phpPath $nonExistentPath
            
            $result | Should -Be -1
            Assert-MockCalled Write-Host -Exactly 1 -ParameterFilter {
                $Object -match "php.ini not found"
            }
        }
    }
    
    Context "When an exception occurs" {
        It "Should handle exceptions gracefully" {
            Mock Get-Content { throw "Access denied" }
            Mock Test-Path { return $true }
            
            $result = Get-PHP-Status -phpPath $script:testDir
            
            $result.opcache | Should -Be $false
            $result.xdebug | Should -Be $false
            Assert-MockCalled Log-Data -Exactly 1
            Assert-MockCalled Write-Host -Exactly 1 -ParameterFilter {
                $Object -match "An error occurred while checking PHP status"
            }
        }
    }
}

Describe "Get-Current-PHP-Version Tests" {
    BeforeAll {
        # Mock dependencies
        Mock Log-Data { return $true }
        Mock Get-PHP-Status { 
            return @{ opcache = $true; xdebug = $false }
        }
        
        # Set up mock environment variable name
        $script:PHP_CURRENT_ENV_NAME = "PHP_CURRENT"
    }
    
    Context "When current PHP version is properly configured" {
        It "Should return version info when environment variables match" {
            Mock Get-EnvVar-ByName { 
                param($name)
                if ($name -eq $script:PHP_CURRENT_ENV_NAME) {
                    return "C:\php\php-8.1.0"
                }
            }
            
            Mock Get-All-EnvVars {
                return @{
                    "PHP_CURRENT" = "C:\php\php-8.1.0"
                    "php8.1.0" = "C:\php\php-8.1.0"
                    "php7.4.0" = "C:\php\php-7.4.0"
                }
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -Be "8.1.0"
            $result.path | Should -Be "C:\php\php-8.1.0"
            $result.status | Should -Not -BeNullOrEmpty
        }
        
        It "Should extract version from path when no matching env var key found" {
            Mock Get-EnvVar-ByName { 
                return "C:\php\php-7.4.5"
            }
            
            Mock Get-All-EnvVars {
                return @{
                    "PHP_CURRENT" = "C:\php\php-7.4.5"
                    "php8.1.0" = "C:\php\php-8.1.0"
                }
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -Be "7.4.5"
            $result.path | Should -Be "C:\php\php-7.4.5"
        }
        
        It "Should handle different version number formats" {
            Mock Get-EnvVar-ByName { 
                return "C:\php\php-8.2"
            }
            
            Mock Get-All-EnvVars {
                return @{
                    "PHP_CURRENT" = "C:\php\php-8.2"
                    "php8.2" = "C:\php\php-8.2"
                }
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -Be "8.2"
            $result.path | Should -Be "C:\php\php-8.2"
        }
        
        It "Should match environment variable keys with php prefix" {
            Mock Get-EnvVar-ByName { 
                return "C:\php\php-8.0.15"
            }
            
            Mock Get-All-EnvVars {
                return @{
                    "PHP_CURRENT" = "C:\php\php-8.0.15"
                    "php8.0.15" = "C:\php\php-8.0.15"
                    "COMPOSER_HOME" = "C:\composer"
                    "php7.4" = "C:\php\php-7.4"
                }
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -Be "8.0.15"
            $result.path | Should -Be "C:\php\php-8.0.15"
        }
    }
    
    Context "When current PHP version cannot be determined" {
        It "Should return null values when no current PHP path is found" {
            Mock Get-EnvVar-ByName { 
                return $null
            }
            
            Mock Get-All-EnvVars {
                return @{}
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -BeNullOrEmpty
            $result.status | Should -BeNullOrEmpty
        }
        
        It "Should return null when path doesn't match version pattern" {
            Mock Get-EnvVar-ByName { 
                return "C:\php\invalidpath"
            }
            
            Mock Get-All-EnvVars {
                return @{
                    "PHP_CURRENT" = "C:\php\invalidpath"
                }
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -BeNullOrEmpty
            $result.status | Should -BeNullOrEmpty
        }
    }
    
    Context "When an exception occurs" {
        It "Should handle exceptions gracefully and return default values" {
            Mock Get-EnvVar-ByName { 
                throw "Environment variable not accessible"
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -BeNullOrEmpty
            $result.status.opcache | Should -Be $false
            $result.status.xdebug | Should -Be $false
            Assert-MockCalled Log-Data -Exactly 1
        }
        
        It "Should log errors when Get-All-EnvVars fails" {
            Mock Get-EnvVar-ByName { 
                return "C:\php\php-8.1.0"
            }
            
            Mock Get-All-EnvVars { 
                throw "Cannot access environment variables"
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -BeNullOrEmpty
            $result.status.opcache | Should -Be $false
            $result.status.xdebug | Should -Be $false
            Assert-MockCalled Log-Data -Exactly 1
        }
    }
    
    Context "Edge cases and special scenarios" {
        It "Should handle empty environment variables collection" {
            Mock Get-EnvVar-ByName { 
                return "C:\php\php-8.1.0"
            }
            
            Mock Get-All-EnvVars {
                return @{}
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -Be "8.1.0"
            $result.path | Should -Be "C:\php\php-8.1.0"
        }
        
        It "Should not match the current environment variable name itself" {
            Mock Get-EnvVar-ByName { 
                return "C:\php\php-8.1.0"
            }
            
            Mock Get-All-EnvVars {
                return @{
                    "PHP_CURRENT" = "C:\php\php-8.1.0"
                    # Only PHP_CURRENT exists, should extract from path
                }
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -Be "8.1.0"
            $result.path | Should -Be "C:\php\php-8.1.0"
        }
        
        It "Should handle version strings with multiple dots" {
            Mock Get-EnvVar-ByName { 
                return "C:\php\php-8.1.0.1"
            }
            
            Mock Get-All-EnvVars {
                return @{
                    "PHP_CURRENT" = "C:\php\php-8.1.0.1"
                    "php8.1.0.1" = "C:\php\php-8.1.0.1"
                }
            }
            
            $result = Get-Current-PHP-Version
            
            $result.version | Should -Be "8.1.0.1"
            $result.path | Should -Be "C:\php\php-8.1.0.1"
        }
    }
}

# Integration tests
Describe "Integration Tests" {
    BeforeAll {
        # Create a more realistic test scenario
        $script:testDir = Join-Path $env:TEMP "PHPIntegrationTests"
        New-Item -Path $script:testDir -ItemType Directory -Force | Out-Null
        
        $script:LOG_ERROR_PATH = Join-Path $script:testDir "error.log"
        $script:PHP_CURRENT_ENV_NAME = "PHP_CURRENT"
        
        # Mock environment functions
        Mock Get-EnvVar-ByName { 
            return "C:\php\php-8.1.0"
        }
        
        Mock Get-All-EnvVars {
            return @{
                "PHP_CURRENT" = "C:\php\php-8.1.0"
                "php8.1.0" = "C:\php\php-8.1.0"
                "php7.4.0" = "C:\php\php-7.4.0"
            }
        }
        
        Mock Log-Data { return $true }
        Mock Write-Host {}
    }
    
    AfterAll {
        if (Test-Path $script:testDir) {
            Remove-Item -Path $script:testDir -Recurse -Force
        }
    }
}

# Performance tests
Describe "Performance Tests" {
    It "Get-PHP-Status should complete within reasonable time" {
        $testDir = Join-Path $env:TEMP "PHPPerfTest"
        New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        
        # Create large ini file
        $largeIniContent = @()
        1..1000 | ForEach-Object {
            $largeIniContent += "; Comment line $_"
            $largeIniContent += "setting$_=value$_"
        }
        $largeIniContent += "zend_extension=opcache.so"
        
        $largeIniContent | Out-File -FilePath (Join-Path $testDir "php.ini") -Encoding UTF8
        
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Get-PHP-Status -phpPath $testDir
        $stopwatch.Stop()
        
        $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000
        $result.opcache | Should -Be $true
        
        Remove-Item -Path $testDir -Recurse -Force
    }
}