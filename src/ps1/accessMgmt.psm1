function Get-TokenByAppSecret
{
    param 
    (
        [string]$appID,
        $secret,
        $tenantID = "82bdf6c1-3e56-4a5e-8c50-c331165e0192"
    )
     #Initialize Graph token
$tokenAuthURI = "https://login.microsoftonline.com/$tenantID/oauth2/token" # Felles tokenAuthURI per tenant. Hentes fra Azure->App registrations->Endpoints->OAuth 2.0 Token Endpoint
$requestBody = "grant_type=client_credentials" + 
    "&client_id=$appID" +
    "&client_secret=$Secret" +
    "&resource=https://graph.microsoft.com/"
 
$tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenAuthURI -body $requestBody -ContentType "application/x-www-form-urlencoded" # Kontakt Microsoft Graph via Rest for å hente token
$accesstoken = $tokenResponse.access_token # Hent tokenet fra svaret   
Write-Output $accesstoken
}