# Put current HTTP Redirect path for the default web site in variable
$path = (Get-WebConfigurationProperty -filter /system.webServer/httpRedirect -name "destination" -PSPath 'IIS:\Sites\Default Web Site').value
$computerName = $env:computername

If ($path -ne "https://$computerName/PasswordVault") {
    try {
        Set-WebConfigurationProperty system.webServer/httpRedirect -Name "destination" -PSPath "IIS:\sites\Default Web Site" -Value "https://$computerName/PasswordVault" -ErrorAction Stop
        Write-Output "HTTP Redirect path for default web site changed to https://$computerName/PasswordVault Successfully"
        exit 0
    } catch {
        Write-Output "The Set-WebConfigurationProperty command failed: $($error[0])"  -ForegroundColor Red
        exit 1
    }
} else {
	Write-Output "HTTP Redirect path has the correct path already, no change needed"
}
