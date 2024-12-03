function WriteLog{
    [CmdletBinding()]
    param(
        $LogFile,
        $LogLevel,
        $Log
    )

    if (!(Test-Path $LogFile)) {
        $NewLogFile = New-Item $LogFile -Force -ItemType File
    }

    $FormattedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$($FormattedDate) [$($LogLevel)] $($Log)" | Out-File -FilePath $LogFile -Append -Encoding ASCII

    if ($LogLevel.StartsWith("USER")) {
        Write-Host "$Log"
    }
}

function ChildScriptErrorHandler {
    [CmdletBinding()]
    param(
      $LogFile,
      $ScriptName
    )
    if ($? -ne $true) {
        throw "$ScriptName script returned a non-zero exit code"
        WriteLog -LogFile $LogFile -LogLevel "ERROR" -Log "Failed to execute $ScriptName configuration: $_"
        exit 1
    }
  }