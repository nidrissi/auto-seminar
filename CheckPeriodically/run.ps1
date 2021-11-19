param($Timer)

if (!$env:KOS_Data) {
    Write-Error "KOS_Data not configured."
    exit 1
}

$Response = Invoke-WebRequest -Uri $env:KOS_Data
if (!$Response.BaseResponse.IsSuccessStatusCode) {
    Write-Error "Fetching KOS_Data failed."
    Write-Error $Response.RawContent
    exit 2
}

$Data = $Response.Content | ConvertFrom-Csv
Push-OutputBinding -Name Event -Value $Data
