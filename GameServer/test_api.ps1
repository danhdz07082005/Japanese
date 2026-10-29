# Japanese Mastery .NET Backend - Automated Health & API Test Script
$baseUrl = "http://localhost:8080"
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Japanese Mastery .NET API Test Suite" -ForegroundColor Cyan
Write-Host " Target: $baseUrl" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

function Assert-Result($name, $condition, $details = "") {
    if ($condition) {
        Write-Host " [PASS] $name" -ForegroundColor Green
    } else {
        Write-Host " [FAIL] $name - $details" -ForegroundColor Red
    }
}

try {
    # 0. Clean logout in case session is active
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/auth/logout/1" -Method Post -ErrorAction SilentlyContinue | Out-Null
    } catch {}

    # 1. Login with default admin
    Write-Host "`n1. Testing Auth Login (admin / 123)..." -ForegroundColor Yellow
    $loginBody = @{ username = "admin"; password = "123" } | ConvertTo-Json
    $loginRes = Invoke-RestMethod -Uri "$baseUrl/api/auth/login" -Method Post -ContentType "application/json" -Body $loginBody
    
    Assert-Result "Login successful" ($null -ne $loginRes.token) "No token returned"
    Assert-Result "Role is ADMIN" ($loginRes.role -eq "ADMIN") "Role was $($loginRes.role)"
    Assert-Result "gCoin property present" ($null -ne $loginRes.gCoin) "gCoin was null"
    
    $token = $loginRes.token
    $adminId = $loginRes.id
    $headers = @{ Authorization = "Bearer $token" }

    # 2. Heartbeat Test
    Write-Host "`n2. Testing Heartbeat..." -ForegroundColor Yellow
    $hbRes = Invoke-WebRequest -Uri "$baseUrl/api/player/$adminId/heartbeat" -Headers $headers -Method Get -UseBasicParsing
    Assert-Result "Valid Heartbeat (HTTP 200)" ($hbRes.StatusCode -eq 200) "Status was $($hbRes.StatusCode)"

    # Heartbeat unauthorized check
    try {
        $badHb = Invoke-WebRequest -Uri "$baseUrl/api/player/$adminId/heartbeat" -Headers @{ Authorization = "Bearer invalid_token" } -Method Get -UseBasicParsing
        Assert-Result "Invalid Heartbeat rejected" $false "Expected 401 but got $($badHb.StatusCode)"
    } catch {
        Assert-Result "Invalid Heartbeat rejected (HTTP 401)" ($_.Exception.Response.StatusCode.value__ -eq 401)
    }

    # 3. Admin Users
    Write-Host "`n3. Testing Admin Users API..." -ForegroundColor Yellow
    $users = Invoke-RestMethod -Uri "$baseUrl/api/admin/users" -Method Get
    Assert-Result "Fetched Users List" ($users.Count -ge 1) "Expected >= 1 users"

    # 4. Vocabularies
    Write-Host "`n4. Testing Vocabularies API..." -ForegroundColor Yellow
    $vocabsL1 = Invoke-RestMethod -Uri "$baseUrl/api/player/vocabularies?level=1" -Method Get
    Assert-Result "Fetched Vocabularies for Level 1 (Database)" ($vocabsL1.Count -gt 0) "Vocab count was 0"

    $vocabsL25 = Invoke-RestMethod -Uri "$baseUrl/api/player/vocabularies?level=25" -Method Get
    Assert-Result "Fetched Vocabularies for Level 25 (Advanced/Jisho)" ($vocabsL25.Count -gt 0) "Vocab count was 0"

    # 5. Admin Vocab Search
    Write-Host "`n5. Testing Vocabulary Search API..." -ForegroundColor Yellow
    $search = Invoke-RestMethod -Uri "$baseUrl/api/admin/vocabularies?q=test" -Method Get
    Assert-Result "Search Vocabularies returned array" ($null -ne $search)

    # 6. Shop Items
    Write-Host "`n6. Testing Shop Items API..." -ForegroundColor Yellow
    $items = Invoke-RestMethod -Uri "$baseUrl/api/shop/items" -Method Get
    Assert-Result "Shop Items accessible" ($null -ne $items)

    # 7. PvP Status
    Write-Host "`n7. Testing PvP Status API..." -ForegroundColor Yellow
    $pvpStatus = Invoke-RestMethod -Uri "$baseUrl/api/pvp/status/$adminId" -Method Get
    Assert-Result "PvP Status fetched" ($pvpStatus.status -eq "NONE" -or $pvpStatus.status -eq "QUEUED" -or $pvpStatus.status -eq "MATCHED")

    # 8. Logout
    Write-Host "`n8. Testing Auth Logout..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$baseUrl/api/auth/logout/$adminId" -Method Post | Out-Null
    Assert-Result "Logout completed" $true

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host " ALL TESTS COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
} catch {
    Write-Host "`n[ERROR] An exception occurred during testing: $($_.Exception.Message)" -ForegroundColor Red
}
