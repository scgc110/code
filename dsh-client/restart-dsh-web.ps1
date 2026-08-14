# restart-dsh-web.ps1 - robust dsh web restart (kill leftovers, wait, relaunch)
$port = 3080
$bootLog = Join-Path $PSScriptRoot 'dsh-web.boot.log'
$launcher = Join-Path $PSScriptRoot 'start-dsh-web.cmd'

function Test-Port([int]$p) {
  $c = New-Object System.Net.Sockets.TcpClient
  try { $c.Connect('127.0.0.1', $p); return $true } catch { return $false } finally { $c.Dispose() }
}

function Stop-DshProcesses {
  # Only kills node.exe/cmd.exe whose command line clearly belongs to dsh.
  # 'restart-dsh-web' must NOT match: require a path separator before 'start-dsh-web'.
  Get-CimInstance Win32_Process | ForEach-Object {
    $cl = $_.CommandLine
    if ($cl -and (($_.Name -eq 'node.exe' -and $cl -match 'dsh') -or ($_.Name -eq 'cmd.exe' -and $cl -match 'dsh\.cmd|[\\/]start-dsh-web'))) {
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    }
  }
  Start-Sleep -Milliseconds 800
}

Write-Host '[1/4] Killing leftover dsh processes...'
Stop-DshProcesses
for ($i = 0; $i -lt 10 -and (Test-Port $port); $i++) { Start-Sleep -Milliseconds 500 }
if (Test-Port $port) {
  $line = netstat -ano | Select-String ':3080' | Select-String 'LISTENING' | Select-Object -First 1
  if ($line) {
    $pid3080 = (($line.Line -split '\s+') | Where-Object { $_ })[-1]
    Write-Host "  killing PID $pid3080 on $port..."
    Stop-Process -Id $pid3080 -Force -ErrorAction SilentlyContinue
  }
}
for ($i = 0; $i -lt 20 -and (Test-Port $port); $i++) { Start-Sleep -Milliseconds 500 }
if (Test-Port $port) { Write-Host '  [FAILED] port still in use.' } else { Write-Host '  port 3080 free.' }

Write-Host '[2/4] Starting dsh web (log: dsh-web.boot.log)...'
if (Test-Path -LiteralPath $launcher) {
  Start-Process -FilePath $launcher -WindowStyle Hidden | Out-Null
} else {
  Start-Process -FilePath (Join-Path $env:APPDATA 'npm\dsh.cmd') -ArgumentList 'web' -WindowStyle Hidden | Out-Null
}

Write-Host '[3/4] Waiting for port 3080 (up to 40s)...'
$ready = $false
for ($i = 0; $i -lt 40; $i++) {
  Start-Sleep -Milliseconds 1000
  if (Test-Port $port) {
    Start-Sleep -Milliseconds 1000
    if (Test-Port $port) { $ready = $true; break }
  }
}
if ($ready) {
  Write-Host '  [OK] Harness restarted: http://127.0.0.1:3080'
  Write-Host '  Next: double-click the dsh-client desktop shortcut.'
} else {
  Write-Host '  [FAILED] Port 3080 not ready after 40s.'
  Write-Host '  Last 30 lines of dsh-web.boot.log:'
  if (Test-Path -LiteralPath $bootLog) { Get-Content -LiteralPath $bootLog -Tail 30 }
}
Write-Host '[4/4] Done.'