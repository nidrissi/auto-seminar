param($Timer)

if (!$env:KOS_Data) {
    Write-Error "KOS_Data not configured."
    exit 1
}

Write-Information "Fetching from: <$env:KOS_Data>."

$Response = Invoke-WebRequest -Uri $env:KOS_Data -SkipHttpErrorCheck

Write-Information "Fetching KOS_Data succeeded."

$SourceEncoding = [System.Text.Encoding]::GetEncoding('iso-8859-1')
$DestinationEncoding = [System.Text.Encoding]::GetEncoding('utf-8')
$EncodedResponse = $DestinationEncoding.GetString($SourceEncoding.GetBytes($Response.Content))

$Data = $EncodedResponse | ConvertFrom-Csv

foreach ($entry in $Data) {
    # Parse date & bail if any is not correct
    if (!($entry.date -match '(\d\d?)/(\d\d?)/(\d\d\d\d)')) {
        throw "Malformed entry:`n$($entry | ConvertTo-Json)"
    }
    $day = $matches[1]
    $month = $matches[2]
    $year = $matches[3]
    $entry.date = '{2:d4}-{1:d2}-{0:d2}' -f $day, $month, $year
    Write-Information "Posting event with date $($entry.date)."

    # Parse HTML entities
    foreach ($key in 'speaker', 'affiliation', 'title') {
        $entry.$key = [System.Web.HttpUtility]::HtmlDecode($entry.$key)
    }
}

Push-OutputBinding -Name Incoming -Value $Data
