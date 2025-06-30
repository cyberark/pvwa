[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)][string]$VaultIpAddress,
    [Parameter(Mandatory=$true)][string]$VaultAdminUser,
    [Parameter(Mandatory=$true)][string]$VaultPort,
    [Parameter(Mandatory=$true)][SecureString]$AdminPassword
)

. "$PSScriptRoot\Common.ps1"
$LogFile = "C:\CyberArk\Deployment\Logs\UserData.log"

# Execute PVWAConfiguration commands
try {
    & $PSScriptRoot\PVWAConfiguration.ps1 -VaultIpAddress $VaultIpAddress `
                            -VaultAdminUser $VaultAdminUser `
                            -VaultPort $VaultPort
    ChildScriptErrorHandler -ScriptName "PVWAConfiguration"
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "PVWAConfiguration configuration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to execute PVWAConfiguration configuration: $_"
    exit 1
}

# Execute PVWARegistration commands
try {
    & $PSScriptRoot\PVWARegistration.ps1 -VaultAdminUser $VaultAdminUser -AdminPassword $AdminPassword
    ChildScriptErrorHandler -ScriptName "PVWARegistration"
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "PVWARegistration configuration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to execute PVWARegistration configuration: $_"
    exit 1
}

# Execute PasswordVaultWebAccessPool commands
try {
    Import-Module 'WebAdministration'
    Start-WebAppPool -Name PasswordVaultWebAccessPool
    Set-ItemProperty -Path IIS:\AppPools\PasswordVaultWebAccessPool -Name autoStart -Value 'true'
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "PasswordVaultWebAccessPool configuration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to execute PasswordVaultWebAccessPool configuration: $_"
    exit 1
}
