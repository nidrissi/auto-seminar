# Input bindings are passed in via param block.
param($Timer)

if (!$env:KOS_Data) {
    Write-Error "KOS_Data not configured."
    exit 1
}

$Response = Invoke-WebRequest -Uri $env:KOS_Data
if (!$Response.BaseResponse.IsSuccessStatusCode) {
    Write-Error "Fetch KOS_Data failed."
    Write-Error $Response.RawContent
    exit 2
}

$Data = $Response.Content | ConvertFrom-Csv
$EncodedData = $Data | ForEach-Object { $_ | ConvertTo-Json -Compress }
Push-OutputBinding -Name Event -Value $EncodedData
