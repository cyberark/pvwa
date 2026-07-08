
[CmdletBinding()]
Param(
  [Parameter(Mandatory=$true)][string]$Region,
  [Parameter(Mandatory=$true)][string]$LogGroup,
  [Parameter(Mandatory=$true)][string]$UserDataLogStream,
  [Parameter(Mandatory=$true)][string]$PVWAConfigurationLogStream,
  [Parameter(Mandatory=$true)][string]$PVWARegistrationLogStream
)

try {
  $agentCtl    = "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1"
  $agentCfgDir = "C:\ProgramData\Amazon\AmazonCloudWatchAgent"
  $configDest  = "$agentCfgDir\amazon-cloudwatch-agent.json"
  $template    = "$PSScriptRoot\amazon-cloudwatch-agent.json"

  if (-not (Test-Path $agentCtl)) {
    Write-Error "CloudWatch Agent control script not found at '$agentCtl'. Ensure the Amazon CloudWatch Agent is installed on this instance."
    exit 1
  }

  if (-not (Test-Path $template)) {
    Write-Error "CloudWatch Agent config template not found at '$template'."
    exit 1
  }

  $configContent = Get-Content -Path $template -Raw
  $updatedContent = $configContent `
    -replace 'AWS_REGION_PH',          $Region `
    -replace 'LOG_GROUP_PH',           $LogGroup `
    -replace 'USERDATA_LOG_PH',        $UserDataLogStream `
    -replace 'PVWA_CONF_LOG_PH',       $PVWAConfigurationLogStream `
    -replace 'PVWAREGISTRATION_LOG_PH',$PVWARegistrationLogStream `

  if (-not (Test-Path $agentCfgDir)) {
    New-Item -ItemType Directory -Path $agentCfgDir -Force | Out-Null
  }
  # PowerShell 5.1 Out-File -Encoding UTF8 writes a BOM; CloudWatch Agent JSON parser rejects it.
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($configDest, $updatedContent, $utf8NoBom)

  Write-Output "Applying CloudWatch Agent configuration."
  & $agentCtl -a fetch-config -m ec2 -c "file:$configDest" -s
  if ($LASTEXITCODE) {
    Write-Error "CloudWatch Agent fetch-config failed with exit code $LASTEXITCODE."
    exit 1
  }

  Write-Output "Waiting for AmazonCloudWatchAgent service to reach Running state."
  $timeout = [datetime]::Now.AddMinutes(2)
  $running = $false
  while ([datetime]::Now -lt $timeout) {
    Start-Sleep -Seconds 5
    $svc = Get-Service AmazonCloudWatchAgent -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') { $running = $true; break }
  }
  if (-not $running) {
    $agentLog = "C:\ProgramData\Amazon\AmazonCloudWatchAgent\Logs\amazon-cloudwatch-agent.log"
    $tail = if (Test-Path $agentLog) { Get-Content $agentLog -Tail 20 | Out-String } else { "(log file not found)" }
    Write-Error "AmazonCloudWatchAgent did not reach Running state within the expected time.`nAgent log tail:`n$tail"
    exit 1
  }

  Write-Output "CloudWatch Agent configured and started successfully."
  exit 0
} catch {
  Write-Error "Error updating CloudWatch configuration: $_"
  exit 1
}
