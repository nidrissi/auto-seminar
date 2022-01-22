param($Timer)

if (!$env:KOS_Data) {
    Write-Error "KOS_Data not configured."
    exit 1
}

Write-Information "Fetching from: <$env:KOS_Data>."

try {
    $Response = Invoke-WebRequest -Uri $env:KOS_Data -SkipHttpErrorCheck
}
catch {
    Write-Error "Fetching KOS_Data failed:`n$_"
    exit 2
}

Write-Information "Fetching KOS_Data succeeded."

$SourceEncoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
$DestinationEncoding = [System.Text.Encoding]::GetEncoding('utf-8')
$EncodedResponse = $DestinationEncoding.GetString($SourceEncoding.GetBytes($Response.Content))

$Data = $EncodedResponse | ConvertFrom-Csv

foreach ($entry in $Data) {
    # Parse date & bail if any is not correct
    if (!($entry.date -match '(\d\d?)/(\d\d?)/(\d\d\d\d)')) {
        $FormattedEntry = $entry | ConvertTo-Json -Compress
        Write-Error "Malformed entry:`n$FormattedEntry"
        exit 3
    }
    $day = $matches[1]
    $month = $matches[2]
    $year = $matches[3]
    $entry.date = '{0:d2}-{1:d2}-{2:d4}' -f $day, $month, $year
    Write-Information "Posting event with date $($entry.date)."

    # Parse HTML entities
    foreach ($key in 'speaker', 'affiliation', 'title') {
        $entry.$key = [System.Web.HttpUtility]::HtmlDecode($entry.$key)
    }
}

Push-OutputBinding -Name Incoming -Value $Data
