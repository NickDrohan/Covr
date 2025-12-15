# Test Deployed Admin Dashboard
Write-Host "=== Testing Deployed Admin Dashboard ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Health Check
Write-Host "1. Testing health endpoint..." -ForegroundColor Yellow
try {
    $health = Invoke-WebRequest -Uri "https://covr-gateway.fly.dev/healthz" -UseBasicParsing
    Write-Host "   ✓ Health check passed: $($health.StatusCode)" -ForegroundColor Green
    Write-Host "   Response: $($health.Content)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Health check failed: $_" -ForegroundColor Red
}

Write-Host ""

# Test 2: Admin Dashboard
Write-Host "2. Testing admin dashboard..." -ForegroundColor Yellow
try {
    $admin = Invoke-WebRequest -Uri "https://covr-gateway.fly.dev/admin" -UseBasicParsing
    Write-Host "   ✓ Admin dashboard accessible: $($admin.StatusCode)" -ForegroundColor Green
    Write-Host "   Opening in browser..." -ForegroundColor Gray
    Start-Process "https://covr-gateway.fly.dev/admin"
} catch {
    Write-Host "   ✗ Admin dashboard not available (Status: $($_.Exception.Response.StatusCode.value__))" -ForegroundColor Red
    Write-Host "   This might mean:" -ForegroundColor Yellow
    Write-Host "   - Deployment is still in progress" -ForegroundColor Gray
    Write-Host "   - Migration hasn't run yet" -ForegroundColor Gray
    Write-Host "   - Check GitHub Actions for deployment status" -ForegroundColor Gray
}

Write-Host ""

# Test 3: API Endpoint
Write-Host "3. Testing API endpoint..." -ForegroundColor Yellow
try {
    $api = Invoke-WebRequest -Uri "https://covr-gateway.fly.dev/api/images" -Method GET -UseBasicParsing
    Write-Host "   ✓ API endpoint accessible: $($api.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "   ✗ API endpoint not available" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Next Steps ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "If admin dashboard is not available:" -ForegroundColor Yellow
Write-Host "1. Check GitHub Actions: https://github.com/NickDrohan/Covr/actions" -ForegroundColor White
Write-Host "2. Wait 5-10 minutes for deployment to complete" -ForegroundColor White
Write-Host "3. Check Fly.io logs: fly logs --app covr-gateway" -ForegroundColor White
Write-Host ""
Write-Host "To install Elixir locally (for development):" -ForegroundColor Yellow
Write-Host "See INSTALL_ELIXIR.md for instructions" -ForegroundColor White
Write-Host ""
Write-Host "To test image upload:" -ForegroundColor Yellow
Write-Host "Open test_upload.html in your browser" -ForegroundColor White
Write-Host ""
