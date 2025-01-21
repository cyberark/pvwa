
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true)][string]$Region,
  [Parameter(Mandatory=$true)][string]$LogGroup,
  [Parameter(Mandatory=$true)][string]$UserDataLogStream,
  [Parameter(Mandatory=$true)][string]$PVWAConfigurationLogStream,
  [Parameter(Mandatory=$true)][string]$PVWARegistrationLogStream
)

try {
  $configPath = "C:\Program Files\Amazon\SSM\Plugins\awsCloudWatch\AWS.EC2.Windows.CloudWatch.json"
  $cwLogPath = "C:\ProgramData\Amazon\SSM\Logs\amazon-ssm-cloudwatch.log"
  $configContent = Get-Content -Path $configPath -Raw

  $updatedContent = $configContent `
    -replace 'false','true' `
    -replace 'AWS_REGION_PH',$Region `
    -replace 'LOG_GROUP_PH',$LogGroup `
    -replace 'USERDATA_LOG_PH',$UserDataLogStream `
    -Replace 'PVWA_CONF_LOG_PH',$PVWAConfigurationLogStream `
    -Replace 'PVWAREGISTRATION_LOG_PH',$PVWARegistrationLogStream

  $updatedContent | Out-File -FilePath $configPath -Force -Encoding ASCII
  Restart-Service AmazonSSMAgent
  $timeout = [datetime]::Now.AddMinutes(2)
  Write-Output "Waiting for CloudWatch execution to start."
  while([datetime]::Now -lt $timeout) {
    if (Get-Content $cwLogPath -ErrorAction Ignore | Select-String "CloudWatch execution started.") {
      break
    }
    Start-Sleep -Seconds 5
  }
  if ([datetime]::Now -ge $timeout) {
    Write-Error "CloudWatch execution did not start within the expected time."
    exit 1
  }
  Write-Output "CloudWatch Configuration file updated successfully."
} catch {
  Write-Error "Error updating CloudWatch configuration: $_"
  exit 1
}
