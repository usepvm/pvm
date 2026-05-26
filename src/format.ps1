

# Load configuration
. $PSScriptRoot\core\config.ps1

$errors = @()
$formatted = 0

# Ensure PSScriptAnalyzer is installed
if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
    Write-Host "Installing PSScriptAnalyzer..." -ForegroundColor Yellow
    Install-Module -Name PSScriptAnalyzer -Force -SkipPublisherCheck
}


# Import the module
Import-Module PSScriptAnalyzer -Force

# Format files in src/ and tests/
@("$PVMRoot\src", "$PVMRoot\tests") | ForEach-Object {
    $directory = $_
    Get-ChildItem "$directory\*.ps1" -Recurse | ForEach-Object {
        try {
            Write-Host "Formatting: $($_.FullName)"
            # Use Invoke-ScriptAnalyzer with formatting
            Invoke-ScriptAnalyzer -Path $_.FullName -Fix -ExcludeRule PSUseSingularNouns
            $formatted++
        } catch {
            $errors += "Error formatting file: $($_.FullName) - $_"
        }
    }
}

Write-Host "`nFormatted $formatted files" -ForegroundColor Green
if ($errors.Count -gt 0) {
    Write-Host "Errors encountered:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
}