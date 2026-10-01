param(
  [string]$BuildDir = (Join-Path (Split-Path -Parent $PSScriptRoot) 'build\debug')
)

$Server = Join-Path $BuildDir 'named-pipe-server.exe'
$Client = Join-Path $BuildDir 'named-pipe-client.exe'
if (!(Test-Path $Server) -or !(Test-Path $Client)) {
  throw "Build server and client first: tools/build.ps1 debug all"
}

$proc = Start-Process -FilePath $Server -PassThru -WindowStyle Hidden
try {
  Start-Sleep -Milliseconds 500

  function Invoke-Client([string[]]$Args) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Client
    foreach ($a in $Args) { [void]$psi.ArgumentList.Add($a) }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $out.Trim(); Stderr = $err.Trim() }
  }

  $ping = Invoke-Client @('ping')
  if ($ping.ExitCode -ne 0 -or $ping.Stdout -ne '{"v":1,"id":1,"ok":true,"result":{"pong":true}}') { throw "ping failed: $($ping | ConvertTo-Json -Compress)" }

  $echo = Invoke-Client @('echo','hello')
  if ($echo.ExitCode -ne 0 -or $echo.Stdout -ne '{"v":1,"id":1,"ok":true,"result":{"text":"hello"}}') { throw "echo failed: $($echo | ConvertTo-Json -Compress)" }

  $add = Invoke-Client @('add','-12','54')
  if ($add.ExitCode -ne 0 -or $add.Stdout -ne '{"v":1,"id":1,"ok":true,"result":{"sum":42}}') { throw "add failed: $($add | ConvertTo-Json -Compress)" }

  $jobs = 1..4 | ForEach-Object { Start-Job -ScriptBlock { param($c) & $c ping } -ArgumentList $Client }
  $results = $jobs | Wait-Job | Receive-Job
  $jobs | Remove-Job
  foreach ($line in $results) {
    if ($line.Trim() -ne '{"v":1,"id":1,"ok":true,"result":{"pong":true}}') { throw "concurrent ping failed: $line" }
  }

  Write-Host 'integration ok'
}
finally {
  if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force }
}
