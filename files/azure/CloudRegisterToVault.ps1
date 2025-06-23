[CmdletBinding(DefaultParameterSetName="PVWA")]
param
(
    [Parameter(ParameterSetName='PVWA')]
	[switch]$PVWA,
	[Parameter(ParameterSetName='PVWA',Mandatory=$true,HelpMessage="Enter the Vault IP")]
	[String]$PVWAVaultIP,
	[Parameter(ParameterSetName='PVWA',Mandatory=$true,HelpMessage="Enter the Vault Port")]
	[String]$PVWAVaultPort,
	[Parameter(ParameterSetName='PVWA',Mandatory=$true,HelpMessage="Enter the Vault User")]
	[String]$PVWAVaultUser,
	[Parameter(ParameterSetName='PVWA',Mandatory=$false,HelpMessage="Enter the PVWA Installation Package Dir")]
	[String]$PVWAInstallPackageDir,
	[Parameter(ParameterSetName='PVWA',Mandatory=$false,HelpMessage="Enter the PVWA Auth Type")]
	[String]$PVWAAuthenticationList,
	[Parameter(ParameterSetName='PVWA',Mandatory=$false,HelpMessage="Enter the PVWA IIS App Folder")]
	[String]$PVWAVirtualDirectoryPath,
	[Parameter(ParameterSetName='PVWA',Mandatory=$true,HelpMessage="Enter the PVWA URL")]
	[String]$PVWAUrl,
	[Parameter(ParameterSetName='PVWA',Mandatory=$false,HelpMessage="Enter the PVWA Installation Path")]
	[String]$PVWAConfigFilePath,
    [Parameter(ParameterSetName='PVWA',Mandatory=$true,HelpMessage="Vault Password")]
	[String]$PVWAVaultPassword
)

function Main{

$ScriptPath = $PSScriptRoot
Set-Location $PSScriptRoot

$FilePath = "$ScriptPath\PVWA\InstallationAutomation\Registration\PVWARegisterComponentConfig.xml"
$xml = [xml](Get-Content $filePath)
$step1 = $xml.SelectSingleNode("//Parameter[@Name = 'vaultip']")
$step1.Value = $PVWAVaultIP
$step2 = $xml.SelectSingleNode("//Parameter[@Name = 'vaultport']")
$step2.Value = $PVWAVaultPort
$step3 = $xml.SelectSingleNode("//Parameter[@Name = 'vaultuser']")
$step3.Value = $PVWAVaultUser
#$step4 = $xml.SelectSingleNode("//Parameter[@Name = 'installpackagedir']")
#$step4.Value = $PVWAInstallPackageDir
#$step5 = $xml.SelectSingleNode("//Parameter[@Name = 'authenticationlist']")
#$step5.Value = $PVWAAuthenticationList
#$step6 = $xml.SelectSingleNode("//Parameter[@Name = 'virtualDirectoryPath']")
#$step6.Value = $PVWAVirtualDirectoryPath
$step7 = $xml.SelectSingleNode("//Parameter[@Name = 'pvwaUrl']")
$step7.Value = $PVWAUrl
#$step8 = $xml.SelectSingleNode("//Parameter[@Name = 'configFilesPath']")
#$step8.Value = $PVWAConfigFilePath

$xml.Save($filePath)

Set-Location "c:\cyberark\PVWA\InstallationAutomation\Registration"
$Action = .\PVWARegisterComponent.ps1 -pwd $PVWAVaultPassword
$Action | Out-File -FilePath "pvwa_registration_log"
$Result = Get-Content "pvwa_registration_log" -Raw | ConvertFrom-Json
if ($Result.isSucceeded -eq 0) {
    exit 0
} else {
    exit 1
}

}

Main
