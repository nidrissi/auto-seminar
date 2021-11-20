param($QueueItem, $BlobInput, $TriggerMetadata)

$ErrorActionPreference = 'Stop'


if ($BlobInput) {
    $differenceCheck = ('date', 'speaker', 'webpage', 'affiliation', 'title', 'abstract-file') `
    | ForEach-Object {
        $QueueItem[$_] -Eq $BlobInput[$_]
    }
    if ($differenceCheck -NotContains $false) {
        # The stored state is equal to the new state, so we return.
        Write-Host "The following item is already dealt with:"
        $QueueItem | Format-List
        exit 0
    }
}

$BaseUrl = "https://www.imj-prg.fr"

Write-Host "Trying to log-in with the provided credentials."

$LoginData = @{
    _username = $env:IMJ_login;
    _password = $env:IMJ_password;
}
$LoginResponse = Invoke-WebRequest `
    -Uri ($BaseUrl + "/gestion/login_check") `
    -Method Post `
    -Form $LoginData `
    -SessionVariable Session

if (!$LoginResponse.BaseResponse.IsSuccessStatusCode) {
    Write-Error "Something went wrong while logging-in:"
    Write-Error $LoginResponse
    exit 1
}

$TokenResponse = Invoke-WebRequest `
    -Uri ($BaseUrl + "/gestion/evenement/admin/affEvenement/43") `
    -WebSession $Session

if (!$TokenResponse.BaseResponse.IsSuccessStatusCode) {
    Write-Error "Something went wrong while getting the token:"
    Write-Error $LoginResponse
    exit 2
}

$Token = $TokenResponse.InputFields.Where({ $_.id -eq "form__token" }, 'First').value
Write-Debug "Token: $Token"

if ($BlobInput -and $BlobInput.id) {
    $QueueItem["id"] = $BlobInput.id
}
else {
    Write-Host "Creating the event."

    $FormData = @{
        "form[titreSeance]"      = "[K-OS] " + $QueueItem["title"];
        "form[dateSeance]"       = $QueueItem["date"];
        "form[heureDeb][hour]"   = "14";
        "form[heureDeb][minute]" = "0";
        "form[heureFin][hour]"   = "15";
        "form[heureFin][minute]" = "0";
        "form[evenement]"        = "43" # séminaire de topologie = 43
        "form[_token]"           = $Token;
        "form[save]"             = "";
    }

    $CreationFormResponse = Invoke-WebRequest `
        -Uri ($BaseUrl + "/gestion/evenement/admin/affEvenement/43") `
        -Method Post `
        -Form $FormData `
        -WebSession $Session

    $EventId = $CreationFormResponse.BaseResponse.RequestMessage.RequestUri.Segments | Select-Object -Last 1
    Write-Debug "Event id: $EventId"
    $QueueItem["id"] = $EventId
}

Write-Host "Updating event."

Write-Host "Trying to fetch the abstract..."
$Abstract = ""
try {
    if ($QueueItem["abstract-file"]) {
        $AbstractResponse = Invoke-WebRequest -Uri ("https://lrobert.perso.math.cnrs.fr/" + $QueueItem["abstract-file"])
        if ($AbstractResponse.BaseResponse.IsSuccessStatusCode) {
            $Abstract = $AbstractResponse.Content
        }
    }
}
catch {}

$FormData += @{
    "form[salle]"                  = "1016";
    "form[adresse]"                = "4"; # Sophie Germain
    "form[diffusion]"              = "https://lrobert.perso.math.cnrs.fr/join-kos.html";

    "form[orateurs][1][nom]"       = $QueueItem["speaker"];
    "form[orateurs][1][pagePerso]" = $QueueItem["webpage"];
    "form[orateurs][1][employeur]" = $QueueItem["affiliation"];
    "form[resume]"                 = $Abstract;
}

Invoke-WebRequest `
    -Uri ($BaseUrl + "/gestion/evenement/admin/modifSeance/43/" + $QueueItem["id"]) `
    -Method Post `
    -Form $FormData `
    -WebSession $Session `
| Out-Null

Push-OutputBinding -Name BlobOutput -Value $QueueItem
