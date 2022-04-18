param($Timer)

if (!$env:KOS_Data) {
    Write-Error "KOS_Data not configured."
    exit 1
}

Write-Information "Fetching from: <$env:KOS_Data>."

$Response = Invoke-WebRequest -Uri $env:KOS_Data -SkipHttpErrorCheck

Write-Information "Fetching KOS_Data succeeded."

$Bytes = [System.Text.Encoding]::Latin1.GetBytes($Response.Content)
$EncodedResponse = [System.Text.Encoding]::UTF8.GetString($Bytes)

$Data = $EncodedResponse | ConvertFrom-Csv

foreach ($entry in $Data) {
    # Parse date & bail if any is not correct
    if (!($entry.date -match '(\d\d?)/(\d\d?)/(\d\d\d\d)')) {
        throw "Malformed entry:`n$($entry | ConvertTo-Json)"
    }
    $day = $Matches[1]
    $month = $Matches[2]
    $year = $Matches[3]
    $entry.date = '{2:d4}-{1:d2}-{0:d2}' -f $day, $month, $year
    Write-Information "Posting event with date $($entry.date)."

    # Parse HTML entities
    foreach ($key in 'speaker', 'affiliation', 'title') {
        $entry.$key = [System.Web.HttpUtility]::HtmlDecode($entry.$key)
    }
}

Push-OutputBinding -Name Incoming -Value $Data
