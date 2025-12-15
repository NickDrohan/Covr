# Testing the Deployed Admin Dashboard

Since Elixir isn't installed locally, let's test the deployed version.

## Step 1: Check Deployment Status

The deployment may still be in progress. Wait a few minutes after pushing to GitHub, then check:

1. **Health Check:**
   ```
   https://covr-gateway.fly.dev/healthz
   ```
   Should return: `{"status":"ok"}`

2. **Admin Dashboard:**
   ```
   https://covr-gateway.fly.dev/admin
   ```
   Should show the admin dashboard

## Step 2: Test Image Upload

Use the test upload page I created:
- Open `test_upload.html` in your browser
- Select "Production" from the API Base dropdown
- Upload an image
- Watch the pipeline process

Or use curl:
```powershell
# Create a test image first (or use an existing one)
$imagePath = "C:\path\to\your\image.jpg"

# Upload
$formData = @{
    image = Get-Item $imagePath
    kind = "cover_front"
}
Invoke-WebRequest -Uri "https://covr-gateway.fly.dev/api/images" -Method POST -Form $formData
```

## Step 3: View Admin Dashboard

Once you've uploaded an image:
1. Go to: https://covr-gateway.fly.dev/admin
2. You should see:
   - Database statistics
   - Pipeline job status
   - Recent executions

## Troubleshooting

If `/admin` returns 404:
- The deployment might still be running
- Check GitHub Actions: https://github.com/NickDrohan/Covr/actions
- Wait 5-10 minutes after pushing
- The migration needs to run (it runs automatically on deploy)

If you see errors:
- Check Fly.io logs: `fly logs --app covr-gateway`
- Verify the migration ran: Check if `pipeline_executions` table exists

## Quick Test Script

Run this in PowerShell to test the full flow:

```powershell
# 1. Check health
Invoke-WebRequest -Uri "https://covr-gateway.fly.dev/healthz" -UseBasicParsing

# 2. Upload test image (replace with your image path)
$imagePath = "C:\path\to\image.jpg"
$formData = @{
    image = Get-Item $imagePath
    kind = "cover_front"
}
$response = Invoke-WebRequest -Uri "https://covr-gateway.fly.dev/api/images" -Method POST -Form $formData
$imageData = $response.Content | ConvertFrom-Json
$imageId = $imageData.image_id

# 3. Check pipeline status
Start-Sleep -Seconds 3
Invoke-WebRequest -Uri "https://covr-gateway.fly.dev/api/images/$imageId/pipeline" -UseBasicParsing

# 4. Open admin dashboard
Start-Process "https://covr-gateway.fly.dev/admin"
```
