#script start

param (
  [Parameter(Mandatory = $true)][string]$Component,
  [Parameter(Mandatory = $true)][string]$VaultPrivateIP,
  [Parameter(Mandatory = $true)][string]$VaultUsername,
  [Parameter(Mandatory = $true)][string]$VaultPassword,
  [Parameter(Mandatory = $false)][string]$pvwaUrl
)

# Creating logoutput and filenames
$LogFolder = "C:\Cyberark"
$LogFile = $LogFolder + "\Deployment-" + (Get-Date -UFormat "%d-%m-%Y") + ".log"

function StartService($ServiceName) {
  $arrService = Get-Service -Name $ServiceName

  while ($arrService.Status -ne 'Running')
  {
    Start-Service $ServiceName
    Write-Host $arrService.status
    Write-Host 'Service starting'
    Start-Sleep -seconds 5
    $arrService.Refresh()
    if ($arrService.Status -eq 'Running')
    {
      Write-Host "Service '$ServiceName' is now Running"
    }
  }
}

function Write-Log
{
	param (
        [Parameter(Mandatory=$True)]
        [array]$LogOutput,
        [Parameter(Mandatory=$True)]
        [string]$Path
	)
	$currentDate = (Get-Date -UFormat "%d-%m-%Y")
	$currentTime = (Get-Date -UFormat "%T")
	$logOutput = $logOutput -join (" ")
	"[$currentDate $currentTime] $logOutput" | Out-File $Path -Append
}

function RunProcess
{
	param (
        [Parameter(Mandatory=$True)]
        [string]$process,
        [Parameter(Mandatory=$True)]
        [string]$arguments,
        [Parameter(Mandatory=$True)]
        [string]$step
	)
    $rc = Start-Process -NoNewWindow -FilePath $process -ArgumentList $arguments -Wait -PassThru
    if($rc.ExitCode -ne 0)
    {
        Write-Output "Step $step Failed, Exiting..."
        Write-Log -LogOutput ("Step $step Failed, Exiting...") -Path $LogFile
        exit 1
    } else {
        Write-Output "Step $step Completed"
        Write-Log -LogOutput ("Step $step Completed") -Path $LogFile
    }
}

try{
	Set-Location "C:\CyberArk"
	$FormattedArgumentList = '-ExecutionPolicy Unrestricted -File C:\CyberArk\HttpRedirectHostname.ps1'
	RunProcess -process "powershell" -arguments $FormattedArgumentList -step "HTTP Redirect Hostname"
  if (-not ($pvwaUrl)) {
      $pvwaUrl = "https://$env:COMPUTERNAME/PasswordVault"
  }
  $FormattedArgumentList = '-ExecutionPolicy Unrestricted -File "C:\CyberArk\CloudRegisterToVault.ps1" -PVWA -PVWAVaultIP "{0}" -PVWAVaultPort 1858 -PVWAVaultUser "{1}" -PVWAVaultPassword "{2}" -PVWAUrl "{3}"' -f $VaultPrivateIP, $VaultUsername, $VaultPassword, $pvwaUrl
  RunProcess -process "powershell" -arguments $FormattedArgumentList -step "Registration"
  Start-WebAppPool -Name "PasswordVaultWebAccessPool"
  Set-ItemProperty -Path IIS:\AppPools\PasswordVaultWebAccessPool -Name autoStart -Value "true"
  Set-Location "C:\Windows\system32"
  $FormattedArgumentList = 'config "CyberArk Scheduled Tasks" start=auto'
  RunProcess -process "sc" -arguments $FormattedArgumentList -step "Set PVWA Service Automatic"
  try {
      StartService("CyberArk Scheduled Tasks")
      Write-Output "PVWA Service Started Successfully"
      Write-Log -LogOutput ("PVWA Service Started Successfully") -Path $LogFile
  } catch {
      Write-Output "Failed to Start PVWA Service"
      Write-Log -LogOutput ("Failed to Start PVWA Service") -Path $LogFile
      exit 1
  }
  Set-Location "C:\CyberArk"
  $FormattedArgumentList = '-ExecutionPolicy Unrestricted -File "C:\CyberArk\CreateSelfCertAndBind.ps1"'
  RunProcess -process "powershell" -arguments $FormattedArgumentList -step "Create and Bind Self Signed Certificate"
}
catch
{
  exit 1
}
#script end
