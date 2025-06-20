[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)][string]$VaultAdminUser,
    [Parameter(Mandatory=$true)][SecureString]$AdminPassword
)

. "$PSScriptRoot\Common.ps1"

$LogFile = "C:\CyberArk\Deployment\Logs\PVWARegistration.log"

try{
    $ScriptPath = $PSScriptRoot
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Setting path location for registration"
    Set-Location "C:\CyberArk\PVWA\InstallationAutomation\Registration"
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Convert Admin password to secure string for registration PS"
    $secStrObj = $AdminPassword # ConvertTo-SecureString $AdminPassword -AsPlainText -Force
    $AdminCred = New-Object System.Management.Automation.PSCredential("pass", $AdminPassword)
    $Action = .\PVWARegisterComponent.ps1 -pwd $AdminCred.GetNetworkCredential().Password
    $Action | Out-File -FilePath "pvwa_registration_log.log"
    $Result = Get-Content "pvwa_registration_log.log" -Raw | ConvertFrom-Json
    if ($Result.isSucceeded -eq 0) {
        WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Step completed successfully"
        exit 0
    } else {
        WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Registration step failed"
        exit 1
    }
}
catch{
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log $_.Exception.Message
    exit 1
}