<#
    Script for REST Request to FreeIPA

    Author - Anton Petrianik
    https://github.com/tato1027
    30 August 2023
    Version 1.0

 #>

# Apply policy to trust all certificates
add-type @"
 using System.Net;
 using System.Security.Cryptography.X509Certificates;
 public class TrustAllCertsPolicy : ICertificatePolicy {
 public bool CheckValidationResult(
 ServicePoint srvPoint, X509Certificate certificate,
 WebRequest request, int certificateProblem) {
 return true;
 }
 }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'

# Get FreeIPA credentials
try {
    $Credentials = Get-Credential -Credential $null
    $Credentials.Password | ConvertFrom-SecureString 
}
catch {
    Write-Host $_ -BackgroundColor Red
    exit 1    
}
$FreeIPAUser = $Credentials.UserName
$FreeIPAPassword = $Credentials.GetNetworkCredential().Password

# Fully qualified domain name of FreeIPA server
$FreeIPAFqdn = "freeipa.domain"

function Invoke-FreeIPALogin {
    param(
        [parameter(Mandatory = $True)]$Session,
        [parameter(Mandatory = $True)][string]$Fqdn,
        [parameter(Mandatory = $True)][string]$User,
        [parameter(Mandatory = $True)][string]$Password
    )
    process {
        $Body = @{"user" = "$($User)"; "password" = "$($Password)"}
        $Header = @{"Cotent-Type" = "application/x-www-form-urlencoded"; "Accept" = "application/json"}
        Invoke-RestMethod -Uri "https://$($Fqdn)/ipa/session/login_password" -Method POST -Body $Body -WebSession $Session -Headers $Header
    }
}

$RestSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession​

try {
    Invoke-FreeIPALogin -Session $RestSession -Fqdn $FreeIPAFqdn -User $FreeIPAUser -Password $FreeIPAPassword
}
catch {
    Write-Host $_ -BackgroundColor Red
    exit 1
}

function Invoke-FreeIPARequest {
    param(
        [parameter(Mandatory = $True)]$Session,
        [parameter(Mandatory = $True)][string]$Fqdn,
        [parameter(Mandatory = $True)][string]$Body
    )
    process {
        $Header = @{"Referer" = "https://$($Fqdn)/ipa"; "Accept" = "application/json"}
        $Type = "application/json"
        $Request = Invoke-RestMethod -Uri "https://$($Fqdn)/ipa/session/json" -WebSession $Session -Method POST -Body $Body -Headers $Header -ContentType $Type
        return $Request
    }
}

$FreeIPAMethod = @"
{"method": "stageuser_add", "params": [["gaben"],{"givenname": "Gabe", "sn": "Newell", "cn": "Gabe Newell"}]}
"@

$Request = Invoke-FreeIPARequest -Session $RestSession -Fqdn $FreeIPAFqdn -Body $FreeIPAMethod
Write-Host ($Request.Result)
