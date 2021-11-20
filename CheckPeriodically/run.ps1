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

foreach ($entry in $Data) {
    if (!($entry.date -match '(\d\d?)/(\d\d?)/(\d\d\d\d)')) {
        Write-Error "Malformed entry:"
        Write-Error $entry
        exit 3
    }
    $day = $matches[1]
    $month = $matches[2]
    $year = $matches[3]
    $entry.date = '{0:d2}-{1:d2}-{2:d4}' -f $day, $month, $year
}

# This will push several items into the queue. Uniquely identified by their date (hopefully!).
Push-OutputBinding -Name Incoming -Value $Data
