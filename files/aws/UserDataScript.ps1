[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]  [string]$Region,
    [Parameter(Mandatory = $true)]  [string]$LogGroup,
    [Parameter(Mandatory = $true)]  [string]$UserDataLogStream,
    [Parameter(Mandatory = $true)]  [string]$PVWAConfigurationLogStream,
    [Parameter(Mandatory = $true)]  [string]$PVWARegistrationLogStream,
    [Parameter(Mandatory = $true)]  [string]$VaultAdminUser,
    [Parameter(Mandatory = $false)] [string]$SSMAdminPassParameterID,
    [Parameter(Mandatory = $false)] [string]$VaultPrivateIP,
    [Parameter(Mandatory = $true)]  [string]$ComponentHostname,
    [Parameter(Mandatory = $false)] [string]$StackName
)

# Configure logging
. "$PSScriptRoot\Common.ps1"
$LogFile = "C:\CyberArk\Deployment\Logs\UserData.log"

# Ensure userdata is running first time
if (Test-Path -Path $LogFile) {
    Write-Output "Userdata already ran, exiting."
    exit 0
}

# Ensure AmazonSSMAgent is enabled and running
try {
    Set-Service AmazonSSMAgent -StartupType Automatic
    Start-Service AmazonSSMAgent
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "AmazonSSMAgent state verified successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to start AmazonSSMAgent: $_"
    exit 1
}

# Execute configCW commands
try {
    & $PSScriptRoot\CloudWatch.ps1 -LogGroup $LogGroup `
        -UserDataLogStream $UserDataLogStream `
        -PVWAConfigurationLogStream $PVWAConfigurationLogStream `
        -PVWARegistrationLogStream $PVWARegistrationLogStream `
        -Region $Region
    ChildScriptErrorHandler -ScriptName "CloudWatch"
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "CloudWatch configuration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to configure CloudWatch: $_"
    exit 1
}

# Execute PVWAConfiguration commands
try {
    & $PSScriptRoot\PVWAConfiguration.ps1 -VaultIpAddress $VaultPrivateIP `
        -VaultAdminUser $VaultAdminUser `
        -VaultPort 1858 `
        -HostName $ComponentHostname
    ChildScriptErrorHandler -ScriptName "PVWAConfiguration"
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "PVWAConfiguration configuration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to execute PVWAConfiguration configuration: $_"
    exit 1
}

# Execute PVWARegistration commands
try {
    & $PSScriptRoot\PVWARegistration.ps1 -VaultAdminUser $VaultAdminUser -SSMAdminPassParameterID $SSMAdminPassParameterID
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

# Generate and apply a new self-signed certificate to the existing HTTPS binding on Default Web Site
try {
    & $PSScriptRoot\CreateSelfCertAndBind.ps1 -CertificateDnsName $ComponentHostname
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "New self-signed certificate created successfully."
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to execute self-signed certificate configuration: $_"
    exit 1
}

# Execute CyberArk Scheduled Tasks service commands
try {
    & sc.exe config "CyberArk Scheduled Tasks" start=auto
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "CyberArk Scheduled Tasks service configuration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to execute CyberArk Scheduled Tasks service configuration: $_"
    exit 1
}

# Execute configHostname commands
try {
    Rename-Computer -NewName $ComponentHostname -Force
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Hostname configuration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to configure hostname: $_"
    exit 1
}

# Configure a completion signal scheduled task
$ResourceName = "PVWAMachine"
$scriptBlock = @"
    # Configure logging
    . "$PSScriptRoot\Common.ps1"
    # Signal completion to CloudFormation
    if ("$StackName" -ne "") {
        `$cfn_signal_output = cfn-signal.exe --stack $StackName --success true --resource $ResourceName --region $Region 2>&1
        if (`$LastExitCode -ne 0) {
            WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to signal CloudFormation: `$cfn_signal_output"
            Unregister-ScheduledTask -TaskName "SignalSuccess" -Confirm:`$false
            exit 1
        }
        WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Signaled CloudFormation completion successfully"
    }
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "$ResourceName deployment process completed successfully"
    Unregister-ScheduledTask -TaskName "SignalSuccess" -Confirm:`$false
"@
# Convert script block to a Base64 encoded string to pass it to the scheduled task
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($scriptBlock))
# Creating the scheduled task
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-EncodedCommand $encodedCommand"
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -User "NT AUTHORITY\SYSTEM" `
    -RunLevel "Highest" `
    -TaskName "SignalSuccess" `
    -Description "Signal completion after reboot"

# Reboot to apply hostname change
try {
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Host will now be restarted to apply hostname change"
    Restart-Computer -Force
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to restart computer: $_"
    exit 1
}