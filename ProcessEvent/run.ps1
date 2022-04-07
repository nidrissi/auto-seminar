param($QueueItem, $BlobInput, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

if ($BlobInput) {
    $differenceCheck = ('date', 'speaker', 'webpage', 'affiliation', 'title', 'abstract-file') `
    | ForEach-Object {
        $QueueItem[$_] -Eq $BlobInput[$_]
    }
    if ($differenceCheck -NotContains $false) {
        # The stored state is equal to the new state, so we return.
        Write-Information "The following item is already dealt with:`n$($QueueItem | ConvertTo-Json)"
        exit 0
    }
}

$BaseUrl = "https://www.imj-prg.fr"

Write-Information "Trying to log-in with the provided credentials."

$LoginData = @{
    _username = $env:IMJ_login;
    _password = $env:IMJ_password;
}

Invoke-WebRequest `
    -Uri ($BaseUrl + "/gestion/login_check") `
    -Method Post `
    -Form $LoginData `
    -SessionVariable Session

Write-Information "Login successful. Fetching token."

$TokenResponse = Invoke-WebRequest `
    -Uri ($BaseUrl + "/gestion/evenement/admin/affEvenement/43") `
    -WebSession $Session

Write-Information "Token request successful."

$Token = $TokenResponse.InputFields.Where({ $_.id -eq "form__token" }, 'First').value
Write-Debug "Token value: $Token"

$FormData = @{
    "form[titreSeance]"      = "[K-OS] " + $QueueItem["title"];
    "form[dateSeance]"       = $QueueItem["date"] -replace '(\d{4})-(\d{2})-(\d{2})', '$3-$2-$1';
    "form[heureDeb][hour]"   = "14";
    "form[heureDeb][minute]" = "0";
    "form[heureFin][hour]"   = "15";
    "form[heureFin][minute]" = "0";
    "form[evenement]"        = "43" # séminaire de topologie = 43
    "form[_token]"           = $Token;
    "form[save]"             = "";
}
Write-Debug "Form data:`n$($FormData | ConvertTo-Json)"

if ($BlobInput -and $BlobInput.id) {
    # The entry already exists: get its ID from the state
    $Id = $BlobInput["id"]
    Write-Information "Found existing entry with id: $Id."
    $QueueItem["id"] = $Id
}
else {
    Write-Information "Creating the event."

    $CreationFormResponse = Invoke-WebRequest `
        -Uri ($BaseUrl + "/gestion/evenement/admin/affEvenement/43") `
        -Method Post `
        -Form $FormData `
        -WebSession $Session `
        -SkipHttpErrorCheck

    $EventId = $CreationFormResponse.BaseResponse.RequestMessage.RequestUri.Segments | Select-Object -Last 1
    Write-Information "Successfully created entry with id: $EventId."

    $QueueItem["id"] = $EventId
}

Push-OutputBinding -Name BlobOutput -Value $QueueItem

Write-Information "Trying to fetch the abstract."
$Abstract = ""
if ($QueueItem["abstract-file"]) {
    try {
        $AbstractResponse = Invoke-WebRequest -Uri ("https://lrobert.perso.math.cnrs.fr/Kos/" + $QueueItem["abstract-file"])
        $Abstract = $AbstractResponse.Content
        Write-Information "Abstract found:`n$Abstract"
    }
    catch {
        Write-Warning "Error fetching the abstract:`n$_"
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
Write-Debug "New form data:`n$($FormData | ConvertTo-Json)"

Write-Information "Posting the update."

Invoke-WebRequest `
    -Uri ($BaseUrl + "/gestion/evenement/admin/modifSeance/43/" + $QueueItem["id"]) `
    -Method Post `
    -Form $FormData `
    -WebSession $Session

Write-Information "Updated entry successfully."
