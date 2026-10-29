# Test Jisho API (equivalent to TestJisho.java)
$level = 25
$keyword = "jlpt-n5"
$offsetLevel = $level - 25
$page = [math]::Floor($offsetLevel / 2) + 1
$url = "https://jisho.org/api/v1/search/words?keyword=$keyword&page=$page"

Write-Host "Calling URL: $url" -ForegroundColor Cyan
try {
    $response = Invoke-RestMethod -Uri $url -Method Get
    $data = $response.data
    Write-Host "Data size: $($data.Count)" -ForegroundColor Green
    if ($data.Count -gt 0) {
        $first = $data[0]
        $word = $first.japanese[0].word
        $reading = $first.japanese[0].reading
        $meaning = $first.senses[0].english_definitions -join ", "
        Write-Host "First item: Word='$word', Reading='$reading', Meaning='$meaning'" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error calling Jisho API: $($_.Exception.Message)" -ForegroundColor Red
}
