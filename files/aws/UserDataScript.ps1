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
# SIG # Begin signature block
# MIIy5wYJKoZIhvcNAQcCoIIy2DCCMtQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAqDf1IgaoJGHFk
# Y7m7Vl1bFyvEq/pQ72THxJ40QoG8RKCCGFcwggROMIIDNqADAgECAg0B7l8Wnf+X
# NStkZdZqMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBH
# bG9iYWxTaWduIG52LXNhMRAwDgYDVQQLEwdSb290IENBMRswGQYDVQQDExJHbG9i
# YWxTaWduIFJvb3QgQ0EwHhcNMTgwOTE5MDAwMDAwWhcNMjgwMTI4MTIwMDAwWjBM
# MSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBSMzETMBEGA1UEChMKR2xv
# YmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBAMwldpB5BngiFvXAg7aEyiie/QV2EcWtiHL8RgJDx7KKnQRf
# JMsuS+FggkbhUqsMgUdwbN1k0ev1LKMPgj0MK66X17YUhhB5uzsTgHeMCOFJ0mpi
# Lx9e+pZo34knlTifBtc+ycsmWQ1z3rDI6SYOgxXG71uL0gRgykmmKPZpO/bLyCiR
# 5Z2KYVc3rHQU3HTgOu5yLy6c+9C7v/U9AOEGM+iCK65TpjoWc4zdQQ4gOsC0p6Hp
# sk+QLjJg6VfLuQSSaGjlOCZgdbKfd/+RFO+uIEn8rUAVSNECMWEZXriX7613t2Sa
# er9fwRPvm2L7DWzgVGkWqQPabumDk3F2xmmFghcCAwEAAaOCASIwggEeMA4GA1Ud
# DwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSP8Et/qC5FJK5N
# UPpjmove4t0bvDAfBgNVHSMEGDAWgBRge2YaRQ2XyolQL30EzTSo//z9SzA9Bggr
# BgEFBQcBAQQxMC8wLQYIKwYBBQUHMAGGIWh0dHA6Ly9vY3NwLmdsb2JhbHNpZ24u
# Y29tL3Jvb3RyMTAzBgNVHR8ELDAqMCigJqAkhiJodHRwOi8vY3JsLmdsb2JhbHNp
# Z24uY29tL3Jvb3QuY3JsMEcGA1UdIARAMD4wPAYEVR0gADA0MDIGCCsGAQUFBwIB
# FiZodHRwczovL3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5LzANBgkqhkiG
# 9w0BAQsFAAOCAQEAI3Dpz+K+9VmulEJvxEMzqs0/OrlkF/JiBktI8UCIBheh/qvR
# XzzGM/Lzjt0fHT7MGmCZggusx/x+mocqpX0PplfurDtqhdbevUBj+K2myIiwEvz2
# Qd8PCZceOOpTn74F9D7q059QEna+CYvCC0h9Hi5R9o1T06sfQBuKju19+095VnBf
# DNOOG7OncA03K5eVq9rgEmscQM7Fx37twmJY7HftcyLCivWGQ4it6hNu/dj+Qi+5
# fV6tGO+UkMo9J6smlJl1x8vTe/fKTNOvUSGSW4R9K58VP3TLUeiegw4WbxvnRs4j
# vfnkoovSOWuqeRyRLOJhJC2OKkhwkMQexejgcDCCBaIwggSKoAMCAQICEHgDGEJF
# cIpBz28BuO60qVQwDQYJKoZIhvcNAQEMBQAwTDEgMB4GA1UECxMXR2xvYmFsU2ln
# biBSb290IENBIC0gUjMxEzARBgNVBAoTCkdsb2JhbFNpZ24xEzARBgNVBAMTCkds
# b2JhbFNpZ24wHhcNMjAwNzI4MDAwMDAwWhcNMjkwMzE4MDAwMDAwWjBTMQswCQYD
# VQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEpMCcGA1UEAxMgR2xv
# YmFsU2lnbiBDb2RlIFNpZ25pbmcgUm9vdCBSNDUwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQC2LcUw3Xroq5A9A3KwOkuZFmGy5f+lZx03HOV+7JODqoT1
# o0ObmEWKuGNXXZsAiAQl6fhokkuC2EvJSgPzqH9qj4phJ72hRND99T8iwqNPkY2z
# BbIogpFd+1mIBQuXBsKY+CynMyTuUDpBzPCgsHsdTdKoWDiW6d/5G5G7ixAs0sdD
# HaIJdKGAr3vmMwoMWWuOvPSrWpd7f65V+4TwgP6ETNfiur3EdaFvvWEQdESymAfi
# dKv/aNxsJj7pH+XgBIetMNMMjQN8VbgWcFwkeCAl62dniKu6TjSYa3AR3jjK1L6h
# wJzh3x4CAdg74WdDhLbP/HS3L4Sjv7oJNz1nbLFFXBlhq0GD9awd63cNRkdzzr+9
# lZXtnSuIEP76WOinV+Gzz6ha6QclmxLEnoByPZPcjJTfO0TmJoD80sMD8IwM0kXW
# LuePmJ7mBO5Cbmd+QhZxYucE+WDGZKG2nIEhTivGbWiUhsaZdHNnMXqR8tSMeW58
# prt+Rm9NxYUSK8+aIkQIqIU3zgdhVwYXEiTAxDFzoZg1V0d+EDpF2S2kUZCYqaAH
# N8RlGqocaxZ396eX7D8ZMJlvMfvqQLLn0sT6ydDwUHZ0WfqNbRcyvvjpfgP054d1
# mtRKkSyFAxMCK0KA8olqNs/ITKDOnvjLja0Wp9Pe1ZsYp8aSOvGCY/EuDiRk3wID
# AQABo4IBdzCCAXMwDgYDVR0PAQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMD
# MA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFB8Av0aACvx4ObeltEPZVlC7zpY7
# MB8GA1UdIwQYMBaAFI/wS3+oLkUkrk1Q+mOai97i3Ru8MHoGCCsGAQUFBwEBBG4w
# bDAtBggrBgEFBQcwAYYhaHR0cDovL29jc3AuZ2xvYmFsc2lnbi5jb20vcm9vdHIz
# MDsGCCsGAQUFBzAChi9odHRwOi8vc2VjdXJlLmdsb2JhbHNpZ24uY29tL2NhY2Vy
# dC9yb290LXIzLmNydDA2BgNVHR8ELzAtMCugKaAnhiVodHRwOi8vY3JsLmdsb2Jh
# bHNpZ24uY29tL3Jvb3QtcjMuY3JsMEcGA1UdIARAMD4wPAYEVR0gADA0MDIGCCsG
# AQUFBwIBFiZodHRwczovL3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5LzAN
# BgkqhkiG9w0BAQwFAAOCAQEArPfMFYsweagdCyiIGQnXHH/+hr17WjNuDWcOe2LZ
# 4RhcsL0TXR0jrjlQdjeqRP1fASNZhlZMzK28ZBMUMKQgqOA/6Jxy3H7z2Awjuqgt
# qjz27J+HMQdl9TmnUYJ14fIvl/bR4WWWg2T+oR1R+7Ukm/XSd2m8hSxc+lh30a6n
# sQvi1ne7qbQ0SqlvPfTzDZVd5vl6RbAlFzEu2/cPaOaDH6n35dSdmIzTYUsvwyh+
# et6TDrR9oAptksS0Zj99p1jurPfswwgBqzj8ChypxZeyiMgJAhn2XJoa8U1sMNSz
# BqsAYEgNeKvPF62Sk2Igd3VsvcgytNxN69nfwZCWKb3BfzCCBugwggTQoAMCAQIC
# EHe9DgW3WQu2HUdhUx4/de0wDQYJKoZIhvcNAQELBQAwUzELMAkGA1UEBhMCQkUx
# GTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExKTAnBgNVBAMTIEdsb2JhbFNpZ24g
# Q29kZSBTaWduaW5nIFJvb3QgUjQ1MB4XDTIwMDcyODAwMDAwMFoXDTMwMDcyODAw
# MDAwMFowXDELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2Ex
# MjAwBgNVBAMTKUdsb2JhbFNpZ24gR0NDIFI0NSBFViBDb2RlU2lnbmluZyBDQSAy
# MDIwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAyyDvlx65ATJDoFup
# iiP9IF6uOBKLyizU/0HYGlXUGVO3/aMX53o5XMD3zhGj+aXtAfq1upPvr5Pc+OKz
# GUyDsEpEUAR4hBBqpNaWkI6B+HyrL7WjVzPSWHuUDm0PpZEmKrODT3KxintkktDw
# tFVflgsR5Zq1LLIRzyUbfVErmB9Jo1/4E541uAMC2qQTL4VK78QvcA7B1MwzEuy9
# QJXTEcrmzbMFnMhT61LXeExRAZKC3hPzB450uoSAn9KkFQ7or+v3ifbfcfDRvqey
# QTMgdcyx1e0dBxnE6yZ38qttF5NJqbfmw5CcxrjszMl7ml7FxSSTY29+EIthz5hV
# oySiiDby+Z++ky6yBp8mwAwBVhLhsoqfDh7cmIsuz9riiTSmHyagqK54beyhiBU8
# wurut9itYaWvcDaieY7cDXPA8eQsq5TsWAY5NkjWO1roIs50Dq8s8RXa0bSV6KzV
# SW3lr92ba2MgXY5+O7JD2GI6lOXNtJizNxkkEnJzqwSwCdyF5tQiBO9AKh0ubcdp
# 0263AWwN4JenFuYmi4j3A0SGX2JnTLWnN6hV3AM2jG7PbTYm8Q6PsD1xwOEyp4Lk
# tjICMjB8tZPIIf08iOZpY/judcmLwqvvujr96V6/thHxvvA9yjI+bn3eD36blcQS
# h+cauE7uLMHfoWXoJIPJKsL9uVMCAwEAAaOCAa0wggGpMA4GA1UdDwEB/wQEAwIB
# hjATBgNVHSUEDDAKBggrBgEFBQcDAzASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1Ud
# DgQWBBQlndD8WQmGY8Xs87ETO1ccA5I2ETAfBgNVHSMEGDAWgBQfAL9GgAr8eDm3
# pbRD2VZQu86WOzCBkwYIKwYBBQUHAQEEgYYwgYMwOQYIKwYBBQUHMAGGLWh0dHA6
# Ly9vY3NwLmdsb2JhbHNpZ24uY29tL2NvZGVzaWduaW5ncm9vdHI0NTBGBggrBgEF
# BQcwAoY6aHR0cDovL3NlY3VyZS5nbG9iYWxzaWduLmNvbS9jYWNlcnQvY29kZXNp
# Z25pbmdyb290cjQ1LmNydDBBBgNVHR8EOjA4MDagNKAyhjBodHRwOi8vY3JsLmds
# b2JhbHNpZ24uY29tL2NvZGVzaWduaW5ncm9vdHI0NS5jcmwwVQYDVR0gBE4wTDBB
# BgkrBgEEAaAyAQIwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFsc2ln
# bi5jb20vcmVwb3NpdG9yeS8wBwYFZ4EMAQMwDQYJKoZIhvcNAQELBQADggIBACV1
# oAnJObq3oTmJLxifq9brHUvolHwNB2ibHJ3vcbYXamsCT7M/hkWHzGWbTONYBgIi
# ZtVhAsVjj9Si8bZeJQt3lunNcUAziCns7vOibbxNtT4GS8lzM8oIFC09TOiwunWm
# dC2kWDpsE0n4pRUKFJaFsWpoNCVCr5ZW9BD6JH3xK3LBFuFr6+apmMc+WvTQGJ39
# dJeGd0YqPSN9KHOKru8rG5q/bFOnFJ48h3HAXo7I+9MqkjPqV01eB17KwRisgS0a
# Ifpuz5dhe99xejrKY/fVMEQ3Mv67Q4XcuvymyjMZK3dt28sF8H5fdS6itr81qjZj
# yc5k2b38vCzzSVYAyBIrxie7N69X78TPHinE9OItziphz1ft9QpA4vUY1h7pkC/K
# 04dfk4pIGhEd5TeFny5mYppegU6VrFVXQ9xTiyV+PGEPigu69T+m1473BFZeIbuf
# 12pxgL+W3nID2NgiK/MnFk846FFADK6S7749ffeAxkw2V4SVp4QVSDAOUicIjY6i
# vSLHGcmmyg6oejbbarphXxEklaTijmjuGalJmV7QtDS91vlAxxCXMVI5NSkRhyTT
# xPupY8t3SNX6Yvwk4AR6TtDkbt7OnjhQJvQhcWXXCSXUyQcAerjH83foxdTiVdDT
# HvZ/UuJJjbkRcgyIRCYzZgFE3+QzDiHeYolIB9r1MIIHbzCCBVegAwIBAgIMSFsb
# X40OspUkzrn/MA0GCSqGSIb3DQEBCwUAMFwxCzAJBgNVBAYTAkJFMRkwFwYDVQQK
# ExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQDEylHbG9iYWxTaWduIEdDQyBSNDUg
# RVYgQ29kZVNpZ25pbmcgQ0EgMjAyMDAeFw0yNTAxMTYwOTQwNThaFw0yNTAyMTUx
# MzM4MzVaMIHUMR0wGwYDVQQPDBRQcml2YXRlIE9yZ2FuaXphdGlvbjESMBAGA1UE
# BRMJNTEyMjkxNjQyMRMwEQYLKwYBBAGCNzwCAQMTAklMMQswCQYDVQQGEwJJTDEQ
# MA4GA1UECBMHQ2VudHJhbDEUMBIGA1UEBxMLUGV0YWggVGlrdmExEzARBgNVBAkT
# CjkgSGFwc2Fnb3QxHzAdBgNVBAoTFkN5YmVyQXJrIFNvZnR3YXJlIEx0ZC4xHzAd
# BgNVBAMTFkN5YmVyQXJrIFNvZnR3YXJlIEx0ZC4wggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQCLULMzRCf2Q3Ic9yPzl8ZRKElvdDwbjLxe9s1bnvqKOIPp
# iP3PcsCA6G2irkXwx5Ui5ZJWsKfenAdgc5gt6Or9286sl9rlXMsPHsJfX6eOFbv4
# xEX2rhoZxjyEayyLHx0XljVk9pNimw7jIrgwrfrF/Z8ibFrPyGNYyiVoUzcKLQQ9
# UzjqLFlBfsxNjT4jF/Tm4ZlRmrkLcg4Q049jh+hZplFz58KPTsYMoFui2TEO+3lh
# B4GkiAhHpWJ8bqq1Ru+BBeACfQg3hU1uCTVGmosxyDmXQ85KA3+80OIx9KRlAGpr
# kOqTjEEyYFm/BGamWv44MYApUcak5WCvJK1uNqQTBAI+Y/6UV6WllDDJGc4t+0jg
# CxI9hn0C2LFFZxRVasreAlz+cNHT8BuQbq+NwYUyu+SmiZBuFNyNstoX4x2/2FIs
# TcFeRJfvs9dNIcf9TsUGqR1z4TP+c/ziOCd73x+q6j262CCaK24I3UD3fFaPR2tA
# sK+GA7GMGV40LRwRuAhM2IZd/vH0VAKwsTc7FJvO0VPVJFQBh5AVcRJr4gexBv6W
# gwurF4tqIpJJcoSW/5L44m6Fl8pSjkXVjlolGq1Y4xZVCfIwhlU1YI61vQHuefmN
# kBeev2oP+ruV1L3HWXU38bxyJJdpQW6RRzNDFCtJAmvwf35zNYx3WgAsnr+l/wID
# AQABo4IBtjCCAbIwDgYDVR0PAQH/BAQDAgeAMIGfBggrBgEFBQcBAQSBkjCBjzBM
# BggrBgEFBQcwAoZAaHR0cDovL3NlY3VyZS5nbG9iYWxzaWduLmNvbS9jYWNlcnQv
# Z3NnY2NyNDVldmNvZGVzaWduY2EyMDIwLmNydDA/BggrBgEFBQcwAYYzaHR0cDov
# L29jc3AuZ2xvYmFsc2lnbi5jb20vZ3NnY2NyNDVldmNvZGVzaWduY2EyMDIwMFUG
# A1UdIAROMEwwQQYJKwYBBAGgMgECMDQwMgYIKwYBBQUHAgEWJmh0dHBzOi8vd3d3
# Lmdsb2JhbHNpZ24uY29tL3JlcG9zaXRvcnkvMAcGBWeBDAEDMAkGA1UdEwQCMAAw
# RwYDVR0fBEAwPjA8oDqgOIY2aHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS9nc2dj
# Y3I0NWV2Y29kZXNpZ25jYTIwMjAuY3JsMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB8G
# A1UdIwQYMBaAFCWd0PxZCYZjxezzsRM7VxwDkjYRMB0GA1UdDgQWBBTUDzDJ2DrL
# snni4opR21IhbpYCDjANBgkqhkiG9w0BAQsFAAOCAgEApe6UYsNMxUtN2Sv8PJkt
# xyBglOy9FO3KRDnj7AA33UCNbRMWM1YHE23yl82f4x33OkxTYn1PsuWxf32npTIM
# dq3AC5ql80DYn6c9o5/QgWD3LFjI+XYe84I8/U9Zohq1FYwcyPjVv73pTBocdwZE
# 5NsnbZ2/rVEwwhwBD5SbgSY+O4Y6R860j6rH4BnQmARmEWDnijaHhDCMSpJ3TPsR
# kT46GXupmLQ+GoriAKYFUDZ8q5+21VQIJ+1se1+oqrLg3liTaoQQXnVn4Z7R+KyO
# SBBSkUpYpt6nQ3AgM/HBfAvmUalFLXxP/EFavn0D64BA9ckN9Uro/nJPIaEZ9bYa
# JlLlfLTojZlf3x3RzGrwYQIQtkmCrbajSPSbOUmrGCJfljUkrK4y2SM0/IqEo6t5
# TLZXfWUsDW4gXVD3jtNMKlL0IGcUZz4F/HF5pMLgFIYTOA+Ae4pT6OPPbxaNEDnl
# 7zcoZkx6JWsi4p3z9P4MdYEnKz/FLU6dA8VpgFHsJObPhrFT/nNgcMJHo5NDLZP5
# h5LOwwU8uWKwJiG1I65RpWYEZT4n9vhVCzz/RiFwlIkC142TS/6XSWnxp4I0vrIF
# Zbf0rlCtJodk6C/0ehISBn+w4lnC9cqiBULt+W7/Tj0H5qATsqHz1boOUHSZDjLg
# /9xeke1i/okrSFBeAxcGX7cxghnmMIIZ4gIBATBsMFwxCzAJBgNVBAYTAkJFMRkw
# FwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQDEylHbG9iYWxTaWduIEdD
# QyBSNDUgRVYgQ29kZVNpZ25pbmcgQ0EgMjAyMAIMSFsbX40OspUkzrn/MA0GCWCG
# SAFlAwQCAQUAoHwwEAYKKwYBBAGCNwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcN
# AQkEMSIEII8SmRJTv14Sn+O4ovduKqR5Gmz2ExAKDefi5BqUEKq7MA0GCSqGSIb3
# DQEBAQUABIICAAdLjDgIr9gX3KQgmAWXjd4rnw9BKk/LWUNpMtQZV0CctASCASQ8
# TOxk4rrO/03pFiXcPx0r3q/SX4Z8dwdgRXaVcBa1S5wwkxAgc9Uy/1xnPTyF7jgl
# LfM2Rw2KU5qo4R2a7JPuPjINqqOgQ3oZHRB2SCDwKpCnImUAuACX+4A8X7zl/3A5
# wJ7Y4lPjSl6cmKAJLE21M3akHH7bminAkieO45HVGlpK5AkAkxCl9aA5OPBNlED7
# 2zeAvmKNfHN+E5xwyEBqiMYbWjf7JPzFm7sulrA7YHWHDNZjOV4syfAvmL0JHqwd
# ygycWLpOr0SosjWVi2SWNRYHP8q9AusfCatuAYsbVle6N/QUSPNBv3u8MlF41ksb
# Ffta+XwZL+3Rd1uEZD4q26vu5iQut8hR3c0Q4dC8c88Cz0ncNd9YiD7G0eVRhkct
# OyWeCIXcV8xz7Yeu0j2jvsMVX35wvImPWUcBox/oWIYSwcnxVtZSgGvUXNUI6atI
# AIeOiFMm193SYS/QT8ga8WW1AXDqz5RibEBFqst56nx8zQhGMQR4xBvukzpLqtED
# AbXYg/FesGBVtwHhCiwZd0Vc/qlTVNuEk4voGjaY4Rgp+j67iVtBAKqYoyNBZuYE
# RUQWIGEUXUaLGdxoCWJo09D/lkf83BnJfEEYTjgvOJqZFFZ1Tl1gX/5noYIWzTCC
# FskGCisGAQQBgjcDAwExgha5MIIWtQYJKoZIhvcNAQcCoIIWpjCCFqICAQMxDTAL
# BglghkgBZQMEAgEwgegGCyqGSIb3DQEJEAEEoIHYBIHVMIHSAgEBBgsrBgEEAaAy
# AgMBAjAxMA0GCWCGSAFlAwQCAQUABCCP/ECiLuJ5LlcIX8TotjfIn1UIaIImmWzc
# FFeO6ibAEgIUYaVNaUx3AEF2O9VsgiQLsQYs9mgYDzIwMjUwMTIwMDcyODIzWjAD
# AgEBoGGkXzBdMQswCQYDVQQGEwJCRTEZMBcGA1UECgwQR2xvYmFsU2lnbiBudi1z
# YTEzMDEGA1UEAwwqR2xvYmFsc2lnbiBUU0EgZm9yIENvZGVTaWduMSAtIFI2IC0g
# MjAyMzExoIISVDCCBmwwggRUoAMCAQICEAGb6t7ITWuP92w6ny4BJBYwDQYJKoZI
# hvcNAQELBQAwWzELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYt
# c2ExMTAvBgNVBAMTKEdsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gU0hBMzg0
# IC0gRzQwHhcNMjMxMTA3MTcxMzQwWhcNMzQxMjA5MTcxMzQwWjBdMQswCQYDVQQG
# EwJCRTEZMBcGA1UECgwQR2xvYmFsU2lnbiBudi1zYTEzMDEGA1UEAwwqR2xvYmFs
# c2lnbiBUU0EgZm9yIENvZGVTaWduMSAtIFI2IC0gMjAyMzExMIIBojANBgkqhkiG
# 9w0BAQEFAAOCAY8AMIIBigKCAYEA6oQ3UGg8lYW1SFRxl/OEcsmdgNMI3Fm7v8tN
# kGlHieUs2PGoan5gN0lzm7iYsxTg74yTcCC19SvXZgV1P3qEUKlSD+DW52/UHDUu
# 4C8pJKOOdyUn4LjzfWR1DJpC5cad4tiHc4vvoI2XfhagxLJGz2DGzw+BUIDdT+nk
# RqI0pz4Yx2u0tvu+2qlWfn+cXTY9YzQhS8jSoxMaPi9RaHX5f/xwhBFlMxKzRmUo
# hKAzwJKd7bgfiWPQHnssW7AE9L1yY86wMSEBAmpysiIs7+sqOxDV8Zr0JqIs/FMB
# BHkjaVHTXb5zhMubg4htINIgzoGraiJLeZBC5oJCrwPr1NDag3rDLUjxzUWRtxFB
# 3RfvQPwSorLAWapUl05tw3rdhobUOzdHOOgDPDG/TDN7Q+zw0P9lpp+YPdLGulki
# bBBYEcUEzOiimLAdM9DzlR347XG0C0HVZHmivGAuw3rJ3nA3EhY+Ao9dOBGwBIln
# i6UtINu41vWc9Q+8iL8nLMP5IKLBAgMBAAGjggGoMIIBpDAOBgNVHQ8BAf8EBAMC
# B4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwHQYDVR0OBBYEFPlOq764+Fv/wscD
# 9EHunPjWdH0/MFYGA1UdIARPME0wCAYGZ4EMAQQCMEEGCSsGAQQBoDIBHjA0MDIG
# CCsGAQUFBwIBFiZodHRwczovL3d3dy5nbG9iYWxzaWduLmNvbS9yZXBvc2l0b3J5
# LzAMBgNVHRMBAf8EAjAAMIGQBggrBgEFBQcBAQSBgzCBgDA5BggrBgEFBQcwAYYt
# aHR0cDovL29jc3AuZ2xvYmFsc2lnbi5jb20vY2EvZ3N0c2FjYXNoYTM4NGc0MEMG
# CCsGAQUFBzAChjdodHRwOi8vc2VjdXJlLmdsb2JhbHNpZ24uY29tL2NhY2VydC9n
# c3RzYWNhc2hhMzg0ZzQuY3J0MB8GA1UdIwQYMBaAFOoWxmnn48tXRTkzpPBAvtDD
# vWWWMEEGA1UdHwQ6MDgwNqA0oDKGMGh0dHA6Ly9jcmwuZ2xvYmFsc2lnbi5jb20v
# Y2EvZ3N0c2FjYXNoYTM4NGc0LmNybDANBgkqhkiG9w0BAQsFAAOCAgEAlfRnz5Oa
# Q5KDF3bWIFW8if/kX7LlFRq3lxFALgBBvsU/JKAbRwczBEy0tGL/xu7TDMI0oJRc
# N5jrRPhf+CcKAr4e0SQdI8svHKsnerOpxS8M5OWQ8BUkHqMVGfjvg+hPu2ieI299
# PQ1xcGEyfEZu8o/RnOhDTfqD4f/E4D7+3lffBmvzagaBaKsMfCr3j0L/wHNp2xyn
# Fk8mGVhz7ZRe5BqiEIIHMjvKnr/dOXXUvItUP35QlTSfkjkkUxiDUNRbL2a0e/5b
# KesexQX9oz37obDzK3kPsUusw6PZo9wsnCsjlvZ6KrutxVe2hLZjs2CYEezG1mZv
# IoMcilgD9I/snE7Q3+7OYSHTtZVUSTshUT2hI4WSwlvyepSEmAqPJFYiigT6tJqJ
# SDX4b+uBhhFTwJN7OrTUNMxi1jVhjqZQ+4h0HtcxNSEeEb+ro2RTjlTic2ak+2Zj
# 4TfJxGv7KzOLEcN0kIGDyE+Gyt1Kl9t+kFAloWHshps2UgfLPmJV7DOm5bga+t0k
# Lgz5MokxajWV/vbR/xeKriMJKyGuYu737jfnsMmzFe12mrf95/7haN5EwQp04ZXI
# V/sU6x5a35Z1xWUZ9/TVjSGvY7br9OIXRp+31wduap0r/unScU7Svk9i00nWYF9A
# 43aZIETYSlyzXRrZ4qq/TVkAF55gZzpHEqAwggZZMIIEQaADAgECAg0B7BySQN79
# LkBdfEd0MA0GCSqGSIb3DQEBDAUAMEwxIDAeBgNVBAsTF0dsb2JhbFNpZ24gUm9v
# dCBDQSAtIFI2MRMwEQYDVQQKEwpHbG9iYWxTaWduMRMwEQYDVQQDEwpHbG9iYWxT
# aWduMB4XDTE4MDYyMDAwMDAwMFoXDTM0MTIxMDAwMDAwMFowWzELMAkGA1UEBhMC
# QkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExMTAvBgNVBAMTKEdsb2JhbFNp
# Z24gVGltZXN0YW1waW5nIENBIC0gU0hBMzg0IC0gRzQwggIiMA0GCSqGSIb3DQEB
# AQUAA4ICDwAwggIKAoICAQDwAuIwI/rgG+GadLOvdYNfqUdSx2E6Y3w5I3ltdPwx
# 5HQSGZb6zidiW64HiifuV6PENe2zNMeswwzrgGZt0ShKwSy7uXDycq6M95laXXau
# v0SofEEkjo+6xU//NkGrpy39eE5DiP6TGRfZ7jHPvIo7bmrEiPDul/bc8xigS5kc
# DoenJuGIyaDlmeKe9JxMP11b7Lbv0mXPRQtUPbFUUweLmW64VJmKqDGSO/J6ffwO
# WN+BauGwbB5lgirUIceU/kKWO/ELsX9/RpgOhz16ZevRVqkuvftYPbWF+lOZTVt0
# 7XJLog2CNxkM0KvqWsHvD9WZuT/0TzXxnA/TNxNS2SU07Zbv+GfqCL6PSXr/kLHU
# 9ykV1/kNXdaHQx50xHAotIB7vSqbu4ThDqxvDbm19m1W/oodCT4kDmcmx/yyDaCU
# sLKUzHvmZ/6mWLLU2EESwVX9bpHFu7FMCEue1EIGbxsY1TbqZK7O/fUF5uJm0A4F
# IayxEQYjGeT7BTRE6giunUlnEYuC5a1ahqdm/TMDAd6ZJflxbumcXQJMYDzPAo8B
# /XLukvGnEt5CEk3sqSbldwKsDlcMCdFhniaI/MiyTdtk8EWfusE/VKPYdgKVbGqN
# yiJc9gwE4yn6S7Ac0zd0hNkdZqs0c48efXxeltY9GbCX6oxQkW2vV4Z+EDcdaxoU
# 3wIDAQABo4IBKTCCASUwDgYDVR0PAQH/BAQDAgGGMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwHQYDVR0OBBYEFOoWxmnn48tXRTkzpPBAvtDDvWWWMB8GA1UdIwQYMBaAFK5s
# BaOTE+Ki5+LXHNbH8H/IZ1OgMD4GCCsGAQUFBwEBBDIwMDAuBggrBgEFBQcwAYYi
# aHR0cDovL29jc3AyLmdsb2JhbHNpZ24uY29tL3Jvb3RyNjA2BgNVHR8ELzAtMCug
# KaAnhiVodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29tL3Jvb3QtcjYuY3JsMEcGA1Ud
# IARAMD4wPAYEVR0gADA0MDIGCCsGAQUFBwIBFiZodHRwczovL3d3dy5nbG9iYWxz
# aWduLmNvbS9yZXBvc2l0b3J5LzANBgkqhkiG9w0BAQwFAAOCAgEAf+KI2VdnK0Jf
# gacJC7rEuygYVtZMv9sbB3DG+wsJrQA6YDMfOcYWaxlASSUIHuSb99akDY8elvKG
# ohfeQb9P4byrze7AI4zGhf5LFST5GETsH8KkrNCyz+zCVmUdvX/23oLIt59h07VG
# SJiXAmd6FpVK22LG0LMCzDRIRVXd7OlKn14U7XIQcXZw0g+W8+o3V5SRGK/cjZk4
# GVjCqaF+om4VJuq0+X8q5+dIZGkv0pqhcvb3JEt0Wn1yhjWzAlcfi5z8u6xM3vre
# U0yD/RKxtklVT3WdrG9KyC5qucqIwxIwTrIIc59eodaZzul9S5YszBZrGM3kWTeG
# CSziRdayzW6CdaXajR63Wy+ILj198fKRMAWcznt8oMWsr1EG8BHHHTDFUVZg6HyV
# PSLj1QokUyeXgPpIiScseeI85Zse46qEgok+wEr1If5iEO0dMPz2zOpIJ3yLdUJ/
# a8vzpWuVHwRYNAqJ7YJQ5NF7qMnmvkiqK1XZjbclIA4bUaDUY6qD6mxyYUrJ+kPE
# xlfFnbY8sIuwuRwx773vFNgUQGwgHcIt6AvGjW2MtnHtUiH+PvafnzkarqzSL3og
# sfSsqh3iLRSd+pZqHcY8yvPZHL9TTaRHWXyVxENB+SXiLBB+gfkNlKd98rUJ9dhg
# ckBQlSDUQ0S++qCV5yBZtnjGpGqqIpswggWDMIIDa6ADAgECAg5F5rsDgzPDhWVI
# 5v9FUTANBgkqhkiG9w0BAQwFADBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3Qg
# Q0EgLSBSNjETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2ln
# bjAeFw0xNDEyMTAwMDAwMDBaFw0zNDEyMTAwMDAwMDBaMEwxIDAeBgNVBAsTF0ds
# b2JhbFNpZ24gUm9vdCBDQSAtIFI2MRMwEQYDVQQKEwpHbG9iYWxTaWduMRMwEQYD
# VQQDEwpHbG9iYWxTaWduMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# lQfoc8pm+ewUyns89w0I8bRFCyyCtEjG61s8roO4QZIzFKRvf+kqzMawiGvFtonR
# xrL/FM5RFCHsSt0bWsbWh+5NOhUG7WRmC5KAykTec5RO86eJf094YwjIElBtQmYv
# Tbl5KE1SGooagLcZgQ5+xIq8ZEwhHENo1z08isWyZtWQmrcxBsW+4m0yBqYe+bnr
# qqO4v76CY1DQ8BiJ3+QPefXqoh8q0nAue+e8k7ttU+JIfIwQBzj/ZrJ3YX7g6ow8
# qrSk9vOVShIHbf2MsonP0KBhd8hYdLDUIzr3XTrKotudCd5dRC2Q8YHNV5L6frxQ
# BGM032uTGL5rNrI55KwkNrfw77YcE1eTtt6y+OKFt3OiuDWqRfLgnTahb1SK8XJW
# bi6IxVFCRBWU7qPFOJabTk5aC0fzBjZJdzC8cTflpuwhCHX85mEWP3fV2ZGXhAps
# 1AJNdMAU7f05+4PyXhShBLAL6f7uj+FuC7IIs2FmCWqxBjplllnA8DX9ydoojRoR
# h3CBCqiadR2eOoYFAJ7bgNYl+dwFnidZTHY5W+r5paHYgw/R/98wEfmFzzNI9cpt
# ZBQselhP00sIScWVZBpjDnk99bOMylitnEJFeW4OhxlcVLFltr+Mm9wT6Q1vuC7c
# Z27JixG1hBSKABlwg3mRl5HUGie/Nx4yB9gUYzwoTK8CAwEAAaNjMGEwDgYDVR0P
# AQH/BAQDAgEGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFK5sBaOTE+Ki5+LX
# HNbH8H/IZ1OgMB8GA1UdIwQYMBaAFK5sBaOTE+Ki5+LXHNbH8H/IZ1OgMA0GCSqG
# SIb3DQEBDAUAA4ICAQCDJe3o0f2VUs2ewASgkWnmXNCE3tytok/oR3jWZZipW6g8
# h3wCitFutxZz5l/AVJjVdL7BzeIRka0jGD3d4XJElrSVXsB7jpl4FkMTVlezorM7
# tXfcQHKso+ubNT6xCCGh58RDN3kyvrXnnCxMvEMpmY4w06wh4OMd+tgHM3ZUACIq
# uU0gLnBo2uVT/INc053y/0QMRGby0uO9RgAabQK6JV2NoTFR3VRGHE3bmZbvGhwE
# XKYV73jgef5d2z6qTFX9mhWpb+Gm+99wMOnD7kJG7cKTBYn6fWN7P9BxgXwA6Jiu
# Dng0wyX7rwqfIGvdOxOPEoziQRpIenOgd2nHtlx/gsge/lgbKCuobK1ebcAF0nu3
# 64D+JTf+AptorEJdw+71zNzwUHXSNmmc5nsE324GabbeCglIWYfrexRgemSqaUPv
# kcdM7BjdbO9TLYyZ4V7ycj7PVMi9Z+ykD0xF/9O5MCMHTI8Qv4aW2ZlatJlXHKTM
# uxWJU7osBQ/kxJ4ZsRg01Uyduu33H68klQR4qAO77oHl2l98i0qhkHQlp7M+S8gs
# Vr3HyO844lyS8Hn3nIS6dC1hASB+ftHyTwdZX4stQ1LrRgyU4fVmR3l31VRbH60k
# N8tFWk6gREjI2LCZxRWECfbWSUnAZbjmGnFuoKjxguhFPmzWAtcKZ4MFWsmkEDGC
# A0kwggNFAgEBMG8wWzELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24g
# bnYtc2ExMTAvBgNVBAMTKEdsb2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gU0hB
# Mzg0IC0gRzQCEAGb6t7ITWuP92w6ny4BJBYwCwYJYIZIAWUDBAIBoIIBLTAaBgkq
# hkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwKwYJKoZIhvcNAQk0MR4wHDALBglghkgB
# ZQMEAgGhDQYJKoZIhvcNAQELBQAwLwYJKoZIhvcNAQkEMSIEIA8ySt+u25doPEBs
# XygcmBYH3AwrmeM0nFfuDP++uXrzMIGwBgsqhkiG9w0BCRACLzGBoDCBnTCBmjCB
# lwQgOoh6lRteuSpe4U9su3aCN6VF0BBb8EURveJfgqkW0egwczBfpF0wWzELMAkG
# A1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExMTAvBgNVBAMTKEds
# b2JhbFNpZ24gVGltZXN0YW1waW5nIENBIC0gU0hBMzg0IC0gRzQCEAGb6t7ITWuP
# 92w6ny4BJBYwDQYJKoZIhvcNAQELBQAEggGAMECI6P4qHbir5oGHxAY53oG6WQRu
# gqgKkFHaOZjmd48CCN6z4jHF5FB3W4mhfu+akxqYGV9NN/+pKjwfIHMPUKaolQhA
# 3TEHegbMOh2LiA2lhCIpfkzRqEnLSfjXygU8968Cl6mDVBeK7KShhVA68yD1g/RY
# QexmtPgM2NT+cCNVNrrkQk9dleTp4MU0RahPLVCQKjPX0WwiQ5HL5CDnGAEkd8QA
# 4PxjbiyouMN0a+oa9/l4WjZr86GsMEeqM4UIc1gptI4krl3idH8YUL868Mxca+Hc
# X8jETCv26ui/RSSUjEcj6i5n733nQ1Ngd1BCB5jgDY0gzm3NQnVDd86cnP3nMWw9
# wPl9dOGLCNeOpBac8JLJrlo1g3KMP0TNllpYohDCrtPlCB+aF4oj/SeF37Vp3hD0
# K3D9kuuR2TGqjpAh6xdyCAZUNcuaHdhwrSSYGS1F54GNe/38ruURDNcIaYtWUP51
# omoUCoaR47RlP9Snxg2PZSA4mif3xaNWsvNR
# SIG # End signature block
