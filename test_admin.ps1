# Test Admin Dashboard Script
# This script helps test the admin dashboard locally

Write-Host "=== Covr Admin Dashboard Test Script ===" -ForegroundColor Cyan
Write-Host ""

# Check if database is running
Write-Host "1. Checking database..." -ForegroundColor Yellow
$dbStatus = docker ps --filter "name=covr-postgres" --format "{{.Status}}"
if ($dbStatus) {
    Write-Host "   Database is running: $dbStatus" -ForegroundColor Green
} else {
    Write-Host "   Database is not running. Starting it..." -ForegroundColor Red
    docker-compose up -d postgres
    Start-Sleep -Seconds 5
}

Write-Host ""
Write-Host "2. Next steps:" -ForegroundColor Yellow
Write-Host "   a) Open a new terminal/command prompt" -ForegroundColor White
Write-Host "   b) Navigate to the project directory" -ForegroundColor White
Write-Host "   c) Run: mix ecto.setup" -ForegroundColor White
Write-Host "   d) Run: mix phx.server" -ForegroundColor White
Write-Host ""
Write-Host "3. Once the server is running:" -ForegroundColor Yellow
Write-Host "   - Open browser: http://localhost:4000/admin" -ForegroundColor White
Write-Host "   - Upload a test image to see pipeline in action" -ForegroundColor White
Write-Host ""
Write-Host "4. To upload a test image, run this in another terminal:" -ForegroundColor Yellow
Write-Host '   curl -X POST http://localhost:4000/api/images -F "image=@path/to/image.jpg" -F "kind=cover_front"' -ForegroundColor White
Write-Host ""
Write-Host "=== Testing on Deployed Version ===" -ForegroundColor Cyan
Write-Host "   URL: https://covr-gateway.fly.dev/admin" -ForegroundColor White
Write-Host "   Note: Deployment may still be in progress" -ForegroundColor Gray
Write-Host ""
