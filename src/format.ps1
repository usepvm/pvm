
# Load configuration
. $PSScriptRoot\core\config.ps1

$errors = @()
$formatted = 0

# Ensure PSScriptAnalyzer is installed
if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
    Write-Host 'Installing PSScriptAnalyzer...' -ForegroundColor Yellow
    Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck
}

# Import the module
Import-Module PSScriptAnalyzer -Force

$settings = @{
    IncludeRules = @(
        'PSUseConsistentIndentation'
        'PSUseConsistentWhitespace'
        'PSPlaceOpenBrace'
        'PSPlaceCloseBrace'
        'PSAlignAssignmentStatement'
        'PSAvoidTrailingWhitespace'
        'PSAvoidSemicolonsAsLineTerminators'
        'PSPossibleIncorrectComparisonWithNull'
        'PSPossibleIncorrectUsageOfAssignmentOperator'
        'PSAvoidLongLines'
    )

    Rules = @{
        PSUseConsistentIndentation = @{
            Kind = 'space'
            IndentationSize = 4
        }

        PSUseConsistentWhitespace = @{
            CheckInnerBrace = $true
            CheckOpenBrace = $true
            CheckOpenParen = $true
            CheckOperator = $true
            CheckPipe = $true
            CheckSeparator = $true
        }
    }
}

# Format files in src/ and tests/
@("$PVMRoot\src", "$PVMRoot\tests") | ForEach-Object {
    $directory = $_
    Get-ChildItem "$directory\*.ps1" -Recurse | ForEach-Object {
        try {
            Write-Host "`nFormatting: $($_.FullName)"

            Invoke-ScriptAnalyzer -Path $_.FullName -Fix -Settings $settings
            $formatted++
        } catch {
            $errors += "Error formatting file: $($_.FullName) - $_"
        }
    }
}

Write-Host "`nFormatted $formatted files" -ForegroundColor Green
if ($errors.Count -gt 0) {
    Write-Host 'Errors encountered:' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}
