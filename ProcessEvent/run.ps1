param($QueueItem, $BlobInput, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

if ($BlobInput) {
    $differenceCheck = ('date', 'speaker', 'webpage', 'affiliation', 'title', 'abstract-file') `
    | ForEach-Object {
        $QueueItem[$_] -Eq $BlobInput[$_]
    }
    if ($differenceCheck -NotContains $false) {
        # The stored state is equal to the new state, so we return.
        Write-Information "The following item is already dealt with:"
        $QueueItem | ConvertTo-Json -Compress | Write-Information
        exit 0
    }
}

Push-OutputBinding -Name BlobOutput -Value $QueueItem

$BaseUrl = "https://www.imj-prg.fr"

Write-Information "Trying to log-in with the provided credentials."

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

Write-Debug "Form data:"
Write-Debug $FormData

if ($BlobInput -and $BlobInput.id) {
    # The entry already exists: get its ID from the state
    $Id = $BlobInput["id"]
    Write-Information "Found existing entry with id $Id."
    $QueueItem["id"] = $Id
}
else {
    Write-Information "Creating the event."

    $FormData | ConvertTo-Json -Compress | Write-Debug

    try {
        $CreationFormResponse = Invoke-WebRequest `
            -Uri ($BaseUrl + "/gestion/evenement/admin/affEvenement/43") `
            -Method Post `
            -Form $FormData `
            -WebSession $Session

        if (!$CreationFormResponse.BaseResponse.IsSuccessStatusCode) {
            throw $CreationFormResponse
        }
    }
    catch {
        Write-Error "Error creating entry: $_"
        exit 5
    }

    Write-Information "Successfully created entry."

    $EventId = $CreationFormResponse.BaseResponse.RequestMessage.RequestUri.Segments | Select-Object -Last 1
    Write-Information "Created event id: $EventId."
    $QueueItem["id"] = $EventId
}

Write-Information "Updating event..."

Write-Information "Trying to fetch the abstract..."
$Abstract = ""
if ($QueueItem["abstract-file"]) {
    try {
        $AbstractResponse = Invoke-WebRequest -Uri ("https://lrobert.perso.math.cnrs.fr/Kos/" + $QueueItem["abstract-file"])
        if ($AbstractResponse.BaseResponse.IsSuccessStatusCode) {
            $Abstract = $AbstractResponse.Content
            Write-Information "Abstract found:`n$Abstract"
        }
    }
    catch {
        Write-Error "Error fetching the abstract:`n$_"
    }
}

$FormData += @{
    "form[salle]"                  = "1016";
    "form[adresse]"                = "4"; # Sophie Germain
    "form[diffusion]"              = "https://lrobert.perso.math.cnrs.fr/join-kos.html";
    "form[vignette]"               = $null;
    "form[vignettePdf]"            = $null;

    "form[orateurs][0][titre]"     = "";
    "form[orateurs][0][nom]"       = $QueueItem["speaker"] ?? "TBA";
    "form[orateurs][0][pagePerso]" = $QueueItem["webpage"] ?? "";
    "form[orateurs][0][employeur]" = $QueueItem["affiliation"] ?? "";
    "form[resume]"                 = $Abstract;
}

Write-Information "Posting the update..."

try {
    $UpdateResponse = Invoke-WebRequest `
        -Uri ($BaseUrl + "/gestion/evenement/admin/modifSeance/43/" + $QueueItem["id"]) `
        -Method Post `
        -Form $FormData `
        -WebSession $Session `

    if ($UpdateResponse.BaseResponse.IsSuccessStatusCode) {
        Write-Information "Updated entry successfully."
    }
    else {
        throw $UpdateResponse
    }
}
catch {
    Write-Error "Error updating entry:`n$_"
}
