<#
    Script for migration users from Active Directory to FreeIPA

    Author - Anton Petrianik
    https://github.com/tato1027
    01 September 2023
    Version 1.0
    
    Example:
    .\MigrateFromAD.ps1 -BaseDN "OU=Users,DC=local,DC=domain"
         -FreeIPAFqdn "freeipa.domain" -Json ".\json\stageuser_add.json"

    All parameters are necessary. Specify source base DN with Active Directory users, FQDN of Free IPA server and path to json file
    with API method. You will asked to prompt a Free IPA credentials.

 #>

param(
    [parameter(Mandatory)][string]$BaseDN,
    [parameter(Mandatory)][string]$FreeIPAFqdn,
    [parameter(Mandatory)][string]$Json
 )

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


function Invoke-FreeIPALogin {
    param(
        [parameter(Mandatory = $True)]$Session,
        [parameter(Mandatory = $True)][string]$Fqdn,
        [parameter(Mandatory = $True)][PSCredential]$Credentials
    )
    process {
        $Credentials.Password | ConvertFrom-SecureString 
        $User = $Credentials.UserName
        $Password = $Credentials.GetNetworkCredential().Password
        $Body = @{"user" = "$($User)"; "password" = "$($Password)"}
        $Header = @{"Content-Type" = "application/x-www-form-urlencoded"; "Accept" = "application/json"}
        Invoke-RestMethod -Uri "https://$($Fqdn)/ipa/session/login_password" -Method POST -Body $Body `
            -WebSession $Session -Headers $Header
    }
}


function Invoke-FreeIPARequest {
    param(
        [parameter(Mandatory = $True)]$Session,
        [parameter(Mandatory = $True)][string]$Fqdn,
        [parameter(Mandatory = $True)][string]$Body
    )
    process {
        $Header = @{"Referer" = "https://$($Fqdn)/ipa"; "Accept" = "application/json"}
        $Type = "application/json; charset=utf-8"
        $Request = Invoke-RestMethod -Uri "https://$($Fqdn)/ipa/session/json" -WebSession $Session `
            -Method POST -Body $Body -Headers $Header -ContentType $Type
        return $Request
    }
}


# Get Active Directory users
try {
    $OrganizationalUnit = Get-ADOrganizationalUnit -Identity $BaseDN
    $ADUsers = Get-ADUser -Filter * -SearchBase $OrganizationalUnit -Properties employeeNumber,
        title,mail,department,telephoneNumber,mobile
    Write-Host "Active Directory users: $($ADUsers.Count)" -ForegroundColor Yellow
}
catch {
    Write-Host $_ -BackgroundColor Red
    exit 1    
}

# Get FreeIPA credentials
try {
    $FreeIPACredentials = Get-Credential -Message "FreeIPA log in with username and password"
}
catch {
    Write-Host $_ -BackgroundColor Red
    exit 1 
}

# New web session
$RestSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# Login to FreeIPA
try {
    Invoke-FreeIPALogin -Session $RestSession -Fqdn $FreeIPAFqdn -Credentials $FreeIPACredentials
}
catch {
    Write-Host $_ -BackgroundColor Red
    exit 1
}

# Transfer users to FreeIPA
foreach ($ADUser in $ADUsers) {
	Invoke-Expression ('$Body = @"' + "`n" + (Get-Content $Json -Encoding UTF8 | ForEach-Object {$_ + "`n"}) + "`n" + '"@')
    try {
        $Request = Invoke-FreeIPARequest -Session $RestSession -Fqdn $FreeIPAFqdn -Body $Body
        Write-Host ($Request.Result)
    }
    catch {
        Write-Host $_ -BackgroundColor Red
        continue 
    }
}

exit 0
