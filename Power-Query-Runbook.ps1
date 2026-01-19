# === LOG START ===
Write-Output "=== SentinelOne → EDL sync started: $(Get-Date -Format u) ==="

# === Load Automation Variables ===
$apiToken         = "ENTER VALUE HERE"
$tenantUrl        = "ENTER VALUE HERE"
$azureFunctionUrl = "ENTER VALUE HERE"

# === Validate Required Inputs ===
if (-not $apiToken -or -not $tenantUrl -or -not $azureFunctionUrl) {
    Write-Error "❌ One or more required automation variables are missing."
    exit 1
}

# === PowerQuery ===
## BELOW IS AN EXAMPLE QUERY
$query = @'
dataSource.category = 'security' | filter( dataSource.name == 'netscaler' AND fullmsg contains:anycase( 'Rejected' ) ) | parse 'client ip : $client_ip$,' from fullmsg | group EventCount = count() by IP = client_ip | filter( EventCount >= 10 ) | columns IP
'@
## END QUERY

# === Prepare Request ===
$url = "https://$tenantUrl/api/powerQuery"
$headers = @{
    "Authorization" = "Bearer $apiToken"
    "Content-Type"  = "application/json"
}
$body = @{
    "query"     = $query
    "startTime" = "2h"
} | ConvertTo-Json

# === Execute PowerQuery ===
try {
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method POST -Body $body -ErrorAction Stop
} catch {
    Write-Error "❌ Failed to query SentinelOne PowerQuery API: $($_.Exception.Message)"
    exit 1
}

# === Validate Response ===
if (-not $response.status -or -not $response.values -or $response.values.Count -eq 0) {
    Write-Warning "⚠ No results returned from PowerQuery."
    exit 0
}

# === Prepare Azure Function Headers ===
$azureHeaders = @{
    "Content-Type" = "application/json"
}

# === Post Each IP to Azure Function ===
foreach ($row in $response.values) {
    $ip = ($row[0] -as [string]).Trim()

    # Skip invalid/empty
    if ([string]::IsNullOrWhiteSpace($ip)) {
        Write-Warning "⚠️ Skipping empty or invalid IP row: $($row | Out-String)"
        continue
    }

    $payload = @{ ip = $ip } | ConvertTo-Json -Compress

    try {
        $azureResponse = Invoke-RestMethod -Uri $azureFunctionUrl -Method Post -Headers $azureHeaders -Body $payload -ErrorAction Stop

        if ($azureResponse -like "*already present*") {
            Write-Output "[$ip] ⚠️ Already on list."
        } elseif ($azureResponse -like "*added*") {
            Write-Output "[$ip] ✅ Added to list."
        } else {
            Write-Warning "[$ip] ❓ Unexpected response: $azureResponse"
        }

        Start-Sleep -Milliseconds 500
    } catch {
        Write-Warning "[$ip] ❌ Failed: $($_.Exception.Message)"
    }
}

# === LOG END ===
Write-Output "=== SentinelOne → EDL sync completed: $(Get-Date -Format u) ==="
