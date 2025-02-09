

Write-Output $args 

if ($args -contains "-f") {
    Write-Host "ok"
} else {
    Write-Host "not ok"
}