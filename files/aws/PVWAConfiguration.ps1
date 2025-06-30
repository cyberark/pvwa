[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)][string]$VaultIpAddress,
    [Parameter(Mandatory=$true)][string]$VaultAdminUser,
    [Parameter(Mandatory=$true)][string]$VaultPort
)

. "$PSScriptRoot\Common.ps1"

$LogFile = "C:\CyberArk\Deployment\Logs\PVWAConfiguration.log"


try{
    $PVWAURL = "https://pvwa/PasswordVault"
    $ScriptPath = $PSScriptRoot
    $FilePath = "C:\CyberArk\PVWA\InstallationAutomation\Registration\PVWARegisterComponentConfig.xml"
    $xml = [xml](Get-Content $filePath)
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Get vault IP"
    $step1 = $xml.SelectSingleNode("//Parameter[@Name = 'vaultip']")
    $step1.Value = $VaultIpAddress
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Get vault port"
    $step2 = $xml.SelectSingleNode("//Parameter[@Name = 'vaultport']")
    $step2.Value = $VaultPort
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Get vault user"
    $step3 = $xml.SelectSingleNode("//Parameter[@Name = 'vaultuser']")
    $step3.Value = $VaultAdminUser
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Get PVWA URL"
    $step4 = $xml.SelectSingleNode("//Parameter[@Name = 'pvwaUrl']")
    $step4.Value = $PVWAURL
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Save xml"
    $xml.Save($filePath)
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Step completed successfully"
}
catch{
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log $_.Exception.Message
    exit 1
}