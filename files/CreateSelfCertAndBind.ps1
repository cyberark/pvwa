
# The name of the certificate
param (
    [string]$CertificateDnsName = $null
)

# Set $CertificateDnsName to $env:computername if the parameter was not provided
if (-not $CertificateDnsName) {
    $CertificateDnsName = $env:computername
}

Write-Output "Certificate DNS Name: $CertificateDnsName"

# The Website that we will assign the certificate
$siteName = "Default Web Site" 

# ----------------------------------------------------------------------------------------
# SSL CERTIFICATE CREATION
# ----------------------------------------------------------------------------------------

# create the ssl certificate that will expire in 30 years
try 
{
    $newCert = New-SelfSignedCertificate -DnsName $CertificateDnsName -CertStoreLocation cert:\LocalMachine\My -NotAfter (Get-Date).AddYears(30)
    "Certificate Details:`r`n`r`n $newCert"
    
    
    # ----------------------------------------------------------------------------------------
    # IIS BINDINGS
    # ----------------------------------------------------------------------------------------
    
    
    $webbindings = Get-WebBinding -Name $siteName
    $webbindings
    
    
    $hasSsl = $webbindings | Where-Object { $_.protocol -like "*https*" }
    
    if($hasSsl)
    {
        Write-Output "An SSL certificate is already assigned. Removing it..."
        Get-WebBinding -Port 443 -Name "Default Web Site" | Remove-WebBinding
        Write-Output "Removing of SSL binding finished successfully"
    }
    
    "Applying TLS/SSL Certificate"
    New-WebBinding -Name $siteName -Port 443 -Protocol https 
    (Get-WebBinding -Name $siteName -Port 443 -Protocol "https").AddSslCertificate($newCert.Thumbprint, "my")
}
catch 
{
    Write-Output "An Error ocured on certificate creation..."
    
}
"`r`n`r`nNew web bindings"
$webbindings = Get-WebBinding -Name $siteName
$webbindings