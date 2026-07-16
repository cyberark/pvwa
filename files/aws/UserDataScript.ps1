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
    ChildScriptErrorHandler -LogFile $LogFile -ScriptName "CloudWatch"
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "CloudWatch configuration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to configure CloudWatch: $_"
    exit 1
}

WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "Getting Admin password from ssm"
$SecuredAdminPassword = ConvertTo-SecureString -AsPlainText (Get-SSMParameterValue -Name "$SSMAdminPassParameterID" -WithDecryption $true).Parameters.Value -Force

# PVWA registration block
try {
    & $PSScriptRoot\PVWAComponentRegistration.ps1 -VaultIpAddress $VaultPrivateIP `
        -VaultAdminUser $VaultAdminUser `
        -VaultPort 1858 `
        -AdminPassword $SecuredAdminPassword
    ChildScriptErrorHandler -LogFile $LogFile -ScriptName "PVWAComponentRegistration"
    WriteLog -LogFile $LogFile -LogLevel "INFO" -Log "PVWA component registration completed successfully"
} catch {
    WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to register PVWA component: $_"
    exit 1
}

# Generate and apply a new self-signed certificate to the existing HTTPS binding on Default Web Site
try {
    & $PSScriptRoot\CreateSelfCertAndBind.ps1 -CertificateDnsName "pvwa"
    ChildScriptErrorHandler -LogFile $LogFile -ScriptName "CreateSelfCertAndBind"
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
# MII6SQYJKoZIhvcNAQcCoII6OjCCOjYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDKFiVsdtFzuTi3
# j3/hcDqLssCU+KHWxUqDJJmiGS3+J6CCGJkwggROMIIDNqADAgECAg0B7l8Wnf+X
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
# HvZ/UuJJjbkRcgyIRCYzZgFE3+QzDiHeYolIB9r1MIIHsTCCBZmgAwIBAgIMBmw4
# iuAOfBdrKw0JMA0GCSqGSIb3DQEBCwUAMFwxCzAJBgNVBAYTAkJFMRkwFwYDVQQK
# ExBHbG9iYWxTaWduIG52LXNhMTIwMAYDVQQDEylHbG9iYWxTaWduIEdDQyBSNDUg
# RVYgQ29kZVNpZ25pbmcgQ0EgMjAyMDAeFw0yNTAxMjgxMDI4MzNaFw0yODAxMjkx
# MDI4MzNaMIH3MR0wGwYDVQQPDBRQcml2YXRlIE9yZ2FuaXphdGlvbjESMBAGA1UE
# BRMJNTEyMjkxNjQyMRMwEQYLKwYBBAGCNzwCAQMTAklMMQswCQYDVQQGEwJJTDEQ
# MA4GA1UECBMHQ2VudHJhbDEUMBIGA1UEBxMLUGV0YWggVGlrdmExEzARBgNVBAkT
# CjkgSGFwc2Fnb3QxHzAdBgNVBAoTFkN5YmVyQXJrIFNvZnR3YXJlIEx0ZC4xHzAd
# BgNVBAMTFkN5YmVyQXJrIFNvZnR3YXJlIEx0ZC4xITAfBgkqhkiG9w0BCQEWEmFk
# bWluQGN5YmVyYXJrLmNvbTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# ANZQPlxrcfMjyi+hhEn41HogbUr17cJB+2rbTOBphAPzZEySpd+GObt2pAyYbXTb
# 1XGHRomYxq/fTVcDWn6ESHKqIpTUnTsai2FakMr4OINfey2c0Lw81SCwedG6ind+
# QxszJ3c1iAoyuO8fbNAJJQHKTNAdTCADAHrfHvv8fuF8iw8vZCP5E6JFdcvaNUL9
# 9lecTTlIuXMyfLoO/9Q6geZ30UeSibynHoZbGzzK20pxL9VM5LA9YiGtA+bfdRGe
# hlqhPD4KgBRkc9bogTxA78QaiBUEnYM1vMmKc86MjXSS6R+z5mFAdhcs5C6cqWdO
# wo5jVFXpwxQh0jNTalt/kkwTjlIeO3+fdDDYLmbmH3nIsMutaHyXPogVp7upktz9
# WeS9r0ZpqKw7viVe/CWS9Df8/ceZD9zBkIbTrYGFU02hDaWaN1pFs6V21iaiTaZX
# pnnpEbtgoy8rptlFFIf0GQBDD0mTBDm7lZ8rDfN7IECcahCN4dMfnFO/QFpxAILa
# ekomXUmtkH3WBaQl4hraHja+fCi4ZtKhYYTZWdakH6bvdkENywuze/liwv2OVdZ4
# qddJpbvblqa9jqnV8RhugofYVEBq6yyd6OgJosdFPIZN7upzrCmHJTiTDtBNQJ2z
# m7LXrryUF9yTyjeUjLbUfTKbpj4UzM3jcKu1J5jDL5zFAgMBAAGjggHVMIIB0TAO
# BgNVHQ8BAf8EBAMCB4AwgZ8GCCsGAQUFBwEBBIGSMIGPMEwGCCsGAQUFBzAChkBo
# dHRwOi8vc2VjdXJlLmdsb2JhbHNpZ24uY29tL2NhY2VydC9nc2djY3I0NWV2Y29k
# ZXNpZ25jYTIwMjAuY3J0MD8GCCsGAQUFBzABhjNodHRwOi8vb2NzcC5nbG9iYWxz
# aWduLmNvbS9nc2djY3I0NWV2Y29kZXNpZ25jYTIwMjAwVQYDVR0gBE4wTDBBBgkr
# BgEEAaAyAQIwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFsc2lnbi5j
# b20vcmVwb3NpdG9yeS8wBwYFZ4EMAQMwCQYDVR0TBAIwADBHBgNVHR8EQDA+MDyg
# OqA4hjZodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29tL2dzZ2NjcjQ1ZXZjb2Rlc2ln
# bmNhMjAyMC5jcmwwHQYDVR0RBBYwFIESYWRtaW5AY3liZXJhcmsuY29tMBMGA1Ud
# JQQMMAoGCCsGAQUFBwMDMB8GA1UdIwQYMBaAFCWd0PxZCYZjxezzsRM7VxwDkjYR
# MB0GA1UdDgQWBBQewhxJyrlxdN3533DHK3x6hrz7uzANBgkqhkiG9w0BAQsFAAOC
# AgEAWgNDad105JaVijYhNrwnSPmm1mIhDpSvPDvIR4pENU9IdPcI8rxXRmJ083JM
# vIx5p7LvuBOTkyaNgZOjmkypMNM4NtMtHHdXAiWb6T+Udv4w0lcgUBWapeRxO7X5
# ok+E9lrVeSiiSrM/6TDF3xkAwcR5CzYjEYsgYa0H+hBXl9+oXe2QYFuArlQ0OfTv
# nXr2iFlvl0AKR7fRY0qBBGoKUATjGiYUFcigc9PyW2vml1BMxXx65jkKdoPIMZSJ
# Ka7xkExONB+t3uJc8yI+n2x24k1bjl8mJdnEkryUATe58vLxfYa93mLFC7VLCTND
# cJjFBvdL86F1HyveXhHX5XMlS/HPcnRk6VV8+zkr72fGP18cxl1nOAftgjOxh0mD
# Y6l9UMkOle1gSlf/S15z6VlRx+TkE/ZeL2n/tw4zHqWaNatHy+Zs2BIzaMdzP/u4
# tYTOuhQfXYnP5zrGw5ldYkIAQawVZwcODVO+FBb8/F3uTBbiMqCaOxy8RGLTqJlI
# bk+fBnkgtYyiIglUE10Y/FwI4qMgG2iZh97WsISLblu4Lfz9t7/bo54Y4bGqOdnW
# rz6e4hDhlkozop7MHG35nqHRN5Qx4iUDxvyDJLpZXG0kes+Cx+zkqhGvz9ST0bB6
# WH5RcnIk2Rog6Rr/bs0O1ZMS5DZy6vm1RB5fAZfAZ451uRwxgiEGMIIhAgIBATBs
# MFwxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTIwMAYD
# VQQDEylHbG9iYWxTaWduIEdDQyBSNDUgRVYgQ29kZVNpZ25pbmcgQ0EgMjAyMAIM
# Bmw4iuAOfBdrKw0JMA0GCWCGSAFlAwQCAQUAoHwwEAYKKwYBBAGCNwIBDDECMAAw
# GQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisG
# AQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEICS5mWqA/lY77/oTTNH2Bf+86jFbsMjC
# HFyeKkw8CLF8MA0GCSqGSIb3DQEBAQUABIICADIRn+hOHRYfM63xvo8W3HaMAlx3
# 4VTBOQTH765uczEDtMRbCieremw5MjK4Ybngmu8J30eI8DBrhbA+0G+AMxXqejA9
# GHe63j6iv8Iw4QOp+TyYxTWQ8HvbtSG+8AtwYWY/UdzBWCMv0v52vdYkCOxaU4Yb
# fgn75UWzsBeIMBcdgf9HG079Wqr3TiKKJAVF6heK64Xv6DZzcG6AP5bii7pfA0T8
# GMyzOV3u0VopnPYfe31MorSO6Ynb/qcTp5sHBgb5bcrFJI95W49GqyxlgZyxfAIL
# K1pHOWXEaRnNIpfQstA/qbtUfH2txT3xq/KFrDqom7mw/J26KP4VJLv/BBVYmtsv
# jqLr5FTXsSkZ8p+QiWuYYlhSjEeU33rNPOtXEYFtNPrNUv4crhhHqYMMYEPDwohk
# rQ7sDr1i9cwcHCP6muVRBaW2U17r/eSmJ/f8waLKD23r5xxN0oegql2NfXXhIRbV
# oiUjncjB7XnYsBcI+oZIBUFx6SbZvzfltLY2TXyzwiO/IfxDnd10ASVgrQjiQLFu
# 60Jh079cXJKMBKkzuW241WEZreDUqjQSJ4CcbwJbqb2ViPYtwR6BiJ28INuBK0Oz
# nHfwLjKVMGATmMdMwQNLBbQUG0wjcdJt+PdY22MbQMYsUPlAca7uEcs3D9N+Wyr9
# mmMYSUFszJAoYP1LoYId7TCCHekGCisGAQQBgjcDAwExgh3ZMIId1QYJKoZIhvcN
# AQcCoIIdxjCCHcICAQMxDTALBglghkgBZQMEAgIwgeQGCyqGSIb3DQEJEAEEoIHU
# BIHRMIHOAgEBBgsrBgEEAaAyAgMCAjAxMA0GCWCGSAFlAwQCAQUABCBXn6+VUwCm
# qTvCKnj8pebJ8vUjMaivFzU26TFmzmJMqQIUP6zYv5D2Jy0Acih49PISTBvtkiIY
# DzIwMjYwNjE4MDcyODM3WjADAgEBoF2kWzBZMQswCQYDVQQGEwJCRTEZMBcGA1UE
# ChMQR2xvYmFsU2lnbiBudi1zYTEvMC0GA1UEAxMmR2xvYmFsc2lnbiBSNDUgVFNB
# IGZvciBDb2RlU2lnbiAyMDI1MTCgghlgMIIGijCCBHKgAwIBAgIRAIRyP8GVzBbx
# 2yui9mDfK+QwDQYJKoZIhvcNAQEMBQAwXjELMAkGA1UEBhMCQkUxGTAXBgNVBAoT
# EEdsb2JhbFNpZ24gbnYtc2ExNDAyBgNVBAMTK0dsb2JhbFNpZ24gT2ZmbGluZSBS
# NDUgVGltZXN0YW1waW5nIENBIDIwMjUwHhcNMjUxMDE1MDcyNTA0WhcNMzcwMTEw
# MDAwMDAwWjBZMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1z
# YTEvMC0GA1UEAxMmR2xvYmFsc2lnbiBSNDUgVFNBIGZvciBDb2RlU2lnbiAyMDI1
# MTAwggGiMA0GCSqGSIb3DQEBAQUAA4IBjwAwggGKAoIBgQDRSo2hjYZASCijCQSc
# 2RMQPPKojE/xf4Uija2JnsJ7Snl2gDoxKjQ9HcU6rVD8pgy1sBKdVxtLLFhY3gzY
# /PA2iwIs6ZzCnxshtjShsN1RyzRrzc4Fq+0xQx6qADUMn96mqHE/0ok53DPbmpBk
# kUDytGM79nQfw9WVymYgA+TkbA0/QOmPNNJIZ6CjX0t3wJfhL0caiXthBBMEWKxT
# 5v2U7ZRbCq/DVDXA9oX1iFVBVaBpx57MLL00nyHux0InYS7Rr54M3tNhm7+0maxp
# yTFa51uY1PHtTJMup/l3RGooQ5YweCH2hDoUNwKOC7QkFbklhPdq27EXkueg8qLO
# nRDmVO1r+B1yMAbl6QuV0L+OPB1SKBAPpmIFklmJ0SoibbUqxsTzejjdI+ywQLUc
# XilogwKWsJ46h6wjlU5AVqT7FEBYzWCTt6hf7SLQbPGs02Ba8oaaNfo0SL+aApN9
# 4luEB/wuE1lgptrckLzbQlCp56OgkAJYpqYuui+TfueCIU0CAwEAAaOCAcYwggHC
# MA4GA1UdDwEB/wQEAwIHgDAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAMBgNVHRMB
# Af8EAjAAMB0GA1UdDgQWBBQy+tPhB2gnkGsI0j8dPIxlNigGGTAfBgNVHSMEGDAW
# gBR3AjsBMQ8edHfDSMjDB2NViKU7ojCBpQYIKwYBBQUHAQEEgZgwgZUwQgYIKwYB
# BQUHMAGGNmh0dHA6Ly9vY3NwLmdsb2JhbHNpZ24uY29tL2dzb2ZmbGluZXI0NXRp
# bWVzdGFtcGNhMjAyNTBPBggrBgEFBQcwAoZDaHR0cDovL3NlY3VyZS5nbG9iYWxz
# aWduLmNvbS9jYWNlcnQvZ3NvZmZsaW5lcjQ1dGltZXN0YW1wY2EyMDI1LmNydDBK
# BgNVHR8EQzBBMD+gPaA7hjlodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29tL2dzb2Zm
# bGluZXI0NXRpbWVzdGFtcGNhMjAyNS5jcmwwVgYDVR0gBE8wTTAIBgZngQwBBAIw
# QQYJKwYBBAGgMgEeMDQwMgYIKwYBBQUHAgEWJmh0dHBzOi8vd3d3Lmdsb2JhbHNp
# Z24uY29tL3JlcG9zaXRvcnkvMA0GCSqGSIb3DQEBDAUAA4ICAQCOrnCmj0eGkYpu
# niz6/WFm91s6KjnhkMKYlbcftgpMBtlhysVniEOfBvhcvoFQw4AOHG9NRVvZpkBn
# ag5Dt1HM3Jg21gRVCBwFyP1ET8IDxoflYx5OD4SCNLHs6vCg6rFkNT81v9Zy8u0x
# Xy3WboN5iK/SbTmLGqCrAGJihLLrfIhvddwVrdByiHteLxgjugT6JQogCSoBF2Jq
# mH0ZBCl515btbTuWZLrQUs5vvl2o98Mdju9yyJRWLzPVcUkRk9d8xBBi638FBOAu
# o3fcyThGcne7wUOa+TghhwIHbZ3pxTYpgo5cCxEZsH8EXwiTUTwHf0qesssg/2Xd
# cGH7s0AR4TyOJ2QnAayYOAM/XOBxNzURQg4mhMdPL/F8VCMKj3koJaVcx2akh0B8
# 2le/aBU8q2Oa++OwOwiHF5e+f9m+yhyYbwGSogWIV3hgRl+VyKrch8gv35FHr/cV
# z8n0/CPGRXGiYJZ7P1wOOgYdkMD2iDKVYQby5Ix/xCB0/lSKLnqEoFezfmnCJbGg
# ACVswMsxhJEUjtxEcQc9afalne+IOts0v/yCRikJsnmVbS0x50Dk2OH+VCiU9s/X
# yzgfC7WzrtQ5diIdc2Ksi3JMTJm4a0LiEIZWitD5+6PokOkQ8+35TsHOwUhs87I/
# yyJjlIZpAV4Of1/JN8bWVB3Edm4WzjCCBqAwggSIoAMCAQICEQCD2oY3t58MhAyU
# e4QKUngfMA0GCSqGSIb3DQEBDAUAMFMxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBH
# bG9iYWxTaWduIG52LXNhMSkwJwYDVQQDEyBHbG9iYWxTaWduIFRpbWVzdGFtcGlu
# ZyBSb290IFI0NTAeFw0yNTA3MTYwMzA1MDRaFw00MTA3MTYwMDAwMDBaMF4xCzAJ
# BgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNhMTQwMgYDVQQDEytH
# bG9iYWxTaWduIE9mZmxpbmUgUjQ1IFRpbWVzdGFtcGluZyBDQSAyMDI1MIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEApHcW+O19i+LdAoZFYzS+5X+WYvnW
# oFqXAfir1hynhUTdH4RW1Db+yOmrQ275jlsQ6bzoZ3nN0CMncZX4E0Qhpp6Qvx27
# +flpfzeMQacD7VciWUiF3TLiu7wT2bBCSENUn3hfGMG4PJvYFvO5o4DA1iNvHhG4
# oSzctodoJfb4c8EjVahCw/NLizB3ra+NWe2gZBSaZKraMxFt676yqx7RcQnjbF4R
# 0OLGovsZt23vU69A5BdoPxdA9zu9rM+qTBsPDVUJexYwEVU0GY7BJ5mUWWniyAPH
# W0Wv4Azk5t7I0XUIjA3+2OGkr0dVBXVBDyEeGBVrYXEdhfVLwuh6HBGJFdIrEY5K
# oGlpoT+4BBQe4XCH5sv15Uo+M72VKWjPA5Ex3nfFJC4P5FW1SR6olCSaIrtnZzc+
# zgmpSyiD+GcE2udQRQHbDi74enXgazk0+ktpHZ1Z8oTvSaSIREovXSLbH3KC8uFI
# kXucl7XPH7ZGIrmF9eF4zuoo5FIUnsvV60kLqFDzPk+UbLmgZDUCPlFFBBehaaNv
# ixEymx9ON2KXev+MfK6OZChqGbrOC2wvvAFHyKlTZbVHdqNiu0u5a2T1C9dSTRny
# 1/hxLwcxL9BWPzQLwhsiyXqUzM7uD0lD9+PYMaxUYgoVSxqb4xvPCiVqLNabI+Wt
# jEzYfQ0P+6tBTFsCAwEAAaOCAWIwggFeMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUE
# DDAKBggrBgEFBQcDCDASBgNVHRMBAf8ECDAGAQH/AgEAMB0GA1UdDgQWBBR3AjsB
# MQ8edHfDSMjDB2NViKU7ojAfBgNVHSMEGDAWgBRGshx34XsV8KU5oXDe0cQu6m2y
# 3jCBjgYIKwYBBQUHAQEEgYEwfzA3BggrBgEFBQcwAYYraHR0cDovL29jc3AuZ2xv
# YmFsc2lnbi5jb20vdGltZXN0YW1wcm9vdHI0NTBEBggrBgEFBQcwAoY4aHR0cDov
# L3NlY3VyZS5nbG9iYWxzaWduLmNvbS9jYWNlcnQvdGltZXN0YW1wcm9vdHI0NS5j
# cnQwPwYDVR0fBDgwNjA0oDKgMIYuaHR0cDovL2NybC5nbG9iYWxzaWduLmNvbS90
# aW1lc3RhbXByb290cjQ1LmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcN
# AQEMBQADggIBADKj7n7RbuRmMZZYXqlMPRJoR6X1n//quXGLVfOpFoR9Ya05L94w
# 0ywBjelyGGf+nAB+CZFQ7gUOd2a2bpfpW8Xw5ArM+YjPEf8AtC4E6Yr105U1YNjl
# TSERoWJKc1hkSN5m4dpsYteFykzFQVwX50hYKH3yZ6Vcu6Ha0EA5ofzLpi2jK2jb
# RDCXbFNLi5mO1xKRdB2AzAF0f5C00b4H3d5sCOB8njTvAwaTMGEMeTkLWM4Z9Y+3
# UOtOpo1QuxXbDpXVkLXraG25iL1VtvjxEAy4534nUINB9whORicJJSTLba6fOK2f
# /1QGWEdewWLHAzE+N5oH0QoNRALpJ5JjIfeInvO+sQdBidnPuLKJ95HTj7XyMvJh
# FZjtbHJGlEWx4UgKcuNKLDLXWALfwQDN2Dey3kTfd4yw4nQdk1PctLLK3F4L2nnL
# v94BMkpY+Rfl53oOEN4yTvtwCYP+VDuZrktc7NacoTVxZnKGkv8a1akckdOwQZC+
# i8Ay1VyzMAX/Tb4+r3c65B7cpAtq3OoUijXUJgvZxci6TX78smL2TYy2tWn+8G4k
# rnXvy2ELR2XYnKEOS4MVmrSCsjM5nxSrghE10VDXQbEfa93lhikfFoIuINKzWDLq
# vu8ZucmxEufxpHjNnnRVXX/Zv5KQq8pu/MQoOz6DC74n5+O5bSwvT5sgMIIGozCC
# BIugAwIBAgIQeEqqgXNmnJAJVOQhyUfrwDANBgkqhkiG9w0BAQwFADBMMSAwHgYD
# VQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBSNjETMBEGA1UEChMKR2xvYmFsU2ln
# bjETMBEGA1UEAxMKR2xvYmFsU2lnbjAeFw0yMDEyMDkwMDAwMDBaFw0zNDEyMTAw
# MDAwMDBaMFMxCzAJBgNVBAYTAkJFMRkwFwYDVQQKExBHbG9iYWxTaWduIG52LXNh
# MSkwJwYDVQQDEyBHbG9iYWxTaWduIFRpbWVzdGFtcGluZyBSb290IFI0NTCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALp0M+wn3BI4IRvF02Eo1lq8T9+L
# zJGEQyRXvGQhvDscHz1PjK0Ht/PF1wLpERSCmqq0lHI7cQ0a72hrhXmOr2bqWJgN
# usF8edL/zbNvMUXQBXQEAHJqJ364Nz86iO2Xg/WrNU0Pn1k79S/fWcV8pTJ2YJbI
# 7e74BH4ZUXKov0RBerx7HjsAm7y64Ja/kP6Nm8NyiwAS+CA6YDj3wcyFivuHeS6h
# KyDmy6CFkSO2xCgHVCje7BAxT4ryzRQfHt1VHOooMUz5IWqozfOWZ/oBQZvNDwto
# f7ve8UPqF+Ww3HAis2k2WXRrxuWJKnzlC4Fdqz+PuNF2cvN8oqnil0G/zIxF/mHJ
# 9mwHCwAE6BUjT4IqLfbvw/oRNkih0f16OTo0XaMsDpt3UCA0QN2xAzGtX+lih3OW
# A2H3lLDZXGxP5xTF4fF7DSOczXCMHWreSi2LKrvbQhQFB6r7FNwx0/YfbMu+aGZE
# cE1tF/lx6wVzjpGSdetoXB72RGEYKWLdF2aI7Ci6SW/bPnf+uTEfdRwYoqZHvdju
# SIU7/bPiDz8qmMaa+oJvsaWlhh1aOvqkbHQPd1Jhan+HKd45m4vus0VgMCSXFRIq
# hTCTJqyWpi3ocG0LqTKtLJsoCnZC8lVhUZiU3u32xRdvPBUQsA6tsN7FFvRl0cwv
# WlYIz5nE8FWRwix5AgMBAAGjggF4MIIBdDAOBgNVHQ8BAf8EBAMCAYYwEwYDVR0l
# BAwwCgYIKwYBBQUHAwgwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQURrIcd+F7
# FfClOaFw3tHELuptst4wHwYDVR0jBBgwFoAUrmwFo5MT4qLn4tcc1sfwf8hnU6Aw
# ewYIKwYBBQUHAQEEbzBtMC4GCCsGAQUFBzABhiJodHRwOi8vb2NzcDIuZ2xvYmFs
# c2lnbi5jb20vcm9vdHI2MDsGCCsGAQUFBzAChi9odHRwOi8vc2VjdXJlLmdsb2Jh
# bHNpZ24uY29tL2NhY2VydC9yb290LXI2LmNydDA2BgNVHR8ELzAtMCugKaAnhiVo
# dHRwOi8vY3JsLmdsb2JhbHNpZ24uY29tL3Jvb3QtcjYuY3JsMEcGA1UdIARAMD4w
# PAYEVR0gADA0MDIGCCsGAQUFBwIBFiZodHRwczovL3d3dy5nbG9iYWxzaWduLmNv
# bS9yZXBvc2l0b3J5LzANBgkqhkiG9w0BAQwFAAOCAgEAi0i6Nlc8csXadfnvMvWG
# vdwSKOOILk82XyaZ7A8BIRCWkjjGcGtt867UDr0l74Z/4omNlaV+KUQDTaqYqPG3
# 3OopYyHc7c2ICssQaWF5KUIMI7zpxe9SHi8zN9VPZnpmqUdUM7HdFvLYZHGjMZTl
# b/ZNS+KEbNDJJWdPyEvQzksF1j37fUH6irHAIeB+CLDZZCv56vLHCvTPLgw0YO5s
# u5LwP/F7UhJod1mB9RwupDqMOQMN7eXMr2ZIeWPVSbj/S9IlT0hOkzuTd7CaSGy2
# oB2zdJ5fvSIEO3w3DYW1w5q73ZxaA420DZ9MdjTVha1Fe7Wfuy6Ju6zIv5JjSMY/
# yheqDbwAEV+L6ONDhIpDNM39O8Cie9sfuGfIjBXeP6Z/xyjvoW9vskHPAiLrAfhL
# yNJ2byXfXtpoaD17RATCQW5JO6eYVgTt0SYrBJTb5O1mjj2AnaSkVXlQXuP4Gh/A
# Fm+QFTyKpkihDHu6KuCxqYcFRpvtJVU9N2mY7UaZmIVHCh5i2/2c5cFDQo69z2/2
# jJH9guSf7K3jlVUF80kvbTT3/2fumUC705qAQkDaI4lgH4NxkrXp5soK+d3HbLJY
# QZxmjZsqbx9vVwRDXINdO2mc3jn6hE0183sbbYvxbwPBKVLilL97VIvfQHoLcAJ3
# Py+IBwIAddKvxtYiMhmjO+gwggWDMIIDa6ADAgECAg5F5rsDgzPDhWVI5v9FUTAN
# BgkqhkiG9w0BAQwFADBMMSAwHgYDVQQLExdHbG9iYWxTaWduIFJvb3QgQ0EgLSBS
# NjETMBEGA1UEChMKR2xvYmFsU2lnbjETMBEGA1UEAxMKR2xvYmFsU2lnbjAeFw0x
# NDEyMTAwMDAwMDBaFw0zNDEyMTAwMDAwMDBaMEwxIDAeBgNVBAsTF0dsb2JhbFNp
# Z24gUm9vdCBDQSAtIFI2MRMwEQYDVQQKEwpHbG9iYWxTaWduMRMwEQYDVQQDEwpH
# bG9iYWxTaWduMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAlQfoc8pm
# +ewUyns89w0I8bRFCyyCtEjG61s8roO4QZIzFKRvf+kqzMawiGvFtonRxrL/FM5R
# FCHsSt0bWsbWh+5NOhUG7WRmC5KAykTec5RO86eJf094YwjIElBtQmYvTbl5KE1S
# GooagLcZgQ5+xIq8ZEwhHENo1z08isWyZtWQmrcxBsW+4m0yBqYe+bnrqqO4v76C
# Y1DQ8BiJ3+QPefXqoh8q0nAue+e8k7ttU+JIfIwQBzj/ZrJ3YX7g6ow8qrSk9vOV
# ShIHbf2MsonP0KBhd8hYdLDUIzr3XTrKotudCd5dRC2Q8YHNV5L6frxQBGM032uT
# GL5rNrI55KwkNrfw77YcE1eTtt6y+OKFt3OiuDWqRfLgnTahb1SK8XJWbi6IxVFC
# RBWU7qPFOJabTk5aC0fzBjZJdzC8cTflpuwhCHX85mEWP3fV2ZGXhAps1AJNdMAU
# 7f05+4PyXhShBLAL6f7uj+FuC7IIs2FmCWqxBjplllnA8DX9ydoojRoRh3CBCqia
# dR2eOoYFAJ7bgNYl+dwFnidZTHY5W+r5paHYgw/R/98wEfmFzzNI9cptZBQselhP
# 00sIScWVZBpjDnk99bOMylitnEJFeW4OhxlcVLFltr+Mm9wT6Q1vuC7cZ27JixG1
# hBSKABlwg3mRl5HUGie/Nx4yB9gUYzwoTK8CAwEAAaNjMGEwDgYDVR0PAQH/BAQD
# AgEGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFK5sBaOTE+Ki5+LXHNbH8H/I
# Z1OgMB8GA1UdIwQYMBaAFK5sBaOTE+Ki5+LXHNbH8H/IZ1OgMA0GCSqGSIb3DQEB
# DAUAA4ICAQCDJe3o0f2VUs2ewASgkWnmXNCE3tytok/oR3jWZZipW6g8h3wCitFu
# txZz5l/AVJjVdL7BzeIRka0jGD3d4XJElrSVXsB7jpl4FkMTVlezorM7tXfcQHKs
# o+ubNT6xCCGh58RDN3kyvrXnnCxMvEMpmY4w06wh4OMd+tgHM3ZUACIquU0gLnBo
# 2uVT/INc053y/0QMRGby0uO9RgAabQK6JV2NoTFR3VRGHE3bmZbvGhwEXKYV73jg
# ef5d2z6qTFX9mhWpb+Gm+99wMOnD7kJG7cKTBYn6fWN7P9BxgXwA6JiuDng0wyX7
# rwqfIGvdOxOPEoziQRpIenOgd2nHtlx/gsge/lgbKCuobK1ebcAF0nu364D+JTf+
# AptorEJdw+71zNzwUHXSNmmc5nsE324GabbeCglIWYfrexRgemSqaUPvkcdM7Bjd
# bO9TLYyZ4V7ycj7PVMi9Z+ykD0xF/9O5MCMHTI8Qv4aW2ZlatJlXHKTMuxWJU7os
# BQ/kxJ4ZsRg01Uyduu33H68klQR4qAO77oHl2l98i0qhkHQlp7M+S8gsVr3HyO84
# 4lyS8Hn3nIS6dC1hASB+ftHyTwdZX4stQ1LrRgyU4fVmR3l31VRbH60kN8tFWk6g
# REjI2LCZxRWECfbWSUnAZbjmGnFuoKjxguhFPmzWAtcKZ4MFWsmkEDGCA2EwggNd
# AgEBMHMwXjELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2Ex
# NDAyBgNVBAMTK0dsb2JhbFNpZ24gT2ZmbGluZSBSNDUgVGltZXN0YW1waW5nIENB
# IDIwMjUCEQCEcj/BlcwW8dsrovZg3yvkMAsGCWCGSAFlAwQCAqCCAUEwGgYJKoZI
# hvcNAQkDMQ0GCyqGSIb3DQEJEAEEMCsGCSqGSIb3DQEJNDEeMBwwCwYJYIZIAWUD
# BAICoQ0GCSqGSIb3DQEBDAUAMD8GCSqGSIb3DQEJBDEyBDBrfHFSxSTpic/WS5ER
# vQUveL5HfFxS1U6cxAx/lzVIFlPS8sVMCMswLoKsgcBmWtEwgbQGCyqGSIb3DQEJ
# EAIvMYGkMIGhMIGeMIGbBCCDKtcuUj/erIP6RpS858bMJhdkiChmVmWIyK3KOoOF
# UTB3MGKkYDBeMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1z
# YTE0MDIGA1UEAxMrR2xvYmFsU2lnbiBPZmZsaW5lIFI0NSBUaW1lc3RhbXBpbmcg
# Q0EgMjAyNQIRAIRyP8GVzBbx2yui9mDfK+QwDQYJKoZIhvcNAQEMBQAEggGAKPiM
# FaMIPQlCOaTh9vLgAvJphKZySeMBHLjJC3J4N3BWPpArn43kVZL5G1Hf95q29YR+
# iC4dV3RdGOEdbvzMbFGYcu17bHJ6YULSLiFmfpxbyAZkiiLVwIOFomZzHoeJcLR5
# ZcOzLBGAJKPtAyayH6jW4YWd5KNrLGgcvw9qlhh+64U3Go9/PNx1332GogOgF1al
# qmHrjoWjtwo80oDv1pX4F5BDXtKdNXNDuYa4kl2SguiHriB0sGtRCOrKqxvt0Jxc
# qLuX7g57WrvErKHes2urrcBXU6jf50MLh3rzqqOrnLK5oN9mLsD3krN3OhbDczIA
# Ez1gmrmepAtDpg481lmBLiuWawS4qPs6Hgd+3nJXkyML7JKP5QCScJmFc/hqbljx
# +Og5JcqNk/XdapzYoho9gds/My5+AuRvruQUKFd8+pseE5eHbCal4KHphG7hxCCq
# Kgw5f5+qMiD4zL4xXeoQ3RI4q6H8iKS/W8M5GkEk03N7aNkk+065Dgi8U/o7
# SIG # End signature block
