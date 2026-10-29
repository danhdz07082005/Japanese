# Test Kuroshiro Romaji Microservice
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$text = "近年の分類体系では、コケ植物が側系統であると考えられていたことを反映し、コケ植物に含まれる蘚類、苔類、ツノゴケ類のそれぞれを門の階級に置く分類が用いられてきた。"
$url = "http://localhost:8081/convert"

Write-Host "Target: $url" -ForegroundColor Cyan
Write-Host "Input Japanese: $text" -ForegroundColor Yellow

$body = @{ text = $text } | ConvertTo-Json

try {
    $res = Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($body))
    Write-Host "Converted Romaji: $($res.romaji)" -ForegroundColor Green
} catch {
    Write-Host "Error connecting to Kuroshiro microservice: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Note: Ensure kuroshiro-service is running (cd kuroshiro-service; node server.js)" -ForegroundColor DarkYellow
}
